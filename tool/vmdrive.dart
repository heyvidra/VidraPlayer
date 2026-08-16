// vmdrive — drive a running Flutter app through the Dart VM Service.
//
// Why this exists: on this machine the OS-level click tooling resolves every
// coordinate inside a Flutter window to the Dock, so nothing can be clicked
// from outside. This goes under the OS entirely — it injects pointer events
// straight into GestureBinding, and finds its targets by walking the element
// tree instead of guessing screen coordinates.
//
// No package deps on purpose (dart:io WebSocket + dart:convert), so it runs
// with a bare `dart run` and needs no pubspec.
//
// ignore_for_file: avoid_print — stdout IS this tool's output. It is a
// developer CLI, never imported by the SDK, and routing it through a logger
// would make its results harder to pipe, not easier to read.
//
//   dart run vmdrive.dart <http-vm-service-uri> libs
//   dart run vmdrive.dart <uri> find  "立即播放"
//   dart run vmdrive.dart <uri> tap   "立即播放"
//   dart run vmdrive.dart <uri> tapxy 120 340
//   dart run vmdrive.dart <uri> eval  "<dart expression>"
//   dart run vmdrive.dart <uri> dump                 # visible Text widgets
import 'dart:async';
import 'dart:convert';
import 'dart:io';

late WebSocket _ws;
var _id = 0;
final _pending = <String, Completer<Map<String, dynamic>>>{};

Future<Map<String, dynamic>> _call(
  String method, [
  Map<String, dynamic> params = const {},
]) {
  final id = '${_id++}';
  final c = Completer<Map<String, dynamic>>();
  _pending[id] = c;
  _ws.add(jsonEncode({
    'jsonrpc': '2.0',
    'id': id,
    'method': method,
    'params': params,
  }));
  return c.future.timeout(const Duration(seconds: 30));
}

/// The VM service takes a ws:// URL ending in /ws; `flutter run` prints the
/// http:// form with the auth token baked into the path.
String _toWs(String uri) {
  var u = uri.trim();
  if (u.startsWith('http')) u = u.replaceFirst('http', 'ws');
  if (!u.endsWith('/')) u = '$u/';
  return '${u}ws';
}

