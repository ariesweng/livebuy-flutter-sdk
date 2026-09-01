import 'package:flutter/material.dart';

import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';

// MARK: - GuestNameEditModalView — family-6 gap-surface 2 (guest nickname-edit modal)
//
// Spec: `reference-ui-rendering/spec.md` (family-6 gap-surfaces — the LAST Flutter
//        Phase-3 family closing out the reconciled "gap" surfaces; PURELY ADDITIVE,
//        2 ADDED modals).
// Design: `design/templates/minimal/live-chrome.jsx` `LiveNicknameModal` (≈388-443):
//          a centered card over a 0.55 scrim, with a logo 徽章 floating above the
//          card's top edge (negative top margin), the「設定暱稱」title +
//          「請輸入直播留言的暱稱」subtitle, a person-icon + max-10 input row, and a
//          送出 primary CTA enabled only while the trimmed buffer is 1..10 chars.
// Parity: iOS `GapSurfaces/GuestNameEditModalView.swift` (rb-ios-gap-surfaces) and
//          Android `gapsurfaces/GuestNameEditModalView.kt` (rb-android-gap-surfaces).
//
// The guest nickname-edit modal — the guest 態 rename affordance. It is the second
// of the two family-6 gap-surface modal sub-views composed by
// `GapSurfacesOverlayView`, and it implements the agreed SUB-VIEW INPUT PATTERN
// (shared with every family surface — see `product_detail_sheet.dart` /
// `gap_surfaces_view.dart`):
//
//   1. `theme:` (ReferenceUITheme, required)  — FIRST, always.
//   2. bound SNAPSHOT VALUE                   — `displayName: String`, passed BY
//      VALUE from `GapSurfacesModel.identity?.displayName` (never the model, never
//      the template). It is read-only PREFILL / context (a guest's `Guest_XXXX`
//      default).
//   3. action callbacks (LAST, each null-defaulted / no-op):
//      `onSubmit(String name) -> Future<String?>` (送出 → host →
//      `LivebuyPlayerController.setGuestNicknameVerified`), `onDismiss` (取消 / scrim
//      tap / close → host clears the container's presentation state).
//
// One-way data flow: this surface reads ONLY its passed-in `displayName`; it never
// reaches back into `GapSurfacesModel` / `DefaultPlayerTemplate`. It renders
// correctly with all actions null (so demo / golden / widget tests construct it
// action-free). reference-ui NEVER calls core directly — the 送出 CTA funnels to
// `onSubmit`, which the container forwards to the host's verified
// `setGuestNicknameVerified` call. This layer MUST NOT call any core rename API and
// MUST NOT add / mutate any view-model.
//
// ─────────────────────────────────────────────────────────────────────────────
// rb-flutter-nickname-taken-inline-error — submitting / inline-error states
// ─────────────────────────────────────────────────────────────────────────────
// `onSubmit` returns a `Future<String?>` (previously fire-and-forget `void`): `null`
// means the host accepted + already persisted/broadcast the name — the HOST (not
// this widget) then closes the modal by flipping its presentation controller, same
// as before. A non-null return is a user-facing error message (nickname 被取走 /
// other checkName failure) — this widget stays open, shows the message inline below
// the input row, and lets the user edit + retry (the CTA re-enables the moment the
// buffer is 1..10 again). While the Future is in flight the CTA shows「送出中…」and is
// LOCKED (re-entrant-submit guard) — but per the `LBPButton` design contract it KEEPS
// its brand fill (loading ≠ disabled; see `_submitButton`). This widget never inspects
// *why* a submit failed — the host/container decides the message text; this layer only
// displays whatever string it is given.
//
// THE RENAME ENTRY is NOT here: opening this modal is the container's lone CORE EXIT
// `GapSurfacesOverlayView._handleRequestNameEdit()` → `template.requestGuestNameEdit()`
// (emits `GUEST_NAME_EDIT_REQUEST`). This modal only renders the editor + forwards
// the typed name on 送出; it never fires the rename INTENT itself.
//
// PRESENTATION-ONLY INPUT BUFFER: the nickname buffer is a LOCAL
// `TextEditingController` (Flutter edit state — ALLOWED, NOT a second copy of
// view-model state; `displayName` stays the single source of truth, the new name
// flows to the host on 送出 and is written back to core, returning via the template
// `identityLabel` notify). The buffer is SEEDED from `displayName` on open.
//
// RENDERING GOTCHAS (family-1..5 lessons): plain `Stack` / `Column` / `Row` only —
// NO `ListView` / `GridView` / `SingleChildScrollView` / `Lazy*` (the golden path
// renders those unreliably). NO `Image.network` / `NetworkImage` (the logo 徽章 is a
// deterministic accent circle + glyph). NO animation / randomness so the golden is
// byte-stable. CRITICAL golden lesson (iOS / Android family-6): a LIVE `TextField`
// renders as a yellow/red unsupported-control box under the golden renderer — so
// when `editable == false` (demo / golden) the field is a STATIC placeholder `Text`
// of the current buffer (the design's empty-field placeholder state); only when
// `editable == true` (host runtime) is it a real editable field.

