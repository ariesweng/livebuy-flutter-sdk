import 'package:flutter/material.dart';
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show LBAuthTriggerAction;

import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';

// MARK: - ChatComposerBar — the on-demand chat composer (SheetKit-of-Flutter; new pixel)
//
// Flutter had NO composer to promote (the example never assembled a player; reference-ui's
// `ChatFeedView` only DISPLAYS the feed). The design's `LBLiveBottomBar`「留言…」pill needs an
// input surface — a pixel, so it belongs in reference-ui (D-5). The container's `onComment`
// default opens + focuses it; submit forwards to the container's `controller.sendChat`.
// Pure Flutter-framework widgets (`TextField` / `FocusNode`), no platform view.

/// Pure state machine driving the on-demand composer (no platform view → unit-testable).
/// `open()` presents + bumps `focusToken` (so the field refocuses even if already open);
/// `close()` hides it.
class ChatComposerController extends ChangeNotifier {
  bool _isPresented = false;
  bool get isPresented => _isPresented;

  /// Monotonic token bumped on every `open()` so the bar can refocus deterministically.
  int _focusToken = 0;
  int get focusToken => _focusToken;

  void open() {
    _isPresented = true;
    _focusToken++;
    notifyListeners();
  }

  void close() {
    if (!_isPresented) return;
    _isPresented = false;
    notifyListeners();
  }
}

/// Pure state machine driving the on-demand 設定暱稱 modal (`GuestNameEditModalView`) — the
/// nickname-modal analogue of [ChatComposerController] (parity with iOS / Android / RN
/// `NicknamePromptController`).
///
/// The container composes the modal gated on [isPresented] (default `false` → golden-neutral);
/// the LIVE bottom-bar 暱稱 button and the 留言 pill's 未設定-暱稱 branch call [present]; a scrim
/// tap / submit calls [dismiss]. [composeAfter] carries the ENTRY intent: when opened FROM the
/// 留言 pill the guest must set a nickname before commenting, so a successful submit hands off to
/// the chat composer; when opened from the 暱稱 button directly it just dismisses.
class NicknamePromptController extends ChangeNotifier {
  bool _isPresented = false;

  /// Whether the 設定暱稱 modal is currently presented. Default `false` (golden-neutral).
  bool get isPresented => _isPresented;

  bool _composeAfter = false;

  /// Whether a successful submit should hand off to the chat composer (留言 pill entry).
  bool get composeAfter => _composeAfter;

  /// A pending「加入活動」(event-join) intent the NICKNAME gate deferred (rb-flutter-event-join-gate,
  /// parity iOS `pendingJoinEvent`): when a未設名訪客 taps 加入活動, the container records the join's
  /// `(eid, keyword)` HERE via [presentForJoin] and presents this modal; a successful submit then
  /// completes that ONE join (bypassing the gate). `null` when the modal was NOT opened for a pending
  /// join (直接暱稱編輯 / 留言 pill). Cleared by [dismiss] (取消 / 關閉 → 不 join) and by [present]
  /// (mutually-exclusive entry). NOT a `notifyListeners` trigger by itself (only set alongside the
  /// existing state) → render-neutral / golden byte-identical.
  ({int eid, String keyword})? _pendingJoin;
  ({int eid, String keyword})? get pendingJoin => _pendingJoin;

  int _generation = 0;

  /// Monotonic PRESENTATION GENERATION (rb-flutter-nickname-taken-inline-error). Bumped by EVERY
  /// presentation-state transition ([present] / [presentForJoin] / an effective [dismiss]), so two
  /// reads of this value are equal **iff** the very same presentation is still on screen.
  ///
  /// 🔴 **Why this exists**: `setGuestNicknameVerified` made the container's submit continuation
  /// ASYNCHRONOUS, but this controller OUTLIVES the modal it drives (it is owned by the container,
  /// not by `GuestNameEditModalView`'s State). Without a generation, a continuation that resumes
  /// after the user cancelled and re-opened the modal would read the **new** presentation's
  /// [composeAfter] / [pendingJoin] and complete a join the user never submitted for — see
  /// `completeGuestNicknameSubmitIfCurrent`. Before the async submit landed, the read and the
  /// side effects happened in one tick and could not interleave, so no generation was needed.
  ///
  /// [dismiss] bumps it too (not just the `present*` entries): a submit whose modal the user
  /// cancelled mid-flight MUST NOT complete after the fact either — that is the same
  /// 「a cancelled / closed modal NEVER joins after the fact」contract [dismiss] already documents,
  /// extended across the await boundary.
  int get generation => _generation;

