import 'package:flutter/foundation.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart';

// product-sheet-stack-template — Default template 商品 sheet-stack view-models
// (behaviour / view-model layer; NO pixels).
//
// Spec: ui-template-foundation/spec.md
//   § "Default Template 商品 Sheet-Stack 狀態與加購行為"
//   (+ MODIFIED "Default Template Bindable State 變更通知").
// Design: design.md D1–D8. Depends on product-bridge-data-core (already applied:
//   the Flutter bridge `LBProduct` now carries `price` / `photos` / `stock` /
//   `specifications` / `specOptions`).
//
// HEADLESS: every class here is a host-bindable view-model the host binds to draw
// the `sdk-components.jsx` components (LBPBottomSheet / LBPProductRow /
// LBPVariantPicker / LBPQtyStepper / LBPMiniCart / LBPCartCTA). The template
// renders NO pixels — it imports only `package:flutter/foundation.dart`
// (ChangeNotifier) + the core models; it has NO Widget subclass, NO
// `package:flutter/widgets.dart` import.
//
// Each view-model `extends ChangeNotifier` (Flutter's coalesced-notification
// idiom, parity with DefaultGoodsTracking / DefaultMomentState): the host binds
// each with `ListenableBuilder` and `notifyListeners()` fires EXACTLY ONCE per
// real change. The fan-in is automatic (each is its own ChangeNotifier).

/// Host-wired delegate for the route-B add-to-cart call. Injectable so the host
/// wires the closure that calls its `LivebuySDK.addToCart(LBAddToCartOptions)`
/// (route B → `LBCartResult`); the template MUST NOT build HTTP itself (mirrors
/// `GoodsTrackingSetter` delegating `setAwaitGoods`). Default is an inert no-op
/// throwing stub supplied by the template ctor — see [DefaultPlayerTemplate].
typedef AddToCartRequester = Future<LBCartResult> Function(LBAddToCartOptions options);

// ── 1. product-detail ─────────────────────────────────────────────────────────

/// One「更多商品」推薦卡片(expose-other-goods-recommendations-template design.md
/// D2)。由 `LBChannel.otherGoods` 映射,刻意精簡 — 只帶渲染推薦卡 + 換片所需的最小欄位
/// 集合,不含 `specifications` / `specOptions`:使用者真的點進巢狀明細時,template 走既有
/// `productTap` → product-detail 映射路徑重新算出完整狀態,不靠這份精簡清單帶規格資料。
///
/// `originalPriceShow`(add-recommendation-original-price-template-flutter)比照
/// `LBProduct.originalPriceShow` 型別/慣例:非 nullable `String`,`''` = 無劃線價 — MUST NOT
/// 比照 `LBProductDetailState.originalPriceShow` 的 `String?` 三態寫法。預設值 `''`(而非
/// `required`)是刻意的:`flutter-reference-ui` 有既存 fixture 直接建構
/// `LBProductRecommendation` 而未帶此欄位(如
/// `test/productsheets/product_detail_recommendations_test.dart`),那個 package 不屬本
/// change 範圍、MUST NOT 被改動——加預設值讓新欄位對既有呼叫端保持加法相容。
///
/// `brief` / `description`(add-recommendation-brief-description-template-flutter)同樣比照
/// `LBProduct.brief` / `LBProduct.description` 型別/慣例:皆為非 nullable `String`,`''` = 無值。
/// 兩者在 Flutter core `LBProduct` 上本身就是非 nullable(不像 RN 的 `description?: string` 是
/// optional),映射時可直接透傳、不需要容錯運算子。預設值 `''`(而非 `required`)理由同
/// `originalPriceShow`:避免強迫修改 `flutter-reference-ui` 既存未帶新欄位的 fixture。
@immutable
class LBProductRecommendation {
  final String productId;
  final String name;
  final String priceShow;
  final String originalPriceShow;
  final String pic;
  final String brief;
  final String description;

