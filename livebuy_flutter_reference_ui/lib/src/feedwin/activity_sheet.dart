import 'package:flutter/material.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart' show LBActiveEvent;

import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';
import 'win_glyph.dart';

// ActivitySheetView — family-2 feed-win surface (直播抽獎「進行中活動」彈窗, Flutter).
//
// Spec: `reference-ui-rendering/spec.md`
//   § "渲染 Flutter 抽獎活動彈窗（`ActivitySheetView`），綁 DefaultActiveEvent"
// Design: `design/templates/minimal/moments.jsx` `LBActivitySheet`
//         (2026-08-29, R26 / rb-flutter-live-activity-sheet design.md D3/D4;
//         分頁能力 2026-09-01, rb-flutter-activity-sheet-pagination — 對齊 `LBActivitySheet`
//         現行 HEAD 的 `pageCount`/`pageIndex`/`onPage` 三個 prop).
// Opened by `WinEntryView(variant: activity)`'s [WinEntryView.onOpenActivity]
// intent (see `win_entry.dart`); container wiring in `feed_win_view.dart`.
//
// Mirrors `WinClaimSheetView`'s (`win_claim_sheet.dart`) centered-modal-card shell
// (scrim + `ClipRRect(radius 20)` + `FractionallySizedBox(widthFactor: 0.84)` +
// `ConstrainedBox(maxWidth: 320)` + a badge floating out the card's top edge) but is
// MUCH simpler: no stage machine, no email input, no confetti — a single static
// presentation of one [LBActiveEvent] snapshot. The rendered `event` is a
// by-value snapshot the container re-supplies on each rebuild (via
// `ListenableBuilder(listenable: DefaultActiveEvent)`), so there is no
// interaction-PHASE local state to own — unlike `WinClaimSheetView`'s multi-stage
// claim/confirm/submit/done/fail machine, this widget never needs a
// `didUpdateWidget` reset when the container pages to a different event (paging
// simply supplies a fresh `event` snapshot, which IS a new render).
//
// 🔴 rb-flutter-activity-sheet-pagination — `StatelessWidget` → `StatefulWidget`:
// the ONLY local state this change adds is the horizontal-drag distance
// accumulator the swipe gesture needs during a single gesture's lifecycle
// (`_dragAccumulator`, zeroed on `onHorizontalDragStart` / consumed on
// `onHorizontalDragEnd` — see `_ActivitySheetViewState`). See design.md D-1 for why
// this does NOT need a `WinClaimSheetView`-style `didUpdateWidget` reset.
//
// 🔴 rb-flutter-activity-sheet-cta-repeatable — the CTA is now REPEATABLE: the
// widget no longer accepts a `joined` snapshot and [activitySheetCtaKind] no
// longer has a disabled/「已參加」branch (the `joined` case is REMOVED, not just
// unreachable — a bound-but-dead enum case/branch was judged worse than a
// smaller two-way enum, see design.md). A keyword-present event's CTA now
// ALWAYS renders as clickable「立即參加」and forwards [ActivitySheetView.onJoin]
// on every tap, no matter how many times it has already been tapped — reported
// bug: the sheet used to lock into a disabled「已參加」state after one join,
// which read as "you can no longer respond" even though repeat participation
// should stay possible. The container (`feed_win_view.dart`) correspondingly no
// longer reads `DefaultActiveEvent.joined` when constructing this widget — that
// view-model getter (`FeedWinModel.activeEventJoined`, now removed as dead code)
// stays owned by `flutter-ui`/`DefaultActiveEvent` untouched; this is a pure
// reference-ui rendering change, not a template-layer behavior change.
//
// ─────────────────────────────────────────────────────────────────────────────
// SUB-VIEW INPUT PATTERN (mirrors the rest of this family)
// ─────────────────────────────────────────────────────────────────────────────
//   1. `theme:` (ReferenceUITheme, required)             — FIRST, always.
//   2. bound SNAPSHOT VALUES (read-only, BY VALUE):
//        `event` (`DefaultActiveEvent.current`, non-null — the container MUST NOT
//        mount this widget when `current == null`, mirroring `WinClaimSheetView`
//        only mounting when a `winner` is selected) / `pageCount` (`int`,
//        default `1`, `DefaultActiveEvent.activities.length` —
//        rb-flutter-activity-sheet-pagination) / `pageIndex` (`int`, default `0`,
//        `DefaultActiveEvent.currentActivityPageIndex` — same change). 🔴 There is
//        no `joined` snapshot — rb-flutter-activity-sheet-cta-repeatable removed
//        it (the CTA no longer reads any "already joined" signal).
//   3. action callbacks (LAST, each defaulting to a no-op):
//        `onJoin: VoidCallback?`      — funnels to `DefaultActiveEvent.join()`.
//        `onClose: VoidCallback?`     — funnels to closing the container's local
//                                        "is the sheet open" state. Design.md D4:
//                                        this is a PURE dismiss — it MUST NOT call
//                                        any view-model method (closing ≠ giving
//                                        up; there is no confirm-dismiss dialog
//                                        here, unlike some other R13-era sheet).
//        `onPage: ValueChanged<int>?` — 換頁（滑動或點分頁圓點，
//                                        rb-flutter-activity-sheet-pagination），container
//                                        forwards to `DefaultActiveEvent.setActivityPageIndex`.
//                                        `null` (demo / golden / `pageCount <= 1`) →
//                                        swipe gesture and dot taps are safe inert.
//        `onOpenTermsOfUse` / `onOpenPrivacyPolicy: VoidCallback?` — the footer's
//                                        two text taps, same forwarding contract
//                                        as `WinClaimSheetView`'s footer.
//
// This sub-view only reads passed-in values — it never reaches back into
// `DefaultActiveEvent` / `DefaultPlayerTemplate` (one-way data flow), and all
// callbacks default to no-ops so demo / golden instances construct action-free.
//
// D3 — `event.keyword` empty (`null` or `''`, a純活動公告 with no participatable
// keyword — the SAME "no CTA" semantics `turnkey-event-join` already applies to
// `LBEventJoinLine`) → the「留言關鍵字【…】即可參加抽獎！」line is NOT drawn, and the
// main CTA's semantics change from「立即參加」to a plain dismiss/acknowledge
// (「知道了」，tapping it forwards `onClose`, NOT `onJoin` — joining a keyword-less
// activity is not a meaningful action). See [activitySheetCtaKind] (a pure
// function, per `docs/unit-test-discipline.md`) for the exhaustive 2-way branch
// (🔴 rb-flutter-activity-sheet-cta-repeatable collapsed the prior 3-way branch
// — `join` / `joined` / `acknowledge` — down to 2: `join` / `acknowledge`. The
// keyword-present CTA is now a single always-clickable「立即參加」presentation).
//
// D4 — the badge glyph reuses `win_glyph.dart`'s `WinTrophyGlyphPainter` (the SAME
// ported SVG Path `WinEntryView` uses) rather than re-porting the coordinate data a
// third time. The design calls for an ACCENT-colored glyph here (vs `WinEntryView`'s
// hardcoded `#F03246`), so the outer fill is overridden via
// `WinTrophyGlyphPainter(outerColor: theme.accent)` — same Path, different tint;
// see `win_glyph.dart`'s header for why `WinClaimSheetView`'s OWN badge (a generic
// `Icon(Icons.card_giftcard)`) is a separate, untouched, pre-existing thing.
//
// RENDER DISCIPLINE (inherited from the rest of this family): plain `Column` /
// `Row` / `Stack`. NO `ListView` / `GridView` / `SingleChildScrollView`, NO
// `Image.network` / `NetworkImage`, NO animation / randomness — so the golden
// baseline is deterministic.

