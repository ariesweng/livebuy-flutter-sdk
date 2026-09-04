import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart' show LBVideoItem, LivebuySDK;

import '../reference_ui_theme.dart';
import '../widget/live_buy_widget_visibility.dart';
import 'live_buy_player.dart';
import 'live_entry_close_gate.dart' show LiveEntryCloseGate;
import 'live_entry_position_timing.dart'
    show LBFloatingEntryPosition, lbLiveEntryClampDx;
import 'reference_ui_design.dart';

// CollapsibleLivebuyPlayer — collapsible player presenter (Flutter, rb-flutter-collapsible-player).
//
// Parity: iOS `Container/LivebuyPlayerPresenter.swift` (`livebuyPlayer(video:)`) — the turnkey
// "full-screen player + minimize → bottom-right floating preview" container. Four-platform
// parity: Flutter / Android / RN previously had NO collapsible presenter (minimize→floating was
// host-owned and unimplemented in the samples); this builds it.
//
// COMPOSITION: an OVERLAY widget the host stacks ABOVE its app shell (so the floating preview
// survives tab switches — issue 3). `video != null` → the turnkey `LivebuyPlayer` is composed
// FULL-SCREEN; the minimize button (`config.onMinimize`, taken over here) COLLAPSES it to a
// bottom-right `FloatingWidgetView` preview card.
//
// KEEP-ALIVE (issue 5, iOS parity): the `LivebuyPlayer` stays MOUNTED the whole time a session
// exists — minimize only HIDES it (`Opacity(0)` + `IgnorePointer`), it is NOT torn down — so
// playback continues while minimized and tapping the card to restore is an instant RESUME
// (no reload). DRAG/TAP (issue 4): the floating card is draggable to reposition (clamped
// on-screen) and a TAP restores; the drag pan recognizer and the card's own tap are separated.
//
// The pure phase / reopen / clamp helpers are extracted (testable) — mirror iOS
// `collapsiblePhase` / `shouldReopenOnVideoChange` / `clampFloatingOffset`.

/// The presentation phase of a collapsible player (parity iOS `CollapsiblePlayerPhase`).
enum CollapsiblePlayerPhase { closed, full, floating }

/// Pure phase derivation: no video → closed; minimized → floating; else full.
CollapsiblePlayerPhase collapsiblePhase({required bool hasVideo, required bool isMinimized}) {
  if (!hasVideo) return CollapsiblePlayerPhase.closed;
  return isMinimized ? CollapsiblePlayerPhase.floating : CollapsiblePlayerPhase.full;
}

/// Whether the presenter should declare the home-screen widget previews COVERED (fed into the
/// opt-in `LivebuyWidgetVisibility` bridge's `notCovered` third axis). Contract:
/// `covered ⟺ phase == full ⟺ (hasVideo && !isMinimized)` — reuses [collapsiblePhase] so there is
/// no second source of truth. Pure (parity iOS `presenterWidgetCovered`, flutter-refui-presenter-
/// widget-cover-by-phase).
///
/// Only the FULL phase declares cover: the keep-alive full-screen player keeps hardware-decoding
/// while the FULL overlay is visible — it is the hardware-decoder contention source, so the home
/// previews must yield the decoder then. FLOATING hides the full player (`Opacity(0)`) down to a
/// single tiny card, so releasing the N home previews then costs far less than "full-screen live +
/// N previews"; CLOSED has no session. Hence `floating`/`closed` → NOT covered.
bool presenterWidgetCovered({required bool hasVideo, required bool isMinimized}) =>
    collapsiblePhase(hasVideo: hasVideo, isMinimized: isMinimized) == CollapsiblePlayerPhase.full;

/// Whether a change of the bound video's id should auto-restore the full-screen player: true
/// ONLY when a new (non-null) video arrives while minimized (the host swapped in another video).
/// Restoring from the floating card keeps the SAME id (only flips minimized) → returns false.
/// Pure (parity iOS / Android `shouldReopenOnVideoChange`).
bool shouldReopenOnVideoChange({required String? newVideoId, required bool isMinimized}) {
  return newVideoId != null && isMinimized;
}

