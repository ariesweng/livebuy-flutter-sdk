library livebuy_flutter;

export 'src/livebuy_sdk.dart';
export 'src/livebuy_player.dart'
    show
        LivebuyPlayerCore,
        // ignore: deprecated_member_use_from_same_package
        LivebuyPlayer, // deprecated alias → LivebuyPlayerCore (v2.0 removal)
        LivebuyPlayerController,
        // Sub-component controllers (expand-simulate-bridge-parity)
        ChatViewController,
        ProductOverlayController,
        ProductListPanelController,
        OperationPanelController,
        VideoInfoPanelController,
        EndScreenController,
        // Widget / FloatingWidget (expand-simulate-bridge-parity Tier 2)
        LivebuyWidgetCore,
        // ignore: deprecated_member_use_from_same_package
        LivebuyWidget, // deprecated alias → LivebuyWidgetCore (v2.0 removal)
        LivebuyFloatingWidget,
        LivebuyWidgetController,
        LivebuyFloatingWidgetController,
        // Bridge-level type helpers
        LBBridgeSpec,
        LBBridgeHotItem,
        LBBridgeVideoItem;
export 'src/models.dart';
export 'src/event_listener.dart';
export 'src/lb_event.dart';
export 'src/lb_route.dart';
// url-open-policy-flutter — URL 開啟裁決策略 + 法務連結事實來源（core，只裁決不開啟）
export 'src/lb_url_open_policy.dart';
export 'src/lb_legal_links.dart';
// add-sdk-config-transport — SDKConfig types + event params
export 'src/sdk_config.dart'
    show
        SDKConfig,
        LBSdkVisibility,
        LBSdkTheme,
        LBSdkTemplateLayout,
        LBSdkBehavior,
        LBSdkConfigLoadFailedSource,
        LBSdkConfigLoadFailedParams,
        LBSdkConfigRefreshedParams;