/// Escape a Dart string literal for embedding in an evaluated expression.
String _lit(String s) =>
    "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$')}'";

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('usage: vmdrive <vm-service-uri> <command> [args]');
    exit(64);
  }
  final command = args[1];

  _ws = await WebSocket.connect(_toWs(args[0]));
  _ws.listen((dynamic raw) {
    final msg = jsonDecode(raw as String) as Map<String, dynamic>;
    final id = msg['id']?.toString();
    if (id != null && _pending.containsKey(id)) {
      _pending.remove(id)!.complete(msg);
    }
  });

  final vm = await _call('getVM');
  final isolates = (vm['result']['isolates'] as List).cast<Map<String, dynamic>>();

  // A multi-window Flutter app (bitsdojo, desktop_multi_window) runs each
  // window in its OWN engine and its own "main" isolate — the player window is
  // a different isolate from the dashboard, and driving the wrong one looks
  // exactly like "the tap did nothing". `isolates` lists them; VMDRIVE_ISO
  // picks by index. There are non-UI isolates in there too (drift workers), so
  // print the list rather than guess.
  if (command == 'isolates') {
    for (var i = 0; i < isolates.length; i++) {
      print('$i  ${isolates[i]['name']}  ${isolates[i]['id']}');
    }
    await _ws.close();
    return;
  }
  final isoIdx = int.tryParse(Platform.environment['VMDRIVE_ISO'] ?? '') ?? 0;
  final isolateId = isolates[isoIdx]['id'] as String;

  final iso = await _call('getIsolate', {'isolateId': isolateId});
  final libs = (iso['result']['libraries'] as List).cast<Map<String, dynamic>>();

  if (command == 'libs') {
    for (final l in libs) {
      print('${l['id']}  ${l['uri']}');
    }
    await _ws.close();
    return;
  }

  // Evaluate inside an app library: it imports material, so Text/Offset/
  // RenderBox/WidgetsBinding are all in scope without qualification.
  // Flutter's own internal libraries are a worse choice — binding.dart does
  // not have Text in scope, and the failure looks like a syntax error.
  // The scope decides which identifiers resolve, and the error when you get it
  // wrong is a bare "Undefined name". main.dart imports material, which is
  // enough for Text/Offset/RenderBox/WidgetsBinding — but NOT for gestures
  // (PointerDeviceKind, kPrimaryButton, HitTestResult). Point VMDRIVE_LIB at a
  // library that imports package:flutter/gestures.dart when you need those.
  final want = Platform.environment['VMDRIVE_LIB'];
  Map<String, dynamic>? target;
  if (want != null) {
    target = libs.cast<Map<String, dynamic>?>().firstWhere(
          (l) => (l!['uri'] as String).contains(want),
          orElse: () => null,
        );
    if (target == null) {
      stderr.writeln('VMDRIVE_LIB=$want matched no library');
      exit(1);
    }
  }
  target ??= libs.cast<Map<String, dynamic>?>().firstWhere(
        (l) => (l!['uri'] as String).endsWith('/main.dart') &&
            (l['uri'] as String).startsWith('package:'),
        orElse: () => null,
      );
  target ??= libs.cast<Map<String, dynamic>?>().firstWhere(
        (l) => (l!['uri'] as String).startsWith('package:vidra'),
        orElse: () => null,
      );
  if (target == null) {
    stderr.writeln('no app library found; run `libs` to inspect');
    exit(1);
  }
  final libId = target['id'] as String;

  Future<String> eval(String expr) async {
    final r = await _call('evaluate', {
      'isolateId': isolateId,
      'targetId': libId,
      'expression': expr,
    });
    if (r['error'] != null) return 'RPC_ERROR ${jsonEncode(r['error'])}';
    final res = r['result'] as Map<String, dynamic>;
    if (res['type'] == '@Error' || res['type'] == 'Error') {
      return 'EVAL_ERROR ${res['message'] ?? jsonEncode(res)}';
    }
    return (res['valueAsString'] ?? jsonEncode(res)).toString();
  }

  // Walks the live element tree for a Text whose data contains [needle] and
  // returns the centre of its RenderBox in GLOBAL LOGICAL coordinates — the
  // space handlePointerEvent expects, which is also why this never has to know
  // where the window sits on screen or what the device pixel ratio is.
  //
  // Written as ONE line, iteratively, with `q.add` as a tear-off. The VM
  // service expression compiler rejects both multi-line bodies and local
  // function declarations ("Can't find '}' to match '{'" at 1:5, whatever the
  // real shape) — so no `void walk(Element e) {...}` and no newlines. The
  // worklist replaces the recursion that would otherwise need one.
  String finder(String needle, String then) =>
      "(() { final q = <Element>[WidgetsBinding.instance.rootElement!];"
      ' Element? hit;'
      ' while (q.isNotEmpty && hit == null) { final e = q.removeAt(0);'
      ' final w = e.widget;'
      " if (w is Text && (w.data ?? '').contains(${_lit(needle)})) { hit = e; }"
      ' else { e.visitChildren(q.add); } }'
      " if (hit == null) return 'NOT_FOUND';"
      ' final ro = hit.findRenderObject();'
      " if (ro is! RenderBox || !ro.attached) return 'NO_BOX';"
      ' final c = ro.localToGlobal(ro.size.center(Offset.zero));'
      ' $then })()';

  switch (command) {
    case 'find':
      print(await eval(finder(args[2], "return '\${c.dx},\${c.dy}';")));
      break;

    case 'tap':
      // Down+up on the resolved centre. pointer id 9001 stays clear of the
      // engine's real pointers so a synthetic tap can never be mistaken for
      // the continuation of a physical gesture.
      print(await eval(finder(
        args[2],
        r"final b = WidgetsBinding.instance;"
        ' b.handlePointerEvent(PointerDownEvent(position: c, pointer: 9001));'
        ' b.handlePointerEvent(PointerUpEvent(position: c, pointer: 9001));'
        r" return 'TAPPED ${c.dx},${c.dy}';",
      )));
      break;

    case 'tapxy':
      print(await eval(
        '(() { final b = WidgetsBinding.instance;'
        ' final p = Offset(${args[2]}, ${args[3]});'
        ' b.handlePointerEvent(PointerDownEvent(position: p, pointer: 9001));'
        ' b.handlePointerEvent(PointerUpEvent(position: p, pointer: 9001));'
        " return 'TAPPED'; })()",
      ));
      break;

    case 'dump':
      print(await eval(
        '(() { final q = <Element>[WidgetsBinding.instance.rootElement!];'
        ' final out = <String>[];'
        ' while (q.isNotEmpty) { final e = q.removeAt(0);'
        ' e.visitChildren(q.add); final w = e.widget;'
        r" if (w is Text && (w.data ?? '').trim().isNotEmpty) {"
        ' final ro = e.findRenderObject();'
        ' if (ro is RenderBox && ro.attached) {'
        ' final c = ro.localToGlobal(ro.size.center(Offset.zero));'
        r" out.add('${w.data}@${c.dx.toStringAsFixed(0)},"
        r"${c.dy.toStringAsFixed(0)}'); } } }"
        // The VM service truncates valueAsString well before a full screen's
        // worth of labels fits, and a truncated dump silently looks like a
        // short page. Page through it instead.
        ' final s = ${args.length > 2 ? args[2] : 0};'
        ' final t = ${args.length > 3 ? args[3] : 12};'
        ' return (s >= out.length)'
        r" ? 'END(${out.length})'"
        r" : '[${out.length}] ' + out.skip(s).take(t).join(' ~ '); })()",
      ));
      break;

    case 'eval':
      print(await eval(args[2]));
      break;

    default:
      stderr.writeln('unknown command: $command');
      exit(64);
  }

  await _ws.close();
}