/// The 2 mutually-exclusive CTA presentations `ActivitySheetView` can show
/// (design.md D3; 🔴 rb-flutter-activity-sheet-cta-repeatable removed the prior
/// 3rd "already joined" presentation entirely — see that change's design.md for
/// why the dead branch was deleted rather than kept-but-unreachable). A pure
/// function ([activitySheetCtaKind]) derives which one applies from
/// `event.keyword` alone — extracted so the branch is unit-testable without
/// pumping a widget tree.
enum ActivitySheetCtaKind {
  /// `keyword` present — ALWAYS clickable「立即參加」, forwards [onJoin] on every
  /// tap. 🔴 rb-flutter-activity-sheet-cta-repeatable: this is now the CTA's ONLY
  /// keyword-present presentation — it MUST NOT ever lock into a disabled state
  /// after a join, so the same activity stays repeatably joinable.
  join,

  /// `keyword` empty/absent (純活動公告, no participatable keyword) — plain
  /// dismiss/acknowledge「知道了」, forwards [onClose] (NOT [onJoin] — joining a
  /// keyword-less activity has no meaning).
  acknowledge,
}

/// Pure function (design.md D3): derives the CTA presentation from the bound
/// [keyword] (`null` / `''` → keyword-less). Exhaustive — every `keyword` value
/// maps to exactly one [ActivitySheetCtaKind]. 🔴 rb-flutter-activity-sheet-cta-repeatable
/// removed the `joined` parameter this function used to take — the CTA no
/// longer reads any "already joined" signal, so a keyword-present event always
/// resolves to [ActivitySheetCtaKind.join] (repeatable, never disabled).
ActivitySheetCtaKind activitySheetCtaKind(String? keyword) {
  if (keyword == null || keyword.isEmpty) return ActivitySheetCtaKind.acknowledge;
  return ActivitySheetCtaKind.join;
}

