/// Global switch for the backdrop blur, for machines that can't afford it.
///
/// Set it once at startup from the host app's own "reduce effects" setting:
///
/// ```dart
/// PlayerEffects.reduced = true; // low-end machine
/// ```
///
/// The blur makes the GPU read back everything already drawn underneath, the
/// live video texture included, every frame. Nearly free on a discrete GPU
/// with Impeller; brutal on an integrated Intel one running Skia, where a
/// full-screen `BackdropFilter` over video can cost more than decoding it did.
///
/// Nothing about layout, colour or behaviour changes — the panels keep their
/// translucent backgrounds and rounded clips, they just stop blurring.
///
/// ponytail: blur only. Drop shadows were gated here too and taken back out —
/// a `blurRadius: 12` on a dialog card, painted when the card appears, is
/// noise next to a full-screen filter running every frame. Gate them again if
/// a profile ever disagrees.
class PlayerEffects {
  PlayerEffects._();

  static bool reduced = false;
}