  /// 跨影片商品參照(`LBProduct.videoId`)。後端該筆 `other_goods[]` 未提供 `video_id`
  /// 時為 null — reference-ui MUST 隱藏/停用換片入口,MUST NOT 補假值。
  final String? videoId;

  /// 0 | 1 — API integer, not boolean.
  final int soldOut;

  const LBProductRecommendation({
    required this.productId,
    required this.name,
    required this.priceShow,
    this.originalPriceShow = '',
    required this.pic,
    this.brief = '',
    this.description = '',
    this.videoId,
    required this.soldOut,
  });

  @override
  bool operator ==(Object other) =>
      other is LBProductRecommendation &&
      other.productId == productId &&
      other.name == name &&
      other.priceShow == priceShow &&
      other.originalPriceShow == originalPriceShow &&
      other.pic == pic &&
      other.brief == brief &&
      other.description == description &&
      other.videoId == videoId &&
      other.soldOut == soldOut;

  @override
  int get hashCode => Object.hash(productId, name, priceShow,
      originalPriceShow, pic, brief, description, videoId, soldOut);
}

/// 純函式(可獨立測試):過濾掉 `productId` 自身(`other_goods[]` 不保證不含目前商品,
/// 資料正確性防線由 template 負責,見 design.md D1),映射為精簡的
/// [LBProductRecommendation]。MUST NOT 裁切張數(裁切屬 reference-ui 版面決定)。
List<LBProductRecommendation> recommendationsFromOtherGoods(
  List<LBProduct> otherGoods,
  String productId,
) {
  return otherGoods
      .where((p) => p.id != productId)
      .map((p) => LBProductRecommendation(
            productId: p.id,
            name: p.name,
            priceShow: p.priceShow,
            originalPriceShow: p.originalPriceShow,
            pic: p.pic,
            brief: p.brief,
            description: p.description,
            videoId: p.videoId,
            soldOut: p.soldOut,
          ))
      .toList();
}

/// One host-bindable product-detail snapshot, mirroring the relevant `LBProduct`
/// fields (D1 — no parallel model). null when no `diversion==0` productTap has
/// been seen (or after [DefaultProductSheet.clearDetail]).
@immutable
class LBProductDetailState {
  final String productId;
  final String name;
  final String priceShow;
  final String? originalPriceShow;
  final double? price;
  final int stock;
  final int soldOut;
  final List<String> photos;
  final List<LBSpec> specifications;
  final List<LBSpecOption> specOptions;

  /// 「更多商品」推薦清單 — 過濾後的完整 `LBChannel.otherGoods`(排除目前商品,不裁切
  /// 張數,expose-other-goods-recommendations-template design.md D1)。無 channel 情境
  /// 時為空清單。
  final List<LBProductRecommendation> recommendations;

  const LBProductDetailState({
    required this.productId,
    required this.name,
    required this.priceShow,
    this.originalPriceShow,
    this.price,
    required this.stock,
    required this.soldOut,
    this.photos = const [],
    this.specifications = const [],
    this.specOptions = const [],
    this.recommendations = const [],
  });
}

/// product-detail view-model — the latest `diversion==0` product mapped from
/// `LBProduct` (D1). Opening a new detail RESETS variant selection + qty (the
/// reset is orchestrated by [DefaultPlayerTemplate], which holds the sibling
/// view-models; this class owns only the detail snapshot).
class DefaultProductSheet extends ChangeNotifier {
  LBProductDetailState? _detail;

  /// Current product-detail snapshot, or null when no sheet is open.
  LBProductDetailState? get detail => _detail;

