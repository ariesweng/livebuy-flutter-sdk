package tv.livebuy.flutter

import tv.livebuy.sdk.models.LBComment
import tv.livebuy.sdk.models.LBError

// flutter-bridge-forward-backend-error-code-and-replay-raw-core — pure wire helpers for two
// things the plugin used to drop on the floor:
//
// 1. The raw backend `error_code` (core `LBError.backendErrorCode`, android-v4.30.0+). Dart
//    already decodes `backend_error_code` from player error maps (`lbErrorFromMap`) and from
//    `PlatformException.details` (`backendErrorCodeFromDetails`); the plugin now sends it.
//    Read the code INSIDE the catch block (before `mainHandler.post`): the `object` subtypes
//    (`GuestNameTaken`, `NotLive`, …) are singletons whose code reflects the latest response.
// 2. The replay chat comment wire map for `replayChatRevealed`, which now also carries the
//    backend raw keys and the core-composed sentences, using the same keys and omit rules as
//    the core's `CHAT_HISTORY_LOADED` comment payload (`ChatComposePayload.addRaw` +
//    `composed_*`, which are internal to the core and so are mirrored here).
//
// Zero Android dependency, so BackendErrorCodeBridgeTest runs on a plain JVM.
object BackendErrorCodeBridge {

    /** Wire key shared with the core event payloads and the Dart decoders. */
    const val KEY = "backend_error_code"

    /** The non-empty backend code of [error], or `null` (not an [LBError] / no code). */
    fun codeOf(error: Throwable?): String? =
        (error as? LBError)?.backendErrorCode?.takeIf { it.isNotEmpty() }

    /** `result.error(...)` details: `{backend_error_code: code}` when [code] is non-empty, else `null`. */
    fun details(code: String?): Map<String, String>? =
        code?.takeIf { it.isNotEmpty() }?.let { mapOf(KEY to it) }

    /** Same as [details] for a caught error. */
    fun detailsFor(error: Throwable?): Map<String, String>? = details(codeOf(error))

    /** Adds `backend_error_code` to an error event [payload] only when [code] is non-empty. */
    fun putCode(payload: MutableMap<String, Any?>, code: String?) {
        code?.takeIf { it.isNotEmpty() }?.let { payload[KEY] = it }
    }

    /**
     * `replayChatRevealed` comment map: the 7 existing keys (`text` / `name` / `color` /
     * `reply` / `reply_color` / `time` / `kind`) + raw keys `is_anonymous` / `host_name` /
     * `reply_template` (omitted when null, like the core) + `composed_text` /
     * `composed_name` / `composed_reply` (always present; equal to `text` / `name` / `reply`
     * when the raw keys are missing). [lang] is the language to compose in — the caller
     * passes `LivebuySDK.currentLanguage` at emit time, as the core does for its payloads.
     */
    fun replayCommentToMap(c: LBComment, lang: String): Map<String, Any> {
        val item = mutableMapOf<String, Any>(
            "text" to c.text,
            "name" to c.name,
            "color" to c.color,
            "reply" to c.reply,
            "reply_color" to c.replyColor,
            "time" to c.time,
            "kind" to c.kind.rawValue,
        )
        c.isAnonymous?.let { item["is_anonymous"] = it }
        c.hostName?.let { item["host_name"] = it }
        c.replyTemplate?.let { item["reply_template"] = it }
        item["composed_text"] = c.composedText(lang)
        item["composed_name"] = c.composedName(lang)
        item["composed_reply"] = c.composedReply(lang)
        return item
    }
}
