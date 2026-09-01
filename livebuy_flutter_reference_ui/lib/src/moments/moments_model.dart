import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show
        DefaultPlayerTemplate,
        LBPStartPhase,
        LBEndNavItem,
        LBEndHotItem,
        LBEndCountdown,
        LBPlayerErrorState,
        LBPlayerErrorKind,
        LBPlayerErrorPhase;

// MomentsModel — family-4 player moment-state read-only snapshot bridge (Flutter).
//
// Spec: `reference-ui-rendering/spec.md` (family-4 moments, 3 full-screen surfaces).
// Flutter sibling of iOS `MomentsModel.swift` (rb-ios-moments) and Android
// `MomentsModel.kt` (rb-android-moments).
//
// It bridges the headless template moment view-models exposed by
// `DefaultPlayerTemplate` (obtained at runtime by the host; tests take
// `LivebuyUI.attachedTemplateForTesting`) into a read-only snapshot the three
// family-4 Flutter surface widgets read. It is a pure read-only MIRROR — IDENTICAL
// pattern to family-1 `PlayerShellModel` / family-2 `FeedWinModel` / family-3
// `ProductSheetsModel`:
//
//   - It owns NO second copy of authoritative state. Every getter reads the
//     template's own public getter each call (`startScreen.phase` /
//     `endScreen.next` / `endScreen.hot` / `endScreen.countdown` /
//     `errorState.current`), so there is nothing to drift from the template.
//   - It adds NO pixels and adds NO accessor / view-model to `livebuy_flutter_ui`
//     (that would be a template-layer concern, out of scope here).
//
// ── CRITICAL: NO mutating forwarders (UNLIKE family-2/3) ─────────────────────────
//   Moments carry NO public template / player intent for skip / retry / watch-next /
//   pick-hot / cancel / dismiss — those are NOT template methods. The moment actions
//   are HOST-WIRED CONTAINER closures (like family-2's event-join / family-3's
//   product-tap), NOT model forwarders. So this model is a PURE read-only snapshot;
//   it carries NO mutating methods. The container (`MomentsOverlayView`) holds the
//   host-wired exits (`onSkip` / `onWatchNext` / `onPickHot` / `onCancel` /
//   `onRetry` / `onDismiss`). retry is a CORE player concern (the SDK auto-retries
//   3×/3s); this layer only forwards the CTA. Do NOT invent template forwarders —
//   none exist for moments (mirrors iOS / Android `MomentsModel`, also pure reads).
//
// ── FLUTTER vs iOS / Android deltas ──────────────────────────────────────────────
//   • start is read via `template.startScreen.phase` (`LBPStartPhase`, camelCase:
//     `loading` / `splash` / `buffering` / `done`) — iOS `startScreen.phase`
//     (`LBStartScreenPhase`), Android `startScreenState.current.phase`
//     (`StartScreenPhase`, UPPERCASE).
//   • end is read via `template.endScreen.{next, hot, countdown}`. The Flutter
//     value types are TEMPLATE-owned (NOT the core `LBNavItem` / `LBHotItem`):
//     `LBEndNavItem` { id, title, cover:String } / `LBEndHotItem`
//     { id, title, cover:String, duration:int (SECONDS — reference-ui formats
//     `mm:ss`) } / `LBEndCountdown` { remain:int, total:int }.
//   • error is `template.errorState.current: LBPlayerErrorState?` with
//     `kind: LBPlayerErrorKind` (`stream` / `notFound` / `outdated`) +
//     `phase: LBPlayerErrorPhase.failed` (mirrors iOS / Android error snapshots).
//
// Flutter observes via ChangeNotifier; the container [MomentsOverlayView] binds the
// three sub view-models (`startScreen` / `endScreen` / `errorState`, each a
// `ChangeNotifier`) with `ListenableBuilder` and RE-READS these getters on each
// notify — so this holder keeps NO Flutter state of its own (no `extends
// ChangeNotifier`); it just centralizes the read mapping + deterministic demo
// seeds. Mirrors the iOS / Android `MomentsModel` intent.
//
// No Flutter-framework dependency here — pure reads + plain-literal demo seeds, so
// it stays unit-testable (see `docs/unit-test-discipline.md`).

