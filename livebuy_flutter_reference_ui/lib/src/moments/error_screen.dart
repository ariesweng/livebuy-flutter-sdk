import 'package:flutter/material.dart';
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show LBPlayerErrorState, LBPlayerErrorKind;

import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';

// ErrorScreenView — family-4 player moment surface 3 (full-screen terminal error).
//
// Spec: `reference-ui-rendering/spec.md` (family-4 moments, surface 3 error).
// Design: `design/templates/minimal/moments.jsx` · `LBPErrorScreen`
//          (lines 652-770: kind / phase / onRetry / onDismiss).
// Parity: iOS `ErrorScreenView.swift`
//   (ios/Sources/LivebuyReferenceUI/Moments/ErrorScreenView.swift, rb-ios-moments §3)
//   and Android `ErrorScreenView.kt`
//   (android/livebuy-reference-ui/.../moments/ErrorScreenView.kt). Golden parity
//   name: `error-screen-stream` (the `.stream` variant — 重試 + 返回).
//
// The full-screen TERMINAL error moment for ONE `LBPlayerErrorState`. It is the
// third of the three family-4 moment sub-views composed by `MomentsOverlayView`,
// and it implements the agreed SUB-VIEW INPUT PATTERN documented in
// `moments_view.dart`:
//
//   1. `theme:` (ReferenceUITheme, required)   — FIRST, always.
//   2. bound SNAPSHOT VALUE                    — `error: LBPlayerErrorState?`,
//        passed BY VALUE from `MomentsModel` (never the model, never the template).
//        `error == null` → renders NOTHING (`SizedBox.shrink()`); the container also
//        gates on non-null, but the sub-view is null-safe on its own.
//   3. action callbacks (LAST, each null-default):
//        `onRetry: VoidCallback?` (host wires to the core player re-load; shown only
//        when retry can help, i.e. `.stream`) + `onDismiss: VoidCallback?` (the 返回 /
//        關閉 exit). The container owns NO core action — these forward to the
//        host-wired container callbacks. NO template / player moment intent exists
//        for retry / dismiss (the Model is pure read-only — see `moments_model.dart`).
//
// This sub-view reads ONLY its passed-in value; it never reaches back into
// `MomentsModel` / `DefaultPlayerTemplate` (one-way data flow). It MUST NOT
// re-classify `LBError` — `kind` is ALREADY classified by the template
// (`DefaultErrorState.kindFor`); this layer ONLY maps the pre-classified `kind` to
// HUMAN copy (NO raw code shown). It MUST NOT drive / call retry itself — retry is
// the CORE player's job (the SDK auto-retries 3×/3s); the 重試 CTA ONLY forwards
// `onRetry`. `phase` is always `failed` (the only case core exposes).
//
// COPY BY KIND (人話, NO raw code — design §"訊息一律人話"; mirrors the Android
// family-4 requirement):
//   • `.stream`   「連線發生問題」 → 重試 (onRetry) + 返回 (onDismiss, outlined)
//   • `.notFound` 「找不到這部影片」 → 返回 (onDismiss) only (retry won't help)
//   • `.outdated` 「請更新 App 以繼續觀看」 → 前往更新 ONLY (onDismiss; design secondary
//                  is null — no 返回; the host treats it as the upgrade entry)
//
// Retrying will not change the outcome for `.notFound` (gone) / `.outdated` (build
// rejected). `.stream` shows 重試 + 返回; `.notFound` shows a solo 返回; `.outdated`
// shows a single accent 前往更新 CTA (aligned to design `LBPErrorScreen`, iOS / Android
// parity). NO raw code.
//
// RENDERING GOTCHAS (inherited from family-1/2/3 / iOS / Android): plain Column /
// Row / Stack only — NO scrollable container (`ListView` / `GridView` /
// `SingleChildScrollView`) and NO network image (`Image.network` / `NetworkImage`).
// The error moment is a dark full-bleed scrim regardless of the light surface theme
// (design-literal). Glyphs are `Icons.*`. No animation / no randomness so the golden
// is byte-stable.

// MARK: - Decorative design tokens (literal hex — lifted verbatim from LBPErrorScreen)
//
// accent / fontScale come from the resolved [ReferenceUITheme]. These are FIXED
// decorative colors lifted verbatim from the design's `LBPErrorScreen` (the dark
// scrim + on-scrim whites + danger). They mirror the iOS / Android `ErrorScreenView`
// static colors so the three platforms read as one family. NOT theme-resolved (the
// error moment is a dark full-bleed scrim regardless of the light surface theme).

/// Full-bleed dim scrim (`rgba(10,10,14,0.9)` — design `LBPErrorScreen` bg).
final Color _scrim = (colorFromHex('#0A0A0E') ?? const Color(0xFF0A0A0E))
    .withValues(alpha: 0.9);

/// Danger glyph / icon color (`#EB6E5F` — design `DANGER` = danger.400).
final Color _danger = colorFromHex('#EB6E5F') ?? const Color(0xFFEB6E5F);

/// Primary on-scrim text (white).
const Color _onScrimText = Color(0xFFFFFFFF);