  /// Map an `LBProduct` (diversion==0 productTap) into the detail snapshot.
  /// [otherGoods] is the current channel's `LBChannel.otherGoods` (empty/omitted
  /// when no channel context, e.g. a headless unit test) — mapped into
  /// [LBProductDetailState.recommendations] via [recommendationsFromOtherGoods]
  /// (expose-other-goods-recommendations-template). Always notifies (a fresh
  /// productTap is a real open even if the same id).
  @internal
  void openDetail(LBProduct product, [List<LBProduct> otherGoods = const []]) {
    _detail = LBProductDetailState(
      productId: product.id,
      name: product.name,
      priceShow: product.priceShow,
      originalPriceShow:
          product.originalPriceShow.isEmpty ? null : product.originalPriceShow,
      price: product.price,
      stock: product.stock,
      soldOut: product.soldOut,
      photos: List.of(product.photos),
      specifications: List.of(product.specifications),
      specOptions: List.of(product.specOptions),
      recommendations: recommendationsFromOtherGoods(otherGoods, product.id),
    );
    notifyListeners();
  }

  /// Host-dismiss clear for the detail sheet. Notifies iff it cleared something.
  void clearDetail() {
    if (_detail == null) return;
    _detail = null;
    notifyListeners();
  }
}

// ── 2. variant-picker ──────────────────────────────────────────────────────────

/// One spec group for the picker (`{ label, options }`), mapped from a single
/// `LBSpecOption` (D2). `label` = `LBSpecOption.name`, `options` = `child`.
@immutable
class LBVariantGroup {
  final String label;
  final List<String> options;
  const LBVariantGroup({required this.label, required this.options});

  @override
  bool operator ==(Object other) =>
      other is LBVariantGroup &&
      other.label == label &&
      listEquals(other.options, options);

  @override
  int get hashCode => Object.hash(label, Object.hashAll(options));
}

/// One spec-option group's CASCADING purchasability snapshot
/// (rb-flutter-variant-cascading-availability-template). `availableOptions[i]`
/// corresponds to [LBVariantGroup.options]`[i]` (same order, same length) —
/// `true` when choosing that value, together with whatever is CURRENTLY chosen
/// in every OTHER group, still resolves to at least one `stock > 0` `LBSpec`.
/// Read via [DefaultVariantPicker.optionAvailability] (instance getter) or the
/// underlying pure `DefaultVariantPicker.optionAvailability(groups, selection,
/// specifications)`, which returns one [LBVariantGroupAvailability] per
/// `groups` entry, in the same order. Structurally identical to iOS
/// `LBVariantGroupAvailability` (`DefaultProductSheet.swift:248-256`) / Android
/// `data class LBVariantGroupAvailability` (`ProductSheetBehavior.kt:143`).
///
/// This is a PURE DERIVATION for host/reference-ui to decide which chips to
/// grey out / disable, and how the not-yet-chosen groups should re-narrow once
/// an earlier group is picked (multi-group "cascading" disable). It does NOT
/// gate [DefaultVariantPicker.selectVariant] — the template still allows
/// selecting any in-range option regardless of its availability flag; whether
/// to block the tap in the UI is a reference-ui decision.
@immutable
class LBVariantGroupAvailability {
  final int groupIndex;
  final List<bool> availableOptions;

  const LBVariantGroupAvailability({
    required this.groupIndex,
    required this.availableOptions,
  });

  @override
  bool operator ==(Object other) =>
      other is LBVariantGroupAvailability &&
      other.groupIndex == groupIndex &&
      listEquals(other.availableOptions, availableOptions);

  @override
  int get hashCode =>
      Object.hash(groupIndex, Object.hashAll(availableOptions));
}

/// variant-picker view-model (D2). `groups` are mapped from `specOptions`;
/// `selection` is template-owned (`groupIndex → optionIndex`); `selectedSpec` /
/// `selectedSpecificationId` are RESOLVED from `specifications` by matching the
/// concatenated selected option labels against `LBSpec.name`.
/// `selectedSpecificationId` is the resolved spec's `LBSpec.id` (wire `id`, the
/// cart request's `specification_id`) — NEVER its `specificationNo`
/// (wire `specification_no`, a different field); see [selectedSpecificationId].
///
/// No-spec product (`specOptions` empty): `groups` empty, `selectedSpec` =
/// the single spec (or null), add-to-cart NOT forced to choose a spec.
/// Has-spec but not fully chosen: `selectedSpec` / `selectedSpecificationId` =
/// null (add-to-cart MUST be gated — see [DefaultPlayerTemplate.addToCart]).
class DefaultVariantPicker extends ChangeNotifier {
  List<LBVariantGroup> _groups = const [];
  List<LBSpec> _specifications = const [];
  final Map<int, int> _selection = {};

