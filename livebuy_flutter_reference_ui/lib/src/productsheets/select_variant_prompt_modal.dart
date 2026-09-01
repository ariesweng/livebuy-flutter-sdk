import 'package:flutter/material.dart';

import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';

// SelectVariantPromptModalView — family-3「請選規格」acknowledge modal (LBPAlertModal).
//
// Spec: `reference-ui-rendering/spec.md` (family-3 product-sheets —「請選規格」prompt 由容器在
//        overlay root 呈現且可關閉).
// Design: `design/templates/minimal/sdk-components.jsx` `LBPAlertModal` / `LBPCenterPopup`
//          (centered card over a black-0.55 full-bleed scrim, 18pt corner card) — a player-root
//          overlay, NEVER nested inside `LBPBottomSheet`.
// Parity: iOS `SelectVariantPromptModalView.swift` + Android `SelectVariantPromptModalView.kt` +
//          RN `SelectVariantPromptModalView.tsx` (*-variant-prompt-overlay-fix). This is the
//          Flutter four-platform parity (final platform). Golden parity name:
//          `select-variant-prompt-modal`.
//
// WHY HOISTED: the「請選規格」prompt used to be drawn INSIDE `ProductDetailSheet` (the bottom-sheet
// widget) as a `Positioned.fill` full-bleed scrim. Mounting it inside the sheet (presented by the
// container's sheet presenter, height measured by `LBSheetScaffold`) broke the sheet layout (跑版);
// the old「我知道了」was a tapless `Container` and the scrim covered the variant chips → 死鎖.
// Hoisting it to the container's player overlay root (mirroring the cart-needs-login gate
// `AuthGateModalView`) fixes both — same LBPAlertModal shell, but「我知道了」/ scrim now dismiss it
// so the chips become reachable.
//
// SUB-VIEW INPUT PATTERN (family convention): `theme:` first; then the dismiss callback (LAST,
// nullable). No bound snapshot value — the copy is fixed. Renders correctly with `onDismiss` null
// (golden / preview safe). Mirrors `playershell/contact_merchant_modal.dart` (same LBPAlertModal
// shell) but WITHOUT the lock badge and with a SINGLE full-width acknowledge button.
//
// RENDERING GOTCHAS (family lessons): plain `Stack` / `Column` / `Container` only — NO scrollable
// container, NO network image, no animation / randomness (golden byte-stable).

/// `theme.surface.textDim` (body text). Matches `ContactMerchantModalView` / `AuthGateModalView`.
final Color _textDim = colorFromHex('#6B6775') ?? const Color(0xFF6B6775);

const String _title = '請選規格';
const String _body = '請先選擇商品規格,再加入購物車。';
const String _primaryLabel = '我知道了';

/// The family-3「請選規格」acknowledge modal (`LBPAlertModal`). Renders a centered card
/// (title「請選規格」/ body「請先選擇商品規格,再加入購物車。」/ single full-width primary
/// 「我知道了」) over a black-0.55 scrim. The「我知道了」CTA and a scrim tap both call `onDismiss`
/// (the container's local dismiss latch, mirroring the cart-needs-login gate) so the variant chips
/// become reachable. Renders correctly with a null action (golden / preview safe).
class SelectVariantPromptModalView extends StatelessWidget {
  /// Resolved reference-ui theme (FIRST positional argument, always).
  final ReferenceUITheme theme;

  /// 「我知道了」/ scrim tap → close the prompt (sets the container's local dismiss latch). The
  /// template's `needsVariantSelection` is read-only — it is cleared by `selectVariant` once the
  /// user picks a spec. `null` for demo / golden instances.
  final void Function()? onDismiss;

  const SelectVariantPromptModalView({
    super.key,
    required this.theme,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    // Full-bleed dim scrim (LBPAlertModal backdrop). Tap = dismiss.
    return GestureDetector(
      key: LbTestKeys.variantPromptScrim,
      behavior: HitTestBehavior.opaque,
      onTap: onDismiss,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {}, // absorb taps on the card (do NOT dismiss)
            child: _card(),
          ),
        ),
      ),
    );
  }

  // Centered alert card (LBPAlertModal — radius 18 over theme.background). padding 22.
  Widget _card() {
    return Container(
      key: LbTestKeys.variantPrompt,
      constraints: const BoxConstraints(maxWidth: 300),
      margin: const EdgeInsets.symmetric(horizontal: 28),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: theme.background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.text,
              fontSize: 17 * theme.fontScale,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _body,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textDim,
              fontSize: 13 * theme.fontScale,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 22),
          _acknowledgeButton(),
        ],
      ),
    );
  }

  // Single full-width primary「我知道了」(acknowledge) — accent fill, #fff fg, theme.cornerRadius
  // (rb-flutter-button-corner-radius-unify). Tap = dismiss.
  Widget _acknowledgeButton() {
    return GestureDetector(
      key: LbTestKeys.variantPromptAck,
      behavior: HitTestBehavior.opaque,
      onTap: onDismiss,
      child: Container(
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.accent,
          borderRadius: BorderRadius.circular(theme.cornerRadius),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          _primaryLabel,
          style: TextStyle(
            color: Colors.white,
            fontSize: 15 * theme.fontScale,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
