import 'package:in_app_purchase/in_app_purchase.dart';

/// Thin wrapper around the `in_app_purchase` plugin (App Store on iOS and macOS), so the license logic can be tested without a store.
abstract class AppStoreGateway {
  Stream<List<PurchaseDetails>> get purchaseStream;

  Future<bool> isAvailable();

  Future<ProductDetailsResponse> queryProducts(Set<String> ids);

  /// Starts the purchase flow. The result arrives on [purchaseStream].
  Future<bool> buy(ProductDetails product);

  /// Asks the store to re-deliver past purchases on [purchaseStream].
  Future<void> restore();

  Future<void> complete(PurchaseDetails purchase);
}

class InAppPurchaseGateway implements AppStoreGateway {
  // Only touched on Apple platforms, the plugin has no other implementation here.
  final InAppPurchase _iap = InAppPurchase.instance;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;

  @override
  Future<bool> isAvailable() => _iap.isAvailable();

  @override
  Future<ProductDetailsResponse> queryProducts(Set<String> ids) => _iap.queryProductDetails(ids);

  // Both non-consumables (free trial and full version) go through this call.
  @override
  Future<bool> buy(ProductDetails product) => _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));

  @override
  Future<void> restore() => _iap.restorePurchases();

  @override
  Future<void> complete(PurchaseDetails purchase) => _iap.completePurchase(purchase);
}