/// Read-only snapshot bridge for the family-4 moment surfaces. Wraps a live
/// [DefaultPlayerTemplate]; every accessor reads the template's public getter each
/// call (no stored mirror). For demos / previews / golden tests, construct with
/// `template: null` — the getters then return the deterministic at-attach defaults
/// (matching a freshly-constructed template: `loading` phase / no countdown / empty
/// next / empty hot / no error); the surfaces' richer fixtures are passed by value
/// from [MomentsSeeds].
class MomentsModel {
  /// The bound template, or `null` for demo / golden instances.
  final DefaultPlayerTemplate? template;

  /// Bridge a live template (host-supplied) — or `null` for the deterministic demo
  /// seeds (previews / golden / widget tests).
  const MomentsModel({this.template});

  // -- Surface 1: StartScreenView ← splash lifecycle phase ----------------------

  /// Splash lifecycle phase (`DefaultPlayerTemplate.startScreen.phase`).
  /// `loading` → full-screen brand spinner; `buffering` → lightweight
  /// over-content indicator (video visible behind); `splash` → brand splash +
  /// skip pill; `done` → no overlay. The container shows the start moment ONLY
  /// while `startPhase != done`. Demo default `loading`.
  LBPStartPhase get startPhase =>
      template?.startScreen.phase ?? LBPStartPhase.loading;

  // -- Surface 2: EndScreenView ← auto-next countdown + next + hot ---------------

  /// Auto-next countdown snapshot (`endScreen.countdown`); non-null ONLY while
  /// core drives the auto-next countdown AND `next` is non-empty
  /// (`countdown != null` ⇔ 倒數變體, null ⇔ 熱門變體). `{ remain, total }` —
  /// ring progress = `remain / total`. Demo default `null`.
  LBEndCountdown? get countdown => template?.endScreen.countdown;

  /// Watch-next targets (`endScreen.next`). The 倒數變體 preview card reads
  /// `next.first` (`cover` placeholder / `title`). Demo default empty.
  List<LBEndNavItem> get next => template?.endScreen.next ?? const [];

  /// 熱門推薦 set (`endScreen.hot`). Rendered as a FIXED SMALL set in a PLAIN
  /// `Row`/`Column` (NEVER lazy/scroll). `duration` is an `int` in SECONDS —
  /// reference-ui formats it to `mm:ss` (e.g. `28` → `"00:28"`). Demo default
  /// empty.
  List<LBEndHotItem> get hot => template?.endScreen.hot ?? const [];

  /// Whether the end screen should be shown at all (`endScreen.endScreenVisible`,
  /// mirrors core「player 進 endScreenShown sub-state」). True on live_end REGARDLESS of
  /// next/hot. The container shows the end moment when `countdown != null ||
  /// endScreenVisible`; when `countdown == null && endScreenVisible`, EndScreenView
  /// renders the no-countdown「直播已結束」variant (end-screen-no-countdown). Demo default
  /// `false`. Parity iOS / Android / RN `MomentsModel.endScreenVisible`.
  bool get endScreenVisible => template?.endScreen.endScreenVisible ?? false;

  // -- Surface 3: ErrorScreenView ← terminal error snapshot ---------------------

  /// Terminal player error snapshot (`errorState.current`); `null` when the player
  /// is not in `error`. `{ kind, phase }` — `phase` is always `failed` (core does
  /// not expose retrying). `kind` (`stream` / `notFound` / `outdated`) is ALREADY
  /// classified by the template (`DefaultErrorState.kindFor`); this layer MUST NOT
  /// re-classify `LBError`. The container shows the error moment (HIGHEST priority)
  /// when `error != null`. Demo default `null`.
  LBPlayerErrorState? get error => template?.errorState.current;
}

