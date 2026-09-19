import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
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
//       with a NON-route overlay (most typically the collapsible presenter's full-screen live
//       player, stacked over the home screen), the card stays laid-out (`visibleFraction` stays
//       non-zero) and the app stays `resumed` — so BOTH (A) and (B) fail and the previews keep
//       decoding under the covering player. The SDK cannot self-detect that kind of z-order cover
//       from the widget layer (coordinates on-screen, app `resumed`, no route boundary); only the
//       host's presentation layer knows. `LivebuyWidgetVisibility.setWidgetsCovered(...)` is the
//       opt-in entry the host feeds it into (Dart parity of Android `LivebuyWidgetVisibility`).
//       An OPAQUE ROUTE cover is a different case and is now self-detected — see (D) below; the
//       host MUST NOT feed this bridge for a `Navigator.push`.
//
// The signals fold into ONE unified `foreground && onScreen && notCovered && routeVisible` gate
// (`PreviewPlaybackController`, edge-triggered, imperative — NOT dependent on a widget rebuild). A
// single gate (rather than independent observers) is deliberate: otherwise returning to the
// foreground / scrolling back would wake a card that is still off-screen OR still covered. Because
// `video_player`'s `play()` / `pause()` are no-ops before `initialize()` completes, the gate is
// `reapply()`-ed once the controller becomes ready (so a card that initializes while off-screen /
// backgrounded / covered / route-hidden does NOT start playing). This widget preview is NEVER PiP
// content and the Flutter full-screen player's PiP lives in the native layer (decoupled from this
// Dart widget's `AppLifecycleState`), so — unlike Android, which shares one Activity lifecycle — NO
// PiP guard is needed here. The non-route "tab-cover" gap is closed via the opt-in
// `LivebuyWidgetVisibility` bridge; when the host does NOT wire it, `notCovered` stays permanently
// true and behaviour is byte-for-byte identical to before (the residual non-route gap still exists
// when unwired — NOT claimed as covered).
//
// MARK: - AUDIO FOCUS (rb-flutter-widget-preview-no-audio-focus)
//
// Flutter-ONLY environment gap — the natives never had it. `video_player_android` (2.12.2,
// `VideoPlayer.java:99-102`) configures ExoPlayer with
// `setAudioAttributes(attrs, /* handleAudioFocus = */ !options.mixWithOthers)`, and a controller
// created WITHOUT `videoPlayerOptions` gets the default `mixWithOthers = false` → ExoPlayer itself
// requests `AUDIOFOCUS_GAIN` on every `play()`. The carousel / grid mount N (= 9 on the sample data)
// muted previews at once (non-lazy `Row` / `Column`, see above); each `play()` takes the focus, the
// previous holder receives `AUDIOFOCUS_LOSS`, and media3's `AudioFocusManager` answers LOSS with
// `PLAYER_COMMAND_DO_NOT_PLAY` → `playWhenReady = false`. Net effect on device (SM-G887F, Android
// 10): every card decodes its first frame and is then paused by the next card — "first frame, no
// motion". Evidence: system `MediaFocusControl` logged, for the example uid, 9 × `requestAudioFocus()`,
// 9 × `onAudioFocusChange(-1)` and 9 × `abandonAudioFocus()` inside a 60 ms window, and
// `dumpsys audio` kept only the last winner in the focus stack.
//
// Native Android `LoopingVideoView.kt` builds `ExoPlayer.Builder(context).build()` and never calls
// `setAudioAttributes` (ExoPlayer default `handleAudioFocus = false`), so N previews play together;
// iOS `LoopingPlayerUIView` (`AVQueuePlayer`) has no per-player focus at all. Parity therefore =
// "a muted preview does NOT take part in audio-focus arbitration": on Android the controller is
// created with `VideoPlayerOptions(mixWithOthers: true)` (`handleAudioFocus = false`), decided by
// the top-level pure function `previewPlayerOptionsFor(TargetPlatform)` below. iOS stays byte-for-
// byte unchanged (`null` → no options): there the same flag rewrites the app-global
// `AVAudioSession` category, which would interact with the SDK main player, and iOS shows no
// symptom. The `PreviewPlaybackController` gate, `setLooping` / `setVolume(0)` / `reapply()` and
// the `live && preview` build gating are NOT touched — this only removes the "paused back by the
// system right after `play()`" link.
//
// MARK: - ROUTE COVER (rb-flutter-widget-preview-route-cover-release)
//
//   (D) route-cover — a fourth, SELF-SUFFICIENT `routeVisible` axis read from `TickerMode`. When
//       an OPAQUE route (`MaterialPageRoute` is opaque by default) is pushed over the screen that
//       hosts the previews, Flutter's `Overlay` wraps every entry below the first opaque one in
//       `TickerMode(enabled: false)` once the push transition COMPLETES (`OverlayState.build` →
//       `_OverlayEntryWidget(tickerEnabled: false)`; `TransitionRoute._handleStatusChanged` sets
//       `overlayEntries.first.opaque = opaque` on `completed` and back to `false` the moment a pop
//       starts). `didChangeDependencies` reads `TickerMode.of(context)` and feeds it
//       to `gate.setRouteVisible(...)`. Neither the host nor the `LivebuyWidgetVisibility` bridge
//       is involved: this is the framework-given "covered by a route" signal — the Flutter analogue
//       of UIKit taking a pushed-over view controller's view out of the window (iOS example
//       `NavigationLink`) and of Compose leaving the composition (Android sample swaps the widget
//       surface in place, `showGrid = true`, so the carousel's `LoopingVideoView.kt` runs
//       `onDispose { exo.release() }`). Non-opaque routes (dialogs, modal bottom sheets,
//       `PageRouteBuilder(opaque: false)`) do NOT flip `TickerMode`, and correctly so — the
//       previews stay visible under them. NON-route overlays (the collapsible presenter's `Stack`
//       full-screen player, any hand-rolled overlay) are invisible to this axis: that is exactly
//       what the bridge (C) remains for, and the bridge itself is byte-for-byte unchanged.
//
//       Why the process-global bridge was the WRONG tool for a route push (SM-G887F / Android 10
//       evidence, 2026-09-18): the example's 「查看更多 ›」 called `setWidgetsCovered(true)` before
//       `Navigator.push`-ing the grid page. `register()` replays the current level to every newly
//       mounted `LoopingVideoView`, so the grid page's OWN cards mounted already-covered and
//       `reapply()`-ed straight into `pause()` — structurally never playing (4 visible grid cards,
//       0.00% pixel change across 2 s, with 0 audio-focus requests in the same window). A single
//       global level cannot express "widget-hosting screen covered by ANOTHER widget-hosting
//       screen"; the route axis is per-subtree by construction.
//
//       Android policy = RELEASE the controller while route-hidden, re-create when the route returns
//       (`previewDecoderPolicyFor`): `video_player_android` keeps its ExoPlayer — and the
//       `MediaCodec` hardware decoder it holds — alive while merely paused. Nine paused home
//       previews therefore still pinned nine decoders, and the grid's new controllers died with
//       `MediaCodec$CodecException: Failed to initialize OMX.qcom.video.decoder.avc, error
//       0xfffffff4` (2 players, 2 × `ExoPlaybackException`) → transparent forever (cover only).
//       Native Android releases on leaving the composition; the only way for a Flutter subtree that
//       is NOT disposed while covered to reach the same resource state is to dispose the controller
//       itself when the route hides and rebuild it when the route comes back. A card that MOUNTS
//       under a hidden route (release policy) does not create a controller at all until the route
//       is visible — `_setup()` therefore never runs from `initState`: under the `pause` policy it
//       runs from the first `didChangeDependencies`, under `release` from the first ON-SCREEN
//       visibility report while route-visible (see (E)). Every other platform only PAUSES on this
//       axis (keep-alive): AVFoundation has no comparable decoder-instance cap, iOS shows no
//       symptom, and its controller stays untouched. The bridge path (C) keeps its keep-alive pause
//       on every platform — release belongs to the route axis and, since (E), the off-screen axis.
//
//       Bounded `initialize()` retry (`previewInitRetryDelay`): during the ~300 ms push transition
//       the home decoders are NOT yet released (the covered route only flips once the transition
//       completes), so the grid's first attempts can still hit the decoder cap; on pop the same race
//       runs the other way. A failed controller is disposed (freeing whatever it did acquire) and,
//       while this widget is still mounted and a controller is allowed, re-created after 500 ms /
//       1 s / 2 s. The `Timer` is cancelled on `dispose()`, on route-cover under the release policy,
//       by the off-screen release (E) and on a `uri` change. After the last attempt the card stays
//       transparent (cover shows through) — exactly the pre-change fallback.
//
// MARK: - OFF-SCREEN DECODER RELEASE (rb-flutter-widget-preview-offscreen-decoder-release)
//
//   (E) off-screen — the SAME per-platform policy (`previewDecoderPolicyFor`) now also governs the
//       on-screen axis. (D) freed the COVERED page's decoders, but every card still created its
//       controller at mount and merely `pause()`d off-screen, and a paused `video_player_android`
//       controller keeps its `MediaCodec` decoder. The 「查看更多」 grid (`ScrollableVideoShopView` →
//       `VideoShopGridView(maxCards: null, autoLoadOnScroll: true)`, a render-ALL plain `Column`,
//       not lazy) mounts 9 cards on its first page and 18 after one load-more, all creating
//       controllers at once; the sample shop's widget has 8 pages × 9 = 65 videos, nearly all with
//       a `preview`, and the SM-G887F (Qualcomm) refuses roughly the 12th decoder with
//       `MediaCodec$CodecException: Failed to initialize OMX.qcom.video.decoder.avc, error
//       0xfffffff4` — every card past the budget exhausted its 3 retries and stayed on the cover.
//       The home carousel has the same shape: 9 cards, 3 visible, 6 off-screen decoders. Native
//       Android / iOS non-lazy containers build every player too (structurally the same cap) but
//       have no host report; this is Flutter `video_player` resource management with no native
//       template to copy — NOT a parity claim.
//
//       `release` (Android): a controller exists only while `routeVisible && on-screen`, where
//       on-screen is what the `VisibilityDetector` LAST REPORTED (`_onScreen`, `null` until the
//       first report). Mount creates nothing; the first `visibleFraction > 0` report creates
//       (`_setup()`); a `visibleFraction == 0` report arms a debounce
//       (`previewOffScreenReleaseDelay`, 1 s) whose expiry releases (`_release()`: pending retry
//       cancelled, failure count reset, `dispose()`, rebuild to the transparent fallback); a report
//       back on-screen before expiry cancels it and keeps the controller. A card that never becomes
//       visible never gets a report at all — `visibility_detector` (0.4.0+2,
//       `RenderVisibilityDetectorBase._fireCallback`) fires the FIRST callback only once a detector
//       is visible — which is exactly "no decoder for a card that was never seen". Route-cover
//       release stays IMMEDIATE (not debounced). `pause` (every other platform) is byte-for-byte the
//       previous behaviour: eager creation in the first `didChangeDependencies`, off-screen only
//       `pause()`.
//
//       First-frame flush: `VisibilityDetectorController.instance.updateInterval` defaults to
//       500 ms (`render_visibility_detector.dart` `_scheduleUpdate`: the composition callback of
//       the first paint arms `Timer(updateInterval)`), which would make every VISIBLE card's
//       preview start half a second late at mount. So, under `release`, `initState` registers one
//       post-frame callback that calls `VisibilityDetectorController.instance.notifyNow()` if no
//       report has arrived yet: `notifyNow` cancels that timer and runs the pending callbacks
//       synchronously, and this card's pending entry IS there by then because
//       `Layer.addCompositionCallback` fires inside `compositeFrame`, before post-frame callbacks.
//       It is a process-global flush — other detectors' pending reports are delivered earlier than
//       their interval, with the same values they would have carried — deliberately chosen over
//       changing the host-global `updateInterval` (not the SDK's setting to change) and over
//       accepting the 500 ms first-frame lag. The 1 s debounce (≈ two detector ticks) keeps a fast
//       fling from creating-then-destroying controllers for cards that merely pass through, while
//       still handing a decoder back within a second of its card leaving; the bounded retry (D)
//       absorbs the transient over-budget a long fling can still cause.

