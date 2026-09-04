import 'package:flutter/material.dart';
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show LBInfoPanelTab, LBInfoTabFields;

import '../productsheets/sheet_header_close_button.dart';
import '../productsheets/sheet_scaffold.dart' show LBSheetScaffold, liveProductImage;
import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';

// VideoInfoPanelView — family-1 player-shell surface 3 (info / notice panel).
//
// Spec: `reference-ui-rendering/spec.md` (family-1 player-shell, surface 3).
// Design: `design/templates/minimal/screens.jsx` `VideoInfoSheet` +
//          `design/templates/minimal/sdk-components.jsx` `LBPBottomSheet` /
//          `LBPSheetHeader`.
// Parity: iOS `VideoInfoPanelView.swift`
//   (ios/Sources/LivebuyReferenceUI/PlayerShell/VideoInfoPanelView.swift) and
//   Android `VideoInfoPanel.kt`
//   (android/livebuy-reference-ui/.../playershell/VideoInfoPanel.kt).
//
// The bottom-sheet info/notice panel. It is the third of the four family-1
// surface widgets composed by `PlayerShellView`, and it implements the agreed
// SUB-VIEW INPUT PATTERN documented in `player_shell_view.dart`:
//
//   1. `theme:` (ReferenceUITheme, required)   — FIRST, always.
//   2. bound SNAPSHOT VALUES (read-only, BY VALUE):
//        `fields: LBInfoTabFields`, `isSubscribed: bool` (Flutter's
//        `LBInfoTabFields` carries NO isSubscribed — single truth lives on the
//        header, so it is a SEPARATE arg, differing from iOS's bundled
//        `LBInfoTabState.isSubscribed`), `activeTab: LBInfoPanelTab`,
//        `noticeCanOpen: bool`, `systemNotice: String`, `notice: String`, plus the
//        PRESENTATION flag `live: bool` (defaulted false) — a runtime IMAGE GATE, NOT a
//        view-model field and NOT the LIVE broadcast state; see [resolveShopLogoUrl].
//   3. action callback (LAST, each defaulting to a no-op):
//        `onSelectTab: ValueChanged<LBInfoPanelTab>?` — the host wires it to the
//        template's `selectInfoTab` navigation intent.
//
// This sub-view reads ONLY its passed-in values; it never reaches back into
// `PlayerShellModel` / `DefaultPlayerTemplate` (one-way data flow), holds NO
// second copy of state, and renders correctly with `onSelectTab` null.
//
// Two-tab panel (mirrors `VideoInfoSheet` + the spec's `LBInfoPanelTab`):
//   • 影片詳情 (`info`)   — ALWAYS selectable. Shows publishAt / title /
//                            shopIntro, a divider, then a shop row (logo monogram
//                            + shopName + 「這裡是 …」 subline + subscribe affordance
//                            bound to `isSubscribed`).
//   • 公告     (`notice`) — rendered ONLY when `noticeCanOpen == true`
//                            (rb-flutter-notice-tab-hide-when-empty, parity iOS
//                            rb-ios-notice-tab-hide-when-empty / Android
//                            rb-android-notice-tab-hide-when-empty). When
//                            `noticeCanOpen == false` the tab item is NOT built at
//                            all — the tab bar shows a single 影片詳情 tab, not a
//                            two-tab switcher with one dead disabled entry. The
//                            content switch also carries a DEFENSIVE fallback to
//                            影片詳情 for the (type-legal but
//                            interaction-path-unreachable) combination
//                            `activeTab == notice && noticeCanOpen == false` — see
//                            `build()`'s doc comment near that branch.
//
// RECONCILED notice design (the agreed final iOS state — done directly here, no
// placeholder-tab stage): the 公告 tab renders `systemNotice` (系統公告, textDim)
// and `notice` (商城公告, accent) IN-PANEL as two blocks, with a hairline divider
// between them ONLY when both are present. When BOTH are empty (a type-legal but
// inconsistent `noticeCanOpen: true` construction — see the defensive fallback
// note above; NOT reachable through the view-model, which only sets `canOpen` true
// when at least one is non-empty) it draws the dim empty placeholder「目前沒有公告」.
//
// RENDERING GOTCHAS (inherited from iOS / Android lessons): plain Column / Row /
// Stack only — NO scrollable container (`ListView` / `GridView` /
// `SingleChildScrollView`). No animation / no randomness so the golden is byte-stable.
//
// NO NETWORK IMAGE **ON THE GOLDEN PATH** (`live == false`, the default): the shop-row
// logo is then the deterministic gradient monogram chip and nothing is fetched, so the
// baselines stay byte-identical. The rule guards GOLDEN DETERMINISM, not "this file may
// never contain an image" — on the host-runtime path (`live == true`) the shop row DOES
// overlay the real `fields.shopLogo` through the shared `liveProductImage` primitive,
// with the chip underneath as the loading / failure placeholder. See [resolveShopLogoUrl]
// and `_shopLogo` (change `flutter-videoinfo-shop-logo-real-image-refui`, parity with the
// header avatar which has painted the same logo this way all along).

