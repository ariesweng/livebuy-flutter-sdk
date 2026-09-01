package tv.livebuy.flutter

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import tv.livebuy.sdk.models.LBVideoItem
import tv.livebuy.sdk.models.LBFeaturedGood
import tv.livebuy.sdk.widget.LivebuyWidget

// MARK: - LivebuyWidgetViewFactory (expand-simulate-bridge-parity Tier 2)

class LivebuyWidgetViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *> ?: emptyMap<String, Any>()
        return LivebuyFlutterWidgetView(context, viewId, messenger, params)
    }
}

class LivebuyFlutterWidgetView(
    context: Context,
    viewId: Int,
    messenger: BinaryMessenger,
    params: Map<*, *>,
) : PlatformView {

    private val widget = LivebuyWidget(context, shopId = params["shopId"] as? String ?: "")
    private val methodChannel = MethodChannel(messenger, "tv.livebuy/widget_$viewId")

    init {
        // NOTE: an `onWidgetResponse` reverse-call (forwarding widget_color /
        // widget_bgcolor to Dart) was hand-stubbed here against a
        // `LivebuyWidget.onWidgetResponse` hook that exists on NO platform SDK — it
        // never compiled. Removed (flutter-bridge-build gate). To restore, add the
        // hook to the Android/iOS SDK first (core + 4-platform parity), then re-wire.
        methodChannel.setMethodCallHandler { call, result ->
            @Suppress("UNCHECKED_CAST")
            val callArgs = call.arguments as? Map<*, *>
            when (call.method) {
                "simulateCardTap" -> {
                    lbVideoItemFrom(callArgs)?.let { widget.simulateCardTap(it) }
                    result.success(null)
                }
                "simulateClose" -> {
                    widget.simulateClose()
                    result.success(null)
                }
                "simulateCardVisibilityChanged" -> {
                    @Suppress("UNCHECKED_CAST")
                    val videoMap = callArgs?.get("video") as? Map<*, *>
                    val visible = callArgs?.get("visible") as? Boolean ?: false
                    lbVideoItemFrom(videoMap)?.let { widget.simulateCardVisibilityChanged(it, visible) }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun getView() = widget
    override fun dispose() {}
}

// MARK: - LBVideoItem deserializer (Widget bridge)

private fun lbVideoItemFrom(map: Map<*, *>?): LBVideoItem? {
    val id = map?.get("id") as? String ?: return null
    return LBVideoItem(
        id = id,
        type = (map["type"] as? Number)?.toInt() ?: 1,
        title = map["title"] as? String ?: "",
        sessionName = "",
        cover = map["cover"] as? String ?: "",
        preview = "",
        duration = 0,
        publishAt = "2000-01-01 00:00:00",
        watchNum = 0,
        pvNum = 0,
        liveStatus = (map["liveStatus"] as? Number)?.toInt() ?: 1,
        pin = 0,
        showPvNum = 0,
        liveurl = map["liveurl"] as? String ?: "",
        playbackurl = map["playbackurl"] as? String ?: "",
        previewTime = "00:00",
        showStock = false,
        goods = LBFeaturedGood(
            name = "", pic = "", price = "0",
            originalPrice = "0", soldOut = 0, stock = 0, status = 1,
        ),
    )
}
