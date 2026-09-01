import 'dart:async';

import 'package:flutter/material.dart';

import 'loading_mark_frame_sequence.dart';

// LoadingMarkAnimationView — Flutter `.loading` brand PNG-sequence loader.
//
// Spec: `reference-ui-rendering/spec.md`
//   § "Flutter reference-ui `.loading` 品牌動畫改用 PNG 序列幀播放"
// Design: `rb-flutter-loading-mark-png-sequence` design.md 決策 1-4.
// Change: rb-flutter-loading-mark-png-sequence.
// Parity: iOS `LoadingMarkAnimationView.swift` / Android
//   `LoadingMarkAnimationView.kt` (both `Timer`/`delay`-driven discrete frame
//   switching over the same locked timeline).
//
// Plays the 17-frame brand loading-mark PNG sequence (500×500 RGBA, byte-identical
// to `ios/Sources/LivebuyReferenceUI/Resources/LoadingMark/`): the "!" mark growing
// in, combined with the "L" mark's 3D flip. Replaces the generic procedural
// `StartScreenView._spinnerRing()` call in `.loading`'s `_loadingScreen()`.
//
// TIMING MECHANISM — `Timer.periodic` (NOT `AnimationController..repeat()`):
// empirically verified via a throwaway probe test (apply-time, not part of this
// change) that `Timer.periodic`-driven `setState` neither (a) trips flutter_test's
// pending-timer checks when a test ends without explicitly unmounting the widget,
// nor (b) hangs `tester.pumpAndSettle()` — unlike a `Ticker`-backed
// `AnimationController.repeat()`, which re-registers a new scheduled frame on every
// tick and is a well-known cause of `pumpAndSettle()` timeouts for infinite
// animations. See design.md 決策 1.
//
// All 17 frames are precached once via [precacheImage] in [didChangeDependencies] —
// not lazily decoded per frame (design.md 決策 2; ~17MB unpacked, released via
// Flutter's normal image-cache LRU once this widget leaves the tree on `.loading`
// phase exit).
class LoadingMarkAnimationView extends StatefulWidget {
  const LoadingMarkAnimationView({super.key, this.size = 76});

  /// Rendered width/height — matches the `_spinnerRing()` call site it replaces
  /// (`StartScreenView`'s `loading` branch, 76×76).
  final double size;

  @override
  State<LoadingMarkAnimationView> createState() =>
      _LoadingMarkAnimationViewState();

  /// Test-only: force-cancels every currently-live instance's [Timer].
  /// Production code never calls this.
  ///
  /// Exists because `flutter_test`'s `AutomatedTestWidgetsFlutterBinding`
  /// asserts NO `Timer` is left pending at test end, regardless of which widget
  /// owns it (`binding.dart` `_verifyInvariants`: `!timersPending`) — and a
  /// documented, out-of-scope CORE limitation (`LivebuyPlayerCore.dispose()`
  /// reading an uninitialized `late _methodChannel` in the test harness, see
  /// `test/container/livebuy_player_container_test.dart`) can throw mid-way
  /// through an element-tree unmount cascade, which skips a LATER sibling's
  /// `dispose()` in the SAME pass (Flutter's teardown does not individually
  /// try/catch each descendant). This widget disposes cleanly in every OTHER
  /// scenario (see its own widget tests) — this hook is a narrowly-scoped
  /// test-harness safety net for that one pre-existing core interaction, not a
  /// production behavior change.
  @visibleForTesting
  static void cancelAllTimersForTesting() {
    for (final timer in List<Timer>.of(_LoadingMarkAnimationViewState._activeTimersForTesting)) {
      timer.cancel();
    }
    _LoadingMarkAnimationViewState._activeTimersForTesting.clear();
  }
}

class _LoadingMarkAnimationViewState extends State<LoadingMarkAnimationView> {
  static final List<String> _framePaths = List.generate(
    LoadingMarkFrameSequence.frameCount,
    LoadingMarkFrameSequence.assetPathForFrame,
  );

  /// Registry backing [LoadingMarkAnimationView.cancelAllTimersForTesting].
  /// Production code only ever adds/removes from this set — it never reads it.
  static final Set<Timer> _activeTimersForTesting = <Timer>{};

  /// The frame currently displayed. Driven by [_timer]; only reassigned when the
  /// computed index actually changes (avoids redundant rebuilds).
  int _currentIndex = 0;

  /// The active frame-clock timer, owned for the lifetime this widget is
  /// mounted. Started in [initState], cancelled in [dispose].
  Timer? _timer;

  /// Anchors elapsed-time lookups to when this widget appeared (not epoch), so
  /// [LoadingMarkFrameSequence.frameIndex] always sees "elapsed since loop
  /// start", matching the iOS/Android `startTicking()` convention.
  final Stopwatch _stopwatch = Stopwatch();

  /// Guards [_precacheAllFrames] to run exactly once (`didChangeDependencies`
  /// can be called more than once per widget lifetime).
  bool _precached = false;

  /// Poll interval — ~60Hz, comfortably oversampling the shortest (34ms) frame
  /// window so no frame is silently skipped under normal conditions.
  static const Duration _tickInterval = Duration(milliseconds: 16);

  @override
  void initState() {
    super.initState();
    _stopwatch.start();
    final timer = Timer.periodic(_tickInterval, (_) => _tick());
    _timer = timer;
    _activeTimersForTesting.add(timer);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precached) {
      _precached = true;
      _precacheAllFrames();
    }
  }

  @override
  void dispose() {
    final timer = _timer;
    if (timer != null) {
      timer.cancel();
      _activeTimersForTesting.remove(timer);
    }
    _timer = null;
    _stopwatch.stop();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final index = LoadingMarkFrameSequence.frameIndex(_stopwatch.elapsed);
    if (index != _currentIndex) {
      setState(() => _currentIndex = index);
    }
  }

  void _precacheAllFrames() {
    for (final path in _framePaths) {
      precacheImage(AssetImage(path), context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _framePaths[_currentIndex],
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
    );
  }
}