// MARK: - Deterministic demo seeds (previews / golden / widget tests)

/// Plain-literal deterministic seeds for the family-4 surfaces' previews + the
/// per-surface golden / widget tests. Constructed via the public template value
/// types (`LBEndNavItem` / `LBEndHotItem` / `LBEndCountdown` / `LBPlayerErrorState`)
/// so a snapshot does NOT depend on a live player. Mirrors the iOS demo seeds (the
/// memberwise `MomentsModel` demo init values) and the Android `MomentsSeeds`.
///
/// The golden baselines each drive ONE moment variant from these seeds:
///   • [splashPhase] — the start-screen splash baseline (`start-screen-splash-default`).
///   • [countdown] + [next] — the end-screen 倒數變體 (`end-screen-countdown-variant`).
///   • [hot] — the end-screen 熱門變體 (durations in SECONDS, formatted `mm:ss`).
///   • [streamError] — the error-screen stream baseline (`error-screen-stream`).
class MomentsSeeds {
  MomentsSeeds._();

  // -- Surface 1: start-screen splash phase ------------------------------------

  /// The splash-phase fixture for the start-screen snapshot baseline
  /// (`start-screen-splash-default` — brand splash + skip pill).
  static const LBPStartPhase splashPhase = LBPStartPhase.splash;

  // -- Surface 2: end-screen 倒數變體 + 熱門變體 -------------------------------

  /// A deterministic auto-next countdown (`remain 3 / total 5` → 60% ring; centre
  /// shows `remain == 3`). Drives the `end-screen-countdown-variant` baseline.
  static const LBEndCountdown countdown =
      LBEndCountdown(remain: 3, total: 5);

  /// The watch-next target list (倒數變體 reads `next[0]` for its preview card +
  /// the「{shopName} · {duration}」meta line — `shopName` / `duration` are the
  /// fields added by `align-endscreen-nav-meta-template`; `duration` is SECONDS,
  /// formatted `mm:ss` (1530 → `25:30`)).
  static const List<LBEndNavItem> next = [
    LBEndNavItem(
      id: 'next-7001',
      title: '下一場 · 春季新品搶先看',
      cover: '',
      shopName: 'Aurora 美妝',
      duration: 1530,
    ),
  ];

  /// A deterministic 熱門推薦 set (FIXED SMALL set; `duration` is an `int` in
  /// SECONDS — reference-ui formats `mm:ss`: 2316 → `"38:36"`, 728 → `"12:08"`,
  /// 347 → `"05:47"`). Mirrors the iOS / Android hot seeds.
  static const List<LBEndHotItem> hot = [
    LBEndHotItem(id: 'hot-8001', title: '夏日通勤彩妝特輯', cover: '', duration: 2316),
    LBEndHotItem(id: 'hot-8002', title: '週年慶必囤清單', cover: '', duration: 728),
    LBEndHotItem(id: 'hot-8003', title: '主持人私藏好物', cover: '', duration: 347),
  ];

  // -- Surface 3: error-screen ---------------------------------------------------

  /// Terminal stream-failure error fixture for the error-screen baseline
  /// (`error-screen-stream` —「播放發生問題」+ 重試 + 返回).
  static const LBPlayerErrorState streamError = LBPlayerErrorState(
    kind: LBPlayerErrorKind.stream,
    phase: LBPlayerErrorPhase.failed,
  );

  /// A not-found error fixture (「找不到影片」僅返回，不可重試).
  static const LBPlayerErrorState notFoundError = LBPlayerErrorState(
    kind: LBPlayerErrorKind.notFound,
    phase: LBPlayerErrorPhase.failed,
  );

  /// An outdated-SDK error fixture (「請更新版本」前往更新，無重試).
  static const LBPlayerErrorState outdatedError = LBPlayerErrorState(
    kind: LBPlayerErrorKind.outdated,
    phase: LBPlayerErrorPhase.failed,
  );
}
