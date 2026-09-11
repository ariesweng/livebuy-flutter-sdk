// T13.7 — Dart public data models

class LBUser {
  /// Required when calling [LivebuySDK.setUser]; optional on [LBConfigOptions].
  final String? displayName;
  final String? avatarUrl;
  final String? externalUserId;

  const LBUser({this.displayName, this.avatarUrl, this.externalUserId});

  Map<String, Object?> toMap() => {
        'displayName': displayName,
        'avatarUrl': avatarUrl,
        'externalUserId': externalUserId,
      };
}

class LBConfigOptions {
  final String apiKey;
  final String secret;
  /// Shop ID (base-62 encoded, e.g. `'Pw8PJ99J'`). Determines which shop's
  /// `/sdk/config` is fetched and is the scope key for the on-disk cache
  /// (`lb_sdk_config_{shopId}`). Required — Platform Key switching shops
  /// must re-configure with the new shopId. Per `sdk-config` capability.
  final String shopId;
  final LBLocaleCode? lang;
  final LBUser? user;
  /// Auto-enter PiP when a navigation interceptor event is taken over by the listener. Default true.
  final bool autoPipOnIntercept;
  /// API major version sent as `X-API-Version` header by the native SDK.
  /// Default `1`. Invalid (0 / negative) values fall back to `1` natively
  /// with a debug log. Per api-version-resilience.
  final int apiVersion;
  /// Max wait for `/sdk/config` on the no-cache blocking path AND the
  /// background-refresh path. Default 5000 ms. Invalid (≤0) values fall back
  /// to 5000 natively with a debug log. Per `sdk-config` capability.
  final int configFetchTimeoutMs;

  /// Opt-in for Meta conversion-attribution context (`conversion-attribution-context`).
  /// Default `false`. When enabled, the native SDK injects non-empty
  /// `fbp` / `fbc` / `referer` into every backend request (centrally, no
  /// per-call site); when disabled nothing is generated, persisted, or injected
  /// (ATT / privacy: no silent tracking — host owns ATT / GDPR consent). The SDK
  /// never sends `ip` / `agent` and never embeds the Facebook SDK. Feed `fbc`
  /// via [LivebuySDK.captureAdClick] / [LivebuySDK.setFbclid], `referer` via
  /// [LivebuySDK.setReferer].
  final bool enableConversionAttribution;

  /// Opt-OUT (default `true`) for thermal-aware power-profile adaptation
  /// (`power-profile-adaptation`). When enabled (the default), the native SDK
  /// auto down-scales live playback as the device heats up (lower quality cap +
  /// longer poll cadence) and restores symmetrically as it cools — nothing is
  /// sacrificed while cool. When `false` the subsystem stays dormant
  /// ([currentPowerProfile] returns [LBPowerProfile.full], no
  /// `POWER_PROFILE_CHANGED` events). The whole subsystem lives natively; this
  /// flag only forwards through the bridge. See [LivebuySDK.currentPowerProfile].
  final bool enablePowerProfileAdaptation;

  /// Opt-OUT (default `true`, on) for SDK-native `/stat` telemetry
  /// (`sdk-stat-reporting`). On by default: the native SDK sends the `/stat`
  /// events (video_pv / video_share / bag_click / goods_cart / person_time /
  /// … ) directly. The `/stat` wire carries only `type` + video/goods `id` +
  /// `val`/`link`/`bid`/`len` (no PII, no device id, no ip), so it defaults on —
  /// unlike [enableConversionAttribution], which stays opt-in because it carries
  /// Meta attribution ids (PII). Pass `false` to fully disable: nothing is
  /// generated, persisted, or sent (headless; ATT / GDPR consent is the host's
  /// responsibility). The whole subsystem (send channel, 30s timers, per-day
  /// dedupe) lives natively in the wrapped iOS/Android SDK; Flutter neither
  /// parses the `/stat` wire nor sends anything itself — this flag only forwards
  /// through the bridge. Use [LivebuySDK.clearStatContext] for a privacy /
  /// erasure request.
  final bool enableStatReporting;

  /// SDK-wide environment selector (`sdk-stat-endpoint-environment-selection-core` +
  /// `sdk-data-api-environment-selection-core` / `android-data-api-environment-selection-core`).
  /// Default [LBEnvironment.production] so existing callers stay on the live
  /// backend (source-compatible). It now has TWO consumers, both resolved
  /// natively:
  ///   1. the data API base URL for every `/sdk/*` request — [LBEnvironment.develop]
  ///      → `https://develop-admin.livebuy.tv/v1`, otherwise `https://api.livebuy.tv/v1`;
  ///   2. the SDK-native `/stat` telemetry channel — [LBEnvironment.develop] routes
  ///      beacons to `https://develop.livebuy.tv/stat`, otherwise `https://livebuy.tv/stat`.
  /// Flutter merely forwards this signal through the method channel to native
  /// `configure(environment:)`; BOTH the data API base URL selection and the `/stat`
  /// endpoint selection (plus the actual `/stat` send) happen entirely in the wrapped
  /// iOS/Android SDK — Dart never resolves a URL itself. `environment` switches URLs
  /// ONLY, never credentials: develop owns its own backend credentials, so a host
  /// selecting [LBEnvironment.develop] MUST pass matching dev `apiKey` / `secret` /
  /// `shopId`. It does not affect whether `/stat` is sent (that stays governed by
  /// [enableStatReporting]).
  final LBEnvironment environment;

  /// UI-only default: whether the `LivebuyPlayer` reference-ui collapse button
  /// closes the player directly instead of the two-step collapse → floating
  /// card → X flow (`player-direct-close-button`). Default `true` (direct
  /// close, skipping the floating card) — a deliberate, breaking UX default
  /// change (`flutter-player-direct-close-button-default-true`); a host that
  /// wants the old two-step behavior must explicitly pass `false`.
  ///
  /// This flag is consumed ENTIRELY by the pure-Dart `flutter-reference-ui`
  /// package — it has NO native iOS/Android SDK consumer (nothing plays or
  /// renders differently in the wrapped native SDK), so it is deliberately
  /// kept Dart-only: it is captured by [LivebuySDK.configure] into
  /// [LivebuySDK.enableDirectCloseButton] and is NEVER sent over the
  /// `tv.livebuy/sdk` method channel.
  final bool enableDirectCloseButton;

  const LBConfigOptions({
    required this.apiKey,
    required this.secret,
    required this.shopId,
    this.lang,
    this.user,
    this.autoPipOnIntercept = true,
    this.apiVersion = 1,
    this.configFetchTimeoutMs = 5000,
    this.enableConversionAttribution = false,
    this.enablePowerProfileAdaptation = true,
    this.enableStatReporting = true,
    this.environment = LBEnvironment.production,
    this.enableDirectCloseButton = true,
  });
}

// MARK: - Environment (sdk-stat-endpoint-environment-selection-core +
//         sdk-data-api-environment-selection-core)

/// SDK-wide environment selector, mirroring the native iOS
/// `enum LBEnvironment { case production, develop }` / Android
/// `enum class LBEnvironment { PRODUCTION, DEVELOP }`. Chosen once by the host
/// at [LivebuySDK.configure] via [LBConfigOptions.environment]; **defaults to
/// [production]** (source-compatible). It now has TWO consumers, both resolved
/// natively: (1) the data API base URL for every `/sdk/*` request — [develop] →
/// `https://develop-admin.livebuy.tv/v1`, otherwise `https://api.livebuy.tv/v1`;
/// and (2) the direct-send `/stat` telemetry channel — [develop] routes beacons
/// to the test backend (`https://develop.livebuy.tv/stat`), otherwise the live
/// backend (`https://livebuy.tv/stat`). It switches URLs only, never credentials
/// (a host on [develop] MUST supply matching dev credentials). Extensible (add
/// `staging` later).
///
/// [wireName] is the stable cross-platform string carried across the method
/// channel (mirroring how `lang` is sent as `LBLocaleCode.code`); the native
/// plugin handlers read it and map back to their own `LBEnvironment` enum.
enum LBEnvironment {
  /// Live backend. Data API → `https://api.livebuy.tv/v1`; `/stat` →
  /// `https://livebuy.tv/stat`.
  production('production'),

  /// Test backend. Data API → `https://develop-admin.livebuy.tv/v1`; `/stat` →
  /// `https://develop.livebuy.tv/stat`. Host must supply matching dev credentials.
  develop('develop');

  final String wireName;
  const LBEnvironment(this.wireName);

  /// Parse a native `wireName` string back to the enum. Unknown / `null`
  /// conservatively maps to [production] so a stale or future value never
  /// mis-routes live traffic to the test backend (or vice versa).
  static LBEnvironment fromWireName(String? name) {
    for (final v in LBEnvironment.values) {
      if (v.wireName == name) return v;
    }
    return LBEnvironment.production;
  }
}

// MARK: - Power profile (power-profile-adaptation, Flutter parity 第 6 支)

/// Thermal power-profile tier the native SDK is currently running under
/// (`power-profile-adaptation`). Mirrors the iOS / Android `LBPowerProfile`
/// enum: four tiers from cool → hot. [wireName] is the stable cross-platform
/// string carried by the `POWER_PROFILE_CHANGED` event `profile` param and by
/// the [LivebuySDK.currentPowerProfile] bridge — the SDK's internal quality cap
/// and poll backoff are driven by a native push sink, not by this enum.
enum LBPowerProfile {
  /// No down-scaling — full quality, base poll cadence (also the value returned
  /// when adaptation is disabled / the subsystem is dormant / API<29).
  full('full'),

  /// Mild reduction.
  reduced('reduced'),

  /// Stronger reduction.
  conservative('conservative'),

  /// Maximum reduction (still NEVER stops playback).
  survival('survival');

  final String wireName;
  const LBPowerProfile(this.wireName);

  /// Parse a native `wireName` string back to the enum. Unknown / `null`
  /// conservatively maps to [full] (cool) so a future tier never mis-sheds.
  static LBPowerProfile fromWireName(String? name) {
    for (final v in LBPowerProfile.values) {
      if (v.wireName == name) return v;
    }
    return LBPowerProfile.full;
  }
}

// MARK: - Locale

enum LBLocaleCode {
  zhTW('zh-TW'),
  zhCN('zh-CN'),
  en('en'),
  msMY('ms-MY'),
  idID('id-ID');

  final String code;
  const LBLocaleCode(this.code);

  static LBLocaleCode? fromCode(String code) {
    for (final v in LBLocaleCode.values) {
      if (v.code == code) return v;
    }
    return null;
  }
}

// MARK: - Checkout

class LBCheckoutItem {
  final String productId;
  final int quantity;
  /// Unit price including tax; null = not disclosed.
  final double? price;
  /// ISO 4217 currency code; null = inherit widget setting (iOS only — Android ignores).
  final String? currency;
  /// Android-only fields (ignored on iOS).
  final String? goodsGpn;
  final String? sdkTrackCode;

  const LBCheckoutItem({
    required this.productId,
    required this.quantity,
    this.price,
    this.currency,
    this.goodsGpn,
    this.sdkTrackCode,
  });

  Map<String, Object?> toMap() => {
        'productId': productId,
        'quantity': quantity,
        'price': price,
        'currency': currency,
        'goodsGpn': goodsGpn,
        'sdkTrackCode': sdkTrackCode,
      };
}

// MARK: - Flush

enum LBFlushStatus { completed, partial, timeout, networkUnavailable, noPending }

class LBFlushResult {
  final LBFlushStatus status;
  final int uploadedCount;
  final int remainingCount;
  final int elapsedMs;

  const LBFlushResult({
    required this.status,
    required this.uploadedCount,
    required this.remainingCount,
    required this.elapsedMs,
  });