// MARK: - Decorative design tokens (literal minimal hex via colorFromHex)
//
// accent / text / background come from the resolved [ReferenceUITheme]. These
// are FIXED decorative colors lifted verbatim from the design `screens.jsx`
// `theme.surface.*` (dim text / hairline strokes) — design-literal, not
// theme-resolved. They mirror the iOS / Android static colors byte-for-byte.

/// `theme.surface.textDim` (secondary / caption text).
final Color _textDim = colorFromHex('#6B6775') ?? const Color(0xFF6B6775);

/// `theme.surface.textFaint` — further-dimmed disabled affordance color.
final Color _textFaint = colorFromHex('#B6B2BE') ?? const Color(0xFFB6B2BE);

/// `theme.surface.stroke` (hairline divider).
final Color _stroke = colorFromHex('#ECEAF0') ?? const Color(0xFFECEAF0);

/// `theme.surface.strokeStrong` (grab handle / stronger hairline).
final Color _strokeStrong = colorFromHex('#D8D5DE') ?? const Color(0xFFD8D5DE);

/// `theme.surface.bgSunken` (#F4F4F6) — ghost footer-button fill (design `LBPButton`).
final Color _bgSunken = colorFromHex('#F4F4F6') ?? const Color(0xFFF4F4F6);

// MARK: - Fixed localized copy (static presentation strings — parity to iOS/Android)

const String _panelTitle = '點播間說明';
const String _panelTitleLive = '直播間說明';
const String _infoTabTitle = '影片詳情';
const String _infoTabTitleLive = '直播詳情';
const String _noticeTabTitle = '公告';
const String _systemNoticeLabel = '系統公告';
const String _mallNoticeLabel = '商城公告';
const String _subscribeLabel = '訂閱通知';
const String _subscribedLabel = '已訂閱';
const String _shopSublinePrefix = '這裡是 ';
const String _noticeEmptyPlaceholder = '目前沒有公告';
const String _contactLabel = '與商家一對一對話';

/// 「直播中」badge label (design `screens.jsx:1368` `直播中`).
const String _liveBadgeLabel = '直播中';

/// 「直播中」badge fill — `#F03246` (design literal, same red as the LIVE pill elsewhere).
final Color _liveBadgeFill = colorFromHex('#F03246') ?? const Color(0xFFF03246);

// MARK: - Shop-logo image gate (pure)