// MARK: - Max nickname length (design `slice(0, 10)`).

const int _maxNicknameLength = 10;

// MARK: - Fixed localized copy (static presentation strings, 繁中 — parity iOS/Android)

const String _titleText = '設定暱稱';
const String _subtitleText = '請輸入直播留言的暱稱';
const String _inputPlaceholder = '暱稱字數上限 10 個字';
const String _submitLabel = '送出';

// rb-flutter-nickname-taken-inline-error: submitting-state CTA label (parity
// `WinClaimSheetView._submittingLabel` — same Chinese copy, reused so the reference-ui family
// reads as one voice for "awaiting a host round-trip").
const String _submittingLabel = '送出中…';

// MARK: - Decorative design tokens (literal minimal hex via colorFromHex)
//
// accent / text / background come from the resolved [ReferenceUITheme]. These are
// FIXED decorative colors lifted verbatim from the design `theme.surface.*` (light
// mode). They mirror the iOS `GuestNameEditModalView` static colors + Android
// `GuestNameEditModalView` decorative tokens byte-for-byte (same `#6B6775` /
// `#B6B2BE` / `#ECEAF0` / `#D8D5DE` / `#F4F4F6` as `product_detail_sheet.dart`), so
// the three platforms read as one family.

/// `theme.surface.textDim` (secondary / caption text + person glyph).
final Color _textDim = colorFromHex('#6B6775') ?? const Color(0xFF6B6775);

/// `theme.surface.textFaint` (placeholder + disabled CTA label).
final Color _textFaint = colorFromHex('#B6B2BE') ?? const Color(0xFFB6B2BE);

/// `theme.surface.stroke` (hairline — badge ring / input outline).
final Color _stroke = colorFromHex('#ECEAF0') ?? const Color(0xFFECEAF0);

/// `theme.surface.strokeStrong` (disabled CTA fill).
final Color _strokeStrong = colorFromHex('#D8D5DE') ?? const Color(0xFFD8D5DE);

/// `theme.surface.bgSunken` (sunken input fill).
final Color _bgSunken = colorFromHex('#F4F4F6') ?? const Color(0xFFF4F4F6);

/// Design `DANGER` (rb-flutter-nickname-taken-inline-error inline error text — parity
/// `WinClaimSheetView._danger`, same hex, so the two family surfaces that show inline
/// validation errors read as one system).
final Color _danger = colorFromHex('#EB6E5F') ?? const Color(0xFFEB6E5F);