  factory LBFlushResult.fromMap(Map<Object?, Object?> map) {
    final raw = map['status'] as String? ?? 'completed';
    final status = switch (raw) {
      'completed' => LBFlushStatus.completed,
      'partial' => LBFlushStatus.partial,
      'timeout' => LBFlushStatus.timeout,
      'network_unavailable' => LBFlushStatus.networkUnavailable,
      'no_pending' => LBFlushStatus.noPending,
      _ => LBFlushStatus.completed,
    };
    return LBFlushResult(
      status: status,
      uploadedCount: (map['uploadedCount'] as num?)?.toInt() ?? 0,
      remainingCount: (map['remainingCount'] as num?)?.toInt() ?? 0,
      elapsedMs: (map['elapsedMs'] as num?)?.toInt() ?? 0,
    );
  }
}

// MARK: - Product / Poll / Player state / Errors (unchanged)

/// Player overlay product (`LBChannel.goods[]` / `other_goods[]`).
///
/// product-bridge-data-core: extended from the legacy 7-field projection to
/// the full field set defined by `shared/data-models.md` (23 fields incl.
/// nested [specifications] / [specOptions]), so a host (and the upcoming
/// product-sheet-stack-template) can read variant / spec / stock / restock
/// data. The original 7 fields (`id` / `name` / `priceShow` / `goodsGpn` /
/// `soldOut` / `isHot` / `diversionUrl`) keep their key / type / semantics
/// — this is a purely additive change. Wire keys are camelCase (per design
/// D1), aligned with the existing bridge payload convention.
class LBProduct {
  /// Product ID. Spec mandates String (per component-contracts §schema
  /// risks). API may return Int but Dart-bridge coerces to String for
  /// cross-platform parity. Accepts either Int or String from the
  /// channel for backward compat.
  final String id;
  /// 商品編號 (`goods_no`). API may return Int; coerced to String.
  final String goodsNo;
  final String name;
  /// Numeric sale price. Flutter keeps the existing `double?` bridge
  /// convention (RN uses string per §price 精度; the arbitrary-precision
  /// Decimal migration is a separate change). `priceShow` stays the primary
  /// display source.
  final double? price;
  final String priceShow;
  /// Numeric original price. `null` (or 0 on the wire) means "no original
  /// price" (per §price 精度「original_price=0 與 null 同義」).
  final double? originalPrice;
  /// Formatted original price ("" = no original price).
  final String originalPriceShow;
  /// Stock quantity.
  final int stock;
  /// Main product image URL.
  final String pic;
  /// Additional product image URLs.
  final List<String> photos;
  /// Product brief / description.
  final String brief;
  /// Product introduction text (parallel to, and distinct from, `brief`). Wire key
  /// `description` on `/sdk/video` `goods[]` / `other_goods[]` items
  /// (add-product-description-core-flutter, parity add-product-description-core-ios /
  /// -android / -rn). Tolerant decode (missing/null/type-mismatch → "") already happened
  /// upstream in iOS/Android core; the native plugin bridge ALWAYS supplies this key with
  /// a non-null string. Defaulted (non-nullable `String`, not optional) — unlike RN's TS
  /// `description?: string`, Dart named parameters support a cross-module field default
  /// (`= ''`), so `flutter-reference-ui`'s existing hand-built `LBProduct(...)` literals
  /// stay source-compatible with no nullable-handling burden.
  final String description;
  /// Spec mandates String (JS/Dart Number-precision rationale).
  final String goodsGpn;
  final int soldOut;         // 0/1 — API returns integer, not boolean
  final int isHot;           // 0/1
  final int isOutSoon;       // 0/1
  /// 0 = normal, 2 = anchor is currently narrating this product (live).
  final int narrateStatus;
  // Backend goods conclusion fields (`/sdk/video/goods` mapGoodsItem,
  // goods-conclusion-fields spec; iOS a9d13a7 / Android 1f5c730 / RN 66ad62c).
  // `narrate_status` is back-filled into [narrateStatus] by the NATIVE core, so
  // existing `narrateStatus == 2` consumers keep working with no Dart change.
  /// 能否看到（恆 true：查詢層已濾刪除/封存/獎品）。
  final bool canView;
  /// 能否買（= !sold_out）。
  final bool canBuy;
  /// 是否介紹中（= narrate_status == 2；僅 type=2 有意義）。
  final bool isNarrating;
  /// 是否需顯示標籤（sold_out||narrating||out_soon||hot）。
  final bool needLabel;
  /// 唯一標籤："sold_out"/"narrating"/"out_soon"/"hot"/""（raw passthrough，不解讀語意）。
  final String label;
  final int isAwait;         // 0/1 — current user tracking this product
  final int isAwaitNotice;   // 0/1 — current user set restock notice
  /// Playback narration segment start second (null = no record).
  final int? beginTime;
  /// Playback narration segment end second (null = no record).
  final int? endTime;
  final String diversionUrl;
  /// Spec list (empty = no specs; selecting a spec is required to add cart).
  final List<LBSpec> specifications;
  /// Spec dimension tree (drives the spec-picker UI).
  final List<LBSpecOption> specOptions;
  /// Cross-video product reference (component-contracts §"other_goods 含
  /// video_id 欄位", add-product-video-id-core-flutter, parity
  /// add-product-video-id-core-ios / -android / -rn). Non-null only for
  /// items sourced from `LBChannel.other_goods[]`; MUST be null for items
  /// sourced from `LBChannel.goods[]`. Lets a host jump-to-video for a
  /// recommended product that belongs to a different video.
  final String? videoId;

  const LBProduct({
    required this.id,
    this.goodsNo = '',
    required this.name,
    this.price,
    required this.priceShow,
    this.originalPrice,
    this.originalPriceShow = '',
    this.stock = 0,
    this.pic = '',
    this.photos = const [],
    this.brief = '',
    this.description = '',
    required this.goodsGpn,
    required this.soldOut,
    required this.isHot,
    this.isOutSoon = 0,
    this.narrateStatus = 0,
    // Goods conclusion fields — defaulted so existing call sites (demo seeds /
    // tests / template / reference-ui literals) stay source-compatible.
    this.canView = true,
    this.canBuy = true,
    this.isNarrating = false,
    this.needLabel = false,
    this.label = '',
    this.isAwait = 0,
    this.isAwaitNotice = 0,
    this.beginTime,
    this.endTime,
    required this.diversionUrl,
    this.specifications = const [],
    this.specOptions = const [],
    this.videoId,
  });

  factory LBProduct.fromMap(Map<Object?, Object?> map) => LBProduct(
        id: _asString(map['id']),
        goodsNo: _asString(map['goodsNo']),
        name: (map['name'] as String?) ?? '',
        price: _asDoubleOrNull(map['price']),
        priceShow: (map['priceShow'] as String?) ?? '',
        // original_price == 0 (or absent) → null ("no original price").
        originalPrice: _asOriginalPrice(map['originalPrice']),
        originalPriceShow: (map['originalPriceShow'] as String?) ?? '',
        stock: (map['stock'] as num?)?.toInt() ?? 0,
        pic: (map['pic'] as String?) ?? '',
        photos: _asStringList(map['photos']),
        brief: (map['brief'] as String?) ?? '',
        // add-product-description-core-flutter: camelCase key, same tolerant direct-cast
        // style as `brief` (缺鍵/null → ''; native always sends a non-null string on the
        // ordinary emit path).
        description: (map['description'] as String?) ?? '',
        goodsGpn: _asString(map['goodsGpn']),
        // 0/1 flags: native emit sends Int; Dart `_productToMap` sends bool.
        // Tolerate both (per CLAUDE.md "Bool fields encoded as Int 0/1").
        soldOut: _asIntFlag(map['soldOut']),
        isHot: _asIntFlag(map['isHot']),
        isOutSoon: _asIntFlag(map['isOutSoon']),
        narrateStatus: (map['narrateStatus'] as num?)?.toInt() ?? 0,
        // Goods conclusion fields: bool-tolerant (native emit may send bool or
        // Int 0/1; Dart `_productToMap` round-trip sends bool). Absent (legacy
        // map) → the field default (native always sends them, a9d13a7).
        canView: _asBoolOr(map['canView'], true),
        canBuy: _asBoolOr(map['canBuy'], true),
        isNarrating: _asBoolOr(map['isNarrating'], false),
        needLabel: _asBoolOr(map['needLabel'], false),
        label: (map['label'] as String?) ?? '',
        isAwait: _asIntFlag(map['isAwait']),
        isAwaitNotice: _asIntFlag(map['isAwaitNotice']),
        beginTime: (map['beginTime'] as num?)?.toInt(),
        endTime: (map['endTime'] as num?)?.toInt(),
        diversionUrl: (map['diversionUrl'] as String?) ?? '',
        specifications: _asSpecList(map['specifications']),
        specOptions: _asSpecOptionList(map['specOptions']),
        // add-product-video-id-core-flutter: camelCase key, tolerant cast
        // (缺鍵/null → null，比照既有 optional String 欄位如 `brief` 的直接
        // cast 寫法；native 只在 other_goods[] 項目送出此 key，goods[] 省略).
        videoId: map['videoId'] as String?,
      );
}

/// 商品規格選項 (`LBProduct.specifications[]`). Per `shared/data-models.md`
/// §LBSpec. Distinct from the reduced [LBBridgeSpec] (used for `simulate*`
/// intent) — this is the full spec carried in product payloads.
class LBSpec {
  final String id;
  final String name;
  final String specificationNo;
  final double? price;
  final String priceShow;
  final double? originalPrice;
  final String originalPriceShow;
  final int stock;
  final List<String> photos;

  const LBSpec({
    required this.id,
    this.name = '',
    this.specificationNo = '',
    this.price,
    this.priceShow = '',
    this.originalPrice,
    this.originalPriceShow = '',
    this.stock = 0,
    this.photos = const [],
  });

  factory LBSpec.fromMap(Map<Object?, Object?> map) => LBSpec(
        id: _asString(map['id']),
        name: (map['name'] as String?) ?? '',
        specificationNo: _asString(map['specificationNo']),
        price: _asDoubleOrNull(map['price']),
        priceShow: (map['priceShow'] as String?) ?? '',
        originalPrice: _asOriginalPrice(map['originalPrice']),
        originalPriceShow: (map['originalPriceShow'] as String?) ?? '',
        stock: (map['stock'] as num?)?.toInt() ?? 0,
        photos: _asStringList(map['photos']),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'specificationNo': specificationNo,
        'price': price,
        'priceShow': priceShow,
        'originalPrice': originalPrice,
        'originalPriceShow': originalPriceShow,
        'stock': stock,
        'photos': photos,
      };
}

/// 規格維度 (`LBProduct.spec_options[]`). Per §LBSpecOption. Drives the
/// spec-matrix UI (e.g. `name: "尺寸"`, `child: ["S", "M", "L"]`).
class LBSpecOption {
  final String name;
  final List<String> child;

  const LBSpecOption({this.name = '', this.child = const []});

  factory LBSpecOption.fromMap(Map<Object?, Object?> map) => LBSpecOption(
        name: (map['name'] as String?) ?? '',
        child: _asStringList(map['child']),
      );

  Map<String, Object?> toMap() => {'name': name, 'child': child};
}

/// Coerce a 0/1 flag to Int. Tolerates Int (native emit), bool
/// (Dart `_productToMap` round-trip), and absent (→ 0).
int _asIntFlag(Object? value) {
  if (value is bool) return value ? 1 : 0;
  if (value is num) return value.toInt();
  return 0;
}

/// Coerce a value to `bool`. Tolerates bool (Dart round-trip), Int 0/1 (native
/// emit), and absent → [fallback] (the goods-conclusion-fields default, which
/// the native side always supplies; only a legacy map omits the key).
bool _asBoolOr(Object? value, bool fallback) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  return fallback;
}

/// Coerce a value to `double?` (null/non-num → null).
double? _asDoubleOrNull(Object? value) =>
    value is num ? value.toDouble() : null;

/// `originalPrice`: absent/null → null; 0 → null (no original price).
double? _asOriginalPrice(Object? value) {
  if (value is! num) return null;
  final d = value.toDouble();
  return d == 0 ? null : d;
}