/// Resolves the shop-logo image URL to overlay on the shop row's gradient monogram
/// chip, or `null` when nothing should be loaded.
///
/// Flutter parity of the iOS lead `VideoInfoPanelView.resolvedShopLogoURL(live:urlString:)`
/// (change `videoinfo-shop-logo-real-image-refui`); Android / RN mirror it too.
///
/// ── DEGRADATION LADDER ──
///
///   1. [live] `== false`  → `null`. Demo / golden / preview paths NEVER load an image,
///      so the goldens stay byte-stable (no network in a widget test).
///   2. [urlString] is `null`, or is blank after trimming → `null`. No logo → the
///      underlying gradient chip IS the final presentation (no hole, no error icon).
///   3. otherwise → the TRIMMED string.
///
/// Trimming is applied for BOTH the judgement and the returned value; characters
/// INSIDE the string are never touched.
///
/// ── ⚠️ `live` IS NOT `isLive` ⚠️ ──
///
/// [live] is the **live-runtime IMAGE GATE** (parity with `PlayerHeaderBarView.live` /
/// `PlayerShellView.live`), NOT the LIVE broadcast state. `PlayerHeaderBarView` carries
/// BOTH — its `isLive` drives the LIVE pill / viewer count, its `live` drives real image
/// loading — so the two names are easy to confuse when mirroring across surfaces.
/// `VideoInfoPanelView` has no `isLive` concept, so there is no clash here.
///
/// ── STRUCTURAL COUPLING: THE DRAW CONDITION *IS* THIS RETURN VALUE ──
///
/// The shop row MUST express "do we overlay an image?" as `resolveShopLogoUrl(...) == null`
/// and MUST NOT re-derive an equivalent test at the draw site (`live && shopLogo.isNotEmpty`
/// and friends). Same discipline as `resolveProductPhoto`'s "source validity == drawability":
/// the moment the decision and the drawing are implemented separately they drift, and this
/// function's unit tests stop saying anything about what is actually painted. Coupling them
/// structurally is the ONLY thing that makes the pure-function matrix meaningful.
///
/// ── WHY `String?` AND NOT `Uri?` (differs from the iOS lead, deliberately) ──
///
/// [liveProductImage] takes a plain `String?` url and already owns scheme validation plus the
/// cleartext http→https upgrade (`sheet_scaffold.dart`). Returning a `Uri?` here would force
/// the caller to `.toString()` it AND would duplicate the scheme policy in a second place that
/// can disagree with the primitive. Same call as `resolved_product_photo.dart`'s documented
/// "NO URL ADAPTER (unlike iOS)" decision.
///
/// Pure: no I/O, no global state, no mutation, no widget types. Safe to call per-build.
String? resolveShopLogoUrl({required bool live, required String? urlString}) {
  // Rung 1 — the runtime image gate is closed (demo / golden / preview).
  if (!live) return null;
  // Rung 2 — nothing usable to load (null / empty / whitespace-only).
  final trimmed = urlString?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  // Rung 3 — load the trimmed URL.
  return trimmed;
}

/// Up-to-3-char monogram from the shop name (deterministic, pure). Mirrors iOS /
/// Android `monogram`.
String _monogram(String shopName) {
  final trimmed = shopName.trim();
  if (trimmed.isEmpty) return 'LB';
  return trimmed.substring(0, trimmed.length < 3 ? trimmed.length : 3).toUpperCase();
}

/// The family-1 bottom-sheet info/notice panel. Renders an always-available
/// 影片詳情 (info) tab plus a 公告 (notice) tab that is built ONLY when
/// [noticeCanOpen] is true (rb-flutter-notice-tab-hide-when-empty) — when
/// [noticeCanOpen] is false the panel is a single-tab surface, not a two-tab
/// switcher with a disabled entry.
class VideoInfoPanelView extends StatelessWidget {
  /// Resolved reference-ui theme (FIRST positional argument, always).
  final ReferenceUITheme theme;

  /// Info-tab field snapshot (`DefaultInfoTab.fields`). Read-only. Carries NO
  /// `isSubscribed` — that is a SEPARATE arg ([isSubscribed], single truth on the
  /// header).
  final LBInfoTabFields fields;

  /// Subscribe-badge state (`DefaultPlayerHeaderState.isSubscribed`, single
  /// truth) — bound to the subscribe affordance in the shop row.
  final bool isSubscribed;

  /// Currently selected tab (`DefaultInfoTab.activeTab`). Read-only.
  final LBInfoPanelTab activeTab;

  /// Whether the 公告 (notice) tab is selectable (`DefaultNoticeTab.current.canOpen`
  /// == `DefaultInfoTab.noticeSelectable`).
  final bool noticeCanOpen;

  /// System-notice text (`DefaultNoticeTab.current.systemNotice`, textDim 段).
  final String systemNotice;

  /// Shop / video notice text (`DefaultNoticeTab.current.notice`, accent 段).
  final String notice;

  /// Live-runtime IMAGE GATE (parity with `PlayerHeaderBarView.live` /
  /// `PlayerShellView.live`, and with iOS / Android / RN's identically-named flag).
  /// `true` → the shop row overlays the real [LBInfoTabFields.shopLogo] via
  /// [liveProductImage]; `false` (demo / golden — the DEFAULT) → only the deterministic
  /// gradient monogram chip renders, so no network is touched and baselines stay stable.
  ///
  /// ⚠️ NOT the LIVE broadcast state (`isLive`). This panel has no `isLive` concept, but
  /// `PlayerHeaderBarView` carries BOTH flags — do not conflate them when mirroring.
  final bool live;

