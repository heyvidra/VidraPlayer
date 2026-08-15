// The low-end-machine switch: PlayerEffects.reduced must actually remove the
// GPU readback passes (backdrop blur, blurred shadows) and nothing else.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra_player/core/player_effects.dart';
import 'package:vidra_player/ui/widget/blur.dart';

void main() {
  // It's a global, so put it back — a leaked `true` would silently disarm the
  // blur in every other widget test in this suite.
  tearDown(() => PlayerEffects.reduced = false);

  testWidgets('blur panel filters by default', (tester) async {
    PlayerEffects.reduced = false;
    await tester.pumpWidget(
      const MaterialApp(home: BlurPanel(child: SizedBox(width: 10, height: 10))),
    );

    expect(find.byType(BackdropFilter), findsOneWidget);
    // The rounded clip is what callers get their corners from — it must
    // survive in both modes.
    expect(find.byType(ClipRRect), findsOneWidget);
  });

  testWidgets('reduced drops the backdrop filter but keeps the clip', (
    tester,
  ) async {
    PlayerEffects.reduced = true;
    await tester.pumpWidget(
      const MaterialApp(home: BlurPanel(child: SizedBox(width: 10, height: 10))),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(ClipRRect), findsOneWidget);
    expect(find.byType(SizedBox), findsWidgets);
  });

}