/// Coerce a value to `List<String>` (null/non-list → []).
List<String> _asStringList(Object? value) {
  if (value is! List) return const [];
  return value.map((e) => e?.toString() ?? '').toList();
}

List<LBSpec> _asSpecList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((e) => LBSpec.fromMap(Map<Object?, Object?>.from(e)))
      .toList();
}

List<LBSpecOption> _asSpecOptionList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((e) => LBSpecOption.fromMap(Map<Object?, Object?>.from(e)))
      .toList();
}

/// Award payload carried by `ActivityNotification.showWin` and surfaced
/// through the unified event listener. Per spec §ActivityNotification
/// 元件契約.
class LBAward {
  /// "product" or "discount".
  final String type;
  /// Backend code (discount code / product SKU pointer).
  final String code;
  /// Pre-i18n'd human-readable award name.
  final String name;

  const LBAward({
    required this.type,
    required this.code,
    required this.name,
  });

  factory LBAward.fromMap(Map<Object?, Object?> map) => LBAward(
        type: (map['type'] as String?) ?? '',
        code: (map['code'] as String?) ?? '',
        name: (map['name'] as String?) ?? '',
      );

  Map<String, Object?> toMap() => {'type': type, 'code': code, 'name': name};
}

class LBWinner {
  final String id;
  final int eventId;
  final String title;
  final LBAward award;

  const LBWinner({
    required this.id,
    required this.eventId,
    required this.title,
    required this.award,
  });

  /// Decodes an [LBWinner] from either shape the SDK produces:
  ///  - **nested** `{id, eventId, title, award: {type, code, name}}` — round-trips
  ///    with [toMap] and matches `requestAwardClaim` host input; and
  ///  - **flat WIN_RECEIVED params** `{id, event_id, title, award_type,
  ///    award_name, award_code}` — top-level snake_case, as emitted by the iOS /
  ///    Android native bridges (there is no nested `award` key).
  /// `event_id` (snake) is tolerated as `eventId` too.
  factory LBWinner.fromMap(Map<Object?, Object?> map) => LBWinner(
        id: _asString(map['id']),
        eventId: (map['event_id'] as num?)?.toInt() ??
            (map['eventId'] as num?)?.toInt() ??
            0,
        title: (map['title'] as String?) ?? '',
        award: _awardFromMap(map),
      );

  /// Resolves the winner's [LBAward] from whichever shape [map] carries: a nested
  /// `award: {...}` map ([toMap] round-trip / `requestAwardClaim` host input) or
  /// the flat WIN_RECEIVED params with `award_*` keys at the top level. Missing
  /// award fields fall back to `''` (mirrors [LBAward.fromMap]'s tolerance).
  static LBAward _awardFromMap(Map<Object?, Object?> map) {
    final nested = map['award'];
    if (nested is Map) {
      return LBAward.fromMap(Map<Object?, Object?>.from(nested));
    }
    return LBAward(
      type: (map['award_type'] as String?) ?? '',
      code: (map['award_code'] as String?) ?? '',
      name: (map['award_name'] as String?) ?? '',
    );
  }

  Map<String, Object?> toMap() =>
      {'id': id, 'eventId': eventId, 'title': title, 'award': award.toMap()};
}

/// Active live event (直播抽獎「進行中活動」) surfaced through the notification event
/// `ACTIVE_EVENT_STARTED` (`active-event-host-facing-exposure-flutter-core`,
/// parity with iOS `LBActiveEvent` / Android `LBActiveEvent` / RN
/// `LBActiveEventStartedParams`). Host-facing convenience model so a UI layer can
/// self-render an activity countdown, award preview, or「加入活動」entry copy without
/// hand-parsing the raw `LBSdkEvent.params` map (mirrors [LBWinner]).
///
/// Built from the event's **flat** params (`{id, title, keyword?, duration,
/// surplus, award}`) — NOT the nested `LBActiveEvent` DTO shape. Notes:
///  - [keyword] is the「加入活動」join keyword (chat event-begin 訊息中用戶可見的口令,
///    non-secret); `null` when the backend omits the key (無可參加 keyword) — the
///    factory keeps it `null` rather than substituting `''`.
///  - [surplus] is a snapshot of the remaining seconds at dispatch time; the host
///    推算即時倒數 with [duration] + wall-clock (the SDK 不逐秒推送).
///  - [award] reuses the existing [LBAward] (`{type, code, name}`); `[]` when the
///    backend omits `award`.
///  - It deliberately does **not** carry `stayTime` (the turnkey eventstay dwell
///    threshold) — native excludes it from the `ACTIVE_EVENT_STARTED` params as an
///    internal gate, not host UI info.
class LBActiveEvent {
  /// `live_event_id` of this active event.
  final int id;

  /// Event title (e.g. "週年慶抽獎").
  final String title;

  /// 「加入活動」join keyword; `null` when the backend omits the key (無可參加 keyword).
  final String? keyword;

  /// Total activity duration in seconds (`0` when absent).
  final int duration;

  /// Remaining seconds at the moment this snapshot was dispatched (`0` when
  /// absent). A snapshot only — host推算即時倒數 with [duration] + wall-clock.
  final int surplus;

  /// Award list (each a public [LBAward] `{type, code, name}`; `code` only present
  /// on discount awards). `[]` when the backend omits `award`.
  final List<LBAward> award;

  const LBActiveEvent({
    required this.id,
    this.title = '',
    this.keyword,
    this.duration = 0,
    this.surplus = 0,
    this.award = const [],
  });

  /// Decodes an [LBActiveEvent] from the **flat** `ACTIVE_EVENT_STARTED` params
  /// (the shape native `notifyActiveEvents` emits). Tolerant (parity with
  /// [LBWinner.fromMap] / [LBProduct.fromMap]): `id` / `duration` / `surplus`
  /// numeric-coerce to int (absent → `0`); `title` → "" when absent; `keyword`
  /// reads `map['keyword'] as String?` so an omitted key stays `null` (NOT `''`);
  /// `award` decodes each entry via [LBAward.fromMap], falling back to `[]`.
  factory LBActiveEvent.fromMap(Map<Object?, Object?> map) => LBActiveEvent(
        id: (map['id'] as num?)?.toInt() ?? 0,
        title: (map['title'] as String?) ?? '',
        keyword: map['keyword'] as String?,
        duration: (map['duration'] as num?)?.toInt() ?? 0,
        surplus: (map['surplus'] as num?)?.toInt() ?? 0,
        award: _asAwardList(map['award']),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'keyword': keyword,
        'duration': duration,
        'surplus': surplus,
        'award': award.map((a) => a.toMap()).toList(),
      };
}

/// Decode an `award` array into `List<LBAward>` (null/non-list → []). Mirrors
/// [_asSpecList]; tolerates non-Map entries and defers per-field tolerance to
/// [LBAward.fromMap].
List<LBAward> _asAwardList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((e) => LBAward.fromMap(Map<Object?, Object?>.from(e)))
      .toList();
}

/// Host-supplied contact info for [LivebuyPlayerController.requestAwardClaim].
/// `email` is required (trimmed by host) for both product and discount awards;
/// it may be omitted only when a prior interceptor already supplied it.
class LBAwardClaimInput {
  final String email;
  const LBAwardClaimInput({required this.email});
  Map<String, Object?> toMap() => {'email': email};
}

/// Result status of an award claim (`POST /sdk/video/claim`).
///
/// code-as-truth: the backend only returns `claimed` (inner code 200) or
/// `failed` (inner code 500); any other wire string (e.g. `unknown_<code>`)
/// is forward-compatibly mapped to [unknown]. Mirrors the [LBFlushStatus]
/// enum style.
///
/// This enum only covers the `status` key. The `AWARD_CLAIM_RESULT`
/// notification carries **nine further keys** with the full award / event
/// information (award name, image, stock, discount code + expiry, winner
/// ticket id, event id / title) so the host can act on the prize without
/// re-calling the API. See the params contract table on
/// [LivebuyPlayerController.requestAwardClaim] for the authoritative field
/// list, the omission rule (nil / empty → key dropped entirely) and the
/// failure-path whitelist.
///
/// **Side-effect boundary** (narrowed by `award-product-auto-cart`): the SDK
/// MUST NOT navigate and MUST NOT render any UI off the back of this event, and
/// a **discount**-type prize is never added to a cart. A **product**-type prize
/// is the one explicit exception — the core adds it to the cart automatically
/// and dispatches a second `CART_ADD_REQUEST` carrying
/// [LBCartAddRequest.awardWinnerId]. So do **not** re-add a product prize to the
/// backend cart yourself, or it lands twice. Everything else stays the host's
/// call.
enum LBAwardClaimStatus {
  claimed,
  failed,
  unknown;

  static LBAwardClaimStatus fromWire(String s) {
    switch (s) {
      case 'claimed':
        return LBAwardClaimStatus.claimed;
      case 'failed':
        return LBAwardClaimStatus.failed;
      default:
        return LBAwardClaimStatus.unknown; // 'unknown_<code>' 等前向相容
    }
  }
}

/// Event metadata on push messages (per spec §LBPushMsg event 欄位).
class LBPushMsgEventMeta {
  final int? eid;
  final String? ek;
  /// "begin" or "end".
  final String? at;
  final String? ct;
  final String? p;

  const LBPushMsgEventMeta({this.eid, this.ek, this.at, this.ct, this.p});

  factory LBPushMsgEventMeta.fromMap(Map<Object?, Object?> map) =>
      LBPushMsgEventMeta(
        eid: (map['eid'] as num?)?.toInt(),
        ek: map['ek'] as String?,
        at: map['at'] as String?,
        ct: map['ct'] as String?,
        p: map['p']?.toString(),
      );

  bool get isEventBegin {
    final id = eid;
    if (id == null || id <= 0) return false;
    return (ek != null && ek!.isNotEmpty) || at == 'begin';
  }

  bool get isEventEnd {
    final id = eid;
    if (id == null || id <= 0) return false;
    return (ek == null || ek!.isEmpty) && at != 'begin';
  }
}

/// Coerce a value to String (passes through if already String;
/// stringifies primitives; returns "" for nulls). Used for `id` / `goodsGpn`
/// fields that the API may return as either Int or String.
String _asString(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  return value.toString();
}

class LBPollResponse {
  /// Poll cursor. API returns a float (e.g. 11988703.261723042), not a string.
  /// poll-comments-decode-robustness-core §8.1: the native side tolerates an
  /// empty cursor (`last: []` / null / number) and normalises it to a `0`
  /// sentinel meaning "no new cursor — do not regress". `0` indicates the
  /// empty-cursor case.
  final double last;
  final int? liveEnd;
  const LBPollResponse({required this.last, this.liveEnd});

  factory LBPollResponse.fromMap(Map<Object?, Object?> map) => LBPollResponse(
        last: _parseCursor(map['last']),
        liveEnd: (map['liveEnd'] as num?)?.toInt(),
      );

  /// Normalise an empty cursor (JSON array `[]`, null, or a number) to `0`.
  /// A bare `(value as num).toDouble()` would crash on an empty array or null,
  /// so coerce defensively and fall back to the `0` sentinel.
  static double _parseCursor(Object? value) {
    if (value is num) return value.toDouble();
    // Empty array / null / unexpected shape → "no new cursor" sentinel.
    return 0;
  }
}

enum LBPlayerState {
  loading, buffering, playing, paused, ended, error,
  // decouple-ui-from-logic sub-states (per spec §Player States).
  awaitingLive,
  startScreenPlaying,
  endScreenShown,
}

LBPlayerState lbPlayerStateFromString(String s) =>
    LBPlayerState.values.firstWhere((e) => e.name == s,
        orElse: () => LBPlayerState.error);

sealed class LBError {
  const LBError();
}

class LBErrorRestricted extends LBError {
  const LBErrorRestricted();
}