  /// Spec groups for the chip UI (host draws `LBPVariantPicker`).
  List<LBVariantGroup> get groups => List.unmodifiable(_groups);

  /// Template-owned selection (`groupIndex → optionIndex`).
  Map<int, int> get selection => Map.unmodifiable(_selection);

  /// The resolved purchasable spec for the current selection, or null when:
  /// (a) the product has specs but selection is not complete; or
  /// (b) the selected combination does not match any `LBSpec`.
  /// For a no-spec product this is the single spec (or null when none).
  LBSpec? get selectedSpec => _resolveSelectedSpec();

  /// The resolved `LBSpec.id` (wire `id`) of [selectedSpec] — i.e. the value the
  /// add-to-cart endpoint takes as `specification_id` — or null.
  ///
  /// MUST take `LBSpec.id`, MUST NOT take `LBSpec.specificationNo` (wire
  /// `specification_no`). They are two DISTINCT wire fields: `specification_no`
  /// is the backend's own SKU number (non-numeric, e.g. `SKU-CORAL` / `SN-04`),
  /// while `specification_id` — the cart request parameter — ranges over
  /// `LBSpec.id`. Feeding `specification_no` into
  /// [DefaultPlayerTemplate.addToCart]'s `int.tryParse` yields `null`, silently
  /// dropping the spec from the request (no exception, no failure flag).
  /// Parity: iOS `resolvedSpec?.id` / Android `selectedSpec()?.id?.toIntOrNull()`
  /// / RN `this._selectedSpec?.id`.
  String? get selectedSpecificationId => _resolveSelectedSpec()?.id;

  /// Cascading purchasability snapshot for the CURRENT `_groups` / `_selection`
  /// / `_specifications` (rb-flutter-variant-cascading-availability-template).
  /// Read-through, recomputed on every access (no caching, no mutation, no
  /// notification) — matches the [selectedSpec] getter pattern. See
  /// [LBVariantGroupAvailability] / [_optionAvailability] (the underlying pure
  /// static function) for the shape and algorithm.
  ///
  /// NOTE (deviation from tasks.md's literal identifier): design.md D3 /
  /// iOS `optionAvailability` (computed property) + `optionAvailability(groups
  /// :selection:specifications:)` (static func with argument labels) / Android
  /// instance `optionAvailability` (property) + `Companion.optionAvailability`
  /// (companion-object func) share the identifier `optionAvailability` across
  /// an instance member and a static member because Swift disambiguates by
  /// argument labels and Kotlin keeps companion-object members in a separate
  /// namespace. Dart has NO such separation — a class MUST NOT declare an
  /// instance member and a static member with the identical name
  /// (`conflicting_static_and_instance` compile error). The underlying pure
  /// function is therefore named [_optionAvailability] (private, mirroring the
  /// file's existing `_specMatches` / `_specNameMatches` / `_resolveSelectedSpec`
  /// private-helper convention — none of which are called directly from
  /// outside this library either); the PUBLIC surface host/reference-ui and
  /// tests actually read is this instance getter, `optionAvailability`.
  List<LBVariantGroupAvailability> get optionAvailability =>
      _optionAvailability(_groups, _selection, _specifications);

  /// True when the product HAS spec groups (host must choose). Drives the
  ///「請選規格」gate when [selectedSpec] is still null.
  bool get hasGroups => _groups.isNotEmpty;

  /// Reset + remap the picker for a freshly-opened product (D1 reset). Always
  /// notifies (a new product is a real change).
  @internal
  void reset(List<LBSpecOption> specOptions, List<LBSpec> specifications) {
    _groups = specOptions
        .map((o) => LBVariantGroup(label: o.name, options: List.of(o.child)))
        .toList();
    _specifications = List.of(specifications);
    _selection.clear();
    notifyListeners();
  }