/// Secondary on-scrim text (`rgba(255,255,255,0.62)`).
final Color _onScrimDim = const Color(0xFFFFFFFF).withValues(alpha: 0.62);

/// Outlined secondary button stroke (`rgba(255,255,255,0.28)`).
final Color _onScrimStroke = const Color(0xFFFFFFFF).withValues(alpha: 0.28);

// MARK: - Fixed localized copy (static presentation strings — 人話, NO raw code)
//
// Mirrors the Android family-4 requirement copy: `.stream`「播放發生問題」(重試 + 返回) /
// `.notFound`「找不到影片」(僅返回) / `.outdated`「請更新版本」(前往更新). NO raw code.

const String _streamTitle = '連線發生問題';
const String _streamBody = '目前無法載入這場直播，請確認網路後再試一次。';
const String _notFoundTitle = '找不到這部影片';
const String _notFoundBody = '這部影片可能已下架或不存在。';
const String _outdatedTitle = '請更新 App 以繼續觀看';
const String _outdatedBody = '你的版本較舊，更新後即可觀看這場直播。';
const String _retryLabel = '重試';
const String _updateLabel = '前往更新';
const String _dismissLabel = '返回';

/// The family-4 full-screen terminal error moment for one [LBPlayerErrorState].
/// Renders a centered error card — an icon disc + kind-specific 人話 title / body —
/// over a full-bleed dim scrim, with a primary CTA (重試 for `.stream`, 前往更新 for
/// `.outdated`; hidden for `.notFound`, where retry can't help) and a 返回 secondary.
/// Retry is the core player's job; the CTA only FORWARDS [onRetry]. Reads ONLY the
/// passed-in error (no re-classification). `error == null` → renders nothing.
class ErrorScreenView extends StatelessWidget {
  /// Resolved reference-ui theme (FIRST positional argument, always).
  final ReferenceUITheme theme;

  /// The terminal error snapshot this moment renders (`{ kind, phase }`). Read-only.
  /// `null` → renders nothing (the container also gates on non-null). `kind` is
  /// ALREADY classified by the template (this layer never re-classifies `LBError`);
  /// `phase` is always `failed`.
  final LBPlayerErrorState? error;

  /// Host-wired「重試」/「前往更新」→ host → core re-load. Retry is the CORE player's
  /// job (SDK auto-retries 3×/3s); this layer ONLY forwards the CTA tap, never
  /// retries / loads itself. Shown only for `.stream` (重試) / `.outdated` (前往更新);
  /// hidden for `.notFound`. `null` → the CTA is inert (demo / golden instances).
  final VoidCallback? onRetry;

  /// Host-wired「返回」/「關閉」→ host → dismiss the error moment / player. `null` →
  /// inert (demo / golden instances render correctly action-free).
  final VoidCallback? onDismiss;

