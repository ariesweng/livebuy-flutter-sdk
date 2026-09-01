import 'package:flutter/material.dart';

import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';

// ContactMerchantModalView — family-1「聯絡商家」confirm modal (LBPAlertModal).
//
// Spec: `reference-ui-rendering/spec.md` (family-1 player-shell —「聯絡商家」確認 modal).
// Design: `design/templates/minimal/sdk-components.jsx` `LBPAlertModal` (centered card over a
//          black-0.55 scrim, 18pt corner card, HORIZONTAL two-button footer
//          [plain secondary][primary]) + `screens.jsx` `contact_merchant` state.
// Parity: iOS `PlayerShell/ContactMerchantModalView.swift` + Android
//          `playershell/ContactMerchantModalView.kt` (rb-*-contact-merchant-modal) — mirrors
//          the structure / copy / tokens. Golden parity name: `contact-merchant-modal`.
//
// A presentation-only CONFIRM before opening the shop's customer-service link. The rail
// `serviceLink` tap and the VideoInfoPanel footer「與商家一對一對話」used to forward
// `onTapRailItem(serviceLink)` directly; now `PlayerShellView` presents THIS modal first and
// only the「確定」CTA proceeds to that existing host exit (per the design's `contact_merchant`
// flow). It owns NO link logic — it just forwards `onConfirm` / `onCancel`.
//
// SUB-VIEW INPUT PATTERN (family convention): `theme:` first; then action callbacks (LAST,
// each nullable). No bound snapshot value — the copy is fixed. Reads NOTHING back from the
// model (one-way data flow) and renders correctly with null actions (golden / preview safe).
//
// RENDERING GOTCHAS (family lessons): plain `Stack` / `Column` / `Row` only — NO scrollable
// container, NO network image, no animation / randomness (golden byte-stable). Mirrors
// `auth_gate_modal.dart` (same LBPAlertModal shell) but WITHOUT the lock badge and with a
// HORIZONTAL two-button footer.

/// `theme.surface.textDim` (body text). Matches `AuthGateModalView`.
final Color _textDim = colorFromHex('#6B6775') ?? const Color(0xFF6B6775);

/// `theme.surface.strokeStrong` (plain-button outline). Matches `AuthGateModalView`.
final Color _strokeStrong = colorFromHex('#D8D5DE') ?? const Color(0xFFD8D5DE);

const String _title = '聯繫商家';
const String _body = '確定要開啟商城指定的客服連結嗎?';
const String _cancelLabel = '取消';
const String _confirmLabel = '確定';

/// The family-1「聯絡商家」confirm modal (`LBPAlertModal`). Renders a centered card
/// (title「聯繫商家」/ body「確定要開啟商城指定的客服連結嗎?」/ horizontal [取消][確定]
/// footer) over a black-0.55 scrim. `onConfirm` proceeds to the host-wired service-link exit;
/// `onCancel` (or a scrim tap) just closes the modal. Renders correctly with null actions.
class ContactMerchantModalView extends StatelessWidget {
  /// Resolved reference-ui theme (FIRST positional argument, always).
  final ReferenceUITheme theme;

  /// Host-wired「確定」CTA → proceed to open the customer-service link (the container wires
  /// this to `onTapRailItem(serviceLink)`). `null` for demo / golden instances.
  final void Function()? onConfirm;

  /// 「取消」/ scrim tap → close the modal WITHOUT opening the link. `null` for demo / golden.
  final void Function()? onCancel;

  const ContactMerchantModalView({
    super.key,
    required this.theme,
    this.onConfirm,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    // Full-bleed dim scrim (LBPAlertModal backdrop). Tap = dismiss.
    return GestureDetector(
      key: LbTestKeys.contactScrim,
      behavior: HitTestBehavior.opaque,
      onTap: onCancel,
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

  // Centered alert card (LBPAlertModal — radius 18 over theme.background). padding `22 22 18`.
  Widget _card() {
    return Container(
      key: LbTestKeys.contactModal,
      constraints: const BoxConstraints(maxWidth: 320),
      margin: const EdgeInsets.symmetric(horizontal: 36),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      decoration: BoxDecoration(
        color: theme.background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
              height: 1.6,
            ),
          ),
          const SizedBox(height: 22),
          _footer(),
        ],
      ),
    );
  }

  // Horizontal two-button footer (LBPAlertModal row: [plain 取消][primary 確定], gap 10).
  Widget _footer() {
    return Row(
      children: [
        // Plain「取消」(LBPButton plain).
        Expanded(
          child: GestureDetector(
            key: LbTestKeys.contactCancel,
            behavior: HitTestBehavior.opaque,
            onTap: onCancel,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _strokeStrong, width: 1),
              ),
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Text(
                _cancelLabel,
                style: TextStyle(
                  color: theme.text,
                  fontSize: 15 * theme.fontScale,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Primary「確定」(LBPButton primary).
        Expanded(
          child: GestureDetector(
            key: LbTestKeys.contactConfirm,
            behavior: HitTestBehavior.opaque,
            onTap: onConfirm,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.accent,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Text(
                _confirmLabel,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15 * theme.fontScale,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