  /// Whether the video this panel describes is an ACTUAL live broadcast in progress
  /// (rb-flutter-live-replay-more-menu-and-video-info-live-copy, design R32) — `true` →
  /// panel title「點播間說明」→「直播間說明」, info tab label「影片詳情」→「直播詳情」, and the
  /// detail tab's date line swaps from plain dim text to a red (`#F03246`)「直播中」badge + `|`
  /// + the SAME [LBInfoTabFields.publishAt] value (no new field — see `design.md`).
  ///
  /// ⚠️ Named `isLiveBroadcast`, deliberately NOT `live` / `isLive` — [live] above is this
  /// panel's own runtime IMAGE GATE (an unrelated concern; see its own dartdoc), and
  /// `PlayerHeaderBarView.isLive` is a DIFFERENT widget's field. The host feeds the SAME
  /// broadcast-live value that already drives `PlayerHeaderBarView(isLive: m.isLive, ...)`
  /// (`PlayerShellModel.isLive` = `channel.liveStatus == 1`). Default `false` — every existing
  /// call site (VOD) renders byte-identically.
  final bool isLiveBroadcast;

  /// Host-wired tab-switch intent (the shell forwards `model.selectInfoTab`).
  /// `null` for demo / golden instances — the panel renders correctly action-free.
  final ValueChanged<LBInfoPanelTab>? onSelectTab;

  /// ⚠️ SOURCE-COMPAT NO-OP (rb-flutter-live-replay-more-menu-and-video-info-live-copy, design
  /// R32): the PRIMARY「前往商城首頁」footer button this used to drive is REMOVED — nothing in
  /// this widget renders it or reads this field anymore. The PARAMETER itself is kept
  /// (governance `docs/contract-governance.md` I6 / 情境F: a public constructor parameter is
  /// part of this widget's back-compat surface even though the pixel it used to trigger is not
  /// — removing the PIXEL is an ordinary reference-ui visual change, but removing the PARAMETER
  /// would be an API break for any existing caller that names it explicitly). Any value passed
  /// here is silently ignored. See `design.md` for the full I6/情境F applicability note.
  final VoidCallback? onOpenStorefront;

  /// Footer「與商家一對一對話」(ghost CTA) intent. The host wires this to the existing
  /// side-rail serviceLink exit (`_handleRailTap(LBSideRailKind.serviceLink)`).
  /// `null` for demo / golden instances — the button renders inert.
  final VoidCallback? onContactMerchant;

  /// Header 右上角關閉 icon tap (rb-flutter-sheet-header-close-unify): the 4th legal close
  /// entry alongside scrim / drag / host-badge re-tap. Host wires it to close the info panel
  /// (`PlayerShellView._infoPanelOpen = false`). Null → inert (demo / golden).
  final VoidCallback? onClose;

  /// Whether the shop row's subscribe pill (`_subscribePill()`) is drawn at all
  /// (rb-flutter-subscribe-favorite-visibility-toggle, parity iOS / Android / RN —
  /// Android's own comment on this pill notes it is "同一入口" / the same subscribe
  /// entry-point as the header avatar badge, not an independent affordance). Default
  /// `true` — this WIDGET's own default preserves EXISTING call sites / golden
  /// baselines byte-identical (this file never gated the pill before); the turnkey
  /// container (`LivebuyPlayer`) flips it off by default via the SAME
  /// `LivebuyPlayerConfig.showSubscribe` flag that already gates the header badge
  /// (both are the second/first rendering location of ONE subscribe feature, not two
  /// independent toggles — `PlayerShellView` forwards its single `showSubscribe`
  /// field to both call sites). `false` removes the whole `_subscribePill()` node
  /// (not just hides it), so the shop row's layout does not reserve dead space for a
  /// hidden pill.
  final bool showSubscribe;

  const VideoInfoPanelView({
    super.key,
    required this.theme,
    required this.fields,
    required this.isSubscribed,
    required this.activeTab,
    required this.noticeCanOpen,
    required this.systemNotice,
    required this.notice,
    this.live = false,
    this.isLiveBroadcast = false,
    this.onSelectTab,
    this.onOpenStorefront,
    this.onContactMerchant,
    this.onClose,
    this.showSubscribe = true,
  });