  const ErrorScreenView({
    super.key,
    required this.theme,
    required this.error,
    this.onRetry,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final e = error;
    if (e == null) return const SizedBox.shrink(); // current == null → nothing

    final copy = _copyFor(e.kind);

    // Full-bleed dim scrim (design `rgba(10,10,14,0.9)`) with the centered error
    // card composited over it. Plain Stack / Column — no Lazy / Scroll.
    return ColoredBox(
      key: LbTestKeys.momentError,
      color: _scrim,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _iconBadge(copy.icon, copy.accentTinted),
                const SizedBox(height: 16),
                _messageBlock(copy),
                const SizedBox(height: 22),
                _actions(copy),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // MARK: - Icon badge (tinted disc + kind glyph — LBPErrorScreen icon disc)
  //
  // `.outdated` tints with the brand accent (a「前往更新」-style affordance, not a
  // danger); `.stream` / `.notFound` tint with the design's danger color.

  Widget _iconBadge(IconData icon, bool accentTinted) {
    final tint = accentTinted ? theme.accent : _danger;
    return Container(
      width: 60,
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        shape: BoxShape.circle,
        border: Border.all(color: tint.withValues(alpha: 0.40), width: 1),
      ),
      child: Icon(icon, size: 28, color: tint),
    );
  }

  // MARK: - Message block (人話 title + body — NO raw code)

  Widget _messageBlock(_ErrorCopy copy) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            copy.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _onScrimText,
              fontSize: 18 * theme.fontScale,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            copy.body,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _onScrimDim,
              fontSize: 13 * theme.fontScale,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // MARK: - Actions (per-kind — aligned to LBPErrorScreen)
  //
  // `.stream`   → 重試 (accent filled primary, forwards onRetry) + 返回 (outlined,
  //               onDismiss).
  // `.outdated` → 前往更新 ONLY (accent filled primary, forwards onDismiss; design
  //               secondary:null) — retry won't help, NO 返回.
  // `.notFound` → 返回 ONLY, the FILLED accent affordance (onDismiss; the single
  //               action) — retry would not help, so the primary CTA is hidden.

  Widget _actions(_ErrorCopy copy) {
    final children = <Widget>[];
    if (copy.primaryLabel != null) {
      // Primary 重試 (onRetry) / 前往更新 (onDismiss — the upgrade entry). This layer
      // never retries / loads itself; it only forwards the CTA tap.
      children.add(_filledButton(
        // `.stream` 重試 forwards onRetry → momentErrorRetry; `.outdated` 前往更新
        // forwards onDismiss (the upgrade/back entry) → momentErrorBack.
        key: copy.primaryForwardsDismiss
            ? LbTestKeys.momentErrorBack
            : LbTestKeys.momentErrorRetry,
        label: copy.primaryLabel!,
        icon: copy.primaryIcon,
        onTap: copy.primaryForwardsDismiss ? onDismiss : onRetry,
      ));
      // Secondary 返回 — outlined (the design's transparent + 1px stroke), only when
      // the kind keeps a 返回 (`.stream`; `.outdated` is a single 前往更新 CTA).
      if (copy.showBack) {
        children.add(const SizedBox(height: 10));
        children.add(_outlinedButton(
          key: LbTestKeys.momentErrorBack,
          label: _dismissLabel,
          onTap: onDismiss,
        ));
      }
    } else {
      // 返回 ONLY — the single action, rendered as the filled accent affordance
      // (the primary CTA is hidden for .notFound).
      children.add(_filledButton(
        key: LbTestKeys.momentErrorBack,
        label: _dismissLabel,
        onTap: onDismiss,
      ));
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  /// Filled accent button (primary CTA / solo 返回). Forwards [onTap] (a no-op when
  /// null — demo / golden). Optional leading [icon] (重試 has a refresh glyph).
  Widget _filledButton({
    Key? key,
    required String label,
    IconData? icon,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.accent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: _onScrimText),
              const SizedBox(width: 7),
            ],
            Text(
              label,
              style: TextStyle(
                color: _onScrimText,
                fontSize: 15 * theme.fontScale,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Outlined secondary button (返回 alongside a primary CTA). Forwards [onTap].
  Widget _outlinedButton({Key? key, required String label, VoidCallback? onTap}) {
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _onScrimStroke, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: _onScrimText,
            fontSize: 14.5 * theme.fontScale,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // MARK: - Human copy per kind (pure — maps PRE-CLASSIFIED kind to copy/glyph)
  //
  // NOTE: this is NOT re-classification of `LBError` — `kind` is already the
  // template's classification (`DefaultErrorState.kindFor`). We map the three KNOWN
  // `kind` cases to human copy + a glyph + the primary CTA. NO raw code shown.

  _ErrorCopy _copyFor(LBPlayerErrorKind kind) {
    switch (kind) {
      case LBPlayerErrorKind.stream:
        return const _ErrorCopy(
          title: _streamTitle,
          body: _streamBody,
          icon: Icons.wifi_off_rounded,
          primaryLabel: _retryLabel,
          primaryIcon: Icons.refresh_rounded,
          accentTinted: false,
        );
      case LBPlayerErrorKind.notFound:
        return const _ErrorCopy(
          title: _notFoundTitle,
          body: _notFoundBody,
          icon: Icons.search_off_rounded,
          primaryLabel: null,
          primaryIcon: null,
          accentTinted: false,
        );
      case LBPlayerErrorKind.outdated:
        // 前往更新 ONLY (design secondary:null) — the dedicated accent upgrade CTA,
        // wired to onDismiss (design `isOutdated ? onDismiss`; the host treats it as
        // the upgrade entry). No 返回. Retry won't help a rejected build.
        return const _ErrorCopy(
          title: _outdatedTitle,
          body: _outdatedBody,
          icon: Icons.system_update_alt_rounded,
          primaryLabel: _updateLabel,
          primaryIcon: null,
          accentTinted: true,
          primaryForwardsDismiss: true,
          showBack: false,
        );
    }
  }
}

/// The resolved human copy + presentation for one error kind (pure value type).
/// `primaryLabel == null` → no primary CTA (返回 is the solo filled action).
@immutable
class _ErrorCopy {
  final String title;
  final String body;
  final IconData icon;

  /// The primary CTA label (重試 / 前往更新), or null when retry won't help
  /// (`.notFound` → 返回 only).
  final String? primaryLabel;

  /// Optional leading glyph on the primary CTA (重試 → refresh; 前往更新 → none).
  final IconData? primaryIcon;

  /// `.outdated` tints the icon disc with the brand accent (update affordance);
  /// `.stream` / `.notFound` tint with the design's danger color.
  final bool accentTinted;

  /// When true, the primary CTA forwards `onDismiss` instead of `onRetry`
  /// (`.outdated` 前往更新 — design wires the outdated primary to onDismiss; the host
  /// treats it as the upgrade entry). `.stream` 重試 → false (forwards onRetry).
  final bool primaryForwardsDismiss;

  /// Whether the secondary 返回 (outlined, onDismiss) is shown beneath the primary
  /// CTA. `.stream` → true; `.outdated` → false (design secondary is null — a single
  /// 前往更新 CTA). `.notFound` has no primary, so 返回 is the solo filled action.
  final bool showBack;

  const _ErrorCopy({
    required this.title,
    required this.body,
    required this.icon,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.accentTinted,
    this.primaryForwardsDismiss = false,
    this.showBack = true,
  });
}
