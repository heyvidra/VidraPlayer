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

    // Sort IP addresses prioritizing good nodes
    List<String> ips = addresses.map((a) => a.address).toList();
    ips.sort((a, b) {
      bool badA = HlsNodeState.isBad(a);
      bool badB = HlsNodeState.isBad(b);
      if (badA && !badB) return 1;
      if (!badA && badB) return -1;
      return 0;
    });

    // Limit to at most 3 IPs to avoid excessive retry chains
    final ipsToTry = ips.take(3).toList();
    const maxRetriesPerIp = 3;
    
    final httpClient = HttpClient()
      ..badCertificateCallback = ((cert, host, port) => true)
      ..connectionTimeout = const Duration(seconds: 5);
    
    try {
      for (final ip in ipsToTry) {
        if (isCancelled?.call() ?? false) throw Exception('Warmup cancelled');
        if (HlsNodeState.isBad(ip)) {
           debugPrint('[HLS] IP $ip is marked as bad, prioritizing other nodes...');
        }

        final resolvedUri = uri.replace(host: ip);

        for (int attempt = 1; attempt <= maxRetriesPerIp; attempt++) {
          if (isCancelled?.call() ?? false) throw Exception('Warmup cancelled');
          try {
            debugPrint('[HLS] attempt=$attempt ip=$ip host=$host url=$resolvedUri warmup');
            
            final request = await httpClient.getUrl(resolvedUri);
            request.headers.set('Host', host);
            request.headers.set('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36');
            
            final response = await request.close().timeout(const Duration(seconds: 8));
            
            if (response.statusCode == 200) {
              // Valid response, consume a bit of stream to ensure connectivity.
              // Bounded: a 200 whose body never arrives (half-open CDN edge)
              // would otherwise hang this await — and the whole switch path
              // behind it — forever. Timeout falls into the retry catch below.
              await response
                  .take(1)
                  .toList()
                  .timeout(const Duration(seconds: 8));
              debugPrint('[HLS] warmup successful for ip=$ip');
              HlsNodeState.markWarm(host);
              return WarmupResult(ip, resolvedUri.toString(), host);
            } 
            
            // Handle fatal status codes (403, 401)
            if (response.statusCode == 403 || response.statusCode == 401) {
              debugPrint('[HLS] Fatal status=${response.statusCode} - URL probably invalid or token expired. Aborting.');
              throw Exception('HTTP ${response.statusCode} forbidden');
            }

            debugPrint('[HLS] attempt=$attempt ip=$ip status=${response.statusCode} -> retry');
            onRetry?.call(attempt, maxRetriesPerIp);
            // No backoff after the final attempt — fail over to the next IP
            // immediately instead of sleeping into markBad.
            if (attempt < maxRetriesPerIp) {
              await Future.delayed(Duration(seconds: attempt));
            }
          } catch (e) {
             if (e is Exception && e.toString().contains('forbidden')) rethrow;

             debugPrint('[HLS] attempt=$attempt ip=$ip error=$e -> retry');
             onRetry?.call(attempt, maxRetriesPerIp);
             if (attempt < maxRetriesPerIp) {
               await Future.delayed(Duration(seconds: attempt));
             }
          }
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
}