/// Pure function (rb-flutter-activity-sheet-pagination, design.md D-2): given the
/// accumulated horizontal drag distance [dx] of a just-ended swipe gesture, the
/// current [pageIndex], and [pageCount], returns the target page index the swipe
/// resolves to — or `null` when the swipe is a no-op (`pageCount <= 1`, the
/// distance is below the 40px threshold, or the resolved index would fall outside
/// `[0, pageCount)`, e.g. swiping further past the first/last page).
///
/// Unlike `WinClaimSheetView`'s equivalent `_handleSwipeEnd` (which inlines this
/// judgement as a `State` instance method reading `widget.*` fields directly),
/// this is a standalone top-level function with no widget/gesture dependency — it
/// can be unit tested with plain numeric inputs, without pumping a widget tree.
/// `dx < 0` (leftward swipe) → next page; `dx > 0` (rightward swipe) → previous
/// page — matches the design source's `LBActivitySheet` `onSwipeEnd` semantics.
int? activitySheetSwipeTargetPage({
  required double dx,
  required int pageIndex,
  required int pageCount,
}) {
  if (pageCount <= 1) return null;
  if (dx.abs() < 40) return null;
  final next = dx < 0 ? pageIndex + 1 : pageIndex - 1;
  if (next < 0 || next >= pageCount) return null;
  return next;
}

// MARK: - Decorative design tokens (literal minimal hex via colorFromHex)
//
// Mirrors `win_claim_sheet.dart`'s established convention: fixed decorative
// colors lifted verbatim from the design (light mode), so this file reads as
// part of the same visual family as `WinClaimSheetView`. Dart's `_` prefix is
// FILE-level (library) private, not class-private — `win_claim_sheet.dart`'s own
// copies of these tokens are NOT visible here, so each decorative color this file
// needs is independently re-declared, matching the pattern already used for
// `_textDim` / `_scrimColor` below (this file never imports
// `win_claim_sheet.dart`'s copies). 🔴 rb-flutter-activity-sheet-cta-repeatable
// REMOVED the former `_joinedBackground` token (`#C9CDD3`, the disabled/「已參加」
// CTA background) — the CTA no longer has a disabled state to color.