/// Whether an incoming `video.id` seen in `didUpdateWidget` is merely an ECHO of an in-place
/// switch this presenter already self-reported via `onVideoSwitchedItem` → `onVideoChanged`
/// (rb-flutter-collapsible-player-switch-sync-and-reopen-signal), as opposed to a genuine
/// externally-initiated swap (e.g. tapping a different carousel card). `onVideoSwitchedItem`
/// advances `_shownVideo` to the switched item's id BEFORE calling `onVideoChanged`, whose
/// notification then round-trips through the host and arrives back here as a new `video` prop —
/// so by the time `didUpdateWidget` runs, `newVideoId` already equals what this presenter itself
/// knows it is showing ([shownVideoId]). A genuine host-initiated swap never pre-advances
/// `_shownVideo`, so its incoming id differs. Only a non-echo (or an `openSignal`-driven re-tap of
/// the same video) is eligible to trigger [shouldReopenOnVideoChange] — an echo MUST NOT, or
/// minimizing during an in-place switch would unexpectedly snap back to full-screen. Pure.
bool isVideoChangeSwitchEcho({required String? newVideoId, required String? shownVideoId}) {
  return newVideoId != null && newVideoId == shownVideoId;
}

/// Clamp the floating card's committed-plus-live drag offset so it can be dragged to reposition
/// but never pushed off-screen. Offsets are SCREEN coordinates measured from the resting corner
/// (resting offset `Offset.zero`; `+x` right, `+y` down). Pure (parity iOS `clampFloatingOffset`).
///
/// [position] selects WHICH bottom corner the card rests in and therefore which way it may be
/// dragged (rb-flutter-floating-entry-position-timing). It is OPTIONAL and defaults to
/// [LBFloatingEntryPosition.rightBottom], so the pre-existing call sites
/// ([CollapsibleLivebuyPlayer]'s own floating preview) and their tests are bit-for-bit unchanged:
///
/// ```text
/// rightBottom : dx ∈ [min(0, -span), 0]   靜止在右，只能往左
/// leftBottom  : dx ∈ [0, max(0,  span)]   靜止在左，只能往右
/// dy          ∈ [min(0, -spanY), 0]       兩個落點相同(皆錨底)
/// 其中 span = 容器邊長 − 卡片邊長 − inset(同一個量，非退化時左右對稱)
/// ```
///
/// 水平夾取委派給 pure [lbLiveEntryClampDx]，該處記錄了「右下分支語意逐位元不變（字面已改寫並換檔）」與 Dart 的
/// `-0.0` 語意(本函式**不宣稱**絕不產生 `-0.0`；在 Flutter 那既無行為影響也不會造成測試假紅)。
Offset clampFloatingOffset({
  required Offset committed,
  required Offset translation,
  required Size cardSize,
  required Size containerSize,
  required Offset inset,
  LBFloatingEntryPosition position = LBFloatingEntryPosition.rightBottom,
}) {
  final desiredX = committed.dx + translation.dx;
  final desiredY = committed.dy + translation.dy;
  final minY = math.min(0.0, -(containerSize.height - cardSize.height - inset.dy));
  final clampedX = lbLiveEntryClampDx(
    position: position,
    desiredDx: desiredX,
    span: containerSize.width - cardSize.width - inset.dx,
  );
  final clampedY = math.max(minY, math.min(0.0, desiredY));
  return Offset(clampedX, clampedY);
}

/// The turnkey collapsible player OVERLAY: full-screen [LivebuyPlayer] for the bound [video],
/// with a built-in minimize → bottom-right floating preview. Place it in a root `Stack` ABOVE
/// the host's app shell so the floating preview survives navigation (issue 3). `video == null`
/// → renders nothing.
class CollapsibleLivebuyPlayer extends StatefulWidget {
  /// The host's session source of truth: non-null → present; null → fully closed.
  final LBVideoItem? video;

