import 'dart:io';
import 'package:flutter/foundation.dart';

class HlsNodeState {
  static final Map<String, DateTime> _badIps = {};

  // Hosts whose warmup succeeded recently. Episode/quality switches hit the
  // same host back-to-back — re-probing it each time just re-buys knowledge
  // we already have at the cost of a serial DNS + m3u8 GET on the open path.
  static final Map<String, DateTime> _warmHosts = {};
  static const _ttl = Duration(minutes: 5);

  static void markBad(String ip) {
    _badIps[ip] = DateTime.now();
  }

  static bool isBad(String ip) {
    final time = _badIps[ip];
    if (time == null) return false;
    if (DateTime.now().difference(time) > _ttl) {
      _badIps.remove(ip);
      return false;
    }
    return true;
  }

  static void markWarm(String host) {
    _warmHosts[host] = DateTime.now();
  }

  static bool isWarm(String host) {
    final time = _warmHosts[host];
    if (time == null) return false;
    if (DateTime.now().difference(time) > _ttl) {
      _warmHosts.remove(host);
      return false;
    }
    return true;
  }
}

class WarmupResult {
  final String ip;
  final String resolvedUrl;
  final String originalHost;

  WarmupResult(this.ip, this.resolvedUrl, this.originalHost);
}

class NetworkResilience {
  static Future<WarmupResult> preflightWarmup(
    String originalUrl, {
    void Function(int attempt, int maxRetries)? onRetry,
    bool Function()? isCancelled,
  }) async {
    final uri = Uri.parse(originalUrl);

    // Skip if not HTTP/HTTPS
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return WarmupResult('', originalUrl, uri.host);
    }

    final host = uri.host;

    // Same host warmed up within the TTL: skip the whole probe. The value of
    // warmup is bad-node detection, and we already have a recent verdict.
    if (HlsNodeState.isWarm(host)) {
      debugPrint('[HLS] host $host warmed recently, skipping preflight');
      return WarmupResult('', originalUrl, host);
    }

    List<InternetAddress> addresses;
    try {
      addresses = await InternetAddress.lookup(host);
    } catch (e) {
      debugPrint('[HLS] DNS Resolution failed for $host: $e');
      throw Exception('DNS Resolution failed');
    }

    // Sort IP addresses prioritizing good nodes, then IPv4. A CDN that
    // publishes AAAA records on a host with no working v6 path (Cloudflare
    // does) would otherwise burn the whole retry chain on addresses that can
    // only time out.
    List<InternetAddress> sorted = List.of(addresses);
    sorted.sort((a, b) {
      bool badA = HlsNodeState.isBad(a.address);
      bool badB = HlsNodeState.isBad(b.address);
      if (badA != badB) return badA ? 1 : -1;
      bool v4A = a.type == InternetAddressType.IPv4;
      bool v4B = b.type == InternetAddressType.IPv4;
      if (v4A != v4B) return v4A ? -1 : 1;
      return 0;
    });
    List<String> ips = sorted.map((a) => a.address).toList();

    // Limit to at most 3 IPs to avoid excessive retry chains
    final ipsToTry = ips.take(3).toList();
    const maxRetriesPerIp = 3;
    
    final httpClient = HttpClient()
      ..badCertificateCallback = ((cert, host, port) => true)
      ..connectionTimeout = const Duration(seconds: 5);
    
    try {
      // Probe the hostname before pinning an IP. Pinning exists to route
      // around a bad CDN node, but rewriting the URL's host to a bare IP also
      // strips SNI — an IP literal is not a valid server name, so nothing is
      // sent — and CDNs that share edges across tenants (Cloudflare among
      // them) reject such a ClientHello outright with HANDSHAKE_FAILURE. The
      // Host header below fixes HTTP routing but cannot fix TLS, which has
      // already failed by then. Hostname first means the common case is one
      // request with a correct handshake; pinning stays as the fallback for
      // CDNs where DNS resolution is the actual problem.
      if (await _probe(
        httpClient,
        uri,
        host,
        'host=$host',
        // One shot: if the hostname does not work immediately, per-IP retries
        // below are the better use of the remaining time budget.
        maxRetries: 1,
        onRetry: onRetry,
        isCancelled: isCancelled,
      )) {
        debugPrint('[HLS] warmup successful for host=$host');
        HlsNodeState.markWarm(host);
        return WarmupResult('', originalUrl, host);
      }
      debugPrint('[HLS] hostname warmup failed, falling back to per-IP pinning');

      for (final ip in ipsToTry) {
        if (isCancelled?.call() ?? false) throw Exception('Warmup cancelled');
        if (HlsNodeState.isBad(ip)) {
           debugPrint('[HLS] IP $ip is marked as bad, prioritizing other nodes...');
        }

        final resolvedUri = uri.replace(host: ip);

        if (await _probe(
          httpClient,
          resolvedUri,
          host,
          'ip=$ip',
          maxRetries: maxRetriesPerIp,
          onRetry: onRetry,
          isCancelled: isCancelled,
        )) {
          debugPrint('[HLS] warmup successful for ip=$ip');
          HlsNodeState.markWarm(host);
          return WarmupResult(ip, resolvedUri.toString(), host);
        }

        HlsNodeState.markBad(ip);
        debugPrint('[HLS] All retries failed for IP $ip, marked as bad node. Switching to next IP...');
      }
    } finally {
      // force: true so a cancelled warmup drops in-flight sockets immediately
      // instead of lingering until the CDN response returns.
      httpClient.close(force: true);
    }

    throw Exception('All IPs failed for domain $host');
  }

  /// One warmup target, retried up to [maxRetries] times.
  ///
  /// [probeUri] is what gets requested; [host] is always sent as the Host
  /// header, so this works both for a hostname URL and for an IP-pinned one.
  /// [label] only tags the log lines. Returns false once the retries are
  /// spent, so the caller can move on to the next target; rethrows on a fatal
  /// status, since a bad URL or an expired token is not something another
  /// node can fix.
  static Future<bool> _probe(
    HttpClient client,
    Uri probeUri,
    String host,
    String label, {
    required int maxRetries,
    void Function(int attempt, int maxRetries)? onRetry,
    bool Function()? isCancelled,
  }) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      if (isCancelled?.call() ?? false) throw Exception('Warmup cancelled');
      try {
        debugPrint('[HLS] attempt=$attempt $label url=$probeUri warmup');

        final request = await client.getUrl(probeUri);
        request.headers.set('Host', host);
        request.headers.set('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36');

        final response = await request.close().timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          // Valid response, consume a bit of stream to ensure connectivity.
          // Bounded: a 200 whose body never arrives (half-open CDN edge)
          // would otherwise hang this await — and the whole switch path
          // behind it — forever. Timeout falls into the retry catch below.
          await response.take(1).toList().timeout(const Duration(seconds: 8));
          return true;
        }

        // Handle fatal status codes (403, 401)
        if (response.statusCode == 403 || response.statusCode == 401) {
          debugPrint('[HLS] Fatal status=${response.statusCode} - URL probably invalid or token expired. Aborting.');
          throw Exception('HTTP ${response.statusCode} forbidden');
        }

        debugPrint('[HLS] attempt=$attempt $label status=${response.statusCode} -> retry');
        onRetry?.call(attempt, maxRetries);
        // No backoff after the final attempt — fail over to the next target
        // immediately instead of sleeping into markBad.
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt));
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('forbidden')) rethrow;

        debugPrint('[HLS] attempt=$attempt $label error=$e -> retry');
        onRetry?.call(attempt, maxRetries);
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt));
        }
      }
    }
    return false;
  }
}