  /// Show the 設定暱稱 modal. `composeAfter == true` → after submit the container opens the composer.
  /// Clears any pending event-join intent — the 留言 pill / 暱稱鈕 entry is mutually exclusive with the
  /// 加入活動 entry (rb-flutter-event-join-gate). Bumps [generation] (new presentation).
  void present(bool composeAfter) {
    _composeAfter = composeAfter;
    _pendingJoin = null;
    _isPresented = true;
    _generation++;
    notifyListeners();
  }

  /// Show the 設定暱稱 modal to satisfy a PENDING「加入活動」join gate (rb-flutter-event-join-gate):
  /// records the join's [eid] / [keyword] so a successful submit completes that ONE join; sets
  /// `composeAfter = false` (this entry does NOT hand off to the composer). Mirrors iOS
  /// `present(pendingJoin:keyword:)`. Bumps [generation] (new presentation).
  void presentForJoin(int eid, String keyword) {
    _composeAfter = false;
    _pendingJoin = (eid: eid, keyword: keyword);
    _isPresented = true;
    _generation++;
    notifyListeners();
  }

  /// Hide the 設定暱稱 modal (scrim tap / close / after submit). `composeAfter` stays sticky. Also clears
  /// any pending event-join intent so a cancelled / closed modal NEVER joins after the fact
  /// (rb-flutter-event-join-gate); the submit continuation snapshots [pendingJoin] BEFORE awaiting.
  /// An EFFECTIVE dismiss (one that actually hides) bumps [generation] — see its doc for why a
  /// cancelled-mid-flight submit must not land either. A no-op dismiss (already hidden) does NOT
  /// bump (it is not a state transition).
  void dismiss() {
    if (!_isPresented) return;
    _isPresented = false;
    _pendingJoin = null;
    _generation++;
    notifyListeners();
  }
}

/// Pure state machine driving the on-demand「請先登入」(commentSend) modal raised by the LIVE 留言
/// login gate — the login-modal analogue of [NicknamePromptController] (parity with iOS / Android /
/// RN `LoginPromptController`; rb-flutter-live-comment-login-gate, 方案 A).
///
/// The container composes the modal gated on [isPresented] (default `false` → golden-neutral). When a
/// guest taps the LIVE 留言 pill on a `chatEnabled == false` live (`guest_comment == 0`) the default
/// `onComment` calls [present]; 前往登入 routes to the host's `config.onLogin` (reference-ui NEVER logs
/// in itself); 稍後再說 / scrim / a successful login calls [dismiss].
class LoginPromptController extends ChangeNotifier {
  bool _isPresented = false;

  /// Whether the「請先登入」modal is currently presented. Default `false` (golden-neutral).
  bool get isPresented => _isPresented;

  /// Which interaction raised the modal — drives `AuthGateModalView`'s body copy per kind (via the
  /// synthetic `LBAuthGateState` the container composes in `GapSurfacesOverlayView`'s login-gate
  /// branch). Set by [present]; ONE controller serves every gate (留言 → `commentSend`, 訂閱 →
  /// `subscribe`, …). Default `commentSend` (the original 留言 gate) keeps existing behaviour
  /// unchanged (rb-flutter-subscribe-login-gate, parity iOS / Android / RN).
  LBAuthTriggerAction _triggerAction = LBAuthTriggerAction.commentSend;
  LBAuthTriggerAction get triggerAction => _triggerAction;

  /// Show the「請先登入」modal for the given [triggerAction]. Default `commentSend` (the 留言 pill's
  /// guest + `guest_comment == 0` branch) so existing無參數 call sites need no change; 訂閱 gate passes
  /// `subscribe`. `_triggerAction` is ALWAYS updated (parity iOS `present(triggerAction:)`); the
  /// already-presented dedup only skips the re-notify.
  void present({LBAuthTriggerAction triggerAction = LBAuthTriggerAction.commentSend}) {
    _triggerAction = triggerAction;
    if (_isPresented) return;
    _isPresented = true;
    notifyListeners();
  }

