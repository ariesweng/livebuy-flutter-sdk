# Changelog — livebuy_flutter

All notable changes to the Livebuy Flutter plugin will be documented in this file.

Format conforms to [pub.dev CHANGELOG guidelines](https://dart.dev/tools/pub/package-layout#changelogmd).

## [Unreleased]

> 🚀 **下一個發版 = v2.0.0（major / breaking）。** 自上一個發版以來累積的所有 breaking
> 與散佈姿態改變一次發。完整對外說明見 [release notes](../docs/release-notes/v2.0.0.md)，升級照
> [migration 總入口](../docs/migration/v2.0.0.md)。**發版時本 `[Unreleased]` → `## 2.0.0 - <date>`**；
> 未 tag 的 `1.3.0`（api-version）內容一併併入 v2.0.0。

### v2.0.0 — major / breaking（總覽）

**⚠ BREAKING**
- **品牌大小寫識別字全改（`brand-casing`）** — 所有公開 Dart class 由 `LiveBuy*` → `Livebuy*`（`LivebuySDK` / `LivebuyPlayerCore` / `LivebuyWidgetCore` / `LivebuyFloatingWidget` / plugin class `LivebuyPlugin` 等），與品牌顯示形一致。**無別名（乾淨改名）**——自最後發布 `1.3.0`（當時為 `LiveBuy*`）升級者須一律改匯入的 class 名。**不變**：pub 套件名 `livebuy_flutter`、`tv.livebuy/*` method/event channel、viewType wire 註冊字串（host 不直接引用、Dart+原生兩端一致改）→ host 的 `pubspec.yaml` 依賴行不受影響。
- **Headless 化（`decouple-ui-from-logic`）** — 原生 Player / Widget 與 9 sub-component 移除所有像素渲染；widget 簽章保留故 host 能編譯但 platform view 空，UI callback 不攔為 no-op。改用 `livebuy_flutter_reference_ui` drop-in 或自組 UI（**必聽 `dismissRequest`**）。
- **Token 模型（`session-token-migration`）** — per-video token 移除；`POST /sdk/video` 不回 token；改用 login session token（native 端處理）。
- **裸 widget / player 改名 → `…Core`** — 黃金名 `LivebuyPlayer` / `LivebuyWidget` 讓給 reference-ui drop-in 容器，裸 headless 版改名 `LivebuyPlayerCore` / `LivebuyWidgetCore`；**Flutter 留 `@Deprecated` alias**（既有 host code 可編譯運行、發 deprecation 通知，v2.x 移除）。詳見下方兩個 `rename-bare-*` 區；method / event channel wire 不變。
- **音訊預設有聲** — 主播放 + 開場 intro 預設不靜音（native 行為；`setMuted` 經 method channel 切換、靜音偏好換片沿用）。
- （下方 `subscribe-like-wire-fix-core` 與兩個 `rename-bare-*` 區的 BREAKING 一併入 v2.0.0。）

**Added**
- **AWS IVS Player 直播低延遲引擎** — 底層原生引擎（iOS / Android）改用 AWS IVS Player，Flutter 原生橋接 view **自動繼承**（無 Dart 端改動）：live `.m3u8` glass-to-glass ~15s（iOS）/ ~9.6s（Android）→ ~2–5s。**散佈改變：iOS 多一個 IVS XCFramework、Android APK 多 IVS native libs（`libplayercore.so` → 體積變大），請 pin v1.52.0。**
- **reference-ui（新 `livebuy_flutter_reference_ui` 套件）** — drop-in 容器 `LivebuyPlayer` / `LivebuyWidget`（Flutter widgets）+ 可客製像素層（對齊 `design/templates/minimal/*`）。
- **api-version-resilience**（原 `1.3.0`，100% 向後相容）、**sdk-widget API 串接**、widget / channel / video 解碼韌性硬化（native 端）。
- **`environment` 選擇器（`LBConfigOptions(environment: …)`，`LBEnvironment.production` / `.develop`）** — SDK 全域環境選擇器，wire string 轉發原生；`develop` 同時切換**資料 API base URL**（→ `https://develop-admin.livebuy.tv/v1`）與 `/stat` 端點，`production`（預設）維持正式站。**只換 URL、不換憑證**（Dart 層不自行解析任何 URL，全由原生 SDK 決定）。對齊 iOS / Android v4.1.0 的 `sdk-data-api-environment-selection`。
- **`ACTIVE_EVENT_STARTED` 通知事件（進行中直播活動 / 直播抽獎）＋ `LBActiveEvent` + `fromMap`** — 原生端從 `POST /sdk/video/goods` 回應 `event[]` 取得尚未通知過的進行中活動時派發（**fire-once per event id**，換片清空），經 event channel 轉發。params（扁平）`{ id, title, keyword?, duration, surplus, award }`——`keyword` 空則省略、`surplus` 為派發當下秒數快照（host 本地倒數）、`award` 複用 winner `[{type, name, code}]` 結構；**不含 `stayTime`**。新增 `LBActiveEvent`（`{ id, title, keyword, award, duration, surplus, stayTime }`）＋ `LBActiveEvent.fromMap` 解析。供 host 自繪活動倒數 / 獎品預告 / 加入活動入口。
- **`activeEvents(): Future<List<LBActiveEvent>>` accessor** — 回傳當前 goods 緩存的進行中活動快照，補「中途進場 host miss 掉 fire-once `ACTIVE_EVENT_STARTED` 事件」的 late-subscriber 盲點。
- **`LivebuySDK.fetchWidget()` 的 map 多帶 `product_card`（`widget-product-card-bridge-flutter`，純加法）** — `POST /sdk/widget` 回應 root 層的「輪播卡商品卡顯示模式」（`below` / `inside` / `hidden`）現在會過橋到 Dart，鍵名為 snake_case 的 `product_card`（同 `widget_color` / `widget_bgcolor` 的既有姿態，**不新增任何 Dart 型別**）。**後端未送此欄時（linetv 分支）該鍵整個缺席、`map['product_card']` 為 `null`——SDK 刻意不補後端預設 `"inside"`**，因為「後端沒送」與「後端明確送 `inside`」是兩件不同的事實；套用預設值屬 UI 層責任。raw passthrough：SDK 不解讀這三個值的語意、不做排版決策，非白名單值原樣傳遞。既有 `LBWidgetColors` 與 `LivebuyWidgetController.onWidgetResponse` **完全未變**。
- **`LBProduct` 新增 `videoId` 欄位（`String?`）** — 承載 `otherGoods[]` 每筆商品所屬的影片 id（`goods[]` 內項目為 `null`），原生序列化處新增 `video_id` key 透傳、`fromMap` tolerant 解析（缺鍵/null → `null`）。補齊 `component-contracts` 規格先前已要求、四端從未實作的缺口。
- **`LBProduct` 新增 `description` 欄位（`String?`）** — 承載商品真實介紹文字，原生序列化處新增 `description` key 透傳、`fromMap` tolerant 解析（缺鍵/null → `null`）。
- **商品明細/加購 sheet Sale 促銷徽章（`livebuy_flutter_reference_ui`）** — 商品有原價且未售完時，`ProductDetailSheet` widget 顯示一個「Sale」徽章 chip；純視覺渲染，不涉及本套件任何型別改動。
- **商品明細「商品介紹」文字區 ＋「更多商品」推薦格（`livebuy_flutter_reference_ui`）** — `ProductDetailSheet` 底部新增商品介紹文字區（改讀真實 `description`，空字串時整塊含標題都不顯示，不使用佔位文案）與最多 **12 筆**（自 4 筆提高）更多商品推薦卡（2×2 grid，新增原價劃線顯示，卡片移除邊框），資料源 `LBChannel.otherGoods`。點播放圖示換片（沿用既有容器層機制，換片後**一併關閉**整個商品 sheet stack 與外層商品袋/清單抽屜）；點卡片本體 / 加購鈕切換到該商品自己的明細/加購（同一個 sheet 換內容，**不再** push breadcrumb——header 關閉鈕永遠是「✕ 全部關閉」，不再有「返回上一層」狀態），加購帶該商品自己的 `videoId`。
- **商品袋 row 播放提示改為「看講解」白底膠囊（`livebuy_flutter_reference_ui`）** — 對齊設計稿 R21，tap handler 邏輯不變，純視覺重繪。
- **商品明細數量列與收藏鈕間補分隔線（`livebuy_flutter_reference_ui`）** — 純視覺排版補強。
- **商品明細 sheet 底部灰色間隔修正（`livebuy_flutter_reference_ui`）** — 捲到底時原本會露出外層灰色背景的間隔，改移入白卡內側，捲到底不再露灰。
- **底部 sheet 拖曳調高與拖曳收合整併為單一連續手勢（`livebuy_flutter_reference_ui`）** — 擴大到全部 5 個 bottom sheet（新增 `ProductListSheet` / `VideoInfoPanelView` 的拖曳調高，且是這兩者首次擁有拖曳收合能力）；`.detail` 的靜態高度上限由固定 90% 回退為內容自適應 50%（90% 改為僅拖曳上限）。
- **⚠️ 訂閱/收藏顯示開關 `showSubscribe` / `showFavorite`（`livebuy_flutter_reference_ui`，BREAKING）** — 新增兩個 optional 參數，控制訂閱徽章/pill（同一旗標）與收藏鈕是否顯示，**預設 `false`（隱藏）**——既有 host 若未設定，升級後這些元素會從顯示變為隱藏；不影響任何 Dart 型別簽章，既有呼叫碼零改動即可編譯運行。
- **商品袋 icon 放大對齊 70% 比例（`livebuy_flutter_reference_ui`）** — 主要商品袋按鈕與直播/回放底部 bar 商品袋 icon，兩個獨立渲染點皆已放大。純視覺，不影響互動行為。
- **一般觀眾留言加全形冒號分隔（`livebuy_flutter_reference_ui`）** — 暱稱與訊息內容間新增冒號，對齊設計稿更新。
- **底部 sheet 拖曳調高上限收斂 90% → 80%（`livebuy_flutter_reference_ui`）** — 全部 5 個 sheet 共用同一個值，計算架構不變。
- **底部 sheet 調高後關不掉修復（`livebuy_flutter_reference_ui`）** — 手勢下限改為每次新手勢重新錨定目前渲染高度，不跨手勢凍結。
- **懸浮 widget 移除影片標題（`livebuy_flutter_reference_ui`）** — 對齊設計稿無標題元素的版面。
- **播放器頂欄標題跑馬燈捲動 ＋ `titleScroll` 能力閘（`livebuy_flutter_reference_ui`，新能力）** — 頂欄標題（`PlayerHeaderBarView`）先前恆為 `maxLines: 1` + `TextOverflow.ellipsis` 的靜態單行截斷，從未實作跑馬燈；改用 `LayoutBuilder` + `Stack` 量測，覆蓋判定 100% 由量測決定（`textWidth > containerWidth`，無任何呼叫端偏好旗標），覆蓋時疊加複製文字兩份 + 固定間距的無縫水平捲動（`AnimationController`，時長 `max(8, textWidth / 32)` 秒）。新增 **public** 欄位 `LivebuyPlayerConfig.titleScroll`（`Object?`，raw 值，預設 `null`，比照既有 `showStock` 的姿態），省略/畸形值一律正規化為 `true`（照常捲動，對齊後端 `extensions.video_title_scroll` 未設定時為 `1`），既有呼叫碼零改動即可編譯運行；`titleScroll` 為假時標題**不隱藏**，只是不捲動。轉發路徑涵蓋 LIVE/VOD 主分支與 upcoming 直播預告分支。Flutter 先前這條能力完全缺席（不同於 iOS/Android，那兩端已在 2026-08-06 落地），本項同時補齊渲染與能力閘，不分兩波上線。
- **字幕 CC 開箱即顯示 VTT 內容（`livebuy_flutter_reference_ui`，新能力）** — CC 開關先前存在但看不到實際字幕文字，本輪補上真正渲染顯示。同一批次補上字幕靜態欄位橋接（`rb-flutter-subtitle-channel-bridge-core`）與 template 層接線（`rb-flutter-subtitle-template-wiring`）。
- **LIVE 進行中雙擊送愛心，擴大到已結束直播回放（`livebuy_flutter_reference_ui`，新能力）** — LIVE 進行中首次落地，同批次擴大到回放（parity 既有 LIVE 行為）。
- **播放器手勢重寫：乾淨模式（`livebuy_flutter_reference_ui`）** — 單擊行為依直播/VOD 分流；長按改為切換「乾淨模式」（隱藏頂欄/底部 bar/聊天等疊層），取代舊版「按住暫停」手勢。
- **直播抽獎活動入口按鈕與彈窗（`livebuy_flutter_reference_ui`，新能力）** — 綁定新增的 `DefaultActiveEvent` template 層 view-model，首次補上 UI 呈現。
- **中獎領獎 modal 新增分頁 ＋ 活動/中獎入口堆疊順序反轉（`livebuy_flutter_reference_ui`）** — 多筆中獎紀錄可翻頁瀏覽；活動入口改佔主槽，中獎入口讓位。**⚠ BREAKING**：`WinClaimPhase.CONFIRM_CLOSE` 移除，連同 ✕ 關閉鈕與「關閉視窗」文字鈕，modal 現在只能透過 scrim 關閉——只有直接窮舉 `WinClaimPhase` 的 host 受影響。
- **VOD / 直播回放播放進度條（`livebuy_flutter_reference_ui`）** — core 補齊控制轉發 API，reference-ui 綁上播放進度條。
- **LIVE 底部 bar 貼底、拿掉裝飾性漸層、播放進度條細線真正貼齊底部（`livebuy_flutter_reference_ui`）** — 純視覺修復，對齊 iOS/Android 同輪修正。

**Removed**
- SDK 內建 UI fallback / 預設 sheet（headless 後移除）；舊 UI snapshot 測試移至 reference-ui 套件的 golden 體系。

**Fixed**
- **`LBWinner.fromMap` 容忍扁平 `WIN_RECEIVED` params** — 原本 `fromMap` 只吃巢狀結構，餵扁平 `WIN_RECEIVED` params 會 crash 的 footgun 已消除（現同時容忍扁平 / 巢狀）。
- **不顯示庫存設定失效（`flutter/example` demo app only）** — `RootShell` 唯一的 `LivebuyPlayerConfig(...)` 建構點先前完全沒有傳 `showStock:` 參數、也未呼叫 `LivebuySDK.getSdkConfig()`，導致後台「不顯示庫存」設定在 example app 上被無視；已補上讀取 `getSdkConfig().extensions['show_stock']` 並轉送的接線。⚠️ 這不是套件本身的行為改變——`LivebuyPlayerConfig.showStock` / `normalizeShowStock()` 契約一直是對的；如果你自己的 host app 有同樣的接線缺口，會踩到一模一樣的靜默失效。
- **乾淨模式漏隱藏聊天 feed 修復、直播多商品同時介紹漏標 badge 修復（`livebuy_flutter_reference_ui`）**。
- **Flutter Android/iOS bridge core pin 過期版補到現行修復（`flutter-distribution-core-pin-refresh`）** — 修復 Flutter 自身 bridge 對 core 版號的過期 pin，與 iOS/Android 本輪發版內容無關，是 Flutter 自身散佈缺陷的獨立修復。partner 安裝文件同輪已改記自建 mirror 消費倉方案（`flutter-remote-distribution-mirror`，取代裝不到的 pub.dev 措辭；純文件，實際建倉留待後續）。

---

### Changed — BREAKING (`subscribe-like-wire-fix-core`, SemVer **major**)

- **`VIDEO_LIKE` event params:** `current_likes` removed; the event carries `{ video_id }` only.
- subscribe/like wire fixes ride the native commands: subscribe sends `shop_id` + reversed `type` (`isSubscribe ? 1 : 0`) + login session token, `401 → AUTH_REQUIRED`; like sends `video_id`, guest-allowed (token optional).

### Changed — BREAKING (`rename-bare-player-livebuyplayercore-flutter`, SemVer **major**)

- **Bare player widget renamed `LivebuyPlayer` → `LivebuyPlayerCore`.** The
  headless bridge widget (`UiKitView` / `AndroidView`, zero overlay pixels) is
  now `LivebuyPlayerCore`.
- **`LivebuyPlayer` is now a `@Deprecated` thin alias** (subclass of
  `LivebuyPlayerCore`, behavior byte-equivalent) — existing
  `LivebuyPlayer(videoId: …)` host code keeps compiling + running, emitting a
  deprecation notice. The alias is **removed at v2.0**.
- The `LivebuyPlayer` name is being **repurposed** for an upcoming turnkey
  drop-in container (philosophy B; the most intuitive name goes to the
  pre-assembled product, the bare bridge takes `…Core`). Migrate bare-player
  usage to `LivebuyPlayerCore`.
- **No bridge-wire / native change:** viewType `LivebuyPlayerView`, method
  channel `tv.livebuy/player_$id`, event channel `tv.livebuy/player_events`,
  `load` / `release` methods, and creationParams are all unchanged — the rename
  is Dart-surface only. `LivebuyPlayerController` is **not** renamed.

### Changed — BREAKING (`rename-bare-widget-to-core-flutter`, SemVer **major**)

- **Bare widget renamed `LivebuyWidget` → `LivebuyWidgetCore`.** The headless
  bridge widget (`UiKitView` / `AndroidView` over `LivebuyWidgetView`, zero
  container assembly) is now `LivebuyWidgetCore`.
- **`LivebuyWidget` is now a `@Deprecated` thin alias** (subclass of
  `LivebuyWidgetCore`, behavior byte-equivalent) — existing
  `LivebuyWidget(shopId: …)` host code keeps compiling + running, emitting a
  deprecation notice. The alias is **removed at v2.0**.
- The `LivebuyWidget` name is being **repurposed** for the upcoming turnkey
  drop-in widget container in `livebuy_flutter_reference_ui` (philosophy B,
  parallel to the player container). Migrate bare-widget usage to
  `LivebuyWidgetCore`.
- **No bridge-wire / native change:** viewType `LivebuyWidgetView`, method
  channel `tv.livebuy/widget_$id`, and creationParams are unchanged — the rename
  is Dart-surface only. `LivebuyWidgetController` and `LivebuyFloatingWidget` are
  **not** renamed.

## 1.3.0 - 2026-05-26

> **發版前剩餘步驟:** `flutter pub publish`(需 pub.dev 帳號)。本機已完成:`pubspec.yaml` `version` 已升至 `1.3.0`、`flutter analyze` 0 issues、`flutter test` 23/23 綠(Mac mini Apple Silicon, Flutter 3.44.0)。example app build 撞 Flutter 3.44 預設 toolchain(Gradle 9.1 / SPM-by-default)獨立議題,不影響 plugin source 發版。

### Added — API version resilience (`api-version-resilience`)

- `LBConfigOptions.apiVersion` — `int`, default `1`. Method-channel `configure`
  call now carries `apiVersion` to native;native SDK (iOS / Android)
  drives the `X-API-Version` request header. Invalid (0 / negative) values
  fall back to `1` natively with a debug log.
- `LBEvent.sdkDeprecationNotice` — new event name dispatched via the
  `tv.livebuy/sdk` method channel reverse path (`onSdkEvent`). Fires once per
  process when backend response header `X-API-Deprecation: true`. Payload:
  `{ sunset_date: String?, sdk_version: String, recommended_action: 'upgrade-sdk' }`.
- `LBErrorSdkVersionUnsupported` — new sealed-class subclass under `LBError`.
  Raised on every API response with inner `code: 426` (no dedup).
- `LBRoute` enum — Dart-only mirror of the native endpoint registry for
  type-check / logging parity. Exported from `package:livebuy_flutter/livebuy_flutter.dart`.

### Changed

- iOS Flutter handler (`LivebuyPlugin.swift`) + Android Flutter handler
  (`LivebuyPlugin.kt`) accept `apiVersion` argument on `configure`.
- Player error path on both native handlers (`LivebuyPlugin.swift` /
  `LivebuyPlayerViewFactory.kt`) maps `LBError.SdkVersionUnsupported` /
  `.sdkVersionUnsupported` to `{ type: 'sdk_version_unsupported' }` on the
  event channel.
- `lbErrorFromMap` 對應加 `'sdk_version_unsupported'` case。

### Migration

See [Migration Guide — API Version Resilience](../docs/migration/api-version-resilience.md).
TL;DR — existing Flutter integration code 不用改;建議:
- listener 依 `event.eventName == LBEvent.sdkDeprecationNotice` 加 case → 軟性提示。
- error path `if (err is LBErrorSdkVersionUnsupported)` → 強制升級提示。
- 未來 backend 推 v2 時,在 `LBConfigOptions(apiVersion: 2)` 切版。
