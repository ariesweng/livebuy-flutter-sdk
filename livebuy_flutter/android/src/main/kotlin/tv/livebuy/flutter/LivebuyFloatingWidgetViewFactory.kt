package tv.livebuy.flutter

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import tv.livebuy.sdk.widget.FloatingWidget

// MARK: - LivebuyFloatingWidgetViewFactory (expand-simulate-bridge-parity Tier 2)

class LivebuyFloatingWidgetViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *> ?: emptyMap<String, Any>()
        return LivebuyFlutterFloatingWidgetView(context, viewId, messenger, params)
    }
}

class LivebuyFlutterFloatingWidgetView(
    context: Context,
    viewId: Int,
    messenger: BinaryMessenger,
    params: Map<*, *>,
) : PlatformView {

    private val widget = FloatingWidget(context, videoId = params["videoId"] as? String ?: "")
    private val methodChannel = MethodChannel(messenger, "tv.livebuy/floating_widget_$viewId")

    init {
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "simulateClose" -> {
                    widget.simulateClose()
                    result.success(null)
                }
                "simulateTap" -> {
                    widget.simulateTap()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun getView() = widget
    override fun dispose() {}
}