  /// Called when the presenter clears the session (close / fatal dismiss) → host sets `video` null.
  final ValueChanged<LBVideoItem?> onVideoChanged;

  /// The host's player config. The presenter OWNS `onMinimize` / `onDismiss`; every other seam
  /// passes through unchanged.
  final LivebuyPlayerConfig config;

  /// Resolved reference-ui theme for the floating card.
  final ReferenceUITheme theme;

  /// Open-intent token (`rb-flutter-collapsible-player-switch-sync-and-reopen-signal`, DEFAULT
  /// `0`, parity Android `openSignal`). `didUpdateWidget`'s reopen re-evaluation SHALL trigger on
  /// EITHER `video.id` changing OR this value changing, so the host can force a reopen
  /// re-evaluation even when `video.id` is unchanged (e.g. the user re-taps the SAME video from a
  /// carousel while minimized) by incrementing a local counter at every "open the player" entry
  /// point. Left at the DEFAULT (never incremented) → behavior is byte-identical to before this
  /// parameter existed.
  final int openSignal;

  const CollapsibleLivebuyPlayer({
    super.key,
    required this.video,
    required this.onVideoChanged,
    required this.theme,
    this.config = const LivebuyPlayerConfig(),
    this.openSignal = 0,
  });

  @override
  State<CollapsibleLivebuyPlayer> createState() => _CollapsibleLivebuyPlayerState();
}

class _CollapsibleLivebuyPlayerState extends State<CollapsibleLivebuyPlayer> {
  /// Resting bottom-right padding of the floating card (parity iOS `floatingInset`).
  static const Offset _floatingInset = Offset(12, 24);

  bool _isMinimized = false;
  Offset _committedOffset = Offset.zero;
  Offset _dragTranslation = Offset.zero;
  Size _cardSize = Size.zero;

  /// The video the floating preview card SHOWS (rb-flutter-collapsible-player-track-switch). Init
  /// to the entry `video`; the turnkey container reports an in-place switch (hot-pick / swipe) via
  /// `config.onVideoSwitchedItem` (consumed in `_composedConfig` below), which updates this to the
  /// switched video's item (REAL cover / title for hot-pick; cover-empty + right id for swipe).
  /// Distinct from the host's `video` (which drives the keep-alive `videoId` prop + the auto-restore
  /// trigger): an in-place switch updates ONLY `_shownVideo`, NOT the keep-alive prop — the switch
  /// already loaded in the native player, so re-driving the prop would force a redundant reload
  /// (same as Android / RN; no latch needed — auto-restore keys on the host `video.id`).
  LBVideoItem? _shownVideo;

  @override
  void initState() {
    super.initState();
    _shownVideo = widget.video;
    // Seed the opt-in cover bridge from the INITIAL phase (parity iOS onAppear): a host that mounts
    // the presenter already bound to a non-null video (straight to full-screen) declares covered at
    // once; a null-video mount stays at the default false (no-op). See `presenterWidgetCovered`.
    _syncWidgetCover();
  }

