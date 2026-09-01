# livebuy_flutter

Flutter plugin for the Livebuy live-shopping SDK (iOS + Android).
Headless — your app composes its own UI on top of plugin-exposed events
and methods.

## Installation

Add to `pubspec.yaml`:

```yaml
dependencies:
  livebuy_flutter: ^1.2.0-rc.2
```

Then:

```bash
flutter pub get
cd ios && pod install
```

iOS minimum: 14.0. Android minSdk: 24. Flutter ≥ 3.10, Dart SDK ≥ 3.0.

## Getting Started

```dart
import 'package:livebuy_flutter/livebuy_flutter.dart';

await LivebuySDK.configure(const LBConfigOptions(
  apiKey: 22081105395545,
  secret: '<your-secret>',
  shopId: 'Pw8PJ99J',           // required — per-shop /sdk/config scope
  autoPipOnIntercept: true,
));

// Merchant-configured settings — available after configure() resolves.
// See `openspec/specs/sdk-config/spec.md` for the full DTO shape.
final config = await LivebuySDK.getSdkConfig();
applyBrandColor(config.theme?.primaryColor ?? defaultBrand);

LivebuySDK.setListener((event) async {
  if (event.eventName == LBEvent.dismissRequest) {
    playerCoordinator.dismiss();
    return LBEventReply.intercept;
  }
  if (event.eventName == LBEvent.sdkConfigRefreshed) {
    // Host decides whether to reload views; SDK does not auto re-render.
  }
  // ...handle AUTH_REQUIRED / PRODUCT_CLICK / CART_ADD_REQUEST...
  return LBEventReply.acknowledge;
});

// Force a fresh /sdk/config fetch when you know the merchant just changed settings:
await LivebuySDK.refreshConfig();

// In a widget tree:
SizedBox(height: 480, child: LivebuyPlayerCore(videoId: 'bsuqqM'))
```

### Migration: `LivebuyPlayer` → `LivebuyPlayerCore` (BREAKING, next major)

The **bare** headless player widget has been renamed from `LivebuyPlayer` to
**`LivebuyPlayerCore`**. The reason: the more intuitive `LivebuyPlayer` name is
being **repurposed** for an upcoming turnkey drop-in container (the
pre-assembled product most hosts actually want), while the bare bridge widget
(for deep customization) takes the `…Core` name.

- **Today**: existing `LivebuyPlayer(videoId: …)` calls keep compiling and
  running with byte-equivalent behavior through a `@Deprecated` thin alias — you
  will only see a deprecation notice in `dart analyze` / your IDE.
- **Now**: migrate bare-player usage to `LivebuyPlayerCore(videoId: …)`.
- **At v2.0**: the deprecated `LivebuyPlayer` alias is removed, and the
  `LivebuyPlayer` name is taken over by the new drop-in container.

→ **Full integration guide (all four platforms, 38-event catalog,
must-handle events, common pitfalls, FAQ)**: see
[`../docs/quick-start.md`](../docs/quick-start.md).

## Android auto-PiP (Picture-in-Picture)

The Android bridge **builds OS auto-PiP entry into the drop-in player** so you
don't have to write native Kotlin. When the player is mounted and the user
leaves the app (Home / app-switch), the player automatically enters system
Picture-in-Picture:

- **API 31+ — fully reliable, zero host native code.** The bridge arms the
  system's own `setAutoEnterEnabled(true)` on your Activity when the view mounts;
  the OS decides when to enter PiP.
- **API 26–30 — best-effort by default, one line to make it reliable.** These
  versions have no `setAutoEnterEnabled`. The bridge falls back to observing a
  genuine background (`onActivityStopped`), which is best-effort and can fire too
  late. For reliable Home-key entry, forward `onUserLeaveHint()` from your host
  Activity (see below).

**Host responsibilities** (a library cannot declare these for your Activity):

1. On the `FlutterActivity` that hosts the player, in `AndroidManifest.xml`:

   ```xml
   <activity
       android:name=".MainActivity"
       android:supportsPictureInPicture="true"
       android:configChanges="screenSize|smallestScreenSize|screenLayout|orientation">
   ```

2. **API 26–30 reliable entry (optional):** override `onUserLeaveHint()` in your
   `MainActivity` and forward it — this is the ENTIRE integration:

   ```kotlin
   import tv.livebuy.flutter.LivebuyPiPUserLeaveHint

   class MainActivity : FlutterActivity() {
       override fun onUserLeaveHint() {
           super.onUserLeaveHint()
           LivebuyPiPUserLeaveHint.notifyUserLeaveHint()
       }
   }
   ```

A host that never forwards `onUserLeaveHint()` keeps identical behavior (API 31+
reliable, API 26–30 best-effort). See [`example/android`](example/android) for a
working reference. This is the Flutter parity of the React Native
`rn-android-auto-pip-entry` change; **iOS has no such gap** (PiP goes through the
SDK's own `AVPictureInPictureController` delegate).

## Sample app

A runnable sample lives at [`example/`](example/) — it exercises
configure, the event listener, the player widget, login / auth gating,
cart resolution, language switching, force-flush, and
`notifyCheckoutCompleted`.

## Status

This package is part of the [Livebuy multi-platform SDK monorepo](https://github.com/livebuy/livebuy-sdk).
The behaviour contract for all four platforms lives in
`openspec/specs/component-contracts/spec.md` of the repo. If the plugin
diverges from the contract, the contract wins.