/// `theme.surface.textDim` (secondary / caption text) — same hex as
/// `win_claim_sheet.dart`'s `_textDim`.
final Color _textDim = colorFromHex('#6B6775') ?? const Color(0xFF6B6775);

/// Modal scrim (`LBActivitySheet` / `WinClaimSheetView` shared `rgba(0,0,0,0.6)`).
final Color _scrimColor = Colors.black.withValues(alpha: 0.6);

/// 分頁圓點（rb-flutter-activity-sheet-pagination）非目前頁的顏色 —— 設計稿
/// `background: i === pageIndex ? accent : (S.border || '#D8DBE0')`。`theme.surface`
/// 實際**沒有** `border` 欄位，故該運算式永遠退回字面值 `#D8DBE0` —— 這才是真正被畫出來的
/// 顏色（同 `win_claim_sheet.dart` 自己那份 `_pageDotInactive` 的既有判斷，此處為該檔案
/// 獨立重新宣告的同值 file-private 常數，非 import）。
final Color _pageDotInactive = colorFromHex('#D8DBE0') ?? const Color(0xFFD8DBE0);

// MARK: - Fixed localized copy (static presentation strings — parity with the
// rest of this family; this layer全層寫死中文常數, 不使用任何 i18n API)

const String _ctaJoin = '立即參加';
const String _ctaAcknowledge = '知道了';
const String _footerTerms = '使用條款';
const String _footerSeparator = ' | ';
const String _footerPrivacy = '隱私政策';

/// Badge glyph render size inside the 60×60 badge circle (`LBActivitySheet`'s
/// literal `giftSvg(30, accent)`).
const double _badgeGlyphSize = 30;

/// The family-2 抽獎活動彈窗 (one [LBActiveEvent] at a time). Presents the
/// activity's title, prize name, an optional「留言關鍵字」CTA hint, a main CTA
/// whose text/tap-target follow [activitySheetCtaKind], an optional pagination
/// dot row (`pageCount > 1`, rb-flutter-activity-sheet-pagination), and a
/// footer「使用條款 | 隱私政策」mirroring `WinClaimSheetView`. 🔴
/// rb-flutter-activity-sheet-cta-repeatable: the keyword-present CTA is ALWAYS
/// clickable「立即參加」— there is no "already joined" disabled state, so a host
/// can join the same activity again on a repeat tap.
///
/// Renders correctly with all callbacks omitted (golden / preview safe).
class ActivitySheetView extends StatefulWidget {
  /// Resolved reference-ui theme (FIRST positional argument, always).
  final ReferenceUITheme theme;

  /// The active event this sheet presents (`DefaultActiveEvent.current`, by
  /// value). The container MUST NOT mount this widget when `current == null`
  /// (mirrors `WinClaimSheetView` only mounting when a `winner` is selected).
  final LBActiveEvent event;

  /// 分頁能力（rb-flutter-activity-sheet-pagination）：目前同時進行中的活動總數。容器
  /// 傳入 `DefaultActiveEvent.activities.length`。`<= 1` 時分頁圓點不畫、滑動手勢為安全
  /// no-op。預設 `1`（既有 golden / demo 單頁行為 byte-identical）。
  final int pageCount;

  /// 目前顯示的頁碼（`DefaultActiveEvent.activities` 的索引，即
  /// `DefaultActiveEvent.currentActivityPageIndex`）。容器持有的呈現層開啟狀態 by value
  /// 傳入 —— 這個 widget 不因此持有第二份「目前顯示哪一筆」的狀態：每次換頁，容器的
  /// `event` 快照本身就已經是新的一次渲染（design.md D-1）。預設 `0`。
  final int pageIndex;