  /// Host-dismiss clear for the picker state (flutter-product-sheet-stack-video-switch-reset-template
  /// — parity RN `variantPicker.clear()`; no such call exists on Android's `clear()`, a known
  /// gap tracked outside this change). Empties `groups` / `specifications` / `selection` — the
  /// same end state as opening a product with no spec groups. Notifies iff it cleared something
  /// (diff-then-notify, same idiom as [DefaultProductSheet.clearDetail]).
  void clear() {
    if (_groups.isEmpty && _specifications.isEmpty && _selection.isEmpty) return;
    _groups = const [];
    _specifications = const [];
    _selection.clear();
    notifyListeners();
  }

  /// Host picked option [optionIndex] in group [groupIndex]. Updates selection
  /// and notifies (the resolved spec / id may change). Out-of-range indices are
  /// ignored (no notify).
  void selectVariant(int groupIndex, int optionIndex) {
    if (groupIndex < 0 || groupIndex >= _groups.length) return;
    final group = _groups[groupIndex];
    if (optionIndex < 0 || optionIndex >= group.options.length) return;
    if (_selection[groupIndex] == optionIndex) return;
    _selection[groupIndex] = optionIndex;
    notifyListeners();
  }

  /// Pure resolver: map the current selection → the matching `LBSpec` (D2).
  LBSpec? _resolveSelectedSpec() {
    // No-spec product: take the single spec (or null).
    if (_groups.isEmpty) {
      return _specifications.length == 1 ? _specifications.first : null;
    }
    // Has-spec: every group MUST be chosen.
    if (_selection.length != _groups.length) return null;
    // Build the selected option labels in group order; match against LBSpec.name
    // (backend spec name = the option values joined — existing LBSpec convention).
    final chosen = <String>[];
    // Each chosen[g]'s OWN group's full option list — the `siblingOptions`
    // that `_specNameMatches` needs to mask out longer same-group siblings
    // (variant-sibling-substring-match-fix-template-flutter).
    final siblingOptionsPerChosen = <List<String>>[];
    for (var g = 0; g < _groups.length; g++) {
      final optIdx = _selection[g];
      if (optIdx == null) return null;
      final opts = _groups[g].options;
      if (optIdx < 0 || optIdx >= opts.length) return null;
      chosen.add(opts[optIdx]);
      siblingOptionsPerChosen.add(opts);
    }
    for (final spec in _specifications) {
      if (_specMatches(spec.name, chosen, siblingOptionsPerChosen)) return spec;
    }
    return null;
  }

  /// A spec matches the chosen labels when EVERY chosen label passes the
  /// precise sibling-masking match ([_specNameMatches]) against the spec name
  /// — each `chosen[i]`'s own group's full option list is passed as its
  /// `siblingOptions` (order-independent, one check per chosen label).
  static bool _specMatches(
    String specName,
    List<String> chosen,
    List<List<String>> siblingOptionsPerChosen,
  ) {
    if (chosen.isEmpty) return false;
    for (var i = 0; i < chosen.length; i++) {
      if (!_specNameMatches(specName, chosen[i], siblingOptionsPerChosen[i])) {
        return false;
      }
    }
    return true;
  }