  @override
  void didUpdateWidget(CollapsibleLivebuyPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final idChanged = oldWidget.video?.id != widget.video?.id;
    // openSignal (rb-flutter-collapsible-player-switch-sync-and-reopen-signal, parity Android
    // `LaunchedEffect(v.id, openSignal)`): re-evaluate reopen on EITHER `video.id` changing OR
    // `openSignal` changing, so the host can force a reopen re-evaluation even when `video.id` is
    // unchanged (e.g. re-tapping the SAME minimized video from a carousel). Left at the DEFAULT `0`
    // (never incremented) → this never changes on its own, byte-identical to before it existed.
    final openSignalChanged = oldWidget.openSignal != widget.openSignal;
    if (!idChanged && !openSignalChanged) return;

    // Whether the incoming id is merely an ECHO of an in-place switch this presenter already
    // self-reported via `onVideoSwitchedItem` → `onVideoChanged` (see `isVideoChangeSwitchEcho`),
    // NOT a genuine externally-initiated swap (e.g. tapping a different carousel card). Snapshot
    // BEFORE reassigning `_shownVideo` below. NOTE: forwarding in-place switches to the REQUIRED
    // `onVideoChanged` (see `_composedConfig` below) means a changed `widget.video.id` is no longer
    // exclusively a "genuine host swap" signal — this guard is what keeps that distinction correct.
    // Only meaningful when the id actually changed: an `openSignal`-only change concerns the SAME id
    // already shown, which is never an echo (there is nothing to echo).
    final isSwitchEcho = idChanged &&
        isVideoChangeSwitchEcho(newVideoId: widget.video?.id, shownVideoId: _shownVideo?.id);

    // A HOST swap (different id, not an echo of our own switch notification) re-seeds the floating
    // card's shown video to the new host video.
    if (idChanged) _shownVideo = widget.video;

    // A newly-bound video while minimized (genuine swap) — or an `openSignal`-driven re-tap of the
    // SAME minimized video — → close the floating preview and re-present full-screen. Tapping the
    // card to RESTORE keeps the same id AND leaves `openSignal` untouched, so it never trips this.
    // An ECHOED in-place switch is excluded: minimizing during an in-place switch MUST NOT
    // unexpectedly snap back to full-screen. Reset the drag offset.
    if (!isSwitchEcho &&
        shouldReopenOnVideoChange(newVideoId: widget.video?.id, isMinimized: _isMinimized)) {
      setState(() {
        _isMinimized = false;
        _committedOffset = Offset.zero;
        _dragTranslation = Offset.zero;
      });
    }
    // Sync the cover bridge AFTER any auto-restore has updated `_isMinimized` (parity iOS
    // onChange(video?.id) end). Covers open (null→id → covered), close (id→null → uncovered), host
    // swap (idA→idB → covered), and auto-restore (floating→full → covered). Reads the fresh
    // `widget.video` (already the new prop here) + the post-setState `_isMinimized`. Edge-triggered
    // (same value = no-op), so calling it for an `openSignal`-only no-reopen pass is safe.
    _syncWidgetCover();
  }

  LivebuyPlayerConfig get _composedConfig => widget.config.copyWith(
        // Minimize/close button tap.
        onMinimize: () {
          // rb-flutter-player-direct-close-button: resolve the SAME pure function
          // `_LivebuyPlayerState._overlayContext()` uses to pick the header's icon
          // (`showCloseIcon`) — "what icon is drawn" and "what tapping it does" can never
          // disagree because both read `resolvedEnableDirectCloseButton(...)`.
          final directClose = resolvedEnableDirectCloseButton(
            configValue: widget.config.enableDirectCloseButton,
            globalValue: LivebuySDK.enableDirectCloseButton,
          );
          if (directClose) {
            // Skip the floating-widget collapse entirely — go straight through the EXACT
            // SAME close path the floating card's own close button (`_close()`) and the
            // fatal-moment `onDismiss` seam use below. `_isMinimized` is NEVER set true on
            // this branch.
            _closeSession();
            return;
          }
          // Default (resolved false, byte-identical to before this change): collapse to the
          // floating preview (keep the session alive — keep-alive). full→floating: sync the
          // cover bridge imperatively (parity iOS onChange(isMinimized)) →
          // `presenterWidgetCovered(true, true)` == false → home previews resume.
          setState(() => _isMinimized = true);
          _syncWidgetCover();
        },
        // Fatal-moment dismiss (end-screen close / unrecoverable error close) → close all. Shares
        // the EXACT same implementation `_close()` (the floating card's own close button) and the
        // direct-close `onMinimize` branch above use — see `_closeSession()`'s own doc comment.
        onDismiss: _closeSession,
        // In-place switch (hot-pick / swipe) → re-bind the FLOATING card's shown video to the
        // switched video's item so the minimized preview shows the switched video, NOT the entry
        // one (rb-flutter-collapsible-player-track-switch). Guard same-id so a no-op switch neither
        // re-binds nor churns. Does NOT touch the keep-alive prop (`v.id`) → no redundant reload +
        // no auto-restore misfire. Any host-supplied `onVideoSwitchedItem` is preserved by chaining.
        //
        // ALSO forwards to the REQUIRED `onVideoChanged` (rb-flutter-collapsible-player-switch-sync-
        // and-reopen-signal, parity Android/RN): `onVideoChanged` previously fired only on close, so
        // a host that relies solely on it (the required, harder-to-miss seam) never learned about
        // in-place switches. Shares the SAME same-id guard as `_shownVideo` so a no-op switch neither
        // notifies nor churns. `didUpdateWidget`'s `isVideoChangeSwitchEcho` guard is what stops this
        // notification from being mistaken for a genuine host swap and snapping back to full-screen
        // while minimized.
        onVideoSwitchedItem: (item) {
          widget.config.onVideoSwitchedItem?.call(item);
          if (item.id != _shownVideo?.id) {
            setState(() => _shownVideo = item);
            widget.onVideoChanged(item);
          }
        },
      );

