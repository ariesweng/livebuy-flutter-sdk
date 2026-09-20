# Changelog — livebuy_flutter

All notable changes to the Livebuy Flutter plugin will be documented in this file.

Format conforms to [pub.dev CHANGELOG guidelines](https://dart.dev/tools/pub/package-layout#changelogmd).

## [Unreleased]

## 2.5.1 - 2026-09-20

> **Patch — regression fix for a broken v2.5.0 release.** `v2.5.0` shipped with
> `flutter/android/build.gradle`'s core dependency pin (`tv.livebuy:livebuy`) still at
> `4.19.0`, two versions behind the core symbols the Android bridge
> (`LivebuyPlayerViewFactory.kt`) already referenced (`LBLiveVideoSurfaceMode`, introduced in
> `android-v4.21.0`; `beginScrub()`/`endScrub()`, introduced in `android-v4.20.0`) — the
> published `v2.5.0` tag itself fails to compile for any consumer resolving the real remote
> Maven artifact. Discovered when a downstream host app upgrading to `v2.5.0` hit a build
> failure. This release only bumps the pin to `4.21.0` (`flutter-android-bridge-core-pin-4-21-0`);
> `v2.5.0` cannot be overwritten, so this patch supersedes it. **Android-only fix** — pure
> Dart consumers and the iOS build are unaffected (`livebuy_flutter.podspec` / `Package.swift`
> already float on `~> 4.0` / `from: "4.0.0"`, which already covered `4.21.0`). **Zero
> BREAKING.**

### Fixed

- **`flutter/android/build.gradle` core dependency pin bumped `4.19.0` → `4.21.0`**
  (`flutter-android-bridge-core-pin-4-21-0`): closes the real compile-time symbol gap that made
  the published `v2.5.0` Android build fail (`LBLiveVideoSurfaceMode` + `beginScrub()`/
  `endScrub()`). No Dart or bridge Kotlin source changed — pin coordinate + explanatory comment
  only.

## 2.5.0 - 2026-09-20

> **三套件版號 lockstep bump（`livebuy_flutter` core / `livebuy_flutter_ui` / 
> `livebuy_flutter_reference_ui` 皆有實際內容變動）。** 自 `2.4.0` 以來累積 23 個內容
> commit，主軸是 VOD/回放拖曳進度條 scrub-tolerance 全鏈路（seek 合併、Android
> CLOSEST_SYNC/EXACT 動態切換、結算順序修復、Android 專屬視覺節流）、design R39/R45/D8/R46/R47
> 五輪視覺批次、MiniCartPeek 原價劃線 parity 收尾（四端完成）、widget 卡片預覽 Android 解碼器
> 資源管理批次、Android 平台視圖重複 `load()` 修復、PiP 凍結緩解、`togglePlayPause` bridge
> 死接線修復，以及 pubspec SDK 下限修正與測試維護。**零 BREAKING。**

### Added

- **MiniCartPeek 原價劃線渲染**（reference-ui，`originalPriceShow`）：`LBMiniCartPeek`
  template 型別新增 additive 欄位，`MiniCartPeek` 補上原價劃線渲染，parity iOS/Android/RN
  已完成，四端全數完成。
- **`seek()` 合併連續 absolute seek 呼叫至最新目標**（core，`flutter-vod-seek-request-
  coalescing-core`）：避免快速/長距離拖曳時一連串 seek 呼叫在 Android UI thread 上堆積成
  MethodChannel 佇列；`seekBy()`（相對位移）刻意不合併，避免破壞累加偏移量。
- **`PlaybackEngine` 新增 `beginScrub()`/`endScrub()`**（core + reference-ui，Android-only，
  透過 `defaultTargetPlatform` guard、零 iOS 檔案異動，`flutter-vod-scrub-seek-tolerance-core`
  /`-reference-ui`）：拖曳中切換 `CLOSEST_SYNC`、結算前還原 `EXACT`，修正拖曳後 2–3 秒追趕
  延遲，同時避免全域套用 `CLOSEST_SYNC` 導致的音畫不同步；`LivebuyPlayer` 既有
  `onScrubbingChange` callback 接上這組開關。

### Fixed

- **Design R39/R45/D8/R46/R47 五輪視覺批次**（reference-ui）：商品列名稱前標籤改用
  `Text.rich`/`WidgetSpan` 修正換行擠壓（R39 parity）、商品列表 row 排版重分組 + 新增折扣
  百分比（R45）、商品明細「更多商品」grid 原價改用 `Wrap` 換行、雙擊快進/快退提示改半螢幕
  漸層、`AddToCartSheet` 主圖旁價格區改垂直堆疊（原價移到現價上方）；商品明細 sheet 原價
  劃線色票統一 `#A0A0A0`。皆為純視覺/排版修正，parity iOS/Android/RN。
- **`VideoInfoPanel` 三態文案改版**（reference-ui，`rb-flutter-video-info-panel-replay-copy`，
  R44 parity，四端完成）。
- **修正 Android 平台視圖建立時重複發送 `load()`**：避免造成雙重 `POST /sdk/video`。
- **修復 scrub 結算 seek 順序 bug**（reference-ui，`fix-flutter-scrub-end-before-final-seek-
  reference-ui`）：`PlaybackProgressBarView._handleUp()` 的 release/cancel 路徑此前最終強制
  `onSeek` 早於 `onScrubEnd` 送出，使結算畫面仍套用 `beginScrub()` 的 `CLOSEST_SYNC`，造成
  真機實測拖曳後畫面持續落後音訊 2–3 秒；改為 `onScrubEnd` 先送，讓 `endScrub()` 在最終 seek
  前生效。
- **Android 拖曳進度條視覺更新加 33ms 節流**（reference-ui，僅 Android，
  `flutter-android-scrub-drag-visual-throttle-reference-ui`）：Flutter Android 用 Hybrid
  Composition 內嵌播放器，逐幀合成成本高於原生 TLHC，拖曳把手先前每次觸控移動都無節流觸發
  `setState` 造成卡頓；新增獨立 33ms 節流（與既有 120ms `onSeek` 節流分開），最終
  release/cancel seek 仍讀取未節流的精確值，不受影響。
- **widget 卡片預覽 Android 解碼器資源管理補強**（reference-ui）：離屏 1 秒後釋放解碼器、
  滾入重建；偵測 opaque route 覆蓋時同步釋放/重建、初始化失敗有上限重試；捲動停止即整新
  可見性回報（免等 500ms 節流）；不再參與 audio focus 仲裁（parity 原生 ExoPlayer 預設）。
- **緩解 Android/Flutter PiP 凍結**、修正 `togglePlayPause` bridge 未轉發到真實原生方法。
- **`flutter-reference-ui` pubspec `flutter` SDK 下限修正**：`>=3.10.0` → 對齊實際使用的
  `Color.withValues` API 所需版本，純 metadata 修正，不影響渲染行為。
- **測試維護**：修正 `uninstall()` method-channel fire-and-forget 造成的偶發測試失敗；
  重生 EndScreen 倒數變體 golden 追上 R41 遮罩改色。皆無行為變化。

## 2.4.0 - 2026-09-13

> **三套件版號 lockstep bump（`livebuy_flutter` core 有實際內容變動，`livebuy_flutter_ui` 有
> 實際內容變動，`livebuy_flutter_reference_ui` 本輪零程式碼變動、隨 lockstep 慣例一併對齊）。**
> 自 `2.3.1` 以來累積 3 個 core 內容 commit + 1 個 template 內容 commit + 1 輪 Android bridge
> core pin 追新，主軸是加購前登入攔截、`CART_ADD_REQUEST` 補回傳加購數量，以及一輪例行 pin
> bump（`4.18.0`→`4.19.0`）。**零 BREAKING。**

### Added

- **加購前本地攔截未登入使用者**（`flutter-add-to-cart-login-gate-core` / `-template`）：新增
  全域設定 `requireLoginForAddToCart`（default `false`，additive），`DefaultTemplate.addToCart()`
  新增本地檢查，重用既有登入閘呈現路徑，parity 四端。
- **`CART_ADD_REQUEST` 事件補回傳加購數量**（`cart-add-request-num-flutter-core`，`num`），
  additive 欄位，parity iOS/Android/RN。

### Fixed

- **Android bridge core pin 例行追新 `4.18.0` → `4.19.0`**（`flutter/android/build.gradle`，
  `flutter-android-bridge-core-pin-4-19-0`，已核對 `livebuy-android-sdk/CHANGELOG.md` 的
  `[4.19.0]` 條目確認本輪 `:livebuy` core 模組零 BREAKING、且新增的兩項
  （`requireLoginForAddToCart` 純 Dart 側實作不經過 native bridge、`CART_ADD_REQUEST.num` 走
  整包泛型透傳不需 bridge Kotlin 跟著改）皆與本 bridge 原始碼無關，回到例行維護，不需符號級
  驗證）。

### Deprecated

- **`addToCart` 的 `ids`（批次結帳模式）標記淘汰**（`deprecate-cart-purchase-ids-mode`）：查證
  零呼叫端使用，加 doc comment 說明，預告下一個四端同步的 major 版本移除。零執行期行為改變，
  parity 四端。

## 2.3.1 - 2026-09-11

> `livebuy_flutter_reference_ui` 專屬的兩個小型 bug fix（`livebuy_flutter` /
> `livebuy_flutter_ui` 兩套件本身無程式碼變動，版號隨 lockstep 慣例一併對齊）。皆為使用者
> 真機回報後查證修復，無 BREAKING。

### Fixed

- **直播間觀看人數恆為初始值**（`fix-flutter-viewer-count-unwired`）：`onMomentStateChange`
  的容器轉發函式只轉發 `products`/`narratingProduct`，`viewerCount` 雖然 native 橋接（Android
  `MomentFieldsBridge` / iOS `LivebuyPlugin`）早已送達，卻從未轉發給
  `DefaultPlayerTemplate.handleViewerCount()`（該方法本身早就寫好且有單元測試，是條死接線）。
  補上這一行轉發，其餘 5 個仍刻意未接線的欄位（`isSubscribed`/`autoNextCountdownActive`/
  `autoNextRemainingSeconds`/`nextItem`/`hotItems`）不變。
- **直播結束畫面右上角關閉/縮小鈕點不到**（`fix-flutter-endscreen-close-button-blocked`）：
  `EndScreenView` 的滿版半透明背景（`Container(color: _scrim)`，本質 `ColoredBox`）的
  `hitTestSelf` 恆為 `true`，攔截了整個螢幕範圍的觸控，擋住底下 `PlayerShellView` header
  的縮小/關閉鈕，即使該背景本身沒有掛任何手勢。改為只把這個背景節點包進
  `IgnorePointer`，倒數/空狀態變體既有的取消/立即觀看/查看購物車按鈕不受影響。**另外**，
  結束畫面顯示期間，header 右上角鈕的行為固定改為「直接關閉整個 player」（複用既有
  `onCloseRequest`／swipe-nav-close-on-empty 出口），**不論全域 `enableDirectCloseButton`
  設定為何**——這是使用者明確決策；此前這顆鈕在結束畫面顯示期間因上述觸控攔截問題完全點不到
  （等同死按鈕），故此行為調整對既有 host 無實際行為倒退。

## 2.3.0 - 2026-09-11

> **三套件皆有實際內容變動**（lockstep）。自 `2.2.0` 以來累積 90 個內容 commit，主軸是
> Android 真機測試回報的三個播放器崩潰/黑畫面修復、`mute-preference-persist-across-session`
> parity 收尾、iOS 自動 PiP、介紹中商品卡在 iOS/Android 兩端的資料缺口，以及一個延續多輪的
> reference-ui 視覺打磨批次（CC 字幕/tooltip、底部安全區、公告橫幅、聊天室配色、等化器動畫、
> 商品名稱標籤系統）。**含 2 項 ⚠️ BREAKING**（詳見下方專節）。四支 Android bridge core pin
> 追新記錄（`4.13.1`→`4.16.0`→`4.17.0`→`4.18.0`）已在 `[Unreleased]` 段落逐輪記錄過，本輪一併
> 折入正式版號，不重複列出細節。

### Added

- **Mute 偏好跨 App session 持久化，Flutter 收尾**（`flutter-player-instantiation-hook-core`、
  `mute-preference-persist-across-session-flutter-core`、`-template`）：新增
  `LivebuyPlayerController.onInstantiate` per-instance hook（parity iOS/Android）與
  `isMuted(): Future<bool>` 查詢出口；已確認 Flutter native 音訊層對 iOS/Android 這輪新增的
  app-session 持久化行為是 no-op（純轉發、無獨立引擎狀態），template 層改用 hook 對齊
  mute 圖示 attach 種子的 per-instance parity。
- **iOS 自動 PiP entry**（`flutter-ios-auto-pip-entry`）：Flutter iOS bridge 補上 app
  切背景時自動觸發 PiP 的生命週期監聽，parity Android sibling，並訂正該 sibling change
  當初「iOS 天然覆蓋、無此缺口」的錯誤假設。
- **介紹中商品卡 / 商品袋資料缺口補齊（iOS + Android）**（`flutter-ios-moment-products-bridge-core`、
  `flutter-android-moment-products-bridge-core`、`flutter-moment-products-wiring-reference-ui`）：
  `momentStateChange` 擴充 `products`/`narratingProduct` 欄位並接線容器，修復商品袋在 iOS/Android
  真機顯示空清單、介紹中商品卡不即時更新的問題。
- **頻道公告文字提早送達**（`channel-notice-bridge-core-flutter`、
  `live-announce-immediate-display-reference-ui-flutter`）：`channelChange` 新增
  `notice`/`sysNotice` 欄位並轉發進 template，公告橫幅不必等首輪 poll 即可顯示。
- **`currentShopId` 讀回介面 + 現正直播 pill 自動 shopId turnkey**
  （`flutter-live-now-pill-auto-shopid-turnkey-core`、`-reference-ui`、
  `flutter-example-wire-live-now-pill-shopid`）：`LivebuySDK.currentShopId` 讀回
  `configure()` 最後一次傳入的 shopId，`LivebuyPlayerConfig` 新增
  `showsLiveNowPill`/自動 shopId fallback，parity iOS。**含 1 項 BREAKING，見下方專節**。
- **`isFlashSale` 頻道旗標**（`channel-flash-sale-flag-core-flutter`、`-template-flutter`、
  `rb-flutter-flash-sale-live-signal-wiring`）：`LBPlayerChannelInfo` 新增
  `isFlashSale`，商品名稱標籤系統新增搶購中分支、narrating 文案二選一，parity iOS/Android/RN。
- **回放聊天室依時間顯示完整鏈路**（`flutter-replay-chat-history-reveal-template` 及其修正、
  `fix-flutter-replay-chat-progressive-reveal-template`/`-reference-ui`）：補接
  `CHAT_HISTORY_LOADED` 事件顯示歷史留言，移除誤接的一次性全灌驅動改為漸進式，reference-ui
  容器接上正確資料來源，parity iOS/Android。
- **加入活動列自帶主播名**（`event-join-streamer-name-template-flutter`、
  `rb-flutter-event-join-streamer-name`），parity Sibling iOS/Android/RN。
- **商品名稱標籤系統 / 等化器動畫（design R39/R40）落地**：`rb-flutter-product-row-name-tag-system`
  （直播價/熱賣中/即將售完）、`rb-flutter-live-equalizer-motion`（呼吸動畫能力）、
  `rb-flutter-product-row-live-equalizer-wiring`、`rb-flutter-vod-and-pinned-equalizer-wiring`
  （VOD遮罩/直播釘選卡接上動畫，`parity-debt-ledger#4` 全數清除）、
  `rb-flutter-collapsible-player-floating-position-inset`（host 覆寫 position/inset）、
  `rb-flutter-collapsible-player-theme-default`（`theme` 改選填自解析）。
- **CC 字幕鈕圖示重新設計**（`rb-flutter-cc-icon-availability-redesign`、
  `rb-flutter-cc-icon-active-fill-state` ×2）：不可用時恆渲染＋提示泡泡，啟用時改 active 填色態。
- **直播公告橫幅圖示改自訂向量**（`rb-flutter-live-announce-bullhorn-icon`），parity Sibling
  iOS/Android/RN。
- **商品照片載入體驗優化**（`rb-flutter-product-image-loading-polish`）：提早 prefetch、
  淡入轉場、佔位色改中性灰，parity iOS/Android/RN。
- **觀眾留言暱稱改粉色 + 訊息不限行數**（`rb-flutter-chat-audience-bubble-pink-nickname-full-lines`）。
- **聊天室最新訊息 pill 改白底 accent 字並水平置中**（`rb-flutter-chat-pill-color-align`）。
- **分享失敗新增 `onShareFailed` host callback**（`flutter-share-failure-onshare-failed-callback-reference-ui`）：
  正式推翻 2026-09-07 崩潰防護規則的錯誤回報限制（使用者授權），`onServiceLink` 不受影響。
- **loading 底改用封面圖 + 深色遮罩**（`player-loading-cover-background-reference-ui-flutter`），
  parity iOS/Android/RN。
- **VOD 介紹中商品卡顯示時機比照側欄/浮動商品袋**（`rb-flutter-now-introducing-carousel-buffering-gate`），
  parity Flutter/iOS。
- **直播模式點商品縮圖跳過關閉商品列表抽屜**（`rb-flutter-product-sheet-keep-open-on-live-seek`）。
- **底部安全區系統性修正**（`fix-flutter-player-shell-bottom-safearea-gaps`、
  `rb-flutter-player-shell-bottom-chrome-safearea`）：進度條/聊天室/開場略過鈕/VOD字幕疊層/
  VOD商品卡等五個表面補齊 `MediaQuery.padding.bottom` 疊加，clean-mode 退出鈕/浮動購物袋/
  VOD側欄/LIVE底部bar 對齊 iOS 原生避開 home indicator。**含 1 項 BREAKING，見下方專節**。
- **進度條拖曳節流**（`rb-flutter-progress-bar-drag-seek-throttle`）：`onSeek` 加節流，避免每個
  拖曳 pixel 都觸發跨 process native seek IPC 往返造成卡頓。

### Fixed

- **真機測試發現的三個 Android 播放器崩潰/顯示缺陷**：聊天室完全收不到訊息（EventChannel 跨
  執行緒呼叫崩潰，`flutter-android-poll-received-main-thread-fix`）、直播 SurfaceView 蓋過
  Flutter 疊層（改走 Hybrid Composition，`flutter-android-player-hybrid-composition`）、換片
  時原生 view 重建繞過 `VIDEO_SWITCH`／公告橫幅死碼未接線／rail 可用性讀舊值三部曲
  （`flutter-video-open-reset-backstop-template` 等三個 change 合併修復）。
- **Android bridge core pin 例行追新**：`4.13.1`→`4.16.0`（補記治理缺口）→`4.17.0`→`4.18.0`
  （四個獨立 commit，逐輪已核對 `livebuy-android-sdk/CHANGELOG.md` 對應版本條目；`4.18.0`
  那輪確認新增 `isMuted` getter 並以 `javap` 反組譯驗證）。
- **widget 卡片封面圖永久空白**（`flutter-refui-widget-uncovered-navigation-blank-cover`）：
  preview/cover/placeholder 原本三選一改為 Stack 疊層。
- **`share_plus` iOS 26 crash**（`fix-flutter-share-plus-ios26-crash-upgrade`）：升級至
  12.0.2 修復無 `sharePositionOrigin` 時 crash；example app 另以 `dependency_overrides`
  釘住相容版本解 compileSdk 34 衝突。
- **換片重置補齊**：`loadingCover`（`flutter-loadingcover-reset-on-new-session-template`）、
  `startScreen`（`flutter-startscreen-reset-on-new-session-template`）、聊天室/活動 feed
  快取還原（`chat-history-video-switch-cache-flutter`）、商品明細 sheet-stack 五個
  view-model 重置（`flutter-product-sheet-stack-video-switch-reset-template`，parity RN）、
  聊天訊息相鄰輪 poll resend 重複顯示（`flutter-chat-push-id-dedupe-template`，Deferred RN）。
- **拖曳播放進度條期間隱藏公告橫幅/聊天室/pin商品卡**（`fix-flutter-scrub-hide-announce-chat-pinned`，
  parity iOS/Android）；**進度條展開暫留期間**同三元件改往上推避讓 transport bar
  （`rb-flutter-scrub-expanded-chrome-lift`）。
- **CC tooltip 系列修復**：LIVE 底部列泡泡文字被寬度鎖死裁切（`rb-flutter-cc-tooltip-bubble-width-clip-fix`）、
  VOD 側欄箭頭三角形頂點座標寫反（`rb-flutter-cc-tooltip-left-arrow-direction-fix`）、
  邊界夾制後箭頭改反向補償維持指向按鈕（`rb-flutter-cc-tooltip-arrow-anchor-fix`）。
- **字幕疊層 / 回放隱藏公式系列**：VOD 字幕疊層底部固定預留商品卡空間
  （`rb-flutter-vod-caption-reserve-card-space`）、窄框內水平置中並在回放開字幕時隱藏聊天室
  （`rb-flutter-caption-overlay-align-hide-chat`）、垂直定位改單一事實來源避免與底部列重疊
  （`rb-flutter-caption-overlay-bottom-bar-clearance-fix`，Android/RN 記入 ledger #23）、回放
  聊天室隱藏公式補 `subtitleAvailable` 判斷（`rb-flutter-caption-chat-hide-availability-gate`）、
  已結束直播回放改嚴格 `isLive` 排除讓真正 VTT/CC 字幕可顯示（`rb-flutter-replay-caption-overlay-fix`）。
- **聊天室底部間距對齊**（`flutter-live-chat-clearance-realign`）：無公告時對齊置頂商品卡，有
  公告時緩衝加倍。
- **觀眾留言暱稱冒號改回白色**（`rb-flutter-chat-audience-nickname-colon-color-fix`，重生 3 張
  golden baseline）。
- **商品明細「更多商品」推薦區塊捲動位置重置**（`rb-flutter-recommendation-switch-scroll-reset`）。
- **`LivebuyLiveEntry` 補 Material 祖先**（`rb-flutter-live-entry-material-ancestor-fix`）：修復
  LIVE 標籤黃底線。
- **「介紹中」equalizer 特效改回恆動畫**（`rb-flutter-equalizer-live-gate-removal`），不再受
  isLive/live 凍結，parity Already-parity iOS/Android/RN。
- **narrating 橫幅撤回搶購場二選一**（`rb-flutter-narrating-banner-revert-flash-sale-text`），
  恆顯示介紹中。
- **容器 loading/開場收斂修復**：loading 階段隱藏 chrome 避免先閃現才被覆蓋
  （`rb-flutter-player-hide-chrome-until-loaded`）、開場容器補不透明兜底背景避免透出底下舊路由
  （`rb-flutter-player-open-opaque-backdrop`）、換片時同步清空 `loadingCover`
  （`rb-flutter-player-reset-loadingcover-on-new-session`）。
- **GuestNameEditModalView 徽章圖示尺寸對齊 iOS/Android/RN**（`rb-flutter-icon-parity-guestname-badge-icon-size`，
  重生對應 golden）。
- **LIVE 公告橫幅改雙行顯示**（`flutter-live-announce-two-line-clearance-fix`），聊天室避讓距離
  校正，重生受影響 golden baseline。
- **Example app 修復**：`LivebuySDK` pod 釘版每次重跑改為比對後才刷新（`flutter-example-bootstrap`）、
  暫時停用手勢引導提示展示（`flutter-example-suppress-gesture-hint-demo`）。

### ⚠️ BREAKING

- **`LivebuyPlayerConfig` 現正直播 pill 預設行為「關」→「開」**（reference-ui，
  `flutter-live-now-pill-auto-shopid-turnkey-reference-ui`）——修復回放/VOD 缺少「前往直播」
  pill 的根因後，預設值連帶翻轉為顯示；不想要的 host 需明確傳 `showsLiveNowPill: false`
  關閉。Android/RN 對等 turnkey 尚未跟進，記錄於 `parity-debt-ledger` #16（Deferred，待使用者
  確認後再排入）。
- **細線進度條 idle 態底部定位公式變更**（reference-ui，
  `fix-flutter-player-shell-bottom-safearea-gaps`）——移除「恆為 `bottom: 0`」的短路，改與展開
  態套用同一套系統底部安全區公式；沒有安全區的裝置（無 home indicator / 無手勢列）視覺不變，
  有安全區的裝置進度條會往上抬升安全區高度，非公開 API 簽章變更，純既有像素表面行為調整。

## 2.2.0 - 2026-09-08

> **三套件皆有實際內容變動**（lockstep）。自 `2.1.0` 以來累積 26 個內容 commit
> （另 2 個純測試補強不列入），主軸是使用者實機測試（Samsung SM-G887F）回報的一系列
> Android/Flutter 播放器互動問題修復，加上讚特效素材落地收尾與商品列表狀態旗標訂正批次。
> **含 3 項 ⚠️ BREAKING**（詳見下方專節）。

### Added

- **讚特效重寫收尾（design R37）**：讚按鈕點擊觸發的飄心特效改為 4 種隨機圖案（愛心/星星/
  箭頭/十字）× 3 種上升軌跡 × 3 種擺動路徑，並新增讚鈕亮色態（`rb-flutter-live-like-burst-
  restyle`）；素材落地問題解除後，4 種圖案全數改用設計稿提供的真實 PNG 素材繪製，取代前一輪
  的 Material icon / 自繪徽章近似畫法（`rb-flutter-live-like-burst-png-glyphs`，含 BREAKING，
  見下方專節）。
- **售完 / 介紹中 / 回放狀態訂正批次**：LIVE 直播疊層置頂商品卡現在會正確顯示「已售完」標籤
  （`rb-flutter-live-pinned-card-soldout-label`）；直播回放中從未被主播介紹過的商品縮圖不再
  顯示看講解／介紹中效果，點擊完全 no-op（`rb-flutter-replay-never-introduced-no-ui` /
  `-tap-noop`）；商品列表縮圖的覆蓋層模式改讀正確的 `isFinishedLiveReplay` 旗標
  （`rb-flutter-product-row-replay-flag-fix`）；VOD 商品列表縮圖撤回先前誤加的「done」狀態
  （`rb-flutter-product-row-vod-done-state-removed`）。
- **商品明細「更多商品」推薦區塊補齊**：`channel.other_goods` 首次真正接上明細 sheet 的推薦格
  （`rb-flutter-other-goods-channel-bridge-core` + `-recommendations-wiring`）。
- **釘選商品卡點擊行為變更**：點擊直播疊層的釘選商品卡改為開啟商品明細 sheet 並攜帶被點擊的
  商品，取代先前固定開啟第一個商品的行為（`rb-flutter-pinned-card-tap-opens-detail`，含
  BREAKING，見下方專節）。

### Fixed

- **播放器手勢與導流修復（使用者實機測試批次）**：修復點擊商品卡完全崩潰跳出 app 的問題
  （`flutter-url-open-crash-guard-template`，導流連結開啟）、分享／聯絡商家按鈕崩潰
  （`flutter-share-crash-guard-reference-ui`）、商品明細／加購／補貨 sheet 完全點不開
  （`flutter-product-tap-diversion-wiring-reference-ui`，補齊 `channel.diversion` 橋接
  `channel-diversion-bridge-core-flutter`）、上下滑手勢切換相鄰影片失效
  （`flutter-swipe-nav-wiring-template`）、開場影片播放時「略過介紹」skip 鈕不出現
  （`flutter-intro-overlay-wiring-reference-ui`）。
- **進度條顯示修復**：修正細線／展開進度條在特定情境下從中間往兩邊跑出、填色錯位的問題
  （`flutter-progress-bar-track-fill-width-guard-reference-ui`）。
- **商品列表縮圖點擊修復**：點擊縮圖前往介紹片段（seek）時同步關閉抽屜，補齊四端唯一缺此行為
  的 Flutter（`rb-flutter-product-bag-seek-dismiss`）；分享鈕改接上真實系統分享，不再只送無人
  接收的頻道事件（`rb-flutter-product-list-share-tap-noop`）。
- **「更多」選單 sheet 對齊修復**：動作列補上遺漏的頂部間距（`rb-flutter-live-more-sheet-
  vertical-padding`，`top` 值原寫成 0）；改用共用 `LBSheetScaffold`，補齊把手與拖曳收合行為
  （`rb-flutter-live-more-sheet-drag-resize-parity`）。
- **Sheet 拖曳 resize 修復**：resize 下限改為恆定的結構性下限，dismiss 下限則獨立每次手勢
  重新錨定，修正先往上拉再往下拖時出現的異常留白（`rb-flutter-sheetkit-resize-floor-not-
  reanchored`）。
- **Icon 對齊修復**：修正商品明細放大鏡圖示的握把方向與圓周錨定問題
  （`rb-flutter-product-detail-zoom-badge-glyph-alignment`）；飄動愛心改用向量 `Icons.favorite`，
  取代字面 Unicode `♥` 字元（`rb-flutter-heart-burst-icon-parity`）；明細鈕改用向量
  `DetailGlyph`、搜尋欄改用向量 `SearchGlyph`（皆取代字面/emoji 字元，2026-09-06 落地，
  本輪重生對應 golden baseline 收尾）。
- **商品清單置頂排除純 VOD**（`flutter-vod-product-list-introducing-order-exclude-vod-template`）。

### ⚠️ BREAKING

- **`LivebuyPlayerConfig.onTapPinnedProduct` 型別變更**（reference-ui，
  `rb-flutter-pinned-card-tap-opens-detail`，**唯一一項源碼相容性破壞**）—— `VoidCallback?` →
  `ValueChanged<LBProduct>?`。既有覆寫此參數的 host（`onTapPinnedProduct: () { ... }`）升級後將
  編譯失敗，修法是把簽章改為 `(product) { ... }`（一行改動）。iOS/Android/RN 套件不受影響。
- **售完商品縮圖覆蓋層行為變更**（reference-ui，非 API 簽章變更，
  `rb-flutter-product-row-soldout-introducing-visible`）—— 售完商品若同時處於介紹中狀態，縮圖
  現在會顯示介紹中效果（VOD 遮罩／LIVE-REPLAY 橫幅），先前這種組合下縮圖只顯示乾淨的售完態。
- **讚特效飄心不再吃 `theme.accent` 染色**（reference-ui，僅本套件內部實作細節，非公開 API，
  `rb-flutter-live-like-burst-png-glyphs`）—— 4 種圖案（含先前吃 accent 染色的 heart）統一改為
  顯示各自 PNG 素材本身烘焙好的固定色，parity RN 同批決策。

## 2.1.0 - 2026-09-07

> **三套件皆有實際內容變動**（lockstep）。自 `2.0.2` 以來累積 47 個 commit，主軸是「四端
> 100% 像素 parity」補課政策的 Flutter 端批次，與 v4.14.0 iOS/Android 同源但版號軌獨立，
> 存底稍晚才折版。**含 3 項本端自身 ⚠️ BREAKING**（詳見下方專節）。

### Added

- **core bridge 補齊欄位**（皆 additive、既有呼叫端不受影響）：`LBVideoItem.goods:
  LBFeaturedGood?`（影片連結精選商品預覽，補齊與 iOS/Android core 的 parity，
  video-linked-goods-core-flutter）、`onMomentStateChange` moment state 6 個欄位、
  `channelChange` 的 `guestComment` / `channel.type` / `channel.goods` / `shop.intro` /
  header chrome 4 個欄位（並復活先前被移除的原生 `channelChange` 發送）、
  `performShare`/`performServiceLink` 攔截 Bool 透傳、`onReplayChatRevealed` 回放聊天揭露
  seam。
- **template 層**：規格連動可購性計算 `optionAvailability`、`loadingCover` 欄位暴露、用既有
  `POLL_RECEIVED` `guest_comment` 推導 `guestEditAvailable`、VOD/回放時介紹中商品置頂到最前。
- **reference-ui 首次接上真實資料**：點播間介紹面板 `handleInfo`（文字內容不再恆空）、商品
  清單 `handleProducts`（商品袋不再顯示空清單）、直播回放版型統一判斷
  `isFinishedLiveReplay`、播放器 header chrome + 側欄「聯繫商家」icon 隨頻道自動衍生。
- **design R30/R32/R33/R34/R35/R36 四輪改版落地**：直播入口卡 2 秒緩衝、VOD 側欄購物袋 icon
  比例校正、collapsible 縮小懸浮播放器修復、大批 icon 改自繪向量（bag/cart、登入鎖頭/中獎
  禮物、送出/略過介紹/縮小 PiP、重試/換一批/斷網/版本過舊、側欄/聊天室、聊天回到最新箭頭、
  商品明細按鈕）、開場影片播放期間抑制商品卡顯示、抽獎活動彈窗 CTA 移除已參加鎖定改可重複
  點擊、商品列縮圖左上角編號徽章、VOD 商品列縮圖三態覆蓋層、商品明細主圖改絕不放大/不裁切、
  widget 輪播卡片封面改 cover、聯絡商家「確定」未攔截時預設開瀏覽器。

### Fixed

- Android bridge 仍引用已改名 `LivebuyWidget` 符號修正；iOS plugin 透過 CocoaPods host 時的
  SPM identity 衝突修復 + 補 iOS podspec；商品規格比對修正子字串誤配對 bug；carousel 卡片
  標題行高改逐卡片實測，修正真實資料下的 1px overflow；`LivebuyPlayer`/縮小浮動預覽補
  Material 祖先修復文字黃底線；播放器頂欄/底部安全區、開場片頭底部購物袋列被乾淨模式擋住等
  多處版位修正。

### ⚠️ BREAKING

- **`enableDirectCloseButton` 全域預設值 `false → true`**（core，
  `flutter-player-direct-close-button-default-true`）——與 iOS/Android/RN 同批對等變更，行為
  面 BREAKING、非源碼相容面：既有呼叫端不帶此參數仍可編譯，但未指定時的有效值改變（右上角
  關閉鈕從「收合」變成「直接關閉」）。
- **`LiveBottomBarView` 組裝條件新增 `&& !_isScrubbing` 閘門**（reference-ui，
  `rb-flutter-replay-live-chrome-parity`）——直播回放版型統一後才會出現的新情境（已結束直播
  回放同時具備 VOD 式進度條與 LIVE 底部 bar），對齊 iOS 既有 `!isScrubbing` 閘門避免拖曳進度
  條時兩者重疊；原提案標注「行為新增，非既有行為破壞」。
- **商品明細相簿 `onZoomImage` callback 簽章變動**（reference-ui，
  `rb-flutter-product-detail-image-gallery`）——現有生產呼叫端僅 `product_sheets_view.dart`
  兩處，爆炸半徑限定在本 change 自己會動的檔案內。

> ⚠️ **事後補記（2.0.2 CHANGELOG 遺漏）**：`2.0.2` 實際上也包含
> `rb-flutter-carousel-card-pin-viewers-duration-removal`（VOD/回放輪播卡時長徽章移除，
> commit `8fcf6c3b`，2026-09-04 14:41，早於 `2.0.2` 版號 bump commit `92d40ee7`）與
> `rb-flutter-activity-sheet-cta-repeatable`（抽獎活動彈窗 `ActivitySheetView` 內部 API 變動，
> commit `0fd582ec`，2026-09-03 13:49）兩項 reference-ui-internal ⚠️ BREAKING——這兩項當時已
> 隨 `2.0.2` 真實發布，但 `2.0.2` 的 CHANGELOG 段落聚焦在 xsmartlive 回報的 3 個 bug 修復，
> 未一併記載。本補記不改變 `2.0.2` 版號、不重新發版。

## 2.0.2 - 2026-09-04

> **三套件皆有實際內容變動**（與 `2.0.1` 只有 reference-ui 動不同）。源自外部 Flutter host
> （xsmartlive）對 mirror repo `v2.0.1` 的整合缺陷回報，逐項查證後修復。
>
> ⚠️ 事後補記（見上方 `2.1.0` 段首）：本版實際上也包含 2 項 reference-ui-internal BREAKING
> （VOD/回放輪播卡時長徽章移除、`ActivitySheetView` 內部 API 變動），當時未記載。

### Fixed

- **`livebuy_flutter`（Android bridge）** — Android 原生端於 2026-06-11 把 `LivebuyWidget` 改名
  `LivebuyWidgetCore`，Flutter 這支 Kotlin bridge 檔（`LivebuyWidgetViewFactory.kt`）三個月來
  沒跟上、仍依賴已 deprecated 的相容 typealias；native SDK pin 同時落後兩版（`4.11.0` →
  `4.13.1`）。已改回正式符號並升版。
- **`livebuy_flutter_reference_ui`** — `CarouselView` 卡片標題行高改用 `TextPainter` 對實際套用
  的 `TextStyle` 做單行量測，取代先前手調的 `12 * fontScale * 1.34` 係數估算；該係數只針對
  Latin/Roboto 字型調校，CJK（中文/日文/韓文）locale 下系統選用的 CJK fallback 字型行高較高，
  會觸發 debug `RenderFlex` overflow。
- **`livebuy_flutter_reference_ui`** — drop-in 容器 `LivebuyPlayer` 掛載時呼叫 `setListener`
  會取代 `LivebuyUI.install()` 註冊的 template 事件訂閱（`setListener` 為單一全域槽），導致
  template 收不到事件、開場動畫 `startScreen.phase` 卡在 `loading` 不退場。容器 wrapper listener
  現在會同時轉發事件給 template（host 回覆優先，template 回覆 fallback）。`LivebuyWidget` 不受
  影響（從未呼叫 `setListener`）。

### Added

- **`livebuy_flutter`（iOS）** — 新增 `ios/livebuy_flutter.podspec`，讓 CocoaPods host（非僅
  Swift Package Manager）也能正常安裝；先前只有 `Package.swift`，CocoaPods-only host 會在
  `flutter pub get` 階段直接被 Flutter tooling 中止。與既有 SwiftPM 共用同一份原始碼樹，零分岔。
- **`livebuy_flutter_ui`** — 新增 `LivebuyUI.forwardToTemplate(LBSdkEvent) → Future<LBEventReply>`
  與 `TemplateAttachment.handleEvent(LBSdkEvent) → Future<LBEventReply>` 公開轉發介面，供
  drop-in 容器在自己的事件監聽器取代 template 訂閱後，仍能把事件轉發進 template（上述
  `livebuy_flutter_reference_ui` 修復即基於此介面）。未安裝 template 時安全 no-op（回傳
  `LBEventReply.passthrough`）。

## 2.0.1 - 2026-09-03

> **Patch，僅 `livebuy_flutter_reference_ui` 有實際內容變動；其餘兩套件（`livebuy_flutter` /
> `livebuy_flutter_ui`）純版號 lockstep bump，本輪零改動。** 含 1 項新增 optional 建構參數
> （additive、非 BREAKING）。兩項獨立修正：① 補齊 `2.0.0`（R29 播放器手勢三度改版）design.md
> 當時刻意記錄的 Non-Goals 延後項——乾淨模式退出鈕像素對齊設計稿；② `CollapsibleLivebuyPlayer`
> in-place 換片同步必填 `onVideoChanged` 回呼＋新增 `openSignal` 機制，parity Android/iOS/RN。

### Added

- **`CollapsibleLivebuyPlayer` 新增選填 `openSignal` 建構參數**（`int`，additive，預設 `0`）——
  縮小播放器後，在浮動小卡狀態下換片再點回同一支影片時，可遞增此值觸發正確重新展開，對齊
  Android/iOS 既有機制。

### Fixed

- **`livebuy_flutter_reference_ui`** — 乾淨模式退出鈕 icon 改為自繪 `DetailGlyph`（`CustomPainter`
  手繪，對齊設計稿 `Icons.detail`：帶邊框圓角矩形＋3 排 dot+line 清單造型），取代先前的 Material
  `Icons.fullscreen_exit`。VOD/已結束直播回放 `bottom` 由 `44` 修正為 `52`，對齊設計稿座標；LIVE
  `bottom: 16` 不變。
- **`CollapsibleLivebuyPlayer` in-place 換片原本只更新內部 `shownVideo`，不會通知必填的
  `onVideoChanged`**，host 若沒接選填的 `config.onVideoSwitchedItem` 會導致 session 狀態卡住
  （真實案例：WooCommerce Android app 輪播點回換片前影片沒反應）——換片時額外呼叫
  `onVideoChanged`（same-id guard 防重複），並新增 `isVideoChangeSwitchEcho` 純函式防止這個
  轉發誤觸浮動小卡狀態下的自動還原。

## 2.0.0 - 2026-09-03

> **首次真實對外發版**（`livebuy-flutter-sdk` mirror repo，git dependency 消費）。自上一個從未
> 真正 tag 對外發布的 `1.3.0`（api-version，2026-05-26 準備但未執行 `pub publish`）以來累積的
> 所有 breaking 與散佈姿態改變一次發。完整對外說明見 [release notes](../docs/release-notes/v2.0.0.md)，
> 升級照 [migration 總入口](../docs/migration/v2.0.0.md)。
>
> ⚠️ **既有紀錄補正**：本 mirror repo 曾於 2026-09-01 以驗證發版管線為目的真實發布過一次
> `v1.3.0` tag（`ariesweng/livebuy-flutter-sdk`）——該次發布**內容上已經是本輪 v2.0.0 等級**
> （brand-casing、headless 化等皆已完成），只是 `pubspec.yaml` 版號欄位當時尚未 bump，故被
> 誤標成 `1.3.0`。**該 tag 應視為管線驗證產物、非正式對外版本，consumer 不應鎖定它**——`v2.0.0`
> 是這個 mirror repo 第一個版號正確反映內容的真實發版。

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
- **現正直播「前往直播」提示鈕（`livebuy_flutter_reference_ui`，新能力）** — 觀看 VOD / 已結束直播回放時，若偵測到同一頻道現正直播中，顯示提示鈕引導前往直播。對齊 iOS/Android/RN 同輪落地。
- **VOD 正在介紹中商品訊號（core，parity iOS/Android/RN）** — 原生端新增 VOD 播放進度對應的「正在介紹中商品」訊號，四端收工。
- **`ActivitySheet` 多活動分頁點＋滑動切換（`livebuy_flutter_reference_ui`）** — `DefaultActiveEvent` template 層反轉舊版「只取第一筆活動」決策，曝露完整清單與分頁索引；`FeedWinModel`/`FeedWinView` 相應調整。
- **活動入口切換影片立即隱藏＋換片還原快取（`livebuy_flutter_reference_ui`）** — 換片時活動入口立即隱藏，換回原片時從快取還原顯示狀態。
- **暫停覆蓋層 ＋ 靜音 toast ＋ 雙擊送愛心延遲取消（`livebuy_flutter_reference_ui`，補建追平 iOS/Android 既有能力）** — `PausedOverlayView` / `GestureMuteToastView` 新增，v4.13.0 批次同輪一併退役（見下方 R29 BREAKING）。
- **播放器手勢三度改版 R29（`livebuy_flutter_reference_ui`，對齊 iOS/Android/RN v4.13.0 批次）新增**：`_cleanMode` 期間 `PlayerHeaderBarView` 新增靜音切換鈕；新增「退出乾淨模式」小圓鈕。
- **縮小按鈕 icon 放大 18 → 20px（`livebuy_flutter_reference_ui`）**，對齊設計稿。

**Changed**
- **⚠️ BREAKING（reference-ui 內部行為契約，R29，`livebuy_flutter_reference_ui`）— 播放器手勢觸發語意整個對調**：取代 R23 舊模型（長按=乾淨模式、單擊=靜音/播放暫停）：短擊切換 `_cleanMode`；雙擊（僅 VOD/回放）依左右半螢幕 seek ±10 秒，雙擊送愛心整段退役；長按（僅 VOD/回放）近似 2 倍速快轉。中央暫停覆蓋層移除，播放/暫停改由播放進度條展開態上的小按鈕操作；商品袋按鈕縮小。

**Fixed**
- **暫停覆蓋層擴大觸控命中框修現正直播提示鈕點擊無反應（`livebuy_flutter_reference_ui`）**＋對齊設計稿縮小尺寸。
- **iOS bridge `handle(_:result:)` 補 `@escaping` 修復編譯錯誤**——今天稍早已真實發版的 Flutter mirror repo（`livebuy-flutter-sdk` v1.3.0）需要在本輪落地後另行用修正後的來源重新發版覆蓋（真實對外發版動作，待另行確認執行）。
- **卡片標題文字縮放隔離，避免 host 端文字放大時觸發 debug overflow**。
- **loading 過場動畫資產補 `package:` scope**，修正被安裝進別的 app 時資產解析失敗。
- **`WinClaimSheet` 領獎 modal 頂部禮物徽章換成白底圓＋trophy glyph 對齊設計稿**。
- **活動入口 modal CTA 接上既有三層閘**，加入成功後自動關閉，被閘攔截時維持開啟。
- **`release-flutter.sh` mirror 內部 sibling 依賴修正為完整 git 依賴**，修復 consumer `pub get` 直接失敗（純 release 腳本修復，不影響已發佈套件行為）。
- **Android bridge core pin 例行追新 `4.10.0` → `4.11.0`**（`flutter/android/build.gradle`，已確認 v4.11.0 唯一 BREAKING 項不影響 bridge 原始碼，純例行維護）。

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
