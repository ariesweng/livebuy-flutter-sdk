// MARK: - LivebuyWidgetVisibility (flutter-refui-widget-host-visibility-pause)
//
// An opt-in host -> SDK bridge that closes the last honest residual gap of
// `flutter-refui-widget-preview-lifecycle-pause`: the "tab-cover" case. When the host keeps the
// widget-hosting screen mounted in the nav tree and merely COVERS it with a NON-route overlay (most
// typically the full-screen live player the collapsible presenter stacks over the home screen),
// the card stays laid-out (`VisibilityDetector`'s `visibleFraction` stays non-zero) and the app
// stays `resumed` (no `didChangeAppLifecycleState`), so the self-sufficient gates in
// `LoopingVideoView` fail and the N background previews keep hardware-decoding on top of the
// playing full-screen player — re-running the ~150% CPU / heat the preview-lifecycle change fixed,
// this time in the FOREGROUND. The SDK cannot self-detect a NON-route z-order cover from the widget
// layer (coordinates are still on-screen, the app is still `resumed`, there is no route boundary
// to observe); only the host's presentation layer knows it covered the widget surface. This is a
// platform / architecture limit — the SDK provides an opt-in entry point, the host feeds the cover
// state. (Being covered by an OPAQUE ROUTE is a different case and IS self-detected — see ROUTE
// COVER below.)
//
// ROUTE COVER (rb-flutter-widget-preview-route-cover-release) — do NOT feed this bridge for a
// `Navigator.push`:
//
//   • An OPAQUE route (`MaterialPageRoute` is opaque by default) pushed over the widget-hosting
//     screen is detected by `LoopingVideoView` ITSELF: Flutter's `Overlay` wraps every entry under
//     the first opaque one in `TickerMode(enabled: false)` once the push transition completes (and
//     re-enables it the moment a pop starts), and the preview reads that via
//     `TickerMode.of(context)` as its own `routeVisible` gate axis — on Android it even
//     RELEASES its decoder while route-hidden and re-creates it on return. No host call needed.
//   • Calling `setWidgetsCovered(true)` around such a push is WRONG, not merely redundant: this
//     bridge is a single PROCESS-GLOBAL level and `register` replays it to every newly mounted
//     preview, so when the pushed page hosts a `LivebuyWidget` of its own (e.g. a carousel page
//     pushing a grid page) the NEW page's cards mount already-covered and never play — exactly what
//     the Flutter example's 「查看更多 ›」 did on device (SM-G887F: 4 visible grid cards frozen at
//     0.00% pixel change while audio focus was already fixed). The example now pushes bare.
//   • This bridge is therefore ONLY for NON-route covers: the collapsible presenter's `Stack`
//     full-screen player (driven for you, see MAIN PATH), or a hand-rolled overlay that is not a
//     route (MANUAL PATH). Non-opaque routes (dialogs, modal bottom sheets,
//     `PageRouteBuilder(opaque: false)`) do not flip `TickerMode` and are not a cover either — the
//     previews stay visible under them.
//
// Dart parity of Android `tv.livebuy.referenceui.widget.LivebuyWidgetVisibility` (an `object`). This
// is an all-static singleton (Dart's idiomatic equivalent). It is DISTINCT from the existing
// `widget_visibility.dart` (a pure predicate for hiding urlless lives) — different feature, no name
// clash.
//
// Who calls setWidgetsCovered — two integration paths (pick by how you present the player):
//
//   • MAIN PATH (most hosts) — the drop-in collapsible presenter `CollapsibleLivebuyPlayer` ALREADY
//     drives this by phase, so the host does NOT and SHOULD NOT call it. Contract
//     `covered <=> full-screen phase full` (`hasVideo && !isMinimized`): covered on full-screen (home
//     previews yield the video decoders), un-covered when minimized to the floating card / closed.
//     Calling setWidgetsCovered yourself ON TOP of the presenter just fights it (both write the same
//     level). See `CollapsibleLivebuyPlayer` + `flutter-refui-presenter-widget-cover-by-phase` /
//     `refui-widget-visibility-kdoc-presenter-owned`.
//
//   • MANUAL PATH (few hosts) — ONLY a host that presents the BARE (non-collapsible) `LivebuyPlayer`,
//     or fully hand-rolls its own NON-route custom cover (never through the collapsible presenter;
//     a hand-rolled `Navigator.push` of an opaque route needs nothing — see ROUTE COVER above),
//     calls this itself:
//
//       // when the full-screen player is opened over the widget-hosting screen:
//       LivebuyWidgetVisibility.setWidgetsCovered(true);
//       // when it is dismissed:
//       LivebuyWidgetVisibility.setWidgetsCovered(false);
//
//     Map true/false to "is the home ACTUALLY covered full-screen". A bare non-collapsible player has
//     NO floating phase, so mapping from `presentedVideo != null` is exactly correct THERE. But if the
//     host hand-rolls its own minimize/floating, do NOT map from `presentedVideo != null` (it stays
//     non-null while floating -> would OVER-pause the then-visible home previews) — distinguish
//     full-screen vs collapsed. (The collapsible presenter already avoids this over-pause by phase.)
//
// Backward compatible: when nothing opts in (no presenter, host never calls `setWidgetsCovered`),
// `notCovered` stays permanently true, so the play-gate degrades to the self-sufficient axes
// (`foreground && onScreen`, plus the route axis since rb-flutter-widget-preview-route-cover-release)
// and behaviour is byte-for-byte identical to before this bridge (the residual NON-route gap still
// exists when unwired — the SDK's own axes cannot detect a non-route z-order cover, so the SDK does
// NOT claim to cover it unaided; that covered detection is the presenter's, or a manual host's,
// responsibility, and is why this host signal exists).
//
// STATEFUL LEVEL, not a stateless edge (the key difference from a one-shot bridge like PiP): "being
// covered" is a persistent visibility LEVEL. A preview that only mounts DURING a covered period
// (e.g. the full-screen player is already open and the home screen rebuilds a card underneath) must
// immediately know the current state is covered so it does NOT play. So this singleton RETAINS the
// current `_covered` value and `register` REPLAYS it to a newly-mounted widget on subscription.
//
// Main-thread-only contract (host calls on the main isolate + `LoopingVideoView` register/unregister
// run in `initState`/`dispose` on the main isolate), so no locking; fan-out iterates a `.toList()`
// snapshot to tolerate a listener mutating the set during dispatch.