class LBErrorVideoNotFound extends LBError {
  const LBErrorVideoNotFound();
}

class LBErrorInvalidSignature extends LBError {
  const LBErrorInvalidSignature();
}

class LBErrorChatRateLimited extends LBError {
  const LBErrorChatRateLimited();
}

// commentsub-checkname-contract-core §8.1: chat business errors. The native
// bridge emits these camelCase `type` strings (consistent with the existing
// Flutter/RN convention, e.g. videoNotFound), mapped from core LBError
// guestNameTaken (403) / chatRequiresLogin (401) / notLive (404).

/// Guest display name already taken (`POST /sdk/video/checkname` 403).
class LBErrorGuestNameTaken extends LBError {
  const LBErrorGuestNameTaken();
}

/// Chat requires a logged-in member (`POST /sdk/video/commentsub` 401).
class LBErrorChatRequiresLogin extends LBError {
  const LBErrorChatRequiresLogin();
}

/// Live broadcast is not currently live (404).
class LBErrorNotLive extends LBError {
  const LBErrorNotLive();
}

/// Backend inner code 426 — this SDK version is no longer accepted.
/// Per api-version-resilience §Deprecation 強制升級訊號.
class LBErrorSdkVersionUnsupported extends LBError {
  const LBErrorSdkVersionUnsupported();
}

class LBErrorNetwork extends LBError {
  final String message;
  const LBErrorNetwork(this.message);
}

class LBErrorServer extends LBError {
  final int code;
  final String message;
  const LBErrorServer(this.code, this.message);
}

/// Add-to-cart 30s 防重複建單 dedupe 命中（cart-add-tier2-unify）：同
/// `(goodsId, videoId)` 30 秒內已加購過，`addToCart` MUST NOT 重打 addcart。host /
/// drop-in template 應視為「已加入購物車」而非失敗。Mirrors native
/// `LBError.cartAddDeduplicated`.
class LBErrorCartAddDeduplicated extends LBError {
  const LBErrorCartAddDeduplicated();
}

LBError lbErrorFromMap(Map<Object?, Object?> map) {
  switch (map['type'] as String) {
    case 'restricted':       return const LBErrorRestricted();
    case 'videoNotFound':    return const LBErrorVideoNotFound();
    case 'invalidSignature': return const LBErrorInvalidSignature();
    case 'chatRateLimited':  return const LBErrorChatRateLimited();
    case 'guestNameTaken':    return const LBErrorGuestNameTaken();
    case 'chatRequiresLogin': return const LBErrorChatRequiresLogin();
    case 'notLive':           return const LBErrorNotLive();
    case 'sdk_version_unsupported':
      return const LBErrorSdkVersionUnsupported();
    case 'cartAddDeduplicated':
      return const LBErrorCartAddDeduplicated();
    case 'networkError':     return LBErrorNetwork(map['message'] as String);
    case 'serverError':
      return LBErrorServer(map['code'] as int, map['message'] as String);
    default:
      return LBErrorNetwork('Unknown error');
  }
}

// MARK: - Video item (fetchLatestLive)

class LBVideoItem {
  final String id;
  final int type;
  final String title;
  final String? sessionName;
  final String cover;
  final String preview;
  final int duration;
  final String publishAt;
  final int watchNum;
  final int pvNum;
  final int liveStatus;
  final int pin;
  final int showPvNum;
  final String liveurl;
  final String playbackurl;
  final String previewTime;
  final bool showStock;
  /// 精選商品（video-linked-goods-core-flutter）；影片無連結商品時為 `null`. Bridge-relayed from
  /// native `LBVideoItem.goods` (iOS `LBFeaturedGood?` / Android nullable `LBFeaturedGood`) — see
  /// [LBFeaturedGood.fromMapOrNull] for the tolerant parsing rule.
  final LBFeaturedGood? goods;

  const LBVideoItem({
    required this.id,
    required this.type,
    required this.title,
    this.sessionName,
    required this.cover,
    required this.preview,
    required this.duration,
    required this.publishAt,
    required this.watchNum,
    required this.pvNum,
    required this.liveStatus,
    required this.pin,
    required this.showPvNum,
    required this.liveurl,
    required this.playbackurl,
    required this.previewTime,
    required this.showStock,
    this.goods,
  });

  factory LBVideoItem.fromMap(Map<Object?, Object?> map) => LBVideoItem(
        id: _asString(map['id']),
        type: (map['type'] as num?)?.toInt() ?? 0,
        title: (map['title'] as String?) ?? '',
        sessionName: map['sessionName'] as String?,
        cover: (map['cover'] as String?) ?? '',
        preview: (map['preview'] as String?) ?? '',
        duration: (map['duration'] as num?)?.toInt() ?? 0,
        publishAt: (map['publishAt'] as String?) ?? '',
        watchNum: (map['watchNum'] as num?)?.toInt() ?? 0,
        pvNum: (map['pvNum'] as num?)?.toInt() ?? 0,
        liveStatus: (map['liveStatus'] as num?)?.toInt() ?? 0,
        pin: (map['pin'] as num?)?.toInt() ?? 0,
        showPvNum: (map['showPvNum'] as num?)?.toInt() ?? 0,
        liveurl: (map['liveurl'] as String?) ?? '',
        playbackurl: (map['playbackurl'] as String?) ?? '',
        previewTime: (map['previewTime'] as String?) ?? '',
        showStock: (map['showStock'] as bool?) ?? false,
        goods: LBFeaturedGood.fromMapOrNull(map['goods']),
      );
}

/// 影片連結精選商品（video-linked-goods-core-flutter）。Bridge-relayed from native
/// `LBFeaturedGood` (iOS `Models/LBModels.swift` / Android `models/LBModels.kt`) — same seven
/// fields, same types, cross-platform aligned.
class LBFeaturedGood {
  final String name;
  final String pic;
  final String price;
  final String originalPrice;
  final int soldOut;
  final int stock;
  final int status;

  const LBFeaturedGood({
    required this.name,
    required this.pic,
    required this.price,
    required this.originalPrice,
    required this.soldOut,
    required this.stock,
    required this.status,
  });

  /// Tolerant factory: [value] is the raw `map['goods']` from a bridge-relayed `LBVideoItem`
  /// map. Returns `null` when [value] is not a usable `Map` shape (missing key, JSON `null`, or
  /// the wrong type) rather than throwing — the nested `goods` map is optional and MUST NOT fail
  /// the enclosing `LBVideoItem.fromMap` (CLAUDE.md "JSON decoder fallback" spirit, applied at
  /// the bridge-map layer since Flutter never decodes the raw wire JSON itself). When [value] IS
  /// a `Map`, missing or wrong-typed sub-fields degrade to safe per-field defaults rather than
  /// nulling the whole object.
  static LBFeaturedGood? fromMapOrNull(Object? value) {
    if (value is! Map) return null;
    // `is`-checks (not `as X?` casts) on purpose: `someWrongTypeValue as String?` THROWS for a
    // non-null value of the wrong type (it only tolerates `null`, not type mismatches), which
    // would defeat the "never throw" contract for a single malformed sub-field.
    String str(Object? key) => value[key] is String ? value[key] as String : '';
    int intOr(Object? key, int fallback) =>
        value[key] is num ? (value[key] as num).toInt() : fallback;
    return LBFeaturedGood(
      name: str('name'),
      pic: str('pic'),
      price: str('price'),
      originalPrice: str('originalPrice'),
      soldOut: intOr('soldOut', 0),
      stock: intOr('stock', 0),
      status: intOr('status', 1),
    );
  }
}

// MARK: - Player channel info (upcoming-intro-core-flutter — channel 轉發 bridge)

/// A LIGHTWEIGHT projection of the player's loaded `LBChannel`, forwarded from the
/// native player view to the Dart host via the `onChannelChange` callback
/// (upcoming-intro-core-flutter; extended by
/// player-channel-chrome-bridge-core-flutter, then product-list-bridge-core-flutter).
/// It carries ONLY the fields the player-side upcoming (直播預告) / live chrome /
/// product-bag needs — it is NOT the full core `LBChannel` (no nav / spec). The
/// host feeds these into the `flutter-ui` template's upcoming view-model (后续
/// `upcoming-intro-template-flutter`):
///
///   • [publishAt]   — scheduled start (UTC+8 `"yyyy-MM-dd HH:mm:ss"`). Feeds
///                     `DefaultUpcomingState.scheduledStartAt`.
///   • [cover]       — video cover URL. The upcoming countdown background.
///   • [start]       — opening MP4 (intro) URL (`channel.start`). Non-empty drives
///                     the StartScreen splash + the upcoming `introPlaying` gate.
///   • [liveStatus]  — `0` = upcoming (直播預告), `1` = live, other = VOD. `-1` =
///                     unknown (field absent) — NOT upcoming.
///   • [title]       — channel title (convenience; the header chrome already has its
///                     own host-fed source, so this is informational).
///   • [serviceLink] — shop service link (`channel.shop.service_link`).
///   • [shopName]    — shop display name (`channel.shop.name`).
///   • [shopLogo]    — shop logo URL (`channel.shop.logo`).
///   • [shareUrl]    — channel share URL (`channel.share_url`).
///   • [type]        — channel type (`channel.type`): `1` = VOD, `2` = live,
///                     `3` = finished-live replay. `-1` = unknown (absent on
///                     the wire). Feeds `isFinishedLiveReplay(type, liveStatus)`
///                     downstream (`channel-type-bridge-core-flutter`).
///   • [goods]       — the channel's primary sellable-product list
///                     (`channel.goods`), unfiltered, channel-load-time snapshot
///                     (`product-list-bridge-core-flutter`).
///   • [shopIntro]   — shop introduction text (`channel.shop.intro`). May
///                     legitimately be "" when a merchant left the store intro
///                     blank (`channel-shop-intro-bridge-core-flutter`).
///   • [guestComment] — raw `channel.guest_comment` permission flag (`0` =
///                     restrict comment submission to logged-in members,
///                     non-`0` = guests allowed). Fail-open default `1` when
///                     absent, distinct from [type]/[liveStatus]'s `-1`-unknown
///                     convention (`guest-comment-channel-bridge-core-flutter`).
///                     Raw passthrough only — does NOT itself compute
///                     `chatEnabled`; that derivation stays a
///                     reference-ui/template-layer concern.
///   • [isFlashSale] — raw `channel.isFlashSale` passthrough (a TOP-LEVEL
///                     `LBChannel` field, NOT nested under `shop`). `true` iff
///                     the upstream `sale_type == 2`; always present on the
///                     wire, independent of [type] / [liveStatus]. Default
///                     `false` when absent (channel-flash-sale-flag-core-flutter).
///   • [notice]      — raw `channel.notice` free-text announcement passthrough
///                     (a TOP-LEVEL `LBChannel` field, NOT nested under `shop`).
///                     "" when absent/no active announcement. Populated at
///                     channel-load time, independent of playback state
///                     (channel-notice-bridge-core-flutter).
///   • [sysNotice]   — raw `channel.sysNotice` system-notice passthrough, same
///                     top-level shape and default-empty convention as
///                     [notice] (channel-notice-bridge-core-flutter).
///
/// `upcoming.active` itself does NOT need this projection — it is derivable from the
/// already-bridged player state (`"awaitingLive"`); this projection supplies the
/// REMAINING upcoming inputs (`scheduledStartAt` / `cover` / `introPlaying` /
/// `hasStart`) that the player state alone cannot carry, plus (as of
/// player-channel-chrome-bridge-core-flutter) the shop/share chrome fields a
/// host's upcoming/live UI needs.
class LBPlayerChannelInfo {
  /// Scheduled start (`channel.publish_at`, UTC+8 `"yyyy-MM-dd HH:mm:ss"`). "" when
  /// absent. The host passes this verbatim to the template (it MUST NOT parse here).
  final String publishAt;