  /// 「立即參加」CTA 被點擊（只在 [activitySheetCtaKind] 為 [ActivitySheetCtaKind.join]
  /// 時可達）。🔴 rb-flutter-activity-sheet-cta-repeatable：這個 CTA 是**可重複**點擊
  /// 的——每次點擊都轉發本 callback，widget 本身 MUST NOT 因為之前點過就把它鎖成
  /// disabled。容器轉發 `DefaultPlayerTemplate.activeEvent.join()` — the view-model
  /// handles dedupe, this layer does not repeat that check. Default no-op so demo /
  /// golden instances construct action-free.
  final VoidCallback? onJoin;

  /// Close the sheet (scrim tap, or the keyword-less「知道了」CTA). A PURE
  /// dismiss (design.md D4) — MUST NOT be interpreted as "gave up the
  /// activity"; the container only clears its own local open/closed state,
  /// MUST NOT call any view-model method. Default no-op.
  final VoidCallback? onClose;

  /// 換頁（滑動或點分頁圓點，rb-flutter-activity-sheet-pagination）。容器轉發
  /// `DefaultActiveEvent.setActivityPageIndex(index)`。`null`（demo / golden /
  /// `pageCount <= 1`）→ 滑動手勢與圓點點擊皆安全 inert。容器 MUST NOT 自行再做邊界
  /// 檢查 —— `setActivityPageIndex` 內部已安全 clamp。
  final ValueChanged<int>? onPage;

  /// footer「使用條款」text tapped. Container forwards to its legal-link route
  /// (mirrors `WinClaimSheetView.onOpenTermsOfUse`). Default no-op — inert.
  final VoidCallback? onOpenTermsOfUse;

  /// footer「隱私政策」text tapped. Same forwarding contract as
  /// [onOpenTermsOfUse]. Default no-op — inert.
  final VoidCallback? onOpenPrivacyPolicy;

  const ActivitySheetView({
    super.key,
    required this.theme,
    required this.event,
    this.pageCount = 1,
    this.pageIndex = 0,
    this.onJoin,
    this.onClose,
    this.onPage,
    this.onOpenTermsOfUse,
    this.onOpenPrivacyPolicy,
  });

  @override
  State<ActivitySheetView> createState() => _ActivitySheetViewState();
}

class _ActivitySheetViewState extends State<ActivitySheetView> {
  /// 累積目前這次水平拖曳手勢的位移（正 = 向右拖、負 = 向左拖）。只在拖曳期間有意義，手勢
  /// 結束時由 [_handleSwipeEnd] 消費並歸零（rb-flutter-activity-sheet-pagination）。這是
  /// 這個 widget 從 `StatelessWidget` 改為 `StatefulWidget` 唯一新增的 local state（見檔頭
  /// 說明 + design.md D-1 為何不需要額外的 `didUpdateWidget` 重置邏輯）。
  double _dragAccumulator = 0;

