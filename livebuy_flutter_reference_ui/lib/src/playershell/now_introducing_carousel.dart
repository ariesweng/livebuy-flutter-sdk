import 'package:flutter/widgets.dart';
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart' show LBMiniCartPeek;

import '../productsheets/mini_cart_peek.dart';
import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';

// MARK: - NowIntroducingCarousel — VOD「正在介紹中的商品」滿寬卡輪播
//
// Spec: `reference-ui-rendering/spec.md` (family-1 player-shell, VOD now-introducing).
// Flutter parity of iOS `NowIntroducingCarouselView` / Android `NowIntroducingCarousel`
// (rb-flutter-now-introducing，問題 9 真實圖+滿寬 / 問題 10 多商品輪播).
//
// Draws ONLY the current card (full-width [MiniCartPeek] with a real image when `live`) + page
// dots — NO PageView / scroll (golden determinism). A horizontal swipe flips to the prev / next
// card. `peeks` empty → nothing drawn. Index clamped (peeks may shrink as the playhead advances).
//
// （rb-flutter-minicart-remove-introducing-tag，2026-09-04）先前這裡的卡片會額外帶一個
// 「介紹中」accent 標籤（`MiniCartPeek(tag: '介紹中')`）——已隨 `tag` 參數整段退役：
// `design/templates/minimal/sdk-components.jsx` 的 `LBPMiniCart` 沒有任何 tag / 介紹中 /
// 描述文案節點。

const double _dotDimAlpha = 0.45;
const int _maxDots = 6;
const double _swipeVelocity = 80; // px/s threshold to commit a card flip

/// INERT per-item E2E key for a [PageDots] dot, selected by the carousel that reuses
/// PageDots via its [PageDots.dotKeyPrefix]: `live-pinned-dot` → [LbTestKeys.livePinnedDot],
/// otherwise (now-introducing, the default) → [LbTestKeys.nowIntroducingDot]. Layered via a
/// KeyedSubtree OUTSIDE the dot's functional identity key (golden byte-identical).
Key _e2eDotKey(String dotKeyPrefix, int idx) => dotKeyPrefix == 'live-pinned-dot'
    ? LbTestKeys.livePinnedDot(idx)
    : LbTestKeys.nowIntroducingDot(idx);

/// The VOD now-introducing carousel.
class NowIntroducingCarousel extends StatefulWidget {
  final ReferenceUITheme theme;
  final List<LBMiniCartPeek> peeks;

  /// Real image only over a live video surface (golden keeps the placeholder).
  final bool live;

  /// Current card's close → host removes that productId locally.
  final void Function(String productId)? onDismiss;

  /// Current card body tap → host opens that product's detail.
  final void Function(String productId)? onOpenDetail;

  const NowIntroducingCarousel({
    super.key,
    required this.theme,
    required this.peeks,
    this.live = false,
    this.onDismiss,
    this.onOpenDetail,
  });

  @override
  State<NowIntroducingCarousel> createState() => _NowIntroducingCarouselState();
}

class _NowIntroducingCarouselState extends State<NowIntroducingCarousel> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final peeks = widget.peeks;
    if (peeks.isEmpty) return const SizedBox.shrink();
    final i = _index.clamp(0, peeks.length - 1);
    final cur = peeks[i];

    return GestureDetector(
      key: LbTestKeys.nowIntroCarousel,
      behavior: HitTestBehavior.deferToChild,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -_swipeVelocity) {
          setState(() => _index = (i + 1).clamp(0, peeks.length - 1));
        } else if (v > _swipeVelocity) {
          setState(() => _index = (i - 1).clamp(0, peeks.length - 1));
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // INERT E2E key on the introducing card (KeyedSubtree → no RenderObject,
          // golden byte-identical) — MiniCartPeek is a shared productsheets widget.
          KeyedSubtree(
            key: LbTestKeys.nowIntroducingCard,
            child: MiniCartPeek(
              theme: widget.theme,
              peek: cur,
              live: widget.live,
              fullWidth: true,
              onDismiss: () => widget.onDismiss?.call(cur.productId),
              onOpenDetail: () => widget.onOpenDetail?.call(cur.productId),
            ),
          ),
          if (peeks.length > 1) ...[
            const SizedBox(height: 6),
            PageDots(
              theme: widget.theme,
              count: peeks.length,
              current: i,
              onSelect: (idx) => setState(() => _index = idx),
            ),
          ],
        ],
      ),
    );
  }
}

/// Page dots — current = accent solid, others dim; capped at [_maxDots] (parity iOS/Android).
/// Each dot is TAPPABLE: it switches the carousel to that page (vod-now-introducing-switchable).
/// The tap is a `GestureDetector(behavior: opaque)` wrapping the existing 6dp dot — NO extra
/// padding, so the dot keeps its exact pixels / layout (golden byte-identical) — parity iOS
/// `contentShape(...).onTapGesture` / Android `clickable(indication = null)` / RN dot responder.
/// Public so the LIVE pinned-card carousel (rb-flutter-live-now-introducing-carousel) can reuse it;
/// [dotKeyPrefix] lets that reuse give its dots distinct keys (default `now-introducing-dot`).
class PageDots extends StatelessWidget {
  final ReferenceUITheme theme;
  final int count;
  final int current;
  final void Function(int idx)? onSelect;
  final String dotKeyPrefix;

  const PageDots({
    super.key,
    required this.theme,
    required this.count,
    required this.current,
    this.onSelect,
    this.dotKeyPrefix = 'now-introducing-dot',
  });

  @override
  Widget build(BuildContext context) {
    final shown = count > _maxDots ? _maxDots : count;
    final cur = current > shown - 1 ? shown - 1 : current;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var idx = 0; idx < shown; idx++) ...[
          if (idx > 0) const SizedBox(width: 5),
          // The dot keeps its FUNCTIONAL `ValueKey('$dotKeyPrefix-$idx')` (identity
          // key, unchanged). The INERT per-item E2E key is layered OUTSIDE via a
          // KeyedSubtree (no RenderObject → golden byte-identical); the value depends
          // on the carousel reusing PageDots (live-pinned vs now-introducing dots).
          KeyedSubtree(
            key: _e2eDotKey(dotKeyPrefix, idx),
            child: GestureDetector(
              key: ValueKey('$dotKeyPrefix-$idx'),
              behavior: HitTestBehavior.opaque,
              onTap: onSelect == null ? null : () => onSelect!(idx),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: idx == cur
                      ? theme.accent
                      : const Color(0xFFFFFFFF).withValues(alpha: _dotDimAlpha),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