  /// Video cover URL (`channel.cover`). "" when absent.
  final String cover;

  /// Opening MP4 (intro) URL (`channel.start`). "" when absent (no intro).
  final String start;

  /// Live status (`channel.live_status`): `0` = upcoming, `1` = live, other = VOD.
  /// `-1` = unknown (the field was absent on the wire) — treated as NOT upcoming.
  final int liveStatus;

  /// Channel title (`channel.title`). "" when absent. Informational.
  final String title;

  /// player-channel-chrome-bridge-core-flutter: shop service link
  /// (`channel.shop.service_link`). "" when absent.
  final String serviceLink;

  /// player-channel-chrome-bridge-core-flutter: shop display name
  /// (`channel.shop.name`). "" when absent.
  final String shopName;

  /// player-channel-chrome-bridge-core-flutter: shop logo URL
  /// (`channel.shop.logo`). "" when absent.
  final String shopLogo;

  /// player-channel-chrome-bridge-core-flutter: channel share URL
  /// (`channel.share_url`). "" when absent.
  final String shareUrl;

  /// channel-type-bridge-core-flutter: channel type (`channel.type`): `1` =
  /// VOD, `2` = live, `3` = finished-live replay. `-1` = unknown (the field
  /// was absent on the wire). Feeds `isFinishedLiveReplay(type, liveStatus)`
  /// downstream — this projection only carries the raw value, it does not
  /// evaluate the function itself.
  final int type;

  /// product-list-bridge-core-flutter: the channel's primary sellable-product
  /// list (`channel.goods`), UNFILTERED, as it stood at the moment this
  /// projection was built. Distinct from [otherGoods] (`channel.other_goods`
  /// — cross-video recommendations, a DIFFERENT list). This is a
  /// channel-LOAD-time snapshot only: it does NOT track the 5s
  /// `/sdk/video/goods` poll's ongoing updates (that refresh path has no
  /// Flutter bridge as of this change). Feeds a host's `handleProducts` /
  /// product-bag UI. Default `const []`.
  final List<LBProduct> goods;

  /// rb-flutter-other-goods-channel-bridge-core: cross-video recommended
  /// products (`channel.other_goods`), UNFILTERED, as they stood at the
  /// moment this projection was built. Distinct from [goods] (the currently
  /// loaded channel's OWN sellable products) — `other_goods[]` items belong
  /// to OTHER videos. Previously NOT carried by this projection at all (see
  /// [goods]'s own doc comment history); now bridged so a host's product-
  /// detail sheet can populate a "more products" / recommendations section
  /// (`DefaultPlayerTemplate.setOtherGoods`). This is a channel-LOAD-time
  /// snapshot only: it does NOT track any subsequent poll's updates. Default
  /// `const []`.
  final List<LBProduct> otherGoods;

  /// channel-shop-intro-bridge-core-flutter: shop introduction text
  /// (`channel.shop.intro`). "" when absent. May legitimately be "" when a
  /// merchant left the store intro blank on the backend — a host MUST NOT
  /// treat an empty value as evidence the bridge is broken.
  final String shopIntro;

  /// guest-comment-channel-bridge-core-flutter: raw `channel.guest_comment`
  /// permission flag (`0` = restrict comment submission to logged-in
  /// members, non-`0` = guests allowed). Default `1` (fail-open) when
  /// absent — a DIFFERENT convention from [type]/[liveStatus]'s `-1`-unknown
  /// sentinel, because this exact field already has an SDK-wide-established
  /// fail-open default of `1` on both native core SDKs (a missing/dropped
  /// `guest_comment` was once a live regression that silently disabled
  /// guest chat entirely). This is a raw passthrough of the wire-level
  /// flag only — it does NOT itself compute `chatEnabled`
  /// (`live_status==1 && !(isGuest && guest_comment==0)`); that derivation
  /// remains a reference-ui/template-layer concern.
  final int guestComment;

  /// channel-diversion-bridge-core-flutter: raw `channel.diversion` passthrough (`0` = in-app
  /// product panel, `1` = purchase-page URL redirect). Default `0` when absent, matching both
  /// native SDKs' own decode default for this field. Feeds
  /// `DefaultPlayerTemplate.handleProductTap(product:diversion:)` — a reference-ui/template-layer
  /// concern; this projection only carries the raw value.
  final int diversion;

  /// channel-flash-sale-flag-core-flutter: raw `channel.isFlashSale` passthrough — a
  /// TOP-LEVEL `LBChannel` field (unlike [shopIntro] / [serviceLink] / [shopName] /
  /// [shopLogo], which all nest under `channel.shop`). `true` iff the upstream
  /// `sale_type == 2`; always present on the wire, independent of [type] /
  /// [liveStatus]. Default `false` when absent. Raw passthrough only — this
  /// projection does not itself decide any flash-sale UI treatment; that stays a
  /// reference-ui/template-layer concern.
  final bool isFlashSale;

  /// channel-notice-bridge-core-flutter: raw `channel.notice` free-text
  /// announcement passthrough — a TOP-LEVEL `LBChannel` field (same shape as
  /// [isFlashSale], unlike [shopIntro] / [serviceLink] / [shopName] / [shopLogo],
  /// which all nest under `channel.shop`). "" when absent — may legitimately be ""
  /// when no announcement is currently active. Populated the moment the channel
  /// loads (independent of playback state), UNLIKE the pre-existing
  /// `POLL_RECEIVED`-relayed `notice` (which only reaches a Flutter host once the
  /// player reaches `.playing` and the first 5s poll round completes) — this
  /// projection gives a host an earlier signal. Raw passthrough only; deciding
  /// any announcement-banner UI treatment stays a reference-ui/template-layer
  /// concern.
  final String notice;

  /// channel-notice-bridge-core-flutter: raw `channel.sysNotice` system-notice
  /// passthrough — a TOP-LEVEL `LBChannel` field, same shape and default-empty
  /// convention as [notice] (a distinct, independently-mutable field on the
  /// backend). "" when absent.
  final String sysNotice;

  const LBPlayerChannelInfo({
    this.publishAt = '',
    this.cover = '',
    this.start = '',
    this.liveStatus = -1,
    this.title = '',
    this.serviceLink = '',
    this.shopName = '',
    this.shopLogo = '',
    this.shareUrl = '',
    this.type = -1,
    this.goods = const [],
    this.otherGoods = const [],
    this.shopIntro = '',
    this.guestComment = 1,
    this.diversion = 0,
    this.isFlashSale = false,
    this.notice = '',
    this.sysNotice = '',
  });

  /// Decode from the native `{"event":"channelChange", …}` EventChannel payload.
  /// Tolerant (parity with `LBProduct` / `LBVideoItem` `fromMap`): missing / null
  /// string fields → ""; `liveStatus` missing → `-1` (unknown); an Int or a
  /// stringified Int is tolerated.
  factory LBPlayerChannelInfo.fromMap(Map<Object?, Object?> map) =>
      LBPlayerChannelInfo(
        publishAt: (map['publishAt'] as String?) ?? '',
        cover: (map['cover'] as String?) ?? '',
        start: (map['start'] as String?) ?? '',
        liveStatus: _asLiveStatus(map['liveStatus']),
        title: (map['title'] as String?) ?? '',
        serviceLink: (map['serviceLink'] as String?) ?? '',
        shopName: (map['shopName'] as String?) ?? '',
        shopLogo: (map['shopLogo'] as String?) ?? '',
        shareUrl: (map['shareUrl'] as String?) ?? '',
        // Reuses `_asLiveStatus`'s tri-state coercion (num → toInt, stringified
        // Int → parse, else → -1): mechanically identical to `type`'s own
        // decode needs, but an independent field — NOT a semantic link to
        // `liveStatus` itself (channel-type-bridge-core-flutter).
        type: _asLiveStatus(map['type']),
        // product-list-bridge-core-flutter: reuses the existing `_asProductList`
        // helper (also used by `LBPlaybackProgress.fromMap`) — missing/null/
        // non-List → `[]`; non-Map entries skipped, not thrown on.
        goods: _asProductList(map['goods']),
        // rb-flutter-other-goods-channel-bridge-core: reuses the SAME
        // `_asProductList` helper `goods` uses above — identical tolerant-decode
        // rules (missing/null/non-List → `[]`; non-Map entries skipped).
        otherGoods: _asProductList(map['otherGoods']),
        shopIntro: (map['shopIntro'] as String?) ?? '',
        // guest-comment-channel-bridge-core-flutter: a NEW, dedicated helper —
        // NOT `_asLiveStatus` — because that helper's `-1` fallback would be
        // the wrong polarity for this field's SDK-wide-established "缺欄時
        // fail-open" default (`1`).
        guestComment: _asGuestComment(map['guestComment']),
        diversion: _asDiversion(map['diversion']),
        // channel-flash-sale-flag-core-flutter: reuses the existing `_asBoolOr`
        // helper (NOT a simple `as bool? ?? false` cast, which THROWS for a
        // non-null value of the wrong type) — tolerates bool (native emit) or
        // num 0/1 (defensive, per the SDK-wide "bool fields tolerate Int 0/1"
        // convention); missing/null/any other type → false.
        isFlashSale: _asBoolOr(map['isFlashSale'], false),
        // channel-notice-bridge-core-flutter: mirrors the existing `shopIntro`
        // tolerant cast exactly (missing/null/non-string → '').
        notice: (map['notice'] as String?) ?? '',
        sysNotice: (map['sysNotice'] as String?) ?? '',
      );
}

