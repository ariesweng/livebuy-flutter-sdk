import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../testing/lb_test_keys.dart';
import 'live_buy_widget_visibility.dart';

// MARK: - LoopingVideoView (rb-flutter-widget-card-looping-preview)
//
// Flutter parity of iOS `LoopingVideoView` (`AVQueuePlayer` + `AVPlayerLooper`) / Android media3
// `LoopingVideoView` / RN `LoopingVideoView`. A muted, control-free, infinitely-looping video that
// fills its parent (`BoxFit.cover` = resizeAspectFill). Used by `CarouselCardView` for the live
// card `LBVideoItem.preview` animated thumbnail.
//
// `video_player` is a federated Flutter plugin (auto-registers on iOS/Android in consumer apps).
// Until the controller is initialized — and on any load error — it renders nothing (transparent),
// so the card's underlying placeholder shows through. It is NEVER built on the `live == false`
// (demo / golden) path, so golden baselines stay byte-stable.
//
// MARK: - BACKGROUND / OFF-SCREEN DECODE STOP (flutter-refui-widget-preview-lifecycle-pause)
//
// Flutter parity of the "widget preview half" of Android `android-refui-player-lifecycle-pause`.
// `video_player` (Android → ExoPlayer) does NOT auto-pause in the background, and the widget uses
// non-lazy `Row` / `Column` layouts (golden determinism — see the spec's "MUST NOT use ListView /
// GridView" lesson), so off-screen cards stay mounted and keep decoding. A list of N live previews
// therefore = N decoders burning CPU in the background / off-screen — the same source that measured
// ~150% background CPU on the Android consumer app.
//
// Two gaps closed here:
//   (A) app background — a `WidgetsBindingObserver`: any non-`resumed` `AppLifecycleState`
//       (`inactive` / `hidden` / `paused` / `detached`) is treated as NOT-foreground → pause;
//       `resumed` → resume (only if the card is also on-screen).
//   (B) off-screen — a `VisibilityDetector`: `visibleFraction == 0` → off-screen → pause;
//       `> 0` → on-screen → resume (only if the app is also foreground).
//
// MARK: - HOST-COVER PAUSE (flutter-refui-widget-host-visibility-pause)
//
//   (C) tab-cover — a `notCovered` axis fed by the opt-in host bridge `LivebuyWidgetVisibility`.
//       When the host keeps the widget-hosting screen mounted in the nav tree and merely COVERS it
//       with another route (most typically a full-screen live player overlay), the card stays
//       laid-out (`visibleFraction` stays non-zero) and the app stays `resumed` — so BOTH (A) and
//       (B) fail and the previews keep decoding under the covering player. The SDK cannot
//       self-detect z-order cover from the widget layer (coordinates on-screen, app `resumed`);
//       only the host's navigation layer knows. `LivebuyWidgetVisibility.setWidgetsCovered(...)` is
//       the opt-in entry the host feeds it into (Dart parity of Android `LivebuyWidgetVisibility`).
//
// The three signals fold into ONE unified `foreground && onScreen && notCovered` gate
// (`PreviewPlaybackController`, edge-triggered, imperative — NOT dependent on a widget rebuild). A
// single gate (rather than independent observers) is deliberate: otherwise returning to the
// foreground / scrolling back would wake a card that is still off-screen OR still covered. Because
// `video_player`'s `play()` / `pause()` are no-ops before `initialize()` completes, the gate is
// `reapply()`-ed once the controller becomes ready (so a card that initializes while off-screen /
// backgrounded / covered does NOT start playing). This widget preview is NEVER PiP content and the
// Flutter full-screen player's PiP lives in the native layer (decoupled from this Dart widget's
// `AppLifecycleState`), so — unlike Android, which shares one Activity lifecycle — NO PiP guard is
// needed here. The "tab-cover" gap is now closed via the opt-in `LivebuyWidgetVisibility` bridge;
// when the host does NOT wire it, `notCovered` stays permanently true and behaviour is byte-for-byte
// identical to before (the residual gap still exists when unwired — NOT claimed as covered).

class LoopingVideoView extends StatefulWidget {
  final String uri;

  const LoopingVideoView({super.key, required this.uri});

  @override
  State<LoopingVideoView> createState() => _LoopingVideoViewState();
}