  /// PURE (testable in isolation): precise sibling-masking matcher — mirrors
  /// iOS `specNameMatches(_:value:siblingOptions:)`
  /// (`DefaultProductSheet.swift:420-426`) / Android `specNameMatches`
  /// (`ProductSheetBehavior.kt:158-161`) line-for-line
  /// (variant-sibling-substring-match-fix-template-flutter,
  /// ui-template-foundation/spec.md 第 1447 行「variant-picker 的 spec 名稱比對」).
  ///
  /// `LBSpec.name`'s multi-group join convention (what separator, if any, the
  /// backend uses to concatenate e.g. a chosen color + a chosen size into one
  /// spec name) has no documented/verified format anywhere in this repo, and
  /// every existing fixture only exercises a single spec-option group — so
  /// this deliberately does NOT assume any separator (unlike splitting `name`
  /// into tokens by a guessed delimiter). Instead it stays substring-based
  /// (like the code this replaces) but first MASKS OUT of `name` any other
  /// option in [siblingOptions] (the full option list of `value`'s OWN group)
  /// that is STRICTLY LONGER than `value` and itself contains `value` as a
  /// substring — e.g. group `[S, XS]`: checking `value == "S"` against
  /// `name == "XS"` first removes the sibling `"XS"` from `name` (leaving
  /// `""`), so the leftover no longer contains `"S"` and the match correctly
  /// fails. Checking `value == "XS"` finds no longer sibling containing
  /// `"XS"` itself, so `name` is used as-is and the match correctly succeeds.
  ///
  /// Known simplification (shared with iOS/Android, not a Flutter-specific
  /// gap): does not attempt to fully disambiguate pathological cases where
  /// the SAME literal string is reused as an option value across two
  /// DIFFERENT groups and also happens to collide as a substring in a spec
  /// name.
  static bool _specNameMatches(
    String name,
    String value,
    List<String> siblingOptions,
  ) {
    final longerSiblings = siblingOptions.where(
      (o) => o != value && o.length > value.length && o.contains(value),
    );
    final masked =
        longerSiblings.fold(name, (acc, sibling) => acc.replaceAll(sibling, ''));
    return masked.contains(value);
  }

  /// PURE (testable in isolation): for EVERY group in [groups], for EVERY
  /// option value in that group, computes whether choosing that value —
  /// together with whatever is CURRENTLY chosen ([selection]) in every OTHER
  /// group — still resolves to at least one `stock > 0` `LBSpec`. Returns one
  /// [LBVariantGroupAvailability] per `groups` entry, IN THE SAME ORDER, each
  /// holding a `List<bool>` parallel to that group's `options`. Mirrors iOS
  /// `DefaultVariantPicker.optionAvailability(groups:selection:specifications:)`
  /// (`DefaultProductSheet.swift:445-464`) / Android
  /// `DefaultVariantPicker.Companion.optionAvailability`
  /// (`ProductSheetBehavior.kt:266-287`) line-for-line. Named `_optionAvailability`
  /// (private, not the bare `optionAvailability` tasks.md's text uses) solely
  /// because Dart — unlike Swift's argument-label overloading or Kotlin's
  /// companion-object namespace — MUST NOT declare an instance member and a
  /// static member with the identical identifier in one class; see the
  /// [DefaultVariantPicker.optionAvailability] getter's doc comment for the
  /// full rationale. This function's PUBLIC name for host/reference-ui/tests
  /// is that instance getter.
  ///
  /// A group's OWN currently-chosen option is NOT held fixed when evaluating
  /// that SAME group's own options — every option in a group (including the
  /// one already selected) is re-checked against the OTHER groups' current
  /// selections only. This means that once a combination becomes invalid
  /// across two dimensions, BOTH groups' conflicting chips report
  /// unavailable, not just the one just tapped — standard cascading-picker
  /// UX. Callers that want a different policy (e.g. never flag the group's
  /// own current selection) can special-case that themselves; this function
  /// reports the full, unfiltered result.
  ///
  /// `groups.isEmpty` (no-spec product) → `[]` (nothing to render).
  static List<LBVariantGroupAvailability> _optionAvailability(
    List<LBVariantGroup> groups,
    Map<int, int> selection,
    List<LBSpec> specifications,
  ) {
    if (groups.isEmpty) return const [];
    return List.generate(groups.length, (gi) {
      final group = groups[gi];
      // Values currently chosen in every OTHER group (this group's own
      // selection is deliberately excluded — see doc comment above).
      final otherChosen = <MapEntry<int, String>>[
        for (var ogi = 0; ogi < groups.length; ogi++)
          if (ogi != gi &&
              selection[ogi] != null &&
              selection[ogi]! >= 0 &&
              selection[ogi]! < groups[ogi].options.length)
            MapEntry(ogi, groups[ogi].options[selection[ogi]!]),
      ];
      final flags = group.options.map((value) {
        final candidates = [...otherChosen, MapEntry(gi, value)];
        return specifications.any((spec) =>
            spec.stock > 0 &&
            candidates.every((c) =>
                _specNameMatches(spec.name, c.value, groups[c.key].options)));
      }).toList();
      return LBVariantGroupAvailability(groupIndex: gi, availableOptions: flags);
    });
  }
}