/// Coerce `diversion` to Int. Absent / unparseable → `0` (in-app product panel — the more
/// common wire value, and both native SDKs' own decode default for this field). Tolerates a
/// num (native emit) OR a stringified Int (defensive). A dedicated helper (not
/// `_asLiveStatus`, whose `-1` fallback would be the wrong polarity here — `0` IS this
/// field's own valid value, not an "unknown" sentinel).
int _asDiversion(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

/// Coerce `liveStatus` to Int. Absent / unparseable → `-1` (unknown). Tolerates a
/// num (native emit) OR a stringified Int (defensive).
int _asLiveStatus(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? -1;
  return -1;
}

/// Coerce `guestComment` to Int. Absent / unparseable → `1` (fail-open —
/// guests allowed). Tolerates a num (native emit) OR a stringified Int
/// (defensive). Deliberately a SEPARATE helper from [_asLiveStatus]: that
/// helper's `-1` fallback means "unknown" for fields (`liveStatus`/`type`)
/// with no pre-existing safe default, whereas `guest_comment` already has an
/// SDK-wide-established fail-open default of `1` — reusing `_asLiveStatus`
/// here would resurface the exact "missing guest_comment silently disables
/// guest chat" regression class this field's `1` default exists to prevent
/// (guest-comment-channel-bridge-core-flutter).
int _asGuestComment(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 1;
  return 1;
}

// MARK: - Player moment fields (player-moment-fields-bridge-core-flutter)

/// Bridge-relayed projection of the native `LBNavItem` struct (iOS
/// `Models/LBModels.swift` / Android `models/LBModels.kt`). Field-parity with
/// the native type — this type previously did not exist in the Flutter core
/// package (see design.md D5). Carried as [LBPlayerMomentInfo.nextItem].
class LBNavItem {
  /// Video ID. "" when absent.
  final String id;

  /// Video cover URL. "" when absent.
  final String cover;

  /// Video title. `null` when absent (native: "absent in prev[], present in
  /// next[]" — this projection only ever carries `next[]`'s item, so in
  /// practice this is populated, but the type stays optional to match the
  /// native struct rather than force-unwrapping — design.md D6).
  final String? title;

  /// Raw second count (NOT a formatted string — contrast [LBHotItem.duration],
  /// an intentional native type asymmetry). Default `0`.
  final int duration;

  /// Shop display name. "" when absent.
  final String shopName;

  /// Short preview-loop URL. "" when absent.
  final String preview;

  const LBNavItem({
    this.id = '',
    this.cover = '',
    this.title,
    this.duration = 0,
    this.shopName = '',
    this.preview = '',
  });

  /// Tolerant factory mirroring [LBFeaturedGood.fromMapOrNull]'s convention:
  /// `is`-checks (not `as X?` casts) per field so a wrong-typed field degrades
  /// to its default rather than throwing; a non-`Map` [value] (missing key,
  /// JSON `null`, or the wrong type) degrades to `null` rather than failing
  /// the enclosing decode.
  static LBNavItem? fromMapOrNull(Object? value) {
    if (value is! Map) return null;
    String str(Object? key) => value[key] is String ? value[key] as String : '';
    return LBNavItem(
      id: str('id'),
      cover: str('cover'),
      title: value['title'] is String ? value['title'] as String : null,
      duration: value['duration'] is num ? (value['duration'] as num).toInt() : 0,
      shopName: str('shopName'),
      preview: str('preview'),
    );
  }
}

/// Bridge-relayed projection of the native `LBHotItem` struct (iOS
/// `Models/LBModels.swift` / Android `models/LBModels.kt`). Field-parity with
/// the native type — this type previously did not exist in the Flutter core
/// package (see design.md D5). Carried as [LBPlayerMomentInfo.hotItems].
class LBHotItem {
  /// Video ID. "" when absent.
  final String id;

  /// Video cover URL. "" when absent.
  final String cover;

  /// Video title. "" when absent.
  final String title;

  /// Pre-formatted display string, e.g. `"38:36"` — NOT a second count
  /// (contrast [LBNavItem.duration], an intentional native type asymmetry —
  /// no seconds parsing happens here, design.md D6). Default `''`.
  final String duration;

  /// Short preview-loop URL. "" when absent.
  final String preview;

  const LBHotItem({
    this.id = '',
    this.cover = '',
    this.title = '',
    this.duration = '',
    this.preview = '',
  });

  /// Tolerant per-entry factory, same `is`-check-per-field convention as
  /// [LBNavItem.fromMapOrNull]. [map] is assumed to already be a `Map` (list
  /// coercion / non-Map-entry skipping happens in [_asHotItemList]).
  factory LBHotItem.fromMap(Map<Object?, Object?> map) {
    String str(Object? key) => map[key] is String ? map[key] as String : '';
    return LBHotItem(
      id: str('id'),
      cover: str('cover'),
      title: str('title'),
      duration: str('duration'),
      preview: str('preview'),
    );
  }
}

/// Coerce a raw `hotItems` wire value to `List<LBHotItem>`. Mirrors
/// `_asProductList`'s convention: missing/null/non-`List` → `[]`; non-`Map`
/// entries are skipped (not thrown on) rather than failing the whole decode.
List<LBHotItem> _asHotItemList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((e) => LBHotItem.fromMap(Map<Object?, Object?>.from(e)))
      .toList();
}

/// Deliberately narrow 6-field subset of the native `LBPlayerMomentState`
/// aggregate (18 fields total — see design.md D2's field-by-field table for
/// why only these 6 are bridged), forwarded from the native player view to
/// the Dart host via the `onMomentStateChange` callback
/// (`player-moment-fields-bridge-core-flutter`). NOT a full bridge of that
/// aggregate — the other 12 fields each already have an established,
/// independent Flutter derivation path (player-state string /
/// `LBPlayerChannelInfo` / `LBPlaybackProgress.vodActiveProducts` /
/// `subtitleChange` / config-driven visibility).
///
///   • [viewerCount]              — live viewer count. Default `0`.
///   • [isSubscribed]             — live subscribe-state mirror (flips on
///                                  subscribe success). Default `false`.
///   • [autoNextCountdownActive]  — whether the end-screen auto-next
///                                  countdown is currently running. Default
///                                  `false`.
///   • [autoNextRemainingSeconds] — seconds remaining in that countdown.
///                                  Re-emitted every tick while active.
///                                  Default `0`.
///   • [nextItem]                 — the end-screen "up next" item
///                                  ([LBNavItem]). `null` when absent.
///   • [hotItems]                 — the end-screen "hot videos" list
///                                  ([LBHotItem]). Default `const []`.
class LBPlayerMomentInfo {
  final int viewerCount;
  final bool isSubscribed;
  final bool autoNextCountdownActive;
  final int autoNextRemainingSeconds;
  final LBNavItem? nextItem;
  final List<LBHotItem> hotItems;

  // flutter-android-moment-products-bridge-core / flutter-ios-moment-products-bridge-core —
  // the currently-loaded channel's FULL product list, refreshed on every native
  // moment-state poll round (unlike `LBPlayerChannelInfo.goods`, a
  // channel-LOAD-TIME-ONLY snapshot). Bridged on Android (see
  // `MomentFieldsBridge.Snapshot.products` doc comment) and iOS (see
  // `LivebuyPlugin.swift`'s `MomentFieldsSnapshot.products` doc comment);
  // default `[]` on RN / older native binaries that don't send this key.
  final List<LBProduct> products;

  /// The single representative `narrate_status == 2` product, or `null` when
  /// no product is currently being narrated. Bridged on Android and iOS (see
  /// [products]'s doc comment); `null` on RN / older native binaries.
  final LBProduct? narratingProduct;

  const LBPlayerMomentInfo({
    this.viewerCount = 0,
    this.isSubscribed = false,
    this.autoNextCountdownActive = false,
    this.autoNextRemainingSeconds = 0,
    this.nextItem,
    this.hotItems = const [],
    this.products = const [],
    this.narratingProduct,
  });

  /// Decode from the native `{"event":"momentStateChange", …}` EventChannel
  /// payload. Tolerant (parity with `LBPlayerChannelInfo.fromMap`): missing /
  /// null / wrong-typed num fields → their Int default; missing / null /
  /// wrong-typed bool fields → `false`; `nextItem` via
  /// [LBNavItem.fromMapOrNull]; `hotItems` via [_asHotItemList]; `products`
  /// via [_asProductList] (missing/null/non-List → `[]`, mirrors
  /// `LBPlayerChannelInfo.goods`); `narratingProduct` via [LBProduct.fromMap]
  /// when present as a `Map`, else `null`.
  factory LBPlayerMomentInfo.fromMap(Map<Object?, Object?> map) =>
      LBPlayerMomentInfo(
        viewerCount: (map['viewerCount'] as num?)?.toInt() ?? 0,
        isSubscribed: (map['isSubscribed'] as bool?) ?? false,
        autoNextCountdownActive:
            (map['autoNextCountdownActive'] as bool?) ?? false,
        autoNextRemainingSeconds:
            (map['autoNextRemainingSeconds'] as num?)?.toInt() ?? 0,
        nextItem: LBNavItem.fromMapOrNull(map['nextItem']),
        hotItems: _asHotItemList(map['hotItems']),
        products: _asProductList(map['products']),
        narratingProduct: map['narratingProduct'] is Map
            ? LBProduct.fromMap(
                Map<Object?, Object?>.from(map['narratingProduct'] as Map))
            : null,
      );
}

// MARK: - Subtitle (rb-flutter-subtitle-channel-bridge-core — core bridge only)

/// Per-channel VTT subtitle projection, forwarded from the native player view
/// to the Dart host via the `onSubtitleChange` callback
/// (`flutter-subtitle-channel-bridge`). STATIC per channel-load — [available] /
/// [url] only change when a fresh `load(videoId:)` swaps to a different
/// channel; they do NOT track the runtime CC on/off toggle.
///
///   • [available] — `channel.is_subtitle == 1` (`LBChannel.isSubtitle` on
///     iOS/Android core). Whether this channel HAS a subtitle track at all.
///   • [url]       — `channel.subtitle_url` (`LBChannel.subtitleUrl`). The
///     WebVTT URL; "" when [available] is false. Raw passthrough — parsing
///     the VTT itself is a reference-ui concern, not this core bridge's.
///
/// The runtime CC on/off toggle is a SEPARATE, ALREADY-bridged concern: it
/// reaches Dart via the existing unified `LivebuySDK.setListener(...)` path
/// as `LBEvent.subtitleToggle` (`SUBTITLE_TOGGLE`, `params['enabled']`) — no
/// core bridge change was needed for that half of the feature.
class LBSubtitleInfo {
  /// Whether the currently-loaded channel has a subtitle track. "" URL when
  /// false. Defaults to `false` (parity with native's own
  /// `SubtitleTrack.configure` default before any channel loads).
  final bool available;

  /// WebVTT subtitle URL. "" when [available] is false or absent.
  final String url;

  const LBSubtitleInfo({this.available = false, this.url = ''});

  /// Decode from the native `{"event":"subtitleChange", …}` EventChannel
  /// payload. Tolerant of missing/null AND wrong-type values (stricter than
  /// `LBPlayerChannelInfo.fromMap` / `LBPlaybackProgress.fromMap`'s
  /// missing/null-only casts, which would throw a `TypeError` on a
  /// wrong-type value): `available` — anything that isn't a `bool` (missing,
  /// null, or a stray non-bool such as an Int) → `false`; `url` — anything
  /// that isn't a `String` → `""`. Deliberately STRICT bool-only tolerance
  /// (unlike this file's `_asBoolOr`, which also treats a `num` as truthy
  /// 0/1 for API-wire Int/Bool fields) — this bridge's native emit always
  /// sends a real Dart `bool` for `available`, so the num-as-0/1 case isn't
  /// a realistic input here; this is a pure defensive fallback.
  factory LBSubtitleInfo.fromMap(Map<Object?, Object?> map) => LBSubtitleInfo(
        available: map['available'] is bool ? map['available'] as bool : false,
        url: _asStringOr(map['url'], ''),
      );
}

/// Coerce a value to `String`. Tolerates String; anything else (missing,
/// null, or the wrong type) → [fallback]. Distinct from `_asString` (used
/// for id-like fields), which STRINGIFIES a non-null value instead of
/// falling back — a URL field wants "wrong type → fallback", not
/// "wrong type → its toString() rendering".
String _asStringOr(Object? value, String fallback) =>
    value is String ? value : fallback;

// MARK: - Playback progress (flutter-vod-playback-progress-core — VOD-1 core
//         bridge parity)

/// VOD playback-progress snapshot forwarded from the native player to the Dart
/// host via [LivebuyPlayerCore.onPlaybackProgressChange] (flutter-vod-playback-progress-core,
/// parity iOS `Player.playbackProgress` / `onPlaybackProgressChange` and Android
/// `LivebuyPlayerView.playbackProgress` / `onPlaybackProgressChange`). Carried on a
/// DEDICATED event, never merged into `LBPlayerState` — mirrors both native SDKs'
/// "own channel, not momentState" design (avoids re-fanning unrelated view-models
/// on a ~1Hz tick).
///
/// `duration == 0` ⇒ live (no scrubbable timeline). `isReplay` = a live stream
/// scrubbed behind the live edge (only meaningful when `liveStatus == 1`, carried
/// separately via `LBPlayerChannelInfo.liveStatus` from `onChannelChange`).
/// `position` / `duration` are native-sanitized to finite, non-negative values;
/// `fromMap` re-sanitizes defensively (missing/null/non-num → 0).
class LBPlaybackProgress {
  final double position;
  final double duration;
  final bool isPlaying;
  final bool isReplay;

  /// Products currently "on screen" at [position] during VOD/replay playback
  /// (vod-narrating-products-core-flutter, parity iOS
  /// `LivebuyPlayerViewController.vodActiveProducts(products:position:)` / Android
  /// `LivebuyPlayerView.vodActiveProducts(products:position:)` / RN
  /// `vodActiveProducts(products, position)`). Every entry's `[beginTime, endTime)`
  /// window (seconds, begin inclusive / end exclusive) contains [position]; entries
  /// missing `beginTime`/`endTime` are excluded; may contain multiple entries when
  /// windows overlap; ordered by `beginTime` ascending. Computed by the top-level
  /// pure function [computeVodActiveProducts] from the wire's raw `products` snapshot +
  /// this same snapshot's [position] — UNCONDITIONALLY (not gated on
  /// `liveStatus`); whether/when a host reads this vs. a LIVE-only narration
  /// signal is entirely the host's decision. Default `[]`. Flutter has no
  /// moment-state type exposed to Dart today — this field MUST NOT be merged into
  /// one if such a type is ever added.
  final List<LBProduct> vodActiveProducts;