class _LoopingVideoViewState extends State<LoopingVideoView>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;

  /// A process-unique key for the `VisibilityDetector` (it requires globally-unique keys). Created
  /// once so a `uri`-change (`didUpdateWidget` → new controller) keeps the same visibility slot.
  final Key _visibilityKey = UniqueKey();

  /// The unified play-gate: the preview plays ONLY while the app is foreground AND the card is
  /// on-screen. `onPlay` / `onPause` drive the (init-guarded) `video_player` controller.
  late final PreviewPlaybackController _gate = PreviewPlaybackController(
    onPlay: () {
      final c = _controller;
      if (c != null && c.value.isInitialized) c.play();
    },
    onPause: () {
      final c = _controller;
      if (c != null && c.value.isInitialized) c.pause();
    },
  );

  /// Bridge listener: `covered` from the host maps to the gate's `notCovered` axis (inverted). Held
  /// as a field so the SAME closure identity can be unregistered on dispose.
  void _onCoveredChanged(bool covered) => _gate.setNotCovered(!covered);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Subscribe to the host-cover bridge. register() immediately replays the CURRENT covered level,
    // so a card that mounts while already covered pauses at once (stateful-level bridge).
    LivebuyWidgetVisibility.register(_onCoveredChanged);
    _setup();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only `resumed` counts as foreground; every other state (inactive / hidden / paused /
    // detached) pauses the muted preview — a safe, power-saving over-pause (resume is instant).
    _gate.setForeground(state == AppLifecycleState.resumed);
  }

  void _setup() {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.uri));
    _controller = c;
    c.initialize().then((_) {
      c.setLooping(true);
      c.setVolume(0);
      if (mounted) setState(() {});
      // The controller is only NOW ready to accept play/pause; apply the CURRENT gate decision
      // (a card that initialized while off-screen / backgrounded must NOT start playing).
      _gate.reapply();
    }).catchError((Object _) {
      // Stay transparent (placeholder shows through) on a load/decoder error.
    });
  }

  @override
  void didUpdateWidget(LoopingVideoView old) {
    super.didUpdateWidget(old);
    if (old.uri != widget.uri) {
      _controller?.dispose();
      _controller = null;
      _setup();
    }
  }

  @override
  void dispose() {
    LivebuyWidgetVisibility.unregister(_onCoveredChanged);
    WidgetsBinding.instance.removeObserver(this);
    // Drop the visibility slot so no `onVisibilityChanged` fires after dispose.
    VisibilityDetectorController.instance.forget(_visibilityKey);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Wrap BOTH the placeholder and the player in the visibility detector so on-screen tracking is
    // live even before the controller initializes.
    return VisibilityDetector(
      key: _visibilityKey,
      onVisibilityChanged: (info) => _gate.setOnScreen(info.visibleFraction > 0),
      child: _content(),
    );
  }

  Widget _content() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const SizedBox.expand(key: LbTestKeys.loopingPreview);
    }
    // BoxFit.cover (resizeAspectFill) over the full card area; the parent ClipRRect rounds it.
    return SizedBox.expand(
      key: LbTestKeys.loopingPreview,
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: c.value.size.width,
          height: c.value.size.height,
          child: VideoPlayer(c),
        ),
      ),
    );
  }
}

// MARK: - PreviewPlaybackController (unified foreground && onScreen && notCovered play-gate)
//
// A pure, framework-free state machine (no Flutter / `video_player` import → unit-testable in
// isolation, mirroring Android's `PreviewPlaybackController`). The preview should play ONLY when the
// app is foreground AND the card is on-screen AND it has not been declared covered by the host. The
// three axes fold into one `foreground && onScreen && notCovered` gate, applied edge-triggered so
// play / pause are not churned. Keeping ONE gate (rather than several independent observers) means
// returning to the foreground / scrolling back / uncovering never wakes a card that is still off on
// one of the other axes. `notCovered` defaults to `true` (= not covered = the pre-bridge behaviour),
// so a host that never feeds `LivebuyWidgetVisibility` sees the gate degrade to `foreground &&
// onScreen` exactly as before (flutter-refui-widget-host-visibility-pause).
class PreviewPlaybackController {
  PreviewPlaybackController({required this.onPlay, required this.onPause});

  /// Called (once, on the rising edge) when the preview SHOULD play.
  final VoidCallback onPlay;

  /// Called (once, on the falling edge) when the preview SHOULD pause.
  final VoidCallback onPause;

  bool _foreground = true;
  bool _onScreen = true;
  bool _notCovered = true;

  /// The last applied decision (`null` = never applied yet). Edge-trigger latch.
  bool? _applied;

  /// Whether the preview should currently be playing.
  bool get shouldPlay => _foreground && _onScreen && _notCovered;

  void setForeground(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    _apply();
  }

  void setOnScreen(bool value) {
    if (_onScreen == value) return;
    _onScreen = value;
    _apply();
  }

  /// The third axis: `true` = not covered (default / current behaviour); `false` = the host has
  /// declared the widget-hosting screen covered (fed via `LivebuyWidgetVisibility.setWidgetsCovered`
  /// → inverted). Edge-triggered.
  void setNotCovered(bool value) {
    if (_notCovered == value) return;
    _notCovered = value;
    _apply();
  }

  /// Force-(re)apply the current desired state. Used once the underlying player becomes ready — its
  /// earlier `onPlay` / `onPause` callbacks were no-ops while the controller was uninitialized, so
  /// the real state must be applied now that it can take effect.
  void reapply() {
    _applied = null;
    _apply();
  }

  void _apply() {
    final desired = shouldPlay;
    if (desired == _applied) return;
    _applied = desired;
    if (desired) {
      onPlay();
    } else {
      onPause();
    }
  }
}