class LoopingVideoView extends StatefulWidget {
  final String uri;

  const LoopingVideoView({super.key, required this.uri});

  @override
  State<LoopingVideoView> createState() => _LoopingVideoViewState();
}

class _LoopingVideoViewState extends State<LoopingVideoView>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;

  /// The pending bounded `initialize()` retry (rb-flutter-widget-preview-route-cover-release), or
  /// `null` when none is scheduled. Cancelled by [_release] (dispose / route-cover release /
  /// off-screen release / `uri` change) so a retry can never outlive the lineage it was scheduled
  /// for.
  Timer? _retryTimer;

  /// Consecutive failed `initialize()` attempts of the CURRENT controller lineage. Indexes
  /// [previewInitRetryDelay]; reset to 0 on success and by [_release].
  int _initFailures = 0;

  /// The route-visible axis as last read from `TickerMode.of(context)` (`true` until the first
  /// `didChangeDependencies`).
  bool _routeVisible = true;

  /// The on-screen axis as LAST REPORTED by the `VisibilityDetector` (`visibleFraction > 0`), or
  /// `null` while no report has arrived (rb-flutter-widget-preview-offscreen-decoder-release). A
  /// card that has never been visible never receives a report (`visibility_detector` fires the
  /// first callback only for a visible detector), so `null` doubles as "never seen" — under the
  /// `release` policy no controller exists in that state. Deliberately distinct from the gate's
  /// optimistic `onScreen` default (`true`), which is untouched.
  bool? _onScreen;

  /// The pending off-screen release debounce (`release` policy only), or `null`. Armed by an
  /// off-screen report while a controller or a pending retry exists; cancelled by an on-screen
  /// report and by [_release].
  Timer? _offScreenTimer;

  /// A process-unique key for the `VisibilityDetector` (it requires globally-unique keys). Created
  /// once so a `uri`-change (`didUpdateWidget` → new controller) keeps the same visibility slot.
  final Key _visibilityKey = UniqueKey();

  /// The unified play-gate: the preview plays ONLY while the app is foreground AND the card is
  /// on-screen AND it is neither bridge-covered nor route-hidden. `onPlay` / `onPause` drive the
  /// (init-guarded) `video_player` controller.
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

  /// The per-platform decoder policy — see [previewDecoderPolicyFor]. Read on every use (not
  /// cached) so it follows `defaultTargetPlatform` exactly as the other call sites do.
  PreviewDecoderPolicy get _policy =>
      previewDecoderPolicyFor(defaultTargetPlatform);

  /// Whether a controller may exist right now: always under the `pause` policy; only while the
  /// route is visible AND the card was last reported on-screen under `release` (Android) — a card
  /// hidden under an opaque route, scrolled off-screen or never yet seen holds no decoder.
  bool get _controllerAllowed {
    switch (_policy) {
      case PreviewDecoderPolicy.pause:
        return true;
      case PreviewDecoderPolicy.release:
        return _routeVisible && _onScreen == true;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Subscribe to the host-cover bridge. register() immediately replays the CURRENT covered level,
    // so a card that mounts while already covered pauses at once (stateful-level bridge).
    LivebuyWidgetVisibility.register(_onCoveredChanged);
    // Deliberately NO `_setup()` here. `pause`: the controller is created from the first
    // `didChangeDependencies`, once the route-visible axis is known. `release`: from the first
    // ON-SCREEN visibility report — a card that mounts under a hidden route, off-screen, or that is
    // never seen must not allocate a decoder on Android. That first report is flushed at the end
    // of this very frame so a visible card does not wait out the detector's 500 ms interval.
    if (_policy == PreviewDecoderPolicy.release) {
      WidgetsBinding.instance.addPostFrameCallback(_flushFirstVisibilityReport);
    }
  }

  /// Post-frame (first frame after mount, `release` policy): if the `VisibilityDetector` has not
  /// reported yet, force its pending report out now instead of after
  /// `VisibilityDetectorController.instance.updateInterval` (500 ms by default). The report is
  /// pending by now because the detector's composition callback ran inside `compositeFrame`,
  /// before post-frame callbacks. `notifyNow()` is process-global: every other detector's pending
  /// report is delivered early too (same values, earlier) — see the class comment (E).
  void _flushFirstVisibilityReport(Duration _) {
    if (!mounted || _onScreen != null) return;
    VisibilityDetectorController.instance.notifyNow();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `TickerMode.of` establishes a dependency on the nearest `TickerMode`
    // (`dependOnInheritedWidgetOfExactType`), so this method re-runs every time the enclosing
    // route is covered by / uncovered from an opaque route. It is deprecated since Flutter 3.35 in
    // favour of `TickerMode.valuesOf(context).enabled` (Flutter >= 3.36), but this package's
    // `pubspec.yaml` floor (`flutter: ">=3.10.0"`) is far older and both build the very same
    // dependency, so `of` stays. TODO: switch to `valuesOf` once the package floor passes 3.35.
    // ignore: deprecated_member_use
    _syncRouteVisible(TickerMode.of(context));
  }

  /// Apply the route-visible axis: feed the gate, release the controller IMMEDIATELY (no
  /// debounce) while hidden under the `release` policy, and (re)create it when a controller is
  /// allowed but none exists and no retry is pending. Idempotent for a repeated same value.
  void _syncRouteVisible(bool visible) {
    _routeVisible = visible;
    if (!visible && _policy == PreviewDecoderPolicy.release) _release();
    _gate.setRouteVisible(visible);
    _setupIfAllowed();
  }

  /// The `VisibilityDetector` report: feed the gate (every policy, unchanged) and, under
  /// `release`, drive the controller's EXISTENCE — create on an on-screen report (cancelling a
  /// pending off-screen release), debounce-release after an off-screen one.
  void _onVisibilityChanged(bool visible) {
    _onScreen = visible;
    _gate.setOnScreen(visible);
    if (_policy != PreviewDecoderPolicy.release) return;
    if (visible) {
      _offScreenTimer?.cancel();
      _offScreenTimer = null;
      _setupIfAllowed();
    } else {
      _scheduleOffScreenRelease();
    }
  }

  /// Arm the off-screen release debounce ([previewOffScreenReleaseDelay]) if something exists to
  /// release (a controller, or a pending retry that would otherwise re-create one) and none is
  /// armed yet. Kept off the hot path for cards that were never seen (nothing to release).
  void _scheduleOffScreenRelease() {
    if (_offScreenTimer != null) return;
    if (_controller == null && _retryTimer == null) return;
    _offScreenTimer = Timer(previewOffScreenReleaseDelay(), _onOffScreenReleaseDue);
  }

  /// The off-screen debounce expired with the card still not allowed a controller: release the
  /// lineage and rebuild so the disposed controller's `VideoPlayer` leaves the tree (transparent
  /// fallback — the card is off-screen, nothing visible changes). Unlike the route path there is
  /// no build following this call, hence the explicit `setState`.
  void _onOffScreenReleaseDue() {
    _offScreenTimer = null;
    if (!mounted || _controllerAllowed) return;
    _release();
    setState(() {});
  }

  /// Create a controller if one may exist and none does (and no retry is pending) — the single
  /// re-entry point for every axis change that can turn "not allowed" into "allowed".
  void _setupIfAllowed() {
    if (_controllerAllowed && _controller == null && _retryTimer == null) {
      _setup();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only `resumed` counts as foreground; every other state (inactive / hidden / paused /
    // detached) pauses the muted preview — a safe, power-saving over-pause (resume is instant).
    _gate.setForeground(state == AppLifecycleState.resumed);
  }

  void _setup() {
    assert(_controller == null && _retryTimer == null);
    final c = VideoPlayerController.networkUrl(
      Uri.parse(widget.uri),
      videoPlayerOptions: previewPlayerOptionsFor(defaultTargetPlatform),
    );
    _controller = c;
    c.initialize().then((_) {
      // Superseded (uri change / route-cover release) while initializing → nothing to apply.
      if (!identical(_controller, c)) return;
      _initFailures = 0;
      c.setLooping(true);
      c.setVolume(0);
      if (mounted) setState(() {});
      // The controller is only NOW ready to accept play/pause; apply the CURRENT gate decision
      // (a card that initialized while off-screen / backgrounded / covered must NOT start playing).
      _gate.reapply();
    }).catchError((Object _) {
      // Stay transparent (placeholder shows through) on a load/decoder error; release the failed
      // controller and retry a bounded number of times while mounted and route-visible.
      _onInitFailed(c);
    });
  }

  /// `initialize()` rejected for [failed]: dispose it (on Android a half-created ExoPlayer still
  /// pins a decoder) and, while this widget is mounted and a controller is allowed (route-visible
  /// and, under `release`, on-screen), schedule a bounded re-creation. The card stays transparent
  /// during and after the retries.
  void _onInitFailed(VideoPlayerController failed) {
    if (!identical(_controller, failed)) return; // already released / replaced
    _controller = null;
    failed.dispose();
    if (!mounted || !_controllerAllowed) return;
    final delay = previewInitRetryDelay(_initFailures);
    if (delay == null) return; // retry budget exhausted → keep the pre-change fallback
    _initFailures += 1;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (!mounted || !_controllerAllowed || _controller != null) return;
      _setup();
    });
  }

  /// Tear down the current controller lineage: cancel a pending retry and a pending off-screen
  /// release (nothing would be left for it to release), dispose the controller and forget its
  /// failure count. Used by the route-cover and off-screen `release` paths, a `uri` change and
  /// `dispose()`. No `setState` here: the route / `uri` call sites are followed by a rebuild anyway
  /// (`didChangeDependencies` / `didUpdateWidget` both precede `build`, which re-evaluates
  /// `_content()` to the transparent fallback), the off-screen path rebuilds itself
  /// ([_onOffScreenReleaseDue]), and `dispose()` must not mark a defunct element.
  void _release() {
    _offScreenTimer?.cancel();
    _offScreenTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _initFailures = 0;
    final c = _controller;
    if (c == null) return;
    _controller = null;
    c.dispose();
  }

  @override
  void didUpdateWidget(LoopingVideoView old) {
    super.didUpdateWidget(old);
    if (old.uri != widget.uri) {
      _release();
      _setupIfAllowed();
    }
  }

  @override
  void dispose() {
    LivebuyWidgetVisibility.unregister(_onCoveredChanged);
    WidgetsBinding.instance.removeObserver(this);
    // Drop the visibility slot so no `onVisibilityChanged` fires after dispose.
    VisibilityDetectorController.instance.forget(_visibilityKey);
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Wrap BOTH the placeholder and the player in the visibility detector so on-screen tracking is
    // live even before the controller initializes (and, under `release`, before it even exists).
    return VisibilityDetector(
      key: _visibilityKey,
      onVisibilityChanged: (info) => _onVisibilityChanged(info.visibleFraction > 0),
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

// MARK: - previewPlayerOptionsFor (rb-flutter-widget-preview-no-audio-focus)

/// The `VideoPlayerOptions` the muted looping preview controller is created with, decided per
/// platform. A top-level pure function (no binding / no widget) so the decision is unit-testable in
/// isolation (`preview_player_options_test.dart`); `_setup()` is its only call site and feeds it
/// `defaultTargetPlatform`.
///
/// * `TargetPlatform.android` → `VideoPlayerOptions(mixWithOthers: true)`. `video_player_android`
///   turns this into `exoPlayer.setAudioAttributes(attrs, /* handleAudioFocus = */ false)`: the
///   preview no longer requests system audio focus, and is no longer paused by media3's
///   `AudioFocusManager` when another preview / player takes the focus. With the default
///   (`mixWithOthers = false`) each of N muted cards requests `AUDIOFOCUS_GAIN` on `play()`, every
///   grant sends `AUDIOFOCUS_LOSS` to the previous holder and forces its `playWhenReady = false`, so
///   N-1 cards freeze on their first frame. Native Android `LoopingVideoView.kt` never handles audio
///   focus (ExoPlayer default), so this IS the parity behaviour.
/// * Every other platform → `null` (no options → byte-for-byte the pre-change controller). On iOS
///   the same flag makes `video_player_avfoundation` rewrite the app-global `AVAudioSession`
///   category (`playback` + `mixWithOthers`), which would interact with the SDK main player's
///   `.playback` session; iOS `AVQueuePlayer` previews have no per-player focus and show no
///   symptom, so it MUST NOT be applied there.
VideoPlayerOptions? previewPlayerOptionsFor(TargetPlatform platform) {
  if (platform == TargetPlatform.android) {
    return VideoPlayerOptions(mixWithOthers: true);
  }
  return null;
}

// MARK: - previewDecoderPolicyFor / previewInitRetryDelay / previewOffScreenReleaseDelay
// (rb-flutter-widget-preview-route-cover-release /
//  rb-flutter-widget-preview-offscreen-decoder-release)

/// What `LoopingVideoView` does with its `VideoPlayerController` while the card is not showing:
/// hidden under an opaque route (`routeVisible == false`, read from `TickerMode`) OR scrolled
/// off-screen (`VisibilityDetector` reported `visibleFraction == 0`). ONE policy governs both axes
/// (formerly `PreviewRouteCoverPolicy`, route-only).
enum PreviewDecoderPolicy {
  /// Dispose the controller (freeing its hardware decoder) when the route hides — immediately —
  /// or once the card has been off-screen for [previewOffScreenReleaseDelay], and re-create it
  /// when the card is route-visible AND on-screen again; a card that mounts hidden / off-screen,
  /// or that is never seen, creates none until then.
  release,

  /// Keep the controller alive (created eagerly at mount) and only pause it on both axes — the
  /// same keep-alive pause the `LivebuyWidgetVisibility` bridge cover applies.
  pause,
}

/// The decoder policy for the muted looping preview, decided per platform. A top-level pure
/// function (no binding / no widget), unit-tested in `preview_decoder_policy_test.dart`;
/// `_LoopingVideoViewState._policy` is its only call site and feeds it `defaultTargetPlatform`.
///
/// * `TargetPlatform.android` → [PreviewDecoderPolicy.release]. `video_player_android` keeps a
///   paused ExoPlayer's `MediaCodec` decoder allocated, and the device has a hard cap on decoder
///   instances (≈ 11–12 on the SM-G887F / Android 10): nine paused home previews left the pushed
///   grid page's new controllers failing with `Failed to initialize OMX.qcom.video.decoder.avc,
///   error 0xfffffff4`, and the grid's own 18 cards after one load-more exceeded the cap on their
///   own. Native Android releases the ExoPlayer on leaving the composition
///   (`onDispose { exo.release() }`), so releasing on the route axis IS the parity resource
///   state; releasing on the off-screen axis is a Flutter-only resource-management hardening
///   (native non-lazy containers keep every player, without a host report).
/// * Every other platform → [PreviewDecoderPolicy.pause]. AVFoundation has no comparable
///   decoder-instance cap and iOS shows no symptom; the controller is kept alive and both axes only
///   pause / resume it, byte-for-byte the bridge-cover behaviour.
PreviewDecoderPolicy previewDecoderPolicyFor(TargetPlatform platform) {
  if (platform == TargetPlatform.android) {
    return PreviewDecoderPolicy.release;
  }
  return PreviewDecoderPolicy.pause;
}

/// How long a card must stay off-screen (`release` policy) before its controller is released
/// (rb-flutter-widget-preview-offscreen-decoder-release). 1 s ≈ two `visibility_detector` ticks
/// at the default 500 ms `updateInterval`: a card flung past is not created-then-destroyed (it is
/// usually never even reported), while a decoder is handed back within a second of its card
/// leaving the viewport — on the SM-G887F the whole budget is ~11–12 decoders, so holding
/// off-screen ones longer (2 s+) would starve the cards scrolling in. A top-level pure function,
/// unit-tested in `preview_decoder_policy_test.dart`; `_scheduleOffScreenRelease` is its only
/// call site.
Duration previewOffScreenReleaseDelay() => const Duration(seconds: 1);

/// The back-off before the `attempt`-th re-creation of a preview controller whose `initialize()`
/// rejected (`attempt` = how many retries have ALREADY been made in the current lineage: 0 → the
/// first retry). `null` once the budget (three retries: 500 ms, 1 s, 2 s) is exhausted — the card
/// then stays transparent (cover shows through) exactly as before the retry existed. A top-level
/// pure function, unit-tested in `preview_decoder_policy_test.dart`.
Duration? previewInitRetryDelay(int attempt) {
  switch (attempt) {
    case 0:
      return const Duration(milliseconds: 500);
    case 1:
      return const Duration(seconds: 1);
    case 2:
      return const Duration(seconds: 2);
    default:
      return null;
  }
}

// MARK: - PreviewPlaybackController
// (unified foreground && onScreen && notCovered && routeVisible play-gate)
//
// A pure, framework-free state machine (no Flutter / `video_player` import → unit-testable in
// isolation, mirroring Android's `PreviewPlaybackController`). The preview should play ONLY when the
// app is foreground AND the card is on-screen AND it has not been declared covered by the host AND
// its route is not hidden under an opaque route. The four axes fold into one
// `foreground && onScreen && notCovered && routeVisible` gate, applied edge-triggered so play /
// pause are not churned. Keeping ONE gate (rather than several independent observers) means
// returning to the foreground / scrolling back / uncovering / popping back never wakes a card that
// is still off on one of the other axes. `notCovered` defaults to `true` (= not covered = the
// pre-bridge behaviour), so a host that never feeds `LivebuyWidgetVisibility` sees the gate degrade
// to `foreground && onScreen && routeVisible` (flutter-refui-widget-host-visibility-pause);
// `routeVisible` defaults to `true` and is fed from `TickerMode` by the widget itself
// (rb-flutter-widget-preview-route-cover-release).
class PreviewPlaybackController {
  PreviewPlaybackController({required this.onPlay, required this.onPause});

  /// Called (once, on the rising edge) when the preview SHOULD play.
  final VoidCallback onPlay;

  /// Called (once, on the falling edge) when the preview SHOULD pause.
  final VoidCallback onPause;

  bool _foreground = true;
  bool _onScreen = true;
  bool _notCovered = true;
  bool _routeVisible = true;

  /// The last applied decision (`null` = never applied yet). Edge-trigger latch.
  bool? _applied;

  /// Whether the preview should currently be playing.
  bool get shouldPlay => _foreground && _onScreen && _notCovered && _routeVisible;

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

  /// The fourth axis: `true` = the enclosing route is visible (default); `false` = it is hidden
  /// under an opaque route (fed from `TickerMode.of(context)` by `LoopingVideoView`
  /// itself — no host involvement). Edge-triggered.
  void setRouteVisible(bool value) {
    if (_routeVisible == value) return;
    _routeVisible = value;
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