/// The family-6 guest nickname-edit modal. Renders a full-bleed dim scrim, a
/// centered card with a floating logo 徽章, the「設定暱稱」title + subtitle, a nickname
/// input row (a live `TextField` seeded from [displayName] at runtime, or a static
/// placeholder `Text` on the golden / demo path), and a 送出 CTA enabled only while
/// the trimmed buffer is 1..10. The [displayName] bind is the prefill / context (a
/// guest's `Guest_XXXX` default); the actual rename is host-fulfilled via [onSubmit].
class GuestNameEditModalView extends StatefulWidget {
  /// The resolved reference-ui theme (FIRST argument, always).
  final ReferenceUITheme theme;

  /// Current display name (`GapSurfacesModel.identity?.displayName` ←
  /// `template.identityLabel.current?.displayName`). Read-only — used as the initial
  /// buffer + prefill context (a guest's `Guest_XXXX` default).
  final String displayName;

  /// Whether the nickname field is a LIVE editable `TextField` (runtime default,
  /// `true`) or a STATIC read-only placeholder display (`false`). The golden / demo
  /// seed passes `false` because the golden renderer paints a live `TextField` as a
  /// yellow/red unsupported-control box (iOS / Android family-6 lesson), so the
  /// read-only rendering reproduces the design's empty-field placeholder state
  /// deterministically. Hosts using the drop-in at runtime keep the default `true`.
  final bool editable;

  /// Host-wired 送出 → the container forwards the trimmed nickname to
  /// `LivebuyPlayerController.setGuestNicknameVerified(name)` (rb-flutter-nickname-taken-inline-error;
  /// previously a fire-and-forget `void` callback into `LivebuySDK.setGuestNickname`).
  /// reference-ui NEVER calls core directly — it only forwards and displays the result.
  ///
  /// Returns `Future<String?>`:
  /// - `null` → the name was accepted (already persisted + broadcast by the host); the HOST
  ///   closes this modal separately (unchanged — this widget never dismisses itself).
  /// - non-null → a user-facing error message (nickname 被取走 / other checkName failure); this
  ///   widget stays open, shows the message inline, and lets the user edit + retry.
  ///
  /// `null` (the field itself) for demo / golden instances (inert CTA, unchanged).
  final Future<String?> Function(String name)? onSubmit;

  /// Host-wired 取消 / scrim tap / close → the container clears its presentation
  /// state. `null` for demo / golden instances (no-op tap).
  final void Function()? onDismiss;

  const GuestNameEditModalView({
    super.key,
    required this.theme,
    required this.displayName,
    this.editable = true,
    this.onSubmit,
    this.onDismiss,
  });

  @override
  State<GuestNameEditModalView> createState() => _GuestNameEditModalViewState();
}

class _GuestNameEditModalViewState extends State<GuestNameEditModalView> {
  /// Presentation-only input buffer (Flutter edit state — NOT a second copy of
  /// view-model state). SEEDED from the bound `displayName` on open (the design
  /// prefills nothing, but seeding the current guest name is the platform-parity
  /// affordance); the trimmed buffer drives the 送出 enabled gate, and on 送出 it is
  /// handed to the host. `displayName` stays the single source of truth.
  late final TextEditingController _controller =
      TextEditingController(text: widget.displayName);

  /// Whether a 送出 is currently awaiting the host's verified result
  /// (rb-flutter-nickname-taken-inline-error). Drives the CTA's disabled state + label
  /// (`送出` → `送出中…`) and guards against a re-entrant double-submit. UI-local — there is no
  /// host/core "in-flight" flag to mirror here (the awaited `Future` itself is the only signal).
  bool _isSubmitting = false;

  /// The last submit's user-facing error message (nickname 被取走 / other checkName failure), or
  /// `null` when there is nothing to show (initial open, or the last attempt succeeded). Cleared
  /// on every new submit attempt AND on any further edit to the input — a stale error sitting
  /// next to a freshly-edited name would be confusing. UI-local presentation state, not a second
  /// copy of any host/core state (the host never hands back a *previous* error to restore).
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Trimmed nickname buffer (pure read of the controller text).
  String get _trimmed => _controller.text.trim();

  /// 送出 enabled only while the trimmed buffer is 1..10 (design `canSubmit`).
  bool get _canSubmit {
    final n = _trimmed.length;
    return n >= 1 && n <= _maxNicknameLength;
  }