  // floating→full (tap the floating card): sync imperatively (parity iOS onChange(isMinimized)) →
  // `presenterWidgetCovered(true, false)` == true → home previews pause (yield the decoder).
  void _restore() {
    setState(() => _isMinimized = false);
    _syncWidgetCover();
  }

  /// The floating card's own close-button path — delegates to [_closeSession], the ONE shared
  /// full-close implementation (see its doc comment).
  void _close() {
    _closeSession();
  }

  /// The shared FULL close path (rb-flutter-live-entry-close-grace-period,
  /// rb-flutter-collapsible-player-close-no-reflash, rb-flutter-player-direct-close-button).
  /// THREE call sites share this EXACT ONE implementation so they can never drift apart:
  /// the floating card's own close button ([_close]), the fatal-moment `onDismiss` config seam
  /// (`_composedConfig`), and — new in rb-flutter-player-direct-close-button — the header's
  /// minimize/close button's `onMinimize` handler when `resolvedEnableDirectCloseButton(...)`
  /// resolves `true` (skipping the floating-widget collapse entirely).
  void _closeSession() {
    // rb-flutter-live-entry-close-grace-period: record "now" as the moment the player was
    // user-closed. A sibling `LivebuyLiveEntry` — a fully independent container the host mounts
    // only once `sessionVideo == null` — reads this to apply a short close-grace wait before
    // reappearing in the same corner, instead of popping in almost immediately.
    LiveEntryCloseGate.instance.recordClose();
    widget.onVideoChanged(null);
    setState(() {
      // MUST NOT reset `_isMinimized` here (rb-flutter-collapsible-player-close-no-reflash):
      // `onVideoChanged(null)` above does not synchronously update `widget.video` (the parent
      // rebuilds next frame — same race the `setWidgetsCovered(false)` call below already
      // guards against). If this method forced `_isMinimized = false` immediately, the
      // transitional frame (still `widget.video != null`) would be misread by `build()` as the
      // `full` phase — the KEEP-ALIVE full-screen player would reappear at `Opacity(1)` and
      // interactive, i.e. the player re-flashing right after the user closed it. Leaving
      // `_isMinimized` at its pre-call value keeps that transitional frame at worst the
      // (already-hidden) floating card — or, on the direct-close `onMinimize` branch, simply
      // irrelevant, since `build()`'s `if (v == null) return const SizedBox.shrink();`
      // early-return takes over once `widget.video` truly turns `null` next frame. A later
      // genuine reopen still correctly clears it back to `false` via the existing
      // `shouldReopenOnVideoChange` auto-restore branch in `didUpdateWidget`.
      _resetFloatingOffset();
    });
    // → closed: release the cover claim with a LITERAL false — NOT `_syncWidgetCover()`, because
    // `onVideoChanged(null)` does not synchronously update `widget.video` (the parent rebuilds
    // next frame), so `_syncWidgetCover()` here would read a stale non-null video and wrongly
    // declare covered. Closing is unconditionally uncovered; the next-frame didUpdateWidget sync
    // (video→null) is an edge-triggered no-op.
    LivebuyWidgetVisibility.setWidgetsCovered(false);
  }

