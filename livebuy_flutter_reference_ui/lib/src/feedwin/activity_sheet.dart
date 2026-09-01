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
//         (2026-08-29, R26 / rb-flutter-live-activity-sheet design.md D3/D4).
// Opened by `WinEntryView(variant: activity)`'s [WinEntryView.onOpenActivity]
// intent (see `win_entry.dart`); container wiring in `feed_win_view.dart`.
//
// Mirrors `WinClaimSheetView`'s (`win_claim_sheet.dart`) centered-modal-card shell
// (scrim + `ClipRRect(radius 20)` + `FractionallySizedBox(widthFactor: 0.84)` +
// `ConstrainedBox(maxWidth: 320)` + a badge floating out the card's top edge) but is
// MUCH simpler: no stage machine, no email input, no confetti — a single static
// presentation of one [LBActiveEvent] snapshot. Unlike `WinClaimSheetView` this is a
// `StatelessWidget`: every piece of rendered state (`event`, `joined`) is a
// by-value snapshot the container re-supplies on each rebuild (via
// `ListenableBuilder(listenable: DefaultActiveEvent)`), so there is no local
// interaction-phase state to own.
//
// ─────────────────────────────────────────────────────────────────────────────
// SUB-VIEW INPUT PATTERN (mirrors the rest of this family)
// ─────────────────────────────────────────────────────────────────────────────
//   1. `theme:` (ReferenceUITheme, required)             — FIRST, always.
//   2. bound SNAPSHOT VALUES (read-only, BY VALUE):
//        `event` (`DefaultActiveEvent.current`, non-null — the container MUST NOT
//        mount this widget when `current == null`, mirroring `WinClaimSheetView`
//        only mounting when a `winner` is selected) / `joined`
//        (`DefaultActiveEvent.joined`).
//   3. action callbacks (LAST, each defaulting to a no-op):
//        `onJoin: VoidCallback?`      — funnels to `DefaultActiveEvent.join()`.
//        `onClose: VoidCallback?`     — funnels to closing the container's local
//                                        "is the sheet open" state. Design.md D4:
//                                        this is a PURE dismiss — it MUST NOT call
//                                        any view-model method (closing ≠ giving
//                                        up; there is no confirm-dismiss dialog
//                                        here, unlike some other R13-era sheet).
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
// function, per `docs/unit-test-discipline.md`) for the exhaustive 3-way branch.
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

/// The 3 mutually-exclusive CTA presentations `ActivitySheetView` can show
/// (design.md D3). A pure function ([activitySheetCtaKind]) derives which one
/// applies from `event.keyword` + `joined` — extracted so the branch is unit-
/// testable without pumping a widget tree.
enum ActivitySheetCtaKind {
  /// `keyword` present, not yet joined — clickable「立即參加」, forwards [onJoin].
  join,

  /// `keyword` present, already joined — disabled「已參加」(gray), inert.
  joined,

  /// `keyword` empty/absent (純活動公告, no participatable keyword) — plain
  /// dismiss/acknowledge「知道了」, forwards [onClose] (NOT [onJoin] — joining a
  /// keyword-less activity has no meaning).
  acknowledge,
}

/// Pure function (design.md D3): derives the CTA presentation from the bound
/// [keyword] (`null` / `''` → keyword-less) and [joined]. Exhaustive — every
/// `(keyword, joined)` combination maps to exactly one [ActivitySheetCtaKind].
ActivitySheetCtaKind activitySheetCtaKind(String? keyword, bool joined) {
  if (keyword == null || keyword.isEmpty) return ActivitySheetCtaKind.acknowledge;
  return joined ? ActivitySheetCtaKind.joined : ActivitySheetCtaKind.join;
}

// MARK: - Decorative design tokens (literal minimal hex via colorFromHex)
//
// Mirrors `win_claim_sheet.dart`'s established convention: fixed decorative
// colors lifted verbatim from the design (light mode), so this file reads as
// part of the same visual family as `WinClaimSheetView`.

/// `theme.surface.textDim` (secondary / caption text) — same hex as
/// `win_claim_sheet.dart`'s `_textDim`.
final Color _textDim = colorFromHex('#6B6775') ?? const Color(0xFF6B6775);

/// Disabled/「已參加」CTA background (`LBActivitySheet`'s literal
/// `background: joined ? '#C9CDD3' : accent`).
final Color _joinedBackground = colorFromHex('#C9CDD3') ?? const Color(0xFFC9CDD3);

/// Modal scrim (`LBActivitySheet` / `WinClaimSheetView` shared `rgba(0,0,0,0.6)`).
final Color _scrimColor = Colors.black.withValues(alpha: 0.6);

// MARK: - Fixed localized copy (static presentation strings — parity with the
// rest of this family; this layer全層寫死中文常數, 不使用任何 i18n API)