  /// Forward the trimmed name on 送出 (guarded by `_canSubmit` + not already mid-submit; the CTA
  /// is also disabled in both cases). AWAITS the host's `Future<String?>` result
  /// (rb-flutter-nickname-taken-inline-error): `null` → accepted — the host closes this modal
  /// separately (this widget never dismisses itself, unchanged from before); non-null → a
  /// user-facing error message — stays open, shows it inline, re-enables retry. This widget never
  /// inspects *why* a submit failed (that mapping is the host/container's job — see
  /// `guestNicknameSubmitErrorText` in `live_buy_player.dart`); it only displays what it is given.
  Future<void> _submit() async {
    if (!_canSubmit || _isSubmitting) return;
    final onSubmit = widget.onSubmit;
    if (onSubmit == null) return;
    final name = _trimmed;
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    final error = await onSubmit(name);
    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _errorText = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Full-bleed dim scrim (tap → dismiss). A plain opaque GestureDetector over
        // the whole area; renders correctly with `onDismiss` null (no-op tap).
        GestureDetector(
          key: LbTestKeys.guestNameScrim,
          behavior: HitTestBehavior.opaque,
          onTap: widget.onDismiss,
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
        ),

        // Centered card (LBPAlertModal — card + floating logo 徽章). The 徽章 floats
        // above the card's top edge, so the centered area reserves its overhang via a
        // top padding equal to half the 徽章 height (see `_card`).
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: _card(theme),
          ),
        ),
      ],
    );
  }

  // MARK: - Centered card (card body + floating logo 徽章)
  //
  // The card body is a RoundedRectangle(18) filled with the theme background, max-width
  // ~300, with a hairline ring, padded 22 horizontal / a tall 48 top (to clear the 徽章
  // that half-overlaps the top edge) / 20 bottom. The logo 徽章 floats ABOVE the card's
  // top edge as a Stack SIBLING (top-center) translated UP by half its height — drawn
  // AFTER the card so it sits on top, not clipped by the card's rounded-corner clip
  // (design `marginTop: -52`). The outer wrapper reserves the 徽章 overhang via a top
  // padding equal to half the 徽章 height.

  static const double _badgeSize = 44;

  Widget _card(ReferenceUITheme theme) {
    return Padding(
      // Reserve room above the card for the 徽章's upper half so it is not clipped by
      // the centered area's bounds.
      padding: const EdgeInsets.only(top: _badgeSize / 2),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          // Card body (clipped, rounded). Top inset is tall enough to clear the 徽章.
          // Card width 320 (parity iOS GuestNameEditModalView / design LiveNicknameModal
          // live-chrome.jsx:400 maxWidth 320 + the sibling AuthGate card 320).
          ConstrainedBox(
            key: LbTestKeys.guestNameModal,
            constraints: const BoxConstraints(maxWidth: 320),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.background,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _stroke, width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 48, 22, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _title(theme),
                    const SizedBox(height: 16),
                    _subtitle(),
                    const SizedBox(height: 16),
                    _inputRow(theme),
                    // Inline error (rb-flutter-nickname-taken-inline-error) — only built when a
                    // submit actually failed. The golden / demo path (`onSubmit == null`, see
                    // `_submit`) never sets `_errorText`, so this NEVER renders there — the
                    // golden baseline is byte-identical / unaffected.
                    if (_errorText != null) ...[
                      const SizedBox(height: 8),
                      _errorMessage(),
                    ],
                    const SizedBox(height: 16),
                    _submitButton(theme),
                  ],
                ),
              ),
            ),
          ),

          // Floating logo 徽章 — translated UP by half its height so it straddles the
          // card top edge (design `marginTop: -52`). Drawn AFTER the card so it is not
          // clipped by the card's rounded-corner clip.
          Transform.translate(
            offset: const Offset(0, -_badgeSize / 2),
            child: _logoBadge(theme),
          ),
        ],
      ),
    );
  }

  // MARK: - Floating logo 徽章 (44×44 WHITE circle, accent person glyph)
  //
  // A 44×44 WHITE circle (theme.background) with a hairline ring, holding an ACCENT
  // person glyph. Mirrors the design's floating brand-mark badge — `LiveNicknameModal`
  // (live-chrome.jsx:406-409) uses a #fff badge background — and iOS / Android (white
  // circle + accent glyph). reference-ui keeps goldens deterministic with the person
  // glyph instead of the design's LB logo network image. (rb-align-flutter-gap-surfaces:
  // fixes an inverted color role — was an accent circle + white glyph.)

  Widget _logoBadge(ReferenceUITheme theme) {
    return Container(
      width: _badgeSize,
      height: _badgeSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.background,
        shape: BoxShape.circle,
        border: Border.all(color: _stroke, width: 1),
      ),
      child: Icon(Icons.person, size: 24, color: theme.accent),
    );
  }

  // MARK: - Title「設定暱稱」(17 bold, centered)

  Widget _title(ReferenceUITheme theme) {
    return Text(
      _titleText,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: theme.text,
        fontSize: 17 * theme.fontScale,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  // MARK: - Subtitle「請輸入直播留言的暱稱」(13 dim, centered)

  Widget _subtitle() {
    return Text(
      _subtitleText,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: _textDim,
        fontSize: 13 * widget.theme.fontScale,
      ),
    );
  }

  // MARK: - Input row (person icon + field, sunken pill with hairline stroke)
  //
  // Runtime (`editable == true`): a live `TextField` seeded from `displayName`, clamped
  // to 10 chars, with the「暱稱字數上限 10 個字」hint. Demo / golden (`editable ==
  // false`): a STATIC placeholder `Text` of the current buffer (else the hint in
  // textFaint) — the golden renderer paints a live `TextField` as a yellow/red
  // unsupported-control box (iOS / Android family-6 lesson), so the read-only rendering
  // reproduces the design's empty-field placeholder state.

  Widget _inputRow(ReferenceUITheme theme) {
    return Container(
      decoration: BoxDecoration(
        color: _bgSunken,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _stroke, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.person_outline, size: 16, color: _textDim),
          const SizedBox(width: 10),
          Expanded(
            child: widget.editable ? _liveField(theme) : _staticField(theme),
          ),
        ],
      ),
    );
  }

  /// Live nickname `TextField` (runtime path). Seeded from `displayName`, clamped to
  /// `_maxNicknameLength`, with the placeholder hint. Re-reads `_canSubmit` on every
  /// change so the 送出 enabled gate updates, and clears any stale `_errorText`
  /// (rb-flutter-nickname-taken-inline-error) — an old error next to a freshly-edited name would
  /// be confusing; the user gets a clean slate to retry.
  Widget _liveField(ReferenceUITheme theme) {
    return TextField(
      key: LbTestKeys.guestNameField,
      controller: _controller,
      maxLength: _maxNicknameLength,
      maxLines: 1,
      onChanged: (_) => setState(() {
        if (_errorText != null) _errorText = null;
      }),
      cursorColor: theme.accent,
      style: TextStyle(
        color: theme.text,
        fontSize: 13 * theme.fontScale,
      ),
      decoration: InputDecoration(
        isDense: true,
        counterText: '',
        border: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        hintText: _inputPlaceholder,
        hintStyle: TextStyle(
          color: _textFaint,
          fontSize: 13 * theme.fontScale,
        ),
      ),
    );
  }

  /// Static read-only field rendering (demo / golden path). Shows the buffer text if
  /// any, else the placeholder hint in textFaint — matching the design's empty-field
  /// state. Golden-safe (plain `Text`, no live control).
  Widget _staticField(ReferenceUITheme theme) {
    final text = _controller.text;
    final isEmpty = text.isEmpty;
    return Text(
      isEmpty ? _inputPlaceholder : text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: isEmpty ? _textFaint : theme.text,
        fontSize: 13 * theme.fontScale,
      ),
    );
  }

  // MARK: - Inline error message (rb-flutter-nickname-taken-inline-error)
  //
  // Shown below the input row only when `_errorText` is non-null (a submit failed — nickname 被
  // 取走 / other checkName failure). This widget does not know or care WHICH failure — it just
  // displays the string the host/container decided (see `guestNicknameSubmitErrorText` in
  // `live_buy_player.dart`). Never rendered in golden / demo (`onSubmit == null` there).

  Widget _errorMessage() {
    return Text(
      _errorText!,
      key: LbTestKeys.guestNameError,
      style: TextStyle(
        color: _danger,
        fontSize: 12.5 * widget.theme.fontScale,
      ),
    );
  }

  // MARK: - 送出 CTA (LBPButton primary — locked when !canSubmit || submitting)
  //
  // 🔴 **`loading` ≠ `disabled`（設計契約，`design/templates/minimal/sdk-components.jsx:1080-1111`
  // 的 `LBPButton`）**：兩者都 LOCK 住點擊（`locked = disabled || loading`），但**只有 `disabled`
  // 會退成灰色的 `strokeStrong` 面**；`loading` **MUST 保留品牌填色**——設計源逐字寫明
  //
  //     // Loading keeps the brand fill (does NOT fall back to the grey disabled
  //     // surface) so the press still reads as committed.
  //     background: loading && filled ? accent : s.bg,
  //     opacity: loading ? 0.96 : 1,
  //
  // 讓「按下去這件事」讀起來仍是**已送出、進行中**，而不是「這顆鈕現在不能用」。所以「能不能點」
  // 與「用什麼顏色」MUST 是兩個獨立的判斷，**MUST NOT** 共用同一個布林（共用正是
  // rb-flutter-nickname-taken-inline-error 初版把送出中畫成灰底的原因）。
  //
  // 注意 `background: loading && filled ? accent : s.bg` 中 `loading` **蓋過** `disabled`：使用者
  // 若在送出中把輸入框清空（欄位在送出中並未鎖住），`_canSubmit` 會翻 false，但這顆鈕 MUST 仍是
  // 品牌色——送出中就是送出中。故 [brandFilled] 用 `_isSubmitting || _canSubmit`，非只看 `_canSubmit`。
  //
  // 契約四件事對照：① 鎖住點擊 = `onTap: interactive ? _submit : null` ✅；② 保留品牌填色 ✅；
  // ③ `opacity 0.96` ✅；④ spinner 取代 icon —— 本檔**刻意不加**，改用設計源明文允許的
  // 「(optionally) the label」換文案「送出中…」，理由見 design.md 決策 B。
  //
  // Disabled（非送出中且長度不合格）維持既有的 strokeStrong 面 / textFaint 字，本 change 不動
  // （那是 disabled 態，不在本次修正範圍）。

  Widget _submitButton(ReferenceUITheme theme) {
    // 能不能點（= 設計源的 `locked` 反面）。送出中 MUST 仍鎖住（防重複送出）。
    final interactive = _canSubmit && !_isSubmitting;
    // 用不用品牌填色（= 設計源的 `loading && filled ? accent : s.bg`）。送出中蓋過 disabled。
    final brandFilled = _isSubmitting || _canSubmit;
    return GestureDetector(
      key: LbTestKeys.guestNameSubmit,
      behavior: HitTestBehavior.opaque,
      onTap: interactive ? _submit : null,
      child: Opacity(
        // 設計源 `opacity: loading ? 0.96 : 1`（整顆鈕，含底與字）。
        opacity: _isSubmitting ? 0.96 : 1,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: brandFilled ? theme.accent : _strokeStrong,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            _isSubmitting ? _submittingLabel : _submitLabel,
            style: TextStyle(
              color: brandFilled ? Colors.white : _textFaint,
              fontSize: 15 * theme.fontScale,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