// ── 3. qty-stepper ─────────────────────────────────────────────────────────────

/// qty-stepper snapshot (`{ qty, min, max }`, D3). Out-of-stock → all 0.
@immutable
class LBQtyState {
  final int qty;
  final int min;
  final int max;
  const LBQtyState({required this.qty, required this.min, required this.max});

  @override
  bool operator ==(Object other) =>
      other is LBQtyState &&
      other.qty == qty &&
      other.min == min &&
      other.max == max;

  @override
  int get hashCode => Object.hash(qty, min, max);
}

/// qty-stepper view-model (D3). `max` = selected spec stock (or product stock);
/// `soldOut == 1` or stock ≤ 0 → `{ qty:0, min:0, max:0 }`; otherwise
/// `min == 1`, `qty` init `min`. `setQty` / `incQty` / `decQty` clamp to
/// `[min, max]`. Switching specs recomputes bounds and re-clamps `qty`.
class DefaultQtyStepper extends ChangeNotifier {
  LBQtyState _state = const LBQtyState(qty: 0, min: 0, max: 0);

  LBQtyState get state => _state;
  int get qty => _state.qty;
  int get min => _state.min;
  int get max => _state.max;

  /// Recompute `min` / `max` from the effective stock + soldOut, then re-clamp
  /// `qty` into the new range (D3). [resetQty] true (a freshly-opened product)
  /// resets `qty` to `min`; false (a spec switch) keeps `qty` but clamps it.
  /// Notifies only on a real change.
  @internal
  void recomputeBounds({
    required int stock,
    required int soldOut,
    bool resetQty = false,
  }) {
    final out = soldOut == 1 || stock <= 0;
    final min = out ? 0 : 1;
    final max = out ? 0 : stock;
    var qty = resetQty ? min : _state.qty;
    if (qty < min) qty = min;
    if (qty > max) qty = max;
    final next = LBQtyState(qty: qty, min: min, max: max);
    if (next == _state) return;
    _state = next;
    notifyListeners();
  }

  /// Host-dismiss clear for the qty-stepper state (flutter-product-sheet-stack-video-switch-reset-template
  /// — parity Android `qtyStepper.clear()` / RN `qtyStepper.clear()`). Resets to
  /// `{ qty: 0, min: 0, max: 0 }` — the same "no product open" state a fresh
  /// [DefaultQtyStepper] starts in. Notifies iff it changed (diff-then-notify, same
  /// idiom as [DefaultProductSheet.clearDetail]).
  void clear() {
    const empty = LBQtyState(qty: 0, min: 0, max: 0);
    if (_state == empty) return;
    _state = empty;
    notifyListeners();
  }

  /// Set `qty`, clamped to `[min, max]`. Notifies only on change.
  void setQty(int value) {
    var v = value;
    if (v < _state.min) v = _state.min;
    if (v > _state.max) v = _state.max;
    if (v == _state.qty) return;
    _state = LBQtyState(qty: v, min: _state.min, max: _state.max);
    notifyListeners();
  }

  /// `qty + 1`, clamped to `max`.
  void incQty() => setQty(_state.qty + 1);

  /// `qty - 1`, clamped to `min`.
  void decQty() => setQty(_state.qty - 1);
}

// ── 4. mini-cart ────────────────────────────────────────────────────────────────

/// mini-cart peek snapshot (`{ productId, name, priceShow, originalPriceShow, soldOut }`, D4).
@immutable
class LBMiniCartPeek {
  final String productId;
  final String name;
  final String priceShow;
  final int soldOut;