  /// Resets the floating card's drag offset (unrelated to `_isMinimized` — deliberately NOT reset
  /// by [_closeSession]). Shared so a fresh floating card (should one reappear via an
  /// auto-restore) starts back at its resting bottom-right position.
  void _resetFloatingOffset() {
    _committedOffset = Offset.zero;
    _dragTranslation = Offset.zero;
  }

  /// Drive the opt-in cover bridge from the CURRENT phase. `covered ⟺ full` (see
  /// [presenterWidgetCovered]). `setWidgetsCovered` is edge-triggered (same value = no-op), so
  /// calling this from multiple hooks is safe and never churns. NOTE: [_closeSession] (all three
  /// close call sites) MUST NOT use this (it sets `widget.video` null via the host, which is not
  /// yet reflected here) — it calls `setWidgetsCovered(false)` directly instead.
  void _syncWidgetCover() {
    LivebuyWidgetVisibility.setWidgetsCovered(
      presenterWidgetCovered(hasVideo: widget.video != null, isMinimized: _isMinimized),
    );
  }

  @override
  void dispose() {
    // Presenter removed from the tree → release any cover claim so the home previews are NOT left
    // permanently paused (parity iOS onDisappear — the important edge case). Literal false:
    // unconditional on unmount. Edge-triggered, so it is a no-op when already uncovered.
    LivebuyWidgetVisibility.setWidgetsCovered(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.video;
    if (v == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final containerSize = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          children: [
            // KEEP-ALIVE full player: mounted the whole time `video != null`. Minimize only HIDES
            // it (Opacity 0 + IgnorePointer) so playback continues + restore is an instant resume.
            Positioned.fill(
              child: IgnorePointer(
                ignoring: _isMinimized,
                child: Opacity(
                  opacity: _isMinimized ? 0 : 1,
                  child: LivebuyPlayer(videoId: v.id, config: _composedConfig),
                ),
              ),
            ),

            // Bottom-right floating preview while minimized. Draggable (clamped on-screen);
            // a tap restores, the close button clears.
            if (_isMinimized)
              Positioned(
                right: _floatingInset.dx - (_committedOffset.dx + _dragTranslation.dx),
                bottom: _floatingInset.dy - (_committedOffset.dy + _dragTranslation.dy),
                child: GestureDetector(
                  onPanUpdate: (d) => setState(() => _dragTranslation += d.delta),
                  onPanEnd: (_) => setState(() {
                    _committedOffset = clampFloatingOffset(
                      committed: _committedOffset,
                      translation: _dragTranslation,
                      cardSize: _cardSize,
                      containerSize: containerSize,
                      inset: _floatingInset,
                    );
                    _dragTranslation = Offset.zero;
                  }),
                  child: _MeasureSize(
                    onChange: (size) => _cardSize = size,
                    // The floating preview card is composed by the resolved design (granularity
                    // A). Default MinimalDesign = the verbatim `FloatingWidgetView`; a host
                    // injects its own via `config.design`.
                    child: widget.config.design.floatingPlayerCard(
                      FloatingCardContext(
                        theme: widget.theme,
                        // The SWITCHED video (rb-flutter-collapsible-player-track-switch): an
                        // in-place switch updates `_shownVideo` so the card shows the switched
                        // video, not the entry `v`.
                        video: _shownVideo ?? v,
                        // A genuine live session → load the real cover (parity with iOS
                        // `LivebuyPlayerPresenter` `FloatingCardContext(live: true)`).
                        live: true,
                        onTap: (_) => _restore(),
                        onClose: _close,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Reports its child's rendered size once (for clamping the floating card's drag offset).
class _MeasureSize extends StatefulWidget {
  final ValueChanged<Size> onChange;
  final Widget child;
  const _MeasureSize({required this.onChange, required this.child});

  @override
  State<_MeasureSize> createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<_MeasureSize> {
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final size = context.size;
      if (size != null) widget.onChange(size);
    });
    return widget.child;
  }
}
