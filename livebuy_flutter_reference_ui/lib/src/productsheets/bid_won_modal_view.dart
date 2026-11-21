import 'package:flutter/widgets.dart';
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart' show LBBidWonItem;

import '../i18n/i18n.dart';
import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';
import 'sheet_scaffold.dart' show liveProductImage;
import 'storefront_fill_glyph.dart';

// MARK: - BidWonModalView — flash-sale「恭喜搶購成功」centered popup (Flutter)
//
// Spec: `reference-ui-rendering/spec.md` §「LivebuyReferenceUI 搶購得標視窗（Flutter）」
// (rb-flutter-flash-sale-bid). Design: `design/templates/minimal/moments.jsx` `LBBidWonModal`
// (claude-design-sync.md D10). Flutter parity of iOS `BidWonModalView.swift` / Android
// `BidWonModalView.kt` / RN `BidWonModalView.tsx`.
//
// Binds `DefaultPlayerTemplate.bidWon` (`DefaultBidWon`, live-bid-flutter-template) through
// `ProductSheetsModel.bidWonItems` / `bidWonPresented`; the container (`ProductSheetsOverlayView`)
// mounts it at the overlay root while `bidWonPresented` and wires「確定」→ `confirmBidWin()`、
// 「取消」→ `dismissBidWon()`. PURE presentation: the only local state is the visible page index.
//
// Layout (same numbers as iOS): black 0.6 scrim (swallows taps, does NOT close), white card
// min(84%, 320) wide, radius 20, padding 44 / 20 / 20, 16 gaps; a 60 white circular merchant logo
// with a 4 white border, half (30) above the card's top edge — the filled storefront glyph (30,
// accent) always sits underneath and the real logo is layered on top only when one resolves;
// title (accent 20 / w800), product name (15 / bold, wraps, never truncated, line height 1.45 as
// Android / RN), 「數量 x{num}」(13.5 / w500, textDim); one item → no dots, several → horizontal swipe
// judged on the FULL down→up displacement (≥ 40 turns the page, no wrap) + 6 pagination dots; bottom
// 「取消」outline 1.5 /「確定」filled, equal width and height. No close button.

/// `rgba(0,0,0,0.6)` scrim.
const Color _scrim = Color(0x99000000);

/// `#6B6775` — design textDim (same literal as iOS / Android / RN).
const Color _textDim = Color(0xFF6B6775);

/// `#D8DBE0` — inactive pagination dot.
const Color _dotInactive = Color(0xFFD8DBE0);

const Color _white = Color(0xFFFFFFFF);

/// Pure helpers (parity iOS `BidWonModalView` statics / Android `BidWonModal` / RN `BidWonModal`).
abstract final class BidWonModal {
  /// Horizontal swipe distance that turns the page (design `onSwipeEnd` `Math.abs(dx) < 40`).
  static const double swipeThreshold = 40;
  static const double logoSize = 60;
  static const double logoBorder = 4;

  /// Card width: 84% of the container, capped at 320.
  static double cardWidth(double containerWidth) {
    final w = containerWidth * 0.84;
    return w < 320 ? w : 320;
  }

  static int clampPage(int page, int count) {
    if (count <= 0) return 0;
    if (page < 0) return 0;
    if (page > count - 1) return count - 1;
    return page;
  }

  /// Next page after a horizontal swipe of [dx] (full displacement): `< 40` or a single item →
  /// unchanged; left swipe → +1, right → −1, never past either end.
  static int pageAfterSwipe(int current, double dx, int count) {
    if (count <= 1 || dx.abs() < swipeThreshold) return current;
    final next = dx < 0 ? current + 1 : current - 1;
    return (next >= 0 && next < count) ? next : current;
  }

  static bool showsDots(int count) => count > 1;
}

/// The「恭喜搶購成功」popup. [shopLogoUrl] is the merchant logo already resolved through the header
/// logo gate (`PlayerHeaderBarView.resolveShopLogoUrl`) — `null` → storefront glyph only, so demo /
/// golden paths (`live == false`) never load an image.
class BidWonModalView extends StatefulWidget {
  final ReferenceUITheme theme;
  final List<LBBidWonItem> items;
  final String? shopLogoUrl;
  final int initialPage;

  /// 「確定」→ confirm every listed win once (container: `model.confirmBidWin()`).
  final VoidCallback? onConfirm;

  /// 「取消」→ close only (container: `model.dismissBidWon()`).
  final VoidCallback? onCancel;

  const BidWonModalView({
    super.key,
    required this.theme,
    required this.items,
    this.shopLogoUrl,
    this.initialPage = 0,
    this.onConfirm,
    this.onCancel,
  });

  @override
  State<BidWonModalView> createState() => _BidWonModalViewState();
}

class _BidWonModalViewState extends State<BidWonModalView> {
  late int _page = BidWonModal.clampPage(widget.initialPage, widget.items.length);
  double? _downX;

