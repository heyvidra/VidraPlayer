import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/utils/network_resilience.dart';

/// Records every URL the warmup asks for, and answers each one according to
/// [succeeds]. Everything the warmup does not touch falls through to
/// [noSuchMethod] and throws, so a probe that starts using some other part of
/// HttpClient fails loudly instead of silently passing.
class _RecordingHttpClient implements HttpClient {
  final List<Uri> requested = [];
  final bool Function(Uri url) succeeds;

  _RecordingHttpClient(this.succeeds);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requested.add(url);
    if (!succeeds(url)) {
      // What Cloudflare actually does to a ClientHello carrying no server
      // name: reject the handshake before any HTTP is exchanged.
      throw const HandshakeException('SNI rejected');
    }
    return _FakeRequest();
  }

  @override
  set badCertificateCallback(
    bool Function(X509Certificate, String, int)? callback,
  ) {}

  @override
  set connectionTimeout(Duration? value) {}

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  Future<HttpClientResponse> close() async => _FakeResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  final int statusCode = 200;

  final Stream<List<int>> _body = Stream.fromIterable([
    [1, 2, 3],
  ]);

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _body.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Overrides extends HttpOverrides {
  final _RecordingHttpClient client;
  _Overrides(this.client);

  @override
  HttpClient createHttpClient(SecurityContext? context) => client;
}

Future<WarmupResult> _warmup(String url, _RecordingHttpClient client) {
  return HttpOverrides.runZoned(
    () => NetworkResilience.preflightWarmup(url),
    createHttpClient: (context) => client,
  );
}

void main() {
  // "localhost" resolves offline and gives back an address string that differs
  // from the hostname, which is what makes a pinned-IP URL distinguishable
  // from a hostname URL here.
  const url = 'https://localhost/vod/chunklist.m3u8';

  setUp(HlsNodeState.reset);

  test('probes the hostname before pinning an IP', () async {
    // The regression this guards: rewriting the host to a bare IP sends no
    // SNI, and CDNs on shared edges reject that handshake outright. If the
    // per-IP loop ever runs first again, the first URL below stops being the
    // hostname and this fails.
    final client = _RecordingHttpClient((_) => true);

    final result = await _warmup(url, client);

    expect(client.requested, hasLength(1));
    expect(client.requested.single.host, 'localhost');
    expect(result.resolvedUrl, url);
    expect(result.ip, isEmpty, reason: 'no IP should have been pinned');
    expect(result.originalHost, 'localhost');
  });

  test('falls back to pinning an IP when the hostname fails', () async {
    final client = _RecordingHttpClient((u) => u.host != 'localhost');

    final result = await _warmup(url, client);

    expect(client.requested.first.host, 'localhost');
    expect(client.requested.length, greaterThan(1));
    expect(result.ip, isNotEmpty);
    expect(result.resolvedUrl, contains(result.ip));
    expect(
      result.originalHost,
      'localhost',
      reason: 'the Host header target must survive the rewrite',
    );
  });

  test('gives up when neither the hostname nor any IP answers', () async {
    final client = _RecordingHttpClient((_) => false);

    await expectLater(_warmup(url, client), throwsA(isA<Exception>()));
    expect(client.requested.first.host, 'localhost');
  });

  test('skips the probe entirely for a non-HTTP url', () async {
    final client = _RecordingHttpClient((_) => true);

    final result = await _warmup('file:///tmp/a.m3u8', client);

    expect(client.requested, isEmpty);
    expect(result.resolvedUrl, 'file:///tmp/a.m3u8');
  });
}
