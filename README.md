# Livebuy Flutter SDK

Embed live shopping experiences — live streams, replays, and shoppable VODs — directly into your
Flutter app.

> **Architecture.** The SDK ships as **three pub packages** under a single dependency chain
> (`livebuy_flutter_reference_ui → livebuy_flutter_ui → livebuy_flutter`). `livebuy_flutter` is a
> **headless** core (it renders no UI); it is itself a thin bridge over the already-protected
> native cores (iOS `LivebuySDK.xcframework`, Android `tv.livebuy:livebuy`), each distributed
> through its own remote mirror. The turnkey, ready-to-use UI ships as drop-in Flutter widgets
> (`LivebuyPlayer` / `LivebuyWidget` / `CollapsibleLivebuyPlayer` / `LivebuyLiveEntry`) in
> **`livebuy_flutter_reference_ui`**. Most integrators depend on `livebuy_flutter_reference_ui`
> and declare all three packages (pub does not resolve transitive `git` dependencies across
> repos, so every package your app needs must be declared explicitly — see Installation below).

> **This repository ships source, not prebuilt binaries.** All three packages — including the
> headless core — are distributed as readable Dart (and bridge Kotlin/Swift) **source**, not
> compiled artifacts. This matches the iOS SDK's UI layers (which also ship as source) rather than
> the Android SDK (which ships prebuilt AARs only) — the Flutter packages have no proprietary
> logic to hide; the real core logic is already protected behind the iOS and Android native
> mirrors that `livebuy_flutter`'s bridge calls into. pub packages are also inherently
> source-distributed — there is no "prebuilt package" concept in Dart, so this is also simply how
> pub itself works.

---

## Requirements

| | Minimum |
|---|---|
| Dart SDK | `>=3.0.0 <4.0.0` |
| Flutter | `>=3.10.0` |

(Aligned with the `environment:` constraints declared in each package's `pubspec.yaml`.)

---

## Installation

This SDK is **not published on pub.dev**. It is distributed as a **single git repository with
three subdirectories**, one per package, consumed via pub's standard
[git dependency `path:` mechanism](https://dart.dev/tools/pub/dependencies#git-packages) — pub
natively supports pointing a `git` dependency at a subdirectory of a repo via `path:`, this is not
a Livebuy-specific mechanism.

Add all three packages to your `pubspec.yaml`, each pointing at this repo with a different
`path:`, and the same `ref:` (the release tag) across all three:

```yaml
dependencies:
  livebuy_flutter:
    git:
      url: https://github.com/ariesweng/livebuy-flutter-sdk.git
      path: livebuy_flutter
      ref: v1.3.0   # pin to a release tag — see CHANGELOG.md for available tags
  livebuy_flutter_ui:
    git:
      url: https://github.com/ariesweng/livebuy-flutter-sdk.git
      path: livebuy_flutter_ui
      ref: v1.3.0
  livebuy_flutter_reference_ui:
    git:
      url: https://github.com/ariesweng/livebuy-flutter-sdk.git
      path: livebuy_flutter_reference_ui
      ref: v1.3.0
```

Then:

```bash
flutter pub get
```

> **Keep all three `ref:` values identical.** Each release tag corresponds to a single sync of all
> three packages from the same monorepo commit; mixing tags across the three packages is not a
> supported combination.

> **Only doing your own UI (Tier 0/1, drawing every pixel yourself)?** You can omit
> `livebuy_flutter_reference_ui` and depend on just `livebuy_flutter` (optionally
> `livebuy_flutter_ui` too, for the overlay view-models). See the integration guide for the
> `simulate*` + unified event listener contract.

### Packages

| Package | Role |
|---|---|
| `livebuy_flutter` | headless core (streaming / 5s polling / signing / events / offline queue), **always required** |
| `livebuy_flutter_ui` | view-model layer backing the drop-in overlays (chat / product card / header). **Required for drop-in too** — call `LivebuyUI.install()` once at startup |
| `livebuy_flutter_reference_ui` | drop-in turnkey pixel layer (`LivebuyPlayer` / `LivebuyWidget` / `CollapsibleLivebuyPlayer` / `LivebuyLiveEntry`) → **most integrators want this** |

---

## Getting Started

### 1. Configure the SDK

```dart
import 'package:livebuy_flutter/livebuy_flutter.dart';
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  LivebuyUI.install();   // required once, before using any drop-in container

  await LivebuySDK.configure(const LBConfigOptions(
    apiKey: '12345',        // numeric string — provided by Livebuy
    secret: '<your-secret>', // HMAC signing secret — never commit this
    shopId: 'YourShopId',    // required — provided by Livebuy
  ));

  runApp(const MyApp());
}
```

### 2. Present the Player

```dart
import 'package:livebuy_flutter_reference_ui/livebuy_flutter_reference_ui.dart';

LivebuyPlayer(videoId: 'abc123')
```

### 3. Embed a Widget

```dart
LivebuyWidget(shopId: 'YourShopId')                                  // carousel (default)
LivebuyWidget(shopId: 'YourShopId', mode: WidgetContainerMode.grid)  // grid
```

> The full integration guide (login / add-to-cart / event catalogue / floating entry) lives in the
> monorepo handoff doc; request it from Livebuy.

---

## Membership & Events

Every SDK→host signal is delivered through a single event listener
(`LivebuySDK.setListener(...)`). Attach a logged-in user with `LivebuySDK.bindSession(...)`; clear
on logout with `LivebuySDK.clearUser()`. See the integration guide for the full event catalogue.

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

---

## License

Copyright © Livebuy. All rights reserved.