  ReferenceUITheme get _theme => widget.theme;

  @override
  Widget build(BuildContext context) => referenceUILocalized(() => _build());

  Widget _build() {
    return LayoutBuilder(builder: (context, constraints) {
      final items = widget.items;
      return Stack(
        fit: StackFit.expand,
        children: [
          // Scrim swallows taps but does NOT close (design: no backdrop dismiss).
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: const ColoredBox(color: _scrim),
          ),
          if (items.isNotEmpty)
            Center(
              child: SizedBox(
                width: BidWonModal.cardWidth(constraints.maxWidth),
                child: _card(items[BidWonModal.clampPage(_page, items.length)]),
              ),
            ),
        ],
      );
    });
  }

  Widget _card(LBBidWonItem item) {
    final count = widget.items.length;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          key: LbTestKeys.bidWonModal,
          padding: const EdgeInsets.fromLTRB(20, 44, 20, 20),
          decoration: BoxDecoration(
            color: _theme.background,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(color: Color(0x59000000), blurRadius: 32, offset: Offset(0, 24)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _swipeArea(_itemText(item), count),
              if (BidWonModal.showsDots(count)) ...[
                const SizedBox(height: 16),
                _dots(count),
              ],
              const SizedBox(height: 16),
              _buttons(),
            ],
          ),
        ),
        Positioned(
          top: -BidWonModal.logoSize / 2,
          left: 0,
          right: 0,
          child: Center(child: _logo()),
        ),
      ],
    );
  }

  /// Full down→up displacement (raw pointer positions, no touch slop subtracted) decides the page
  /// — same semantics as iOS `translation.width` / Android's corrected full displacement / RN `dx`.
  Widget _swipeArea(Widget child, int count) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _downX = e.position.dx,
      onPointerUp: (e) {
        final down = _downX;
        _downX = null;
        if (down == null) return;
        final next = BidWonModal.pageAfterSwipe(_page, e.position.dx - down, count);
        if (next != _page) setState(() => _page = next);
      },
      onPointerCancel: (_) => _downX = null,
      child: child,
    );
  }

  Widget _logo() {
    const inner = BidWonModal.logoSize - BidWonModal.logoBorder * 2;
    final url = widget.shopLogoUrl;
    return Container(
      width: BidWonModal.logoSize,
      height: BidWonModal.logoSize,
      decoration: const BoxDecoration(
        color: _white,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 11, offset: Offset(0, 8))],
      ),
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          StorefrontFillGlyph(color: _theme.accent, size: 30),
          if (url != null)
            ClipOval(
              child: SizedBox(
                width: inner,
                height: inner,
                // `live: true` — the gate is already settled by the caller's
                // `resolveShopLogoUrl` (same idiom as `PlayerHeaderBarView._avatarFill`). An empty
                // placeholder keeps the glyph visible while loading / on failure.
                child: liveProductImage(live: true, url: url, placeholder: const SizedBox.shrink()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _itemText(LBBidWonItem item) {
    final scale = _theme.fontScale;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          ReferenceUIStrings.text('bid_won_title'),
          textAlign: TextAlign.center,
          style: TextStyle(color: _theme.accent, fontSize: 20 * scale, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Text(
          item.name,
          textAlign: TextAlign.center,
          softWrap: true,
          style: TextStyle(
            color: _theme.text,
            fontSize: 15 * scale,
            fontWeight: FontWeight.bold,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          ReferenceUIStrings.text('bid_won_qty', {'num': item.num}),
          textAlign: TextAlign.center,
          style: TextStyle(color: _textDim, fontSize: 13.5 * scale, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _dots(int count) {
    return Row(
      key: LbTestKeys.bidWonPaginationDots,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _page = i),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == _page ? _theme.accent : _dotInactive,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buttons() {
    final label = TextStyle(fontSize: 15 * _theme.fontScale, fontWeight: FontWeight.w800);
    // Both buttons carry the same 1.5 border (the confirm one in its own fill colour) so the
    // `Container` border inset is identical and the two are exactly the same height.
    final border = Border.all(color: _theme.accent, width: 1.5);
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            key: LbTestKeys.bidWonCancel,
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onCancel?.call(),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: border),
              child: Text(ReferenceUIStrings.text('common_cancel'),
                  style: label.copyWith(color: _theme.accent)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            key: LbTestKeys.bidWonConfirm,
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onConfirm?.call(),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: _theme.accent,
                borderRadius: BorderRadius.circular(12),
                border: border,
                boxShadow: [
                  BoxShadow(
                    color: _theme.accent.withValues(alpha: 0.27),
                    blurRadius: 8,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Text(ReferenceUIStrings.text('common_confirm'),
                  style: label.copyWith(color: _white)),
            ),
          ),
        ),
      ],
    );
  }
}