const String _ctaJoin = '立即參加';
const String _ctaJoined = '已參加';
const String _ctaAcknowledge = '知道了';
const String _footerTerms = '使用條款';
const String _footerSeparator = ' | ';
const String _footerPrivacy = '隱私政策';

/// Badge glyph render size inside the 60×60 badge circle (`LBActivitySheet`'s
/// literal `giftSvg(30, accent)`).
const double _badgeGlyphSize = 30;

/// The family-2 抽獎活動彈窗 (one [LBActiveEvent] at a time). Presents the
/// activity's title, prize name, an optional「留言關鍵字」CTA hint, a main CTA
/// whose text/enabled-state/tap-target follow [activitySheetCtaKind], and a
/// footer「使用條款 | 隱私政策」mirroring `WinClaimSheetView`.
///
/// Renders correctly with all callbacks omitted (golden / preview safe).
class ActivitySheetView extends StatelessWidget {
  /// Resolved reference-ui theme (FIRST positional argument, always).
  final ReferenceUITheme theme;

  /// The active event this sheet presents (`DefaultActiveEvent.current`, by
  /// value). The container MUST NOT mount this widget when there is none
  /// (mirrors `WinClaimSheetView` only mounting when a `winner` is selected).
  final LBActiveEvent event;

  /// Whether [event] has already been joined (`DefaultActiveEvent.joined`), by
  /// value. Drives [activitySheetCtaKind]'s disabled「已參加」branch. This
  /// widget MUST NOT hold a second copy of this state — the container re-reads
  /// the view-model getter on every rebuild.
  final bool joined;

  /// 「立即參加」CTA tapped (only reachable when [activitySheetCtaKind] is
  /// [ActivitySheetCtaKind.join]). Container forwards
  /// `DefaultPlayerTemplate.activeEvent.join()` — the view-model handles
  /// dedupe, this layer does not repeat that check. Default no-op so demo /
  /// golden instances construct action-free.
  final VoidCallback? onJoin;

  /// Close the sheet (scrim tap, or the keyword-less「知道了」CTA). A PURE
  /// dismiss (design.md D4) — MUST NOT be interpreted as "gave up the
  /// activity"; the container only clears its own local open/closed state,
  /// MUST NOT call any view-model method. Default no-op.
  final VoidCallback? onClose;

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
    required this.joined,
    this.onJoin,
    this.onClose,
    this.onOpenTermsOfUse,
    this.onOpenPrivacyPolicy,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Outer scrim — tapping it is a PURE dismiss (forwards onClose only).
        Positioned.fill(
          child: GestureDetector(
            key: LbTestKeys.activitySheetScrim,
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
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
    );
  }

  /// The badge floating out the card's top edge: a white 60×60 circle, 4px
  /// card-background-colored border, centered ACCENT-colored trophy/gift glyph
  /// (design.md D4 — the SAME ported Path `WinEntryView` uses, tinted with
  /// [ReferenceUITheme.accent] instead of `WinEntryView`'s hardcoded red).
  Widget _badge() {
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
        const SizedBox(height: 14),
        _footerRow(),
      ],
    );
  }

  /// The main CTA — text/enabled-state/tap-target follow [activitySheetCtaKind]
  /// (a pure function of `event.keyword` + `joined`).
  Widget _ctaButton(String? keyword) {
    final kind = activitySheetCtaKind(keyword, joined);
    final String label;
    final VoidCallback? tap;
    final Color background;
    final Color foreground;
    switch (kind) {
      case ActivitySheetCtaKind.join:
        label = _ctaJoin;
        tap = onJoin;
        background = theme.accent;
        foreground = Colors.white;
      case ActivitySheetCtaKind.joined:
        label = _ctaJoined;
        tap = null;
        background = _joinedBackground;
        // `LBActivitySheet` keeps the CTA text WHITE regardless of the
        // joined/disabled state — only the background swaps to the neutral gray.
        foreground = Colors.white;
      case ActivitySheetCtaKind.acknowledge:
        label = _ctaAcknowledge;
        tap = onClose;
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

  // MARK: - Footer（使用條款 | 隱私政策 — 各自可點擊，鏡射 WinClaimSheetView 既有慣例）

  Widget _footerRow() {
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
          onTap: onOpenTermsOfUse,
          child: Text(_footerTerms, style: style),
        ),
        Opacity(opacity: 0.5, child: Text(_footerSeparator, style: style)),
        GestureDetector(
          key: LbTestKeys.activitySheetFooterPrivacy,
          behavior: HitTestBehavior.opaque,
          onTap: onOpenPrivacyPolicy,
          child: Text(_footerPrivacy, style: style),
        ),
      ],
    );
  }
}