  /// 商品圖 URL（rb-flutter-now-introducing parity，問題 9）。預設 '' → 既有呼叫 / demo /
  /// setPeek 仍可建構、placeholder 不變；reference-ui 的 VOD 介紹輪播以 photos.first ?? pic 填入。
  final String pic;

  /// 原價劃線（vod-now-introducing-original-price-template-flutter）比照
  /// `LBProductRecommendation.originalPriceShow` 型別/慣例：非 nullable `String`，`''` = 無原價 —
  /// MUST NOT 比照 `LBProductDetailState.originalPriceShow` 的 `String?` 三態寫法。預設值 `''`
  /// （而非 `required`）是刻意的：`default_template.dart` 兩個既有 `LBMiniCartPeek(...)` 建構呼叫點
  /// （加購成功/去重浮卡）與既有測試皆未帶此欄位——加預設值讓新欄位對既有呼叫端保持加法相容。是否
  /// 畫出劃線價像素屬 reference-ui 版面判斷，本欄位本身不預先過濾或清空。
  final String originalPriceShow;

  const LBMiniCartPeek({
    required this.productId,
    required this.name,
    required this.priceShow,
    required this.soldOut,
    this.pic = '',
    this.originalPriceShow = '',
  });

  @override
  bool operator ==(Object other) =>
      other is LBMiniCartPeek &&
      other.productId == productId &&
      other.name == name &&
      other.priceShow == priceShow &&
      other.soldOut == soldOut &&
      other.pic == pic &&
      other.originalPriceShow == originalPriceShow;

  @override
  int get hashCode =>
      Object.hash(productId, name, priceShow, soldOut, pic, originalPriceShow);
}

/// mini-cart view-model (D4). `peek` = the most recent successfully-added
/// product **ONLY** (minicart-peek-add-only / tmpl-ios-remove-minicart-peek-fallback):
/// the 講解中商品 (`narrate_status == 2`) is shown by the pinned card (LIVE) /
/// now-introducing card (VOD), so the mini-cart peek is NOT seeded from it (that
/// duplicated the same MiniCart component + leaked the VOD-only peek into LIVE).
/// `openDetail` is a host intent forwarded by [DefaultPlayerTemplate];
/// `dismissMiniCart` clears.
class DefaultMiniCart extends ChangeNotifier {
  LBMiniCartPeek? _peek;

  /// Current mini-cart peek, or null when none.
  LBMiniCartPeek? get peek => _peek;

  /// Set the peek (most recent successful add only). Notifies only on change.
  @internal
  void setPeek(LBMiniCartPeek peek) {
    if (peek == _peek) return;
    _peek = peek;
    notifyListeners();
  }

  /// Clear the peek (host dismiss). Notifies iff it cleared something.
  void dismissMiniCart() {
    if (_peek == null) return;
    _peek = null;
    notifyListeners();
  }
}

// ── 5. cart CTA ──────────────────────────────────────────────────────────────────

/// cart CTA snapshot (`{ count }`, D4). per-session count, NOT a real cart.
@immutable
class LBCartCTAState {
  final int count;
  const LBCartCTAState({required this.count});

  @override
  bool operator ==(Object other) => other is LBCartCTAState && other.count == count;

  @override
  int get hashCode => count.hashCode;
}

/// cart-CTA view-model (D4). `count` = this-session successful route-B adds (+1
/// per success). `openCart` is a passthrough intent (host owns checkout); the
/// template maintains NO local persistent cart. Reset per session.
class DefaultCartCTA extends ChangeNotifier {
  int _count = 0;

  /// This-session successful-add count.
  int get count => _count;

  /// One successful route-B add → `count += 1`. Always notifies.
  @internal
  void incrementOnAdd() {
    _count += 1;
    notifyListeners();
  }

  /// Reset the per-session count (teardown / new video, D4 / OQ2). Notifies iff
  /// it changed.
  void resetForSession() {
    if (_count == 0) return;
    _count = 0;
    notifyListeners();
  }
}