  /// 分頁滑動手勢結束時的判定（rb-flutter-activity-sheet-pagination）：讀取累積位移、歸零，
  /// 呼叫抽出的純函式 [activitySheetSwipeTargetPage] 判斷結果，非 `null` 且
  /// [ActivitySheetView.onPage] 非 `null` 時才轉發。`pageCount <= 1` 或 `onPage == null`
  /// 皆安全 no-op（MUST NOT 拋錯）。
  void _handleSwipeEnd() {
    final dx = _dragAccumulator;
    _dragAccumulator = 0;
    final next = activitySheetSwipeTargetPage(
      dx: dx,
      pageIndex: widget.pageIndex,
      pageCount: widget.pageCount,
    );
    if (next == null) return;
    widget.onPage?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 分頁滑動手勢（rb-flutter-activity-sheet-pagination）：包住整個 modal（scrim + 底
      // 卡），對齊設計稿 `LBActivitySheet` 外層 `onTouchStart`/`onTouchEnd` 量測 `clientX`
      // 位移的做法，同時比照 `WinClaimSheetView.build()` 既有的外層水平拖曳
      // `GestureDetector` 包裹結構（其內層各顆 tap `GestureDetector` 已證實可與外層水平
      // 拖曳共存於同一個 gesture arena，不互相搶奪）。`_handleSwipeEnd` 本身對
      // `pageCount <= 1` / `onPage == null` 皆安全 no-op，故此手勢不需要另外用
      // `pageCount > 1` 條件式掛載。
      onHorizontalDragStart: (_) => _dragAccumulator = 0,
      onHorizontalDragUpdate: (details) => _dragAccumulator += details.delta.dx,
      onHorizontalDragEnd: (_) => _handleSwipeEnd(),
      child: Stack(
        children: [
          // Outer scrim — tapping it is a PURE dismiss (forwards onClose only).
          Positioned.fill(
            child: GestureDetector(
              key: LbTestKeys.activitySheetScrim,
              behavior: HitTestBehavior.opaque,
              onTap: widget.onClose,
              child: ColoredBox(color: _scrimColor),
            ),
          ),

          // Centered card (含浮出卡頂外的徽章). Outer Stack does NOT clip so the
          // badge can float above the card's top edge; the card itself clips its
          // own content via ClipRRect.
          Positioned.fill(
            child: Center(
              child: FractionallySizedBox(
                widthFactor: 0.84,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _card(),
                      Positioned(
                        top: -30,
                        left: 0,
                        right: 0,
                        child: Center(child: _badge()),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The badge floating out the card's top edge: a white 60×60 circle, 4px
  /// card-background-colored border, centered ACCENT-colored trophy/gift glyph
  /// (design.md D4 — the SAME ported Path `WinEntryView` uses, tinted with
  /// [ReferenceUITheme.accent] instead of `WinEntryView`'s hardcoded red).
  Widget _badge() {
    final theme = widget.theme;
    return Container(
      width: 60,
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFFFFFFF),
        border: Border.all(color: theme.background, width: 4),
      ),
      child: CustomPaint(
        size: const Size(_badgeGlyphSize, _badgeGlyphSize),
        painter: WinTrophyGlyphPainter(outerColor: theme.accent),
      ),
    );
  }

  /// The card body shell (radius 20, `ColoredBox(theme.background)`, top padding
  /// 46 to clear the floating badge — mirrors BOTH `LBActivitySheet`'s literal
  /// `padding: '46px 24px 24px'` AND `WinClaimSheetView._card`'s `claim`-stage
  /// padding; the 22 side inset (vs. the design's literal 24) follows
  /// `WinClaimSheetView`'s own established side-inset value).
  Widget _card() {
    final theme = widget.theme;
    return GestureDetector(
      key: LbTestKeys.activitySheet,
      behavior: HitTestBehavior.opaque,
      // Swallow taps on the card itself so they don't fall through to the scrim.
      onTap: () {},
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x59000000), // black @ 0.35
              blurRadius: 32,
              offset: Offset(0, 24),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: ColoredBox(
            color: theme.background,
            child: Padding(
              padding: const EdgeInsets.only(top: 46, left: 22, right: 22, bottom: 22),
              child: _cardBody(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cardBody() {
    final theme = widget.theme;
    final event = widget.event;
    final awardName = event.award.isNotEmpty ? event.award.first.name : '';
    final keyword = event.keyword;
    final hasKeyword = keyword != null && keyword.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              event.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.text,
                fontSize: 22 * theme.fontScale,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              awardName,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _textDim,
                fontSize: 14.5 * theme.fontScale,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        // D3 — keyword-less (純活動公告) → the留言關鍵字 line is NOT drawn (no
        // blank-bracket「留言關鍵字【】」placeholder).
        if (hasKeyword) ...[
          const SizedBox(height: 14),
          Text(
            '留言關鍵字【$keyword】即可參加抽獎！',
            textAlign: TextAlign.center,
            // `LBActivitySheet`'s literal `fontSize:14, fontWeight:700, height:1.5`.
            style: TextStyle(
              color: theme.accent,
              fontSize: 14 * theme.fontScale,
              fontWeight: FontWeight.bold,
              height: 1.5,
            ),
          ),
        ],
        const SizedBox(height: 14),
        _ctaButton(keyword),
        // 分頁圓點（rb-flutter-activity-sheet-pagination）—— 僅 `pageCount > 1` 時畫，位置
        // 在 CTA 之後、footer 之前，對齊設計稿 `LBActivitySheet` 的子元素順序，也對齊
        // `WinClaimSheetView._claimCardBody()` 的既有順序（CTA → dots → footer）。
        if (widget.pageCount > 1) ...[
          const SizedBox(height: 14),
          _paginationDots(),
        ],
        const SizedBox(height: 14),
        _footerRow(),
      ],
    );
  }

  /// The main CTA — text/tap-target follow [activitySheetCtaKind] (a pure
  /// function of `event.keyword` alone). 🔴 rb-flutter-activity-sheet-cta-repeatable:
  /// there is no disabled state any more — [ActivitySheetCtaKind.join] is always
  /// clickable and always forwards [ActivitySheetView.onJoin], repeat taps
  /// included.
  Widget _ctaButton(String? keyword) {
    final theme = widget.theme;
    final kind = activitySheetCtaKind(keyword);
    final String label;
    final VoidCallback? tap;
    final Color background;
    final Color foreground;
    switch (kind) {
      case ActivitySheetCtaKind.join:
        label = _ctaJoin;
        tap = widget.onJoin;
        background = theme.accent;
        foreground = Colors.white;
      case ActivitySheetCtaKind.acknowledge:
        label = _ctaAcknowledge;
        tap = widget.onClose;
        background = theme.accent;
        foreground = Colors.white;
    }
    return GestureDetector(
      key: LbTestKeys.activitySheetCta,
      behavior: HitTestBehavior.opaque,
      onTap: tap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontSize: 15.5 * theme.fontScale,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  /// 分頁圓點列（rb-flutter-activity-sheet-pagination）——`pageCount` 個 6×6 圓點，5px
  /// 間距，僅 `pageCount > 1` 時畫（見 [_cardBody]）。當前頁 [ReferenceUITheme.accent]
  /// 實色、其餘為設計稿等效色 [_pageDotInactive]。每顆圓點皆可點擊，呼叫 `onPage(index)`
  /// （[ActivitySheetView.onPage] 為 `null` 時安全 inert）。視覺樣式逐字比照
  /// `WinClaimSheetView._paginationDots()`（design.md D-3：file-local 私有 widget，不抽
  /// 共用元件）。
  Widget _paginationDots() {
    final theme = widget.theme;
    return Row(
      key: LbTestKeys.activitySheetPageDots,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < widget.pageCount; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          GestureDetector(
            key: LbTestKeys.activitySheetPageDot(i),
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onPage?.call(i),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == widget.pageIndex ? theme.accent : _pageDotInactive,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // MARK: - Footer（使用條款 | 隱私政策 — 各自可點擊，鏡射 WinClaimSheetView 既有慣例）

  Widget _footerRow() {
    final theme = widget.theme;
    final style = TextStyle(
      color: _textDim,
      fontSize: 12.5 * theme.fontScale,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.2,
    );
    return Row(
      key: LbTestKeys.activitySheetFooter,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          key: LbTestKeys.activitySheetFooterTerms,
          behavior: HitTestBehavior.opaque,
          onTap: widget.onOpenTermsOfUse,
          child: Text(_footerTerms, style: style),
        ),
        Opacity(opacity: 0.5, child: Text(_footerSeparator, style: style)),
        GestureDetector(
          key: LbTestKeys.activitySheetFooterPrivacy,
          behavior: HitTestBehavior.opaque,
          onTap: widget.onOpenPrivacyPolicy,
          child: Text(_footerPrivacy, style: style),
        ),
      ],
    );
  }
}