  const LBPlaybackProgress({
    this.position = 0,
    this.duration = 0,
    this.isPlaying = false,
    this.isReplay = false,
    this.vodActiveProducts = const [],
  });

  /// Decode from the native `{"event":"playbackProgress", …}` EventChannel
  /// payload. Tolerant (parity with `LBPlayerChannelInfo.fromMap` /
  /// `LBProduct.fromMap`): missing/null numeric fields → 0; missing/null bool
  /// fields → false; missing/null/non-List `products` → `[]` (an older native
  /// plugin binary that doesn't yet send `products` degrades gracefully, never
  /// throws).
  factory LBPlaybackProgress.fromMap(Map<Object?, Object?> map) {
    final position = (map['position'] as num?)?.toDouble() ?? 0;
    final products = _asProductList(map['products']);
    return LBPlaybackProgress(
      position: position,
      duration: (map['duration'] as num?)?.toDouble() ?? 0,
      isPlaying: (map['isPlaying'] as bool?) ?? false,
      isReplay: (map['isReplay'] as bool?) ?? false,
      vodActiveProducts: computeVodActiveProducts(products, position),
    );
  }
}

/// Coerce a value to `List<LBProduct>` (mirrors [_asSpecList]/[_asSpecOptionList]).
/// null / non-`List` → `[]`; each entry is decoded via the existing tolerant
/// [LBProduct.fromMap] (non-`Map` entries are skipped, not thrown on).
List<LBProduct> _asProductList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((e) => LBProduct.fromMap(Map<Object?, Object?>.from(e)))
      .toList();
}

/// Pure VOD-active-products filter (vod-narrating-products-core-flutter, mirrors
/// iOS `LivebuyPlayerViewController.vodActiveProducts(products:position:)` /
/// Android `LivebuyPlayerView.vodActiveProducts(products:position:)` / RN
/// `vodActiveProducts(products, position)`): returns every product in [products]
/// whose `[beginTime, endTime)` window (seconds, begin inclusive / end exclusive)
/// contains [position]. Products missing `beginTime` or `endTime` are excluded.
/// May return multiple entries when windows overlap; ordered by `beginTime`
/// ascending (tie-break order is unspecified, matching every other platform's
/// identical non-reliance on sort stability for equal `beginTime`s).
///
/// Named `computeVodActiveProducts` (NOT `vodActiveProducts`, unlike the other
/// three platforms' equivalent function) because `LBPlaybackProgress` already
/// declares an INSTANCE field called `vodActiveProducts` — inside that class's own
/// factory constructor, a bare `vodActiveProducts` identifier resolves to that
/// instance member (Dart's class-body lexical scope shadows library scope for a
/// same-named top-level declaration), not this top-level function, and instance
/// members are unreachable from a factory constructor (no `this` yet). This is a
/// Dart-specific naming constraint, not a semantic difference — the algorithm is a
/// literal mirror of the other platforms' identically-behaving function.
List<LBProduct> computeVodActiveProducts(
    List<LBProduct> products, double position) {
  final hits = products.where((p) {
    final begin = p.beginTime;
    final end = p.endTime;
    return begin != null && end != null && begin <= position && position < end;
  }).toList();
  hits.sort((a, b) => a.beginTime!.compareTo(b.beginTime!));
  return hits;
}

/// Pure VOD-scrub gate (flutter-vod-playback-progress-core, parity iOS `static
/// vodScrubAllowed(liveStatus:duration:)` / component-contracts §對比 seek).
///
/// `liveStatus == 1` (actively-live) always returns `false` — a live stream is
/// not scrubbable. `liveStatus == 3` (replay) or `liveStatus == 0` (upcoming,
/// per the same truth table as iOS) WITH a finite positive `duration` returns
/// `true`. Every other case (an unknown/other `liveStatus`, a `null`
/// `liveStatus`, or a non-positive `duration`) returns `false`.
///
/// Used as an OPT-IN Dart-layer pre-gate by [LivebuyPlayerController.seek] /
/// [LivebuyPlayerController.seekBy] when the caller supplies `liveStatus` —
/// see those methods' docs. Native remains the authoritative enforcer on
/// whichever platform enforces it (iOS today).
bool vodScrubAllowed(int? liveStatus, double duration) {
  if (liveStatus == 1) return false;
  if ((liveStatus == 3 || liveStatus == 0) && duration > 0) return true;
  return false;
}

// MARK: - Widget colors (widget-bridge-color-core)

/// Web-embed widget colors carried in the `POST /sdk/widget` root response and
/// surfaced through [LivebuyWidgetController.onWidgetResponse].
///
/// widget-bridge-color-core: raw passthrough of the two web-embed color fields
/// (`widget_color` / `widget_bgcolor`). The SDK does **not** interpret their
/// semantics (1=black text / 2=white text; Int 1=transparent / hex string) —
/// the host / template decides how to render. These are STRICTLY separate from
/// `sdkConfig.theme.primaryColor` (the native SDK global theme): this class
/// only reflects `/sdk/widget` colors and never overrides or merges with the
/// `/sdk/config` theme.
///
/// `widgetBgcolor` is always `String?` on the bridge: the backend mixed
/// Int/String value is normalised upstream (Int `1` → `"1"`, hex → raw,
/// missing → null), mirroring the iOS / Android `decodeStringOrInt` passthrough.
class LBWidgetColors {
  /// Web-embed text color (1=black text / 2=white text). Missing → default 1.
  final int widgetColor;

  /// Web-embed background color. Int `1` (transparent) → `"1"`, otherwise the
  /// raw hex string; missing → null. Always `String?` on the bridge (the mixed
  /// Int/String value is normalised to a single String? shape).
  final String? widgetBgcolor;

  const LBWidgetColors({this.widgetColor = 1, this.widgetBgcolor});

  /// Decode from the native reverse `invokeMethod('onWidgetResponse', ...)`
  /// args. Reads the snake_case wire keys `widget_color` (missing → 1) and
  /// `widget_bgcolor` (missing → null). `widget_bgcolor` is read as a String;
  /// if a bare Int slips through it is stringified to match the
  /// always-`String?` bridge contract (raw passthrough, e.g. Int 1 → `"1"`).
  factory LBWidgetColors.fromMap(Map<Object?, Object?> map) => LBWidgetColors(
        widgetColor: (map['widget_color'] as num?)?.toInt() ?? 1,
        widgetBgcolor: _asBgcolor(map['widget_bgcolor']),
      );

  Map<String, Object?> toMap() => {
        'widget_color': widgetColor,
        'widget_bgcolor': widgetBgcolor,
      };
}

/// Coerce `widget_bgcolor` to the bridge's always-`String?` shape: null → null,
/// String → passthrough, any stray Int (e.g. backend Int 1) → its string form.
String? _asBgcolor(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  return value.toString();
}

// MARK: - addToCart (video-addcart-endpoint-core, 路線 B)
//
// NOTE: this is DISTINCT from the route-A `CART_ADD_REQUEST` host-callback
// flow. This is the SDK-driven route-B online add-to-cart, mirroring native
// `LBCartResult { goodsNo, specificationNo, buyNo }`. `LBCartResult` is free
// in the Flutter namespace (no pre-existing collision), so we use it here
// rather than the RN `LBAddToCartResult` alias.

/// Options for [LivebuySDK.addToCart] (`POST /sdk/video/addcart`).
class LBAddToCartOptions {
  /// Shop ID (required).
  final String shopId;
  final int? goodsId;
  final int? num;
  final int? specificationId;
  final List<int>? ids;
  final int? live;
  final int? isLive;
  final int? isWidget;
  final int? inDomain;
  final String? userid;
  final String? thirdpartyUserId;
  final int? buyingId;
  final int? eventId;
  final String? guestName;
  final String? dbsc;

  /// 當前影片短碼（cart-add-tier2-unify）。透傳給 native `addToCart(videoId:)`，使後續
  /// `CART_ADD_REQUEST.video_id` 為當前影片（而非 `""`）。Mirrors native `videoId`.
  final String? videoId;

  const LBAddToCartOptions({
    required this.shopId,
    this.goodsId,
    this.num,
    this.specificationId,
    this.ids,
    this.live,
    this.isLive,
    this.isWidget,
    this.inDomain,
    this.userid,
    this.thirdpartyUserId,
    this.buyingId,
    this.eventId,
    this.guestName,
    this.dbsc,
    this.videoId,
  });

  Map<String, Object?> toMap() => {
        'shopId': shopId,
        'goodsId': goodsId,
        'num': num,
        'specificationId': specificationId,
        'ids': ids,
        'live': live,
        'isLive': isLive,
        'isWidget': isWidget,
        'inDomain': inDomain,
        'userid': userid,
        'thirdpartyUserId': thirdpartyUserId,
        'buyingId': buyingId,
        'eventId': eventId,
        'guestName': guestName,
        'dbsc': dbsc,
        'videoId': videoId,
      };
}

// MARK: - addcart track (addcart-track ④, parity iOS core-addcart-track / RN)
//
// 後端 addcart 回應的導購歸因指令（雙向錨）。`mode` 決定 host 如何套用；RAW PASSTHROUGH——
// SDK 不解讀語意，host 依 mode 決定行為。對齊 native `LBCartTrack` / RN `LBCartTrack`。

/// 單一歸因欄位。`value` 已由後端組好（raw passthrough，host 原樣套用）。
class LBCartTrackField {
  final String key;
  final String value;
  const LBCartTrackField({required this.key, required this.value});

  factory LBCartTrackField.fromMap(Map<Object?, Object?> map) => LBCartTrackField(
        key: _asString(map['key']),
        value: _asString(map['value']),
      );
}

/// addcart 回應的導購歸因指令。`mode`（raw String，host 解讀：`'attribute'` → 寫 fields；
/// `'token'` → 結帳前呼叫 [LivebuySDK.reportCartTrack]；`'unsupported'`；未知直通）決定 host 如何套用；
/// `level`（如 `'line_item'` / `'order'`）僅 attribute mode 有意義（缺 → null）；`fields` 的 `value`
/// 已由後端組好。
class LBCartTrack {
  final String mode;
  final String? level;
  final List<LBCartTrackField> fields;
  const LBCartTrack({required this.mode, this.level, this.fields = const []});

  factory LBCartTrack.fromMap(Map<Object?, Object?> map) {
    final rawFields = map['fields'];
    final fields = rawFields is List
        ? rawFields
            .whereType<Map<Object?, Object?>>()
            .map(LBCartTrackField.fromMap)
            .toList()
        : <LBCartTrackField>[];
    return LBCartTrack(
      mode: _asString(map['mode']),
      level: map['level'] is String ? map['level'] as String : null,
      fields: fields,
    );
  }

  /// `mode == 'attribute'` 時把 `fields` 攤平為 `key → value` map；`mode` 為
  /// `'token'` / `'unsupported'` / 其他，或 `fields` 為空時回 `null`
  /// (`event-payload-typed-accessors-flutter-core`, mirrors iOS
  /// `LBCartTrack.attributeFields` / Android `LBCartTrack.attributeFields`).
  ///
  /// 把 host 反覆 copy-paste 的「只在 `mode == 'attribute'` 才取 fields」gating
  /// 收斂為 SDK 一處實作。不改既有 `mode` / `level` / `fields` 欄位或其解碼
  /// （唯讀衍生）。
  Map<String, String>? get attributeFields {
    if (mode != 'attribute' || fields.isEmpty) return null;
    final map = <String, String>{};
    for (final field in fields) {
      map[field.key] = field.value;
    }
    return map;
  }
}