/// Opt-in bridge for declaring whether the screen hosting Livebuy widget previews is currently
/// COVERED by a NON-route overlay (e.g. a full-screen player stacked over it). Feeds the third axis
/// (`notCovered`) of every mounted [LoopingVideoView]'s play-gate. NOT for `Navigator.push`: an
/// opaque route cover is detected by the preview itself from `TickerMode` (its fourth axis), and
/// declaring it here would also cover the pushed page's own previews — see the ROUTE COVER note in
/// the file header for rationale.
///
/// Most hosts do NOT touch this directly: the drop-in collapsible presenter `CollapsibleLivebuyPlayer`
/// owns [setWidgetsCovered] and drives it by phase (`covered <=> full`). Only a host on the BARE
/// (non-collapsible) `LivebuyPlayer` or a fully hand-rolled non-route cover calls it — see the file
/// header for both paths and the `presentedVideo != null` caveat.
class LivebuyWidgetVisibility {
  LivebuyWidgetVisibility._();

  /// The current covered LEVEL (retained so late-mounting widgets can be replayed). `false` = not
  /// covered = the pre-bridge default.
  static bool _covered = false;

  static final Set<void Function(bool)> _listeners = <void Function(bool)>{};

  /// Host: declare whether the screen hosting the widget previews is currently covered (`true` =
  /// covered by another route / full-screen overlay, invisible to the user). EDGE-TRIGGERED — only
  /// fans out when the value actually changes (no churn). Safe to call in any state.
  static void setWidgetsCovered(bool covered) {
    if (_covered == covered) return;
    _covered = covered;
    // Snapshot fan-out: a listener may register/unregister during dispatch.
    for (final listener in _listeners.toList()) {
      listener(covered);
    }
  }

  /// Subscribe [listener] and IMMEDIATELY replay the current [_covered] level to it, so a widget
  /// that mounts while already covered applies the pause at once. Called by [LoopingVideoView] on
  /// `initState`.
  static void register(void Function(bool) listener) {
    _listeners.add(listener);
    listener(_covered);
  }

  /// Unsubscribe [listener] (safe no-op if it was never registered). Called on `dispose`.
  static void unregister(void Function(bool) listener) {
    _listeners.remove(listener);
  }

  /// Test-only: clear all listeners and reset the covered level to `false`.
  static void resetForTesting() {
    _listeners.clear();
    _covered = false;
  }
}