  @override
  Widget build(BuildContext context) {
    // Top-rounded sheet shell (LBPBottomSheet rounds ONLY the top two corners,
    // 20 20 0 0). The container shadow is handled by the host; reference-ui keeps
    // this deterministic (shadows are disabled in golden tests anyway).
    //
    // `activeTab == notice && !noticeCanOpen` is a DEFENSIVE fallback branch
    // (rb-flutter-notice-tab-hide-when-empty): the tab-bar tap path (`_tabBar()`
    // only ever builds the 公告 tab, and therefore only ever forwards `notice`
    // via `onSelectTab`, when `noticeCanOpen` is true) plus the upstream
    // view-model guards (`DefaultInfoTab.selectTab` no-ops selecting `notice`
    // while `canOpen` is false; its `_onNoticeChanged` listener snaps a resting
    // `notice` back to `info` the moment `canOpen` flips false) already make
    // this combination unreachable via normal interaction. But
    // `VideoInfoPanelView` is a public widget any caller (demo / golden / tests
    // / a future call site) can construct with an arbitrary `activeTab` /
    // `noticeCanOpen` pair — the type system does not forbid it — so this
    // widget owns its own fallback rather than assuming a caller upheld the
    // view-model layer's invariant. Falling back to `_infoContent()` avoids
    // ever showing notice content with no corresponding tab, or a blank pane.
    return ClipRRect(
      key: LbTestKeys.infoPanel,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(20),
        topRight: Radius.circular(20),
      ),
      child: ColoredBox(
        color: theme.background,
        // Renders via the shared `LBSheetScaffold` (rb-flutter-sheetkit-resize-dismiss-unify) —
        // takes over from a bare, uncapped `Column`: this panel had NO height cap and NO drag
        // capability at all before this change (an existing gap vs. iOS, which already caps
        // `VideoInfoPanelView` at 0.5). It now gets the same drag-resize (floor↔80%) +
        // drag-to-dismiss the other 4 bottom sheets have, plus that 0.5 safety cap.
        child: LBSheetScaffold(
          onDismiss: onClose,
          header: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _grabHandle(),
              _sheetHeader(),
              _tabBar(),
              // Hairline divider under the tab row.
              Container(height: 1, color: _stroke),
            ],
          ),
          body: activeTab == LBInfoPanelTab.info || !noticeCanOpen
              ? _infoContent()
              : _noticeContent(),
          // Footer CTAs — pinned below the tab content on BOTH tabs (design
          // `VideoInfoSheet`, parity to iOS / Android / RN footer).
          footer: _footer(),
        ),
      ),
    );
  }

  // MARK: - Footer CTA (VideoInfoSheet bottom button — present on BOTH tabs)
  //
  // The single bottom action button the design pins below the tab content regardless of tab
  // (`screens.jsx` `VideoInfoSheet`): a ghost「與商家一對一對話」. Full-width (padding 0 18 18).
  // Forwards its host-wired intent and is still drawn (inert) when null. Glyph uses Material
  // `Icons.*` (package convention; tofu in golden is the documented limitation — the label
  // carries the meaning).
  //
  // rb-flutter-live-replay-more-menu-and-video-info-live-copy (design R32): the PRIMARY
  // 「前往商城首頁」button that used to sit above this one is REMOVED — per the user's 2026-09-03
  // explicit decision (見 `proposal.md` "Decisions"). This is a PIXEL removal only (an ordinary
  // reference-ui visual change, no governance flow needed for that half): the button, its
  // `_storefrontLabel` const and `LbTestKeys.infoPanelHome` E2E key are all gone. The
  // [onOpenStorefront] CALLBACK PARAMETER on the other hand is KEPT on the public constructor as
  // a source-compat no-op (`docs/contract-governance.md` I6 / 情境F — removing a public
  // constructor parameter, unlike removing the pixel it drove, is the kind of change that flow
  // actually governs; see [onOpenStorefront]'s own dartdoc and `design.md`).

  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // INERT E2E key via KeyedSubtree (no RenderObject → golden byte-identical).
          KeyedSubtree(
            key: LbTestKeys.infoFooterContact,
            child: _footerButton(
              glyph: Icons.chat_bubble_outline,
              label: _contactLabel,
              primary: false,
              onTap: onContactMerchant,
            ),
          ),
        ],
      ),
    );
  }

  /// One full-width footer button mirroring the design `LBPButton` (radius 12, 14
  /// vertical padding, 15 * fontScale / bold label, glyph + label, gap 8). Primary =
  /// accent fill + white; ghost = [_bgSunken] fill + theme text. Renders correctly
  /// (and inert) when [onTap] is null.
  Widget _footerButton({
    required IconData glyph,
    required String label,
    required bool primary,
    required VoidCallback? onTap,
  }) {
    final bg = primary ? theme.accent : _bgSunken;
    final fg = primary ? Colors.white : theme.text;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(glyph, size: 16, color: fg),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 15 * theme.fontScale,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // MARK: - Grab handle (LBPBottomSheet handle)

  Widget _grabHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: _strokeStrong,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ),
    );
  }

  // MARK: - Sheet header (LBPSheetHeader — centered title)

  Widget _sheetHeader() {
    // 置中標題 + 右上角共用透明關閉鈕（rb-flutter-sheet-header-close-unify，iOS/Android parity）：
    // close 疊右上、標題保留置中，是第四個合法關閉入口。onClose null → 不接線。
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 10, bottom: 14),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            isLiveBroadcast ? _panelTitleLive : _panelTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.text,
              fontSize: 15 * theme.fontScale,
              fontWeight: FontWeight.bold,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: SheetHeaderCloseButton(theme: theme, onTap: onClose),
          ),
        ],
      ),
    );
  }

  // MARK: - Tab bar (active = accent + 2pt underline)

  Widget _tabBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          // INERT E2E key via KeyedSubtree (no RenderObject → golden byte-identical).
          KeyedSubtree(
            key: LbTestKeys.infoTabDetail,
            child: _tab(LBInfoPanelTab.info,
                isLiveBroadcast ? _infoTabTitleLive : _infoTabTitle),
          ),
          // 公告 tab item is built ONLY when noticeCanOpen — NOT built at all
          // (not built-but-hidden/disabled) when it is false
          // (rb-flutter-notice-tab-hide-when-empty). The gap moves inside the
          // conditional too: a single remaining tab must not carry a stray
          // trailing gap.
          if (noticeCanOpen) ...[
            const SizedBox(width: 24),
            KeyedSubtree(
              key: LbTestKeys.infoTabNotice,
              child: _tab(LBInfoPanelTab.notice, _noticeTabTitle),
            ),
          ],
        ],
      ),
    );
  }

  /// One tab label. Callers only ever build a tab that IS currently
  /// selectable (`info` always; `notice` only from the `noticeCanOpen`-gated
  /// branch in `_tabBar()`), so this helper carries no disabled/dimmed styling
  /// branch — there is no longer a "built but disabled" tab state to render.
  Widget _tab(LBInfoPanelTab tab, String title) {
    final isActive = activeTab == tab;
    final underline = isActive ? theme.accent : Colors.transparent;
    final labelColor = isActive ? theme.accent : _textDim;

    final label = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 10),
          child: Text(
            title,
            style: TextStyle(
              color: labelColor,
              fontSize: 13 * theme.fontScale,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        // 2pt accent underline under the active tab.
        Container(height: 2, width: 28, color: underline),
      ],
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelectTab?.call(tab),
      child: label,
    );
  }

  // MARK: Info tab content (VideoInfoSheet body)

  Widget _infoContent() {
    final publishAt = fields.publishAt;
    final title = fields.title;
    final shopIntro = fields.shopIntro;

    return Padding(
      padding: const EdgeInsets.only(left: 18, right: 18, top: 14, bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // publishAt — 直播中 badge + date (isLiveBroadcast) OR plain dim caption (VOD, existing).
          // Both branches reuse the SAME `publishAt` value — no new date field (design R32,
          // 見 `isLiveBroadcast` 自身 dartdoc + `design.md` "Decisions": the host is responsible
          // for feeding an appropriate `publishAt` string for the live case; this widget never
          // parses/strips it).
          if (isLiveBroadcast)
            _liveBadgeRow(publishAt)
          else if (publishAt.isNotEmpty)
            Text(
              publishAt,
              style: TextStyle(color: _textDim, fontSize: 12 * theme.fontScale),
            ),
          // title — primary heading.
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                title,
                style: TextStyle(
                  color: theme.text,
                  fontSize: 17 * theme.fontScale,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          // shopIntro — dim body copy.
          if (shopIntro.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                shopIntro,
                style: TextStyle(
                  color: _textDim,
                  fontSize: 13 * theme.fontScale,
                  height: 1.5,
                ),
              ),
            ),
          // hairline divider.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Container(height: 1, color: _stroke),
          ),
          _shopRow(),
        ],
      ),
    );
  }

  /// The `isLiveBroadcast` date row — a red (`#F03246`)「直播中」badge + `|` + [publishAt]
  /// (design `screens.jsx:1362-1373`). `publishAt` is rendered AS-IS (no parsing / stripping —
  /// see the `isLiveBroadcast` field dartdoc); an empty value still draws the badge alone (no
  /// crash, no placeholder text invented).
  Widget _liveBadgeRow(String publishAt) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: _liveBadgeFill,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _liveBadgeLabel,
            style: TextStyle(
              color: Colors.white,
              fontSize: 10 * theme.fontScale,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('|', style: TextStyle(color: _textDim, fontSize: 12 * theme.fontScale)),
        const SizedBox(width: 8),
        Text(publishAt, style: TextStyle(color: _textDim, fontSize: 12 * theme.fontScale)),
      ],
    );
  }

  /// Shop row — circular shop logo ([_shopLogo]: gradient monogram chip, with the real
  /// `fields.shopLogo` overlaid on the host-runtime path) + shopName + 「這裡是 …」 subline
  /// + subscribe affordance bound to [isSubscribed].
  Widget _shopRow() {
    final shopName = fields.shopName;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _shopLogo(shopName),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (shopName.isNotEmpty) ...[
                Text(
                  shopName,
                  style: TextStyle(
                    color: theme.text,
                    fontSize: 14 * theme.fontScale,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$_shopSublinePrefix$shopName',
                  style: TextStyle(
                    color: _textDim,
                    fontSize: 12 * theme.fontScale,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (showSubscribe) ...[
          const SizedBox(width: 12),
          _subscribePill(),
        ],
      ],
    );
  }

  /// The 44×44 circular shop logo: the deterministic gradient monogram chip, with the
  /// REAL [LBInfoTabFields.shopLogo] overlaid on top on the host-runtime path.
  ///
  /// OVERLAY, NEVER EITHER/OR — the chip is the permanent bottom layer. A remote image
  /// paints NO pixels while it is still downloading and none at all if it fails, so a
  /// two-branch version with no floor underneath would show a transparent HOLE in those
  /// two states. Letting the chip sit underneath makes it the loading AND the failure
  /// placeholder for free: no spinner, no error glyph, no extra asset, not one line of
  /// error handling. (Structurally identical to the iOS lead's `ZStack`; here the shared
  /// [liveProductImage] primitive already Stacks its required `placeholder` underneath,
  /// with `loadingBuilder` / `errorBuilder` drawing empty boxes — so hand-rolling a
  /// `Stack` would only duplicate it and diverge from the six existing call sites.)
  ///
  /// The draw condition IS [resolveShopLogoUrl]'s return value — never a re-derived
  /// `live && shopLogo.isNotEmpty` (see that function's doc for why). The early return
  /// hands back the chip WIDGET-FOR-WIDGET unchanged (no extra SizedBox / ClipOval), so
  /// the golden path's render tree is untouched by construction, not by assumption.
  ///
  /// `live: true` is a literal on purpose: the gate is already settled by the pure
  /// function, so the primitive's own `_httpUri` re-check is its contract (and carries
  /// the cleartext http→https upgrade), not a second copy of the gate. `PlayerHeaderBarView`
  /// passes the same literal. `fit` is deliberately NOT passed — the primitive already
  /// defaults to `BoxFit.cover` and the header avatar relies on that same default.
  Widget _shopLogo(String shopName) {
    final Widget chip = Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD7A8), Color(0xFFE27D5A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Text(
        _monogram(shopName),
        style: TextStyle(
          color: Colors.white,
          fontSize: 12 * theme.fontScale,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    final String? logoUrl = resolveShopLogoUrl(live: live, urlString: fields.shopLogo);
    if (logoUrl == null) return chip;

    // The SizedBox is load-bearing: `liveProductImage`'s drawing branch returns a
    // `Stack(fit: StackFit.expand)`, and the chip's own width/height do NOT propagate as
    // constraints to it inside an unbounded-width Row.
    return SizedBox(
      width: 44,
      height: 44,
      child: ClipOval(
        child: liveProductImage(live: true, url: logoUrl, placeholder: chip),
      ),
    );
  }

  /// Subscribe affordance — outlined accent pill. The label reflects
  /// [isSubscribed] (already-subscribed vs subscribe). Presentation only; the
  /// actual subscribe action is host-wired through core, not owned here.
  Widget _subscribePill() {
    final labelColor = isSubscribed ? _textDim : theme.accent;
    final borderColor = isSubscribed ? _strokeStrong : theme.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Text(
        isSubscribed ? _subscribedLabel : _subscribeLabel,
        style: TextStyle(
          color: labelColor,
          fontSize: 13 * theme.fontScale,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // MARK: Notice tab content (公告) — RECONCILED in-panel two-段 rendering

  Widget _noticeContent() {
    final hasNoticeText = systemNotice.isNotEmpty || notice.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(left: 18, right: 18, top: 16, bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasNoticeText) ...[
            // 系統公告 — faint dot + textDim heading (mirrors design announceBlock).
            if (systemNotice.isNotEmpty)
              _announceBlock(
                label: _systemNoticeLabel,
                labelColor: _textDim,
                dotColor: _textFaint,
                text: systemNotice,
              ),
            // Hairline divider only when BOTH sections are present.
            if (systemNotice.isNotEmpty && notice.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Container(height: 1, color: _stroke),
              ),
            // 商城公告 — accent dot + accent heading.
            if (notice.isNotEmpty)
              _announceBlock(
                label: _mallNoticeLabel,
                labelColor: theme.accent,
                dotColor: theme.accent,
                text: notice,
              ),
          ] else
            // Defensive empty-state placeholder — reached only when a caller
            // constructs noticeCanOpen: true with both texts actually empty (a
            // type-legal but inconsistent combination the view-model never
            // produces). See the DEFENSIVE fallback note near `build()`.
            Text(
              _noticeEmptyPlaceholder,
              style: TextStyle(
                color: _textFaint,
                fontSize: 13 * theme.fontScale,
              ),
            ),
        ],
      ),
    );
  }

  /// One announcement block — a dot + heading (系統 vs 商城 differ by color) then
  /// the body text (always `theme.text`). Mirrors the design's `announceBlock`.
  Widget _announceBlock({
    required String label,
    required Color labelColor,
    required Color dotColor,
    required String text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: labelColor,
                fontSize: 13 * theme.fontScale,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          text,
          style: TextStyle(
            color: theme.text,
            fontSize: 13 * theme.fontScale,
            height: 1.55,
          ),
        ),
      ],
    );
  }
}

// MARK: - Deterministic demo seeds (previews + widget / golden tests)
//
// Fully-populated info-tab fields + notice texts so previews / tests render the
// panel's "happy path" deterministically (no live player). Mirrors iOS
// `VideoInfoPanelView.demo*` and Android `demoVideoInfoPanelState` / `DEMO_*`.

/// A deterministic demo info-tab field snapshot (a 點播 show with title /
/// publishAt / shop / intro). `isSubscribed` is a separate arg (false in demos).
const LBInfoTabFields kDemoVideoInfoFields = LBInfoTabFields(
  title: '夏日通勤彩妝 LIVE 精選',
  publishAt: '點播影片 · Feb 04, 2026',
  shopName: 'BeautyToYou',
  shopIntro:
      '這場直播主推夏日通勤彩妝。整理出 8 款熱銷商品，觀眾可一邊看示範一邊下單，精選色號限時 5 折。',
  shopLogo: '',
);

/// Deterministic demo system-notice copy (textDim 段).
const String kDemoSystemNotice = '系統公告：本場次將於 21:00 開始，敬請準時收看。';

/// Deterministic demo shop-notice copy (accent 段).
const String kDemoNotice =
    '本場直播限定：單筆滿 NT\$999 免運，結帳輸入折扣碼 LIVE5 享 5 折。';