/// Route-B add-to-cart result. Fields stay `String` for cross-platform parity
/// (mirrors native `LBCartResult` + RN `LBAddToCartResult`).
class LBCartResult {
  final String goodsNo;
  final String specificationNo;
  /// Backend checkout-list id; usable as `notifyCheckoutCompleted(orderId:)`.
  final String buyNo;
  /// 導購歸因指令（addcart-track ④）。後端回應含 `track` 時附帶；缺 → null（三欄向後相容）。
  /// host 依 `track.mode` 套用：`'attribute'` → 寫 fields；`'token'` → 結帳前呼叫
  /// [LivebuySDK.reportCartTrack]。
  final LBCartTrack? track;

  const LBCartResult({
    required this.goodsNo,
    required this.specificationNo,
    required this.buyNo,
    this.track,
  });

  factory LBCartResult.fromMap(Map<Object?, Object?> map) {
    final rawTrack = map['track'];
    return LBCartResult(
      goodsNo: _asString(map['goodsNo']),
      specificationNo: _asString(map['specificationNo']),
      buyNo: _asString(map['buyNo']),
      track: rawTrack is Map<Object?, Object?> ? LBCartTrack.fromMap(rawTrack) : null,
    );
  }
}

// MARK: - Typed event-payload accessors (event-payload-typed-accessors-flutter-core)
//
// `LBEventListener` (event_listener.dart) flattens every event's payload into
// `LBSdkEvent.params: Map<String, Object?>`. This section adds **purely additive**
// typed convenience entry points so hosts don't have to re-do untyped archaeology
// on the map (`params['goods_no'] as String? ?? ''`, hand-parsing nested `track`).
// Mirrors iOS `LBEventPayloads.swift` / Android `LBEventPayloads.kt`.
//
// ⚠️ These types **coexist** with the raw map — `LBSdkEvent.params`'s type and the
// event-channel dispatch are unchanged (see spec `event-payload-typed-accessors`).
// Hosts that don't want them can keep reading the map directly.
//
// Field semantics are **fully inherited** from the `event-interceptor` params
// contract, MUST NOT be redefined here:
//   - `specification_id` / `goods_no` / `specification_no` omitted by the backend
//     → `''` (key not missing)
//   - `VIEW_CART.product_id` omitted (list-bottom CTA) → `null` (not empty string)
//   - `track` omitted by the backend → `null`, and **reuses** existing
//     `LBCartTrack.fromMap` (no parallel type)
//
// `fromMap` always takes a "decode leniently" stance: only returns `null` when the
// required `video_id` key is missing. A Dart `factory` constructor cannot return
// `null`, so these use `static` methods instead of `factory`.

/// Typed payload convenience entry point for the `CART_ADD_REQUEST` notification
/// event.
///
/// Use it in your `LBEventListener` handler:
///
/// ```dart
/// if (event.eventName == LBEvent.cartAddRequest) {
///   final req = LBCartAddRequest.fromMap(event.params);
///   if (req == null) return LBEventReply.acknowledge;
///   // req.goodsNo / req.buyNo / req.track?.attributeFields ...
///   if (req.awardWinnerId != null) { /* 這筆是獎品自動加購 */ }
/// }
/// ```
///
/// `award-product-auto-cart`: a **product**-type prize claimed successfully makes
/// the native core add that prize to the cart **automatically**, dispatching one
/// extra `CART_ADD_REQUEST`. That one event carries [awardWinnerId] so the host
/// can tell "this add-to-cart is a prize" without diffing `product_id` or
/// remembering the previous event; a normal (user-tapped) add-to-cart omits the
/// `award_winner_id` key entirely. See [LivebuyPlayerController.requestAwardClaim]
/// for the two-event sequence and its failure degradation.
class LBCartAddRequest {
  /// Current video short code (`video_id`, required — `fromMap` returns `null`
  /// if this key is missing).
  final String videoId;

  /// Product id (`product_id`). The backend returns `''` for the cart-purchase
  /// (`ids`) path where there is no single product id.
  final String productId;

  /// Selected specification id (`specification_id`); `''` when there is no
  /// named specification (key not missing).
  final String specificationId;

  /// addcart response product number (`goods_no`); `''` when omitted by the
  /// backend.
  final String goodsNo;

  /// addcart response specification number (`specification_no`); `''` when
  /// omitted by the backend.
  final String specificationNo;

  /// SDK-generated attribution anchor (`sdk_track_code`).
  final String sdkTrackCode;

  /// addcart response checkout-list id (`buy_no`); the input to host
  /// `LivebuySDK.reportCartTrack`.
  final String buyNo;

  /// Checkout attribution instruction (`track`). `null` when the backend
  /// doesn't return one. Reuses existing `LBCartTrack` / `LBCartTrackField`
  /// (no parallel type).
  final LBCartTrack? track;

  /// Winning-ticket id (`award_winner_id`) — the same value as
  /// `AWARD_CLAIM_RESULT`'s `winner_id`. **Only** present on the add-to-cart
  /// that a **product**-type prize claim triggered automatically
  /// (`award-product-auto-cart`); a normal add-to-cart omits the key entirely,
  /// so this reads `null`.
  ///
  /// ⚠️ **`null` is NOT `''`** — deliberately divergent from this class's
  /// [goodsNo] / [specificationNo] / [specificationId], which fall back to `''`
  /// when the backend omits a *value* while the key always exists. Here the
  /// **absence itself is the meaning**: `null` means "this is not a prize
  /// add-to-cart". Never collapse a missing key into `''`, or hosts can no
  /// longer tell "not a prize" from "a prize whose ticket id was empty".
  ///
  /// The SDK MUST NOT change any pricing behaviour because of this field —
  /// prizes are free by virtue of the backend's 0-priced SKU, not by anything
  /// the SDK or the host does here.
  final String? awardWinnerId;

  const LBCartAddRequest({
    required this.videoId,
    this.productId = '',
    this.specificationId = '',
    this.goodsNo = '',
    this.specificationNo = '',
    this.sdkTrackCode = '',
    this.buyNo = '',
    this.track,
    this.awardWinnerId,
  });

  /// Parses `CART_ADD_REQUEST`'s `params` into typed fields in one call. Pure
  /// function (`Map<Object?, Object?> -> LBCartAddRequest?`). Returns `null`
  /// only when the required `video_id` key is missing.
  ///
  /// `award_winner_id` is read with an explicit type check (never `_asString`,
  /// which would turn a missing key into `''`, and never `as String?`, which
  /// would throw on a drifted type): a missing key, an explicit null, or any
  /// non-`String` value all decode to `null` — the safe side, meaning "not a
  /// prize add-to-cart" — and never fail the whole payload.
  static LBCartAddRequest? fromMap(Map<Object?, Object?> map) {
    final videoId = map['video_id'];
    if (videoId is! String) return null;
    final rawTrack = map['track'];
    final rawAwardWinnerId = map['award_winner_id'];
    return LBCartAddRequest(
      videoId: videoId,
      productId: _asString(map['product_id']),
      specificationId: _asString(map['specification_id']),
      goodsNo: _asString(map['goods_no']),
      specificationNo: _asString(map['specification_no']),
      sdkTrackCode: _asString(map['sdk_track_code']),
      buyNo: _asString(map['buy_no']),
      track: rawTrack is Map<Object?, Object?> ? LBCartTrack.fromMap(rawTrack) : null,
      awardWinnerId: rawAwardWinnerId is String ? rawAwardWinnerId : null,
    );
  }
}

/// Typed payload convenience entry point for the `VIEW_CART` notification event.
///
/// Semantics are inherited from the `event-interceptor` §view-cart event
/// contract: `videoId` is required; `productId` is that value on the product
/// detail CTA (params **contains** the `product_id` key) and `null` on the
/// list-bottom CTA (params **omits** the key) — the boundary is "does the key
/// exist", not an empty string standing in for "none".
class LBViewCartIntent {
  /// Current video short code (`video_id`, required — `fromMap` returns `null`
  /// if this key is missing).
  final String videoId;

  /// Product id (`product_id`). Only present on the detail-page CTA; the
  /// list-bottom CTA omits the key → `null`.
  final String? productId;

  const LBViewCartIntent({required this.videoId, this.productId});

  /// Parses `VIEW_CART`'s `params` into typed fields. Pure function. Returns
  /// `null` only when the required `video_id` key is missing; `productId` is
  /// `null` when the `product_id` key doesn't exist.
  static LBViewCartIntent? fromMap(Map<Object?, Object?> map) {
    final videoId = map['video_id'];
    if (videoId is! String) return null;
    final productId = map['product_id'];
    return LBViewCartIntent(
      videoId: videoId,
      productId: productId is String ? productId : null,
    );
  }
}

// MARK: - Replay chat revealed (replay-chat-revealed-seam-core-flutter)

/// A single chat comment, forwarded to the Dart host via
/// [LivebuyPlayerCore.onReplayChatRevealed] (the `replayChatRevealed`
/// `EventChannel` event) during finished-live replay playback.
///
/// Scoped to EXACTLY the 6 fields this seam's own spec contract enumerates
/// (`replay-chat-revealed-seam-core-flutter`, mirrors the iOS/Android
/// `onReplayChatRevealed` requirements' payload contract) — deliberately NOT
/// the native SDKs' full 8-field `LBComment` struct (no `kind` / `isTop`; a
/// later change can widen this if a real consumer needs them). Byte-identical
/// field set to the existing `CHAT_HISTORY_LOADED` / `replayHistoryEventComments`
/// comment wire shape, so a Dart consumer that already parses one can reuse
/// the same mental model for the other.
class LBComment {
  final String text;
  final String name;
  final String color;

  /// Admin reply. ⚠ By-design the backend passes the literal `{live_master}`
  /// placeholder through unreplaced; host MUST substitute it with the
  /// broadcaster name on display (parity with the native `LBComment.reply`
  /// doc contract).
  final String reply;

  /// Wire key `reply_color`.
  final String replyColor;

  /// Playback offset seconds (distance from video start), NOT a Unix
  /// timestamp. Kept as `String` (parity with the native `LBComment.time`
  /// cross-platform-precision convention).
  final String time;

  const LBComment({
    this.text = '',
    this.name = '',
    this.color = '',
    this.reply = '',
    this.replyColor = '',
    this.time = '',
  });

  /// Tolerant decode: missing / null / wrong-type → `""` per field, never
  /// throws (mirrors this file's `_asStringOr` convention).
  factory LBComment.fromMap(Map<Object?, Object?> map) => LBComment(
        text: _asStringOr(map['text'], ''),
        name: _asStringOr(map['name'], ''),
        color: _asStringOr(map['color'], ''),
        reply: _asStringOr(map['reply'], ''),
        replyColor: _asStringOr(map['reply_color'], ''),
        time: _asStringOr(map['time'], ''),
      );
}

/// Coerce a value to `List<LBComment>` (mirrors [_asProductList]). null /
/// non-`List` → `[]`; each entry is decoded via [LBComment.fromMap]
/// (non-`Map` entries are skipped, not thrown on). An empty input list
/// decodes to `[]`, never `null` — the `replayChatRevealed` seam relies on
/// this to forward its cleanup `[]` emits as-is (design D6).
///
/// PUBLIC (no leading underscore), unlike [_asProductList]/[_asSpecList]:
/// those are only ever called from WITHIN this file (a containing model's
/// own `fromMap`), whereas this helper is called directly from
/// `livebuy_player.dart`'s `_handleEvent` switch — Dart's `_`-privacy is
/// per-FILE, so a private symbol here would not be visible there. Mirrors
/// the existing cross-file precedent [lbPlayerStateFromString] /
/// [lbErrorFromMap] (both public, both called from `_handleEvent` too).
List<LBComment> asCommentList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((e) => LBComment.fromMap(Map<Object?, Object?>.from(e)))
      .toList();
}