  /// Hide the「請先登入」modal (前往登入 hand-off / 稍後再說 / scrim).
  void dismiss() {
    if (!_isPresented) return;
    _isPresented = false;
    notifyListeners();
  }
}

/// The bottom chat composer (a rounded `TextField` + send button), presented only while
/// `controller.isPresented`. Submitting forwards the trimmed, non-empty text to [onSend]
/// (the container wires `controller.sendChat`) and closes; a guest send triggers
/// `AUTH_REQUIRED` via the SDK listener (existing behavior, unchanged).
class ChatComposerBar extends StatefulWidget {
  final ChatComposerController controller;
  final ReferenceUITheme theme;
  final ValueChanged<String> onSend;

  const ChatComposerBar({
    super.key,
    required this.controller,
    required this.theme,
    required this.onSend,
  });

  @override
  State<ChatComposerBar> createState() => _ChatComposerBarState();
}

class _ChatComposerBarState extends State<ChatComposerBar> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  int _lastFocusToken = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChange);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onControllerChange() {
    if (!mounted) return;
    setState(() {});
    if (widget.controller.focusToken != _lastFocusToken) {
      _lastFocusToken = widget.controller.focusToken;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.controller.isPresented) _focus.requestFocus();
      });
    }
  }

  void _submit() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _text.clear();
    widget.controller.close();
  }

  /// "不留言返回": unfocus (hide the keyboard) and close the bar WITHOUT sending. Parity
  /// iOS rb-ios-chat-composer-dismiss-without-send / Android / RN.
  void _dismissWithoutSending() {
    FocusScope.of(context).unfocus();
    widget.controller.close();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.isPresented) return const SizedBox.shrink();
    final theme = widget.theme;
    // The transparent tap-to-dismiss layer is drawn FIRST (underneath); the bar (Align)
    // is the later Stack child, so it paints on top: taps on the bar hit the field / send
    // button, taps ABOVE it dismiss without sending. Hidden (SizedBox.shrink) when not
    // presented, so chrome taps fall through normally (no regression).
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        GestureDetector(
          key: LbTestKeys.chatComposerDismiss,
          behavior: HitTestBehavior.opaque,
          onTap: _dismissWithoutSending,
        ),
        Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        // OPAQUE charcoal bar (chrome rgb(20,20,24), full opacity) so the video does NOT show
        // through the composer (parity iOS rb-ios-chat-composer-opaque); the old translucent
        // theme.background (white) let it bleed and clashed on a dark video.
        color: _barFill,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: LbTestKeys.chatComposer,
                    controller: _text,
                    focusNode: _focus,
                    // White text on the dark solid field (the bar is now opaque charcoal).
                    style: TextStyle(
                        color: Colors.white, fontSize: 14 * theme.fontScale),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      hintText: '留言…',
                      hintStyle:
                          TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                      isDense: true,
                      // Solid input fill (iOS Color(white:0.18) = #2E2E2E) — opaque, not the old
                      // transparent outline that let the video show through the field.
                      filled: true,
                      fillColor: _fieldFill,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(18)),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(18)),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(18)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Send glyph tints accent when there is sendable text, else a dim white (parity
                // iOS arrow.up.circle.fill accent / white-0.35). Listens to the field directly.
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _text,
                  builder: (context, value, _) {
                    final canSend = value.text.trim().isNotEmpty;
                    return IconButton(
                      key: LbTestKeys.chatSend,
                      onPressed: canSend ? _submit : null,
                      color: canSend
                          ? theme.accent
                          : Colors.white.withValues(alpha: 0.35),
                      icon: const Icon(Icons.send),
                    );
                  },
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

  /// Opaque composer bar fill — chrome charcoal `rgb(20,20,24)` at full opacity (parity iOS
  /// `ChatComposerBar.barFill`).
  static const Color _barFill = Color(0xFF141418);

  /// Solid input-field fill — `#2E2E2E` (iOS `Color(white:0.18)`), a lighter shade so the field
  /// reads clearly on the opaque bar.
  static const Color _fieldFill = Color(0xFF2E2E2E);
}
