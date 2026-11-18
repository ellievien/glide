import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:glide/provider/license_store.dart';
import 'package:glide/provider/persistence_provider.dart';
import 'package:glide/util/license_key.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';

final _logger = Logger('License');

/// Length of the free trial.
const glideTrialDuration = Duration(days: 3);

/// App Store product ids (iOS and macOS).
/// [glideTrialProductId]: free Non-Consumable. The trial starts at the purchase date (the original one on restore).
/// [glideFullProductId]: Non-Consumable, the Full Version.
const glideTrialProductId = 'glide_free_trial';
const glideFullProductId = 'glide_full';

/// Stripe payment link used outside the App Store. After paying, the website shows a license key.
/// This is the test link, swap it for the live one.
const glideStripeCheckoutUrl = 'https://buy.stripe.com/test_eVq6oGgXLeSY0vi7AWaR201';

enum UnlockSource { iap, licenseKey }

/// One-shot messages for the paywall, translated by the UI.
enum LicenseNotice { storeUnavailable, productsUnavailable, purchaseFailed, nothingToRestore, restored, invalidKey }

class LicenseState {
  /// The clock the state was computed with (never goes backwards, see [LicenseNotifier]).
  final DateTime now;
  final DateTime? trialStart;
  final UnlockSource? unlock;

  /// Only meaningful on Apple platforms.
  final bool storeAvailable;
  final String? trialPrice;
  final String? fullPrice;
  final bool busy;
  final LicenseNotice? notice;

  const LicenseState({
    required this.now,
    required this.trialStart,
    required this.unlock,
    this.storeAvailable = true,
    this.trialPrice,
    this.fullPrice,
    this.busy = false,
    this.notice,
  });

  bool get isUnlocked => unlock != null;

  bool get trialUsed => trialStart != null;

  DateTime? get trialEnd => trialStart?.add(glideTrialDuration);

  bool get trialActive => trialEnd != null && now.isBefore(trialEnd!);

  Duration get trialRemaining => trialActive ? trialEnd!.difference(now) : Duration.zero;

  /// Only sending is locked. Receiving is always free.
  bool get canSend => isUnlocked || trialActive;

  LicenseState copyWith({
    DateTime? now,
    DateTime? trialStart,
    UnlockSource? unlock,
    bool? storeAvailable,
    String? trialPrice,
    String? fullPrice,
    bool? busy,
    LicenseNotice? notice,
    bool clearNotice = false,
  }) {
    return LicenseState(
      now: now ?? this.now,
      trialStart: trialStart ?? this.trialStart,
      unlock: unlock ?? this.unlock,
      storeAvailable: storeAvailable ?? this.storeAvailable,
      trialPrice: trialPrice ?? this.trialPrice,
      fullPrice: fullPrice ?? this.fullPrice,
      busy: busy ?? this.busy,
      notice: clearNotice ? null : (notice ?? this.notice),
    );
  }
}

/// Trial and Full Version state. Only sending is gated by it ([LicenseNotifier.canSendNow]).
final licenseProvider = NotifierProvider<LicenseNotifier, LicenseState>((ref) => LicenseNotifier());

class LicenseNotifier extends Notifier<LicenseState> {
  final DateTime Function() _clock;
  final LicenseKeyVerifier _verifier;
  final bool _isApple;
  final AppStoreGateway Function() _gatewayFactory;
  final Duration _restoreWait;

  AppStoreGateway? _gateway;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  Timer? _ticker;
  bool _restoredSomething = false;

  /// All parameters are for tests.
  LicenseNotifier({
    DateTime Function()? clock,
    LicenseKeyVerifier? verifier,
    bool? isApple,
    AppStoreGateway Function()? gatewayFactory,
    Duration restoreWait = const Duration(seconds: 6),
  }) : _clock = clock ?? DateTime.now,
       _verifier = verifier ?? LicenseKeyVerifier(),
       _isApple = isApple ?? (!kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS)),
       _gatewayFactory = gatewayFactory ?? InAppPurchaseGateway.new,
       _restoreWait = restoreWait;

  /// Apple platforms sell through the App Store only: no trial without the store purchase, no license keys, no Stripe.
  bool get isApple => _isApple;

  @override
  LicenseState init() {
    final persistence = ref.read(persistenceProvider);
    final now = _effectiveNow();

    DateTime? trialStart;
    final storedStart = persistence.getLicenseTrialStart();
    if (storedStart != null) {
      trialStart = DateTime.fromMillisecondsSinceEpoch(storedStart);
    } else if (!_isApple) {
      // Starts on the first launch (for installs that predate the license: the first launch of this version).
      trialStart = now;
      unawaited(persistence.setLicenseTrialStart(now.millisecondsSinceEpoch));
    }

    UnlockSource? unlock;
    switch (persistence.getLicenseUnlock()) {
      case 'iap':
        unlock = _isApple ? UnlockSource.iap : null;
      case 'licenseKey':
        // Verified again on every start.
        final key = persistence.getLicenseKey();
        if (!_isApple && key != null && _verifier.verify(key) != null) {
          unlock = UnlockSource.licenseKey;
        }
    }

    return LicenseState(now: now, trialStart: trialStart, unlock: unlock, storeAvailable: !_isApple);
  }

  @override
  void postInit() {
    super.postInit();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) => refresh());
    if (_isApple) {
      unawaited(_initStore());
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_purchaseSubscription?.cancel());
    super.dispose();
  }

  /// Reads the clock again. The returned time never goes back: if the clock was set back, the latest time seen so far is used.
  DateTime _effectiveNow() {
    final persistence = ref.read(persistenceProvider);
    final raw = _clock();
    final maxSeenMillis = persistence.getLicenseMaxSeen();
    final maxSeen = maxSeenMillis == null ? null : DateTime.fromMillisecondsSinceEpoch(maxSeenMillis);
    if (maxSeen != null && raw.isBefore(maxSeen)) {
      return maxSeen;
    }
    // Written at most once per minute.
    if (maxSeen == null || raw.difference(maxSeen) >= const Duration(minutes: 1)) {
      unawaited(persistence.setLicenseMaxSeen(raw.millisecondsSinceEpoch));
    }
    return raw;
  }

  void refresh() {
    state = state.copyWith(now: _effectiveNow());
  }

  /// The check used before every send. Always looks at the current clock.
  bool canSendNow() {
    refresh();
    return state.canSend;
  }

  void clearNotice() {
    state = state.copyWith(clearNotice: true);
  }

  /// Unlocks with a license key pasted by the user (not on Apple platforms). Returns whether the key was valid.
  Future<bool> submitLicenseKey(String key) async {
    if (_isApple || _verifier.verify(key) == null) {
      state = state.copyWith(notice: LicenseNotice.invalidKey);
      return false;
    }
    final persistence = ref.read(persistenceProvider);
    await persistence.setLicenseKey(key.replaceAll(RegExp(r'\s+'), ''));
    await persistence.setLicenseUnlock('licenseKey');
    state = state.copyWith(unlock: UnlockSource.licenseKey, clearNotice: true);
    return true;
  }

  // ---- App Store (iOS, macOS) ----

  Future<void> _initStore() async {
    try {
      final gateway = _gateway = _gatewayFactory();
      // Listening from the start: pending purchases are delivered right away and must be completed.
      _purchaseSubscription = gateway.purchaseStream.listen(_onPurchases, onError: (Object e) => _logger.warning('Purchase stream error', e));
      await _loadProducts(gateway);
    } catch (e, st) {
      _logger.warning('Could not initialize the store', e, st);
      state = state.copyWith(storeAvailable: false);
    }
  }

  Future<void> _loadProducts(AppStoreGateway gateway) async {
    if (!await gateway.isAvailable()) {
      state = state.copyWith(storeAvailable: false);
      return;
    }
    final response = await gateway.queryProducts({glideTrialProductId, glideFullProductId});
    state = state.copyWith(
      storeAvailable: true,
      trialPrice: response.productDetails.where((p) => p.id == glideTrialProductId).firstOrNull?.price,
      fullPrice: response.productDetails.where((p) => p.id == glideFullProductId).firstOrNull?.price,
    );
  }

  /// Starts the free trial (a purchase of the free non-consumable).
  Future<void> startTrial() => _buy(glideTrialProductId);

  /// Buys the Full Version.
  Future<void> buyFull() => _buy(glideFullProductId);

  Future<void> _buy(String productId) async {
    final gateway = _gateway;
    if (!_isApple || gateway == null || !state.storeAvailable) {
      state = state.copyWith(notice: LicenseNotice.storeUnavailable);
      return;
    }
    if (state.busy) {
      return;
    }
    state = state.copyWith(busy: true, clearNotice: true);
    try {
      final response = await gateway.queryProducts({productId});
      final product = response.productDetails.where((p) => p.id == productId).firstOrNull;
      if (product == null) {
        state = state.copyWith(busy: false, notice: LicenseNotice.productsUnavailable);
        return;
      }
      final started = await gateway.buy(product);
      if (!started) {
        state = state.copyWith(busy: false, notice: LicenseNotice.purchaseFailed);
      }
      // Otherwise the result arrives on the purchase stream.
    } catch (e, st) {
      _logger.warning('Purchase of $productId failed to start', e, st);
      state = state.copyWith(busy: false, notice: LicenseNotice.storeUnavailable);
    }
  }

  /// Re-delivers earlier purchases (trial start date and Full Version) on this Apple ID.
  Future<void> restorePurchases() async {
    final gateway = _gateway;
    if (!_isApple || gateway == null || !state.storeAvailable) {
      state = state.copyWith(notice: LicenseNotice.storeUnavailable);
      return;
    }
    if (state.busy) {
      return;
    }
    _restoredSomething = false;
    state = state.copyWith(busy: true, clearNotice: true);
    try {
      await gateway.restore();
      // The store only answers through the stream, and stays silent if there is nothing to restore.
      await Future<void>.delayed(_restoreWait);
      if (state.busy) {
        state = state.copyWith(busy: false, notice: _restoredSomething ? LicenseNotice.restored : LicenseNotice.nothingToRestore);
      }
    } catch (e, st) {
      _logger.warning('Restoring purchases failed', e, st);
      state = state.copyWith(busy: false, notice: LicenseNotice.storeUnavailable);
    }
  }

  @visibleForTesting
  Future<void> handlePurchases(List<PurchaseDetails> purchases) => _onPurchases(purchases);

  /// The date the purchase was originally made: a restored purchase carries the restore time as its own date.
  DateTime _purchaseDate(PurchaseDetails purchase) {
    var millis = int.tryParse(purchase.transactionDate ?? '');
    if (purchase is AppStorePurchaseDetails) {
      final original = purchase.skPaymentTransaction.originalTransaction?.transactionTimeStamp;
      if (original != null) {
        millis = (original * 1000).toInt();
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(millis ?? _clock().millisecondsSinceEpoch);
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    final persistence = ref.read(persistenceProvider);
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          state = state.copyWith(busy: true);
        case PurchaseStatus.canceled:
          state = state.copyWith(busy: false);
        case PurchaseStatus.error:
          _logger.warning('Purchase error: ${purchase.error?.message}');
          state = state.copyWith(busy: false, notice: LicenseNotice.purchaseFailed);
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (purchase.productID == glideFullProductId) {
            await persistence.setLicenseUnlock('iap');
            _restoredSomething = true;
            state = state.copyWith(unlock: UnlockSource.iap, busy: false, clearNotice: true);
          } else if (purchase.productID == glideTrialProductId) {
            final date = _purchaseDate(purchase);
            final existing = state.trialStart;
            // The earliest trial purchase counts, so reinstalling does not restart the trial.
            final start = existing != null && existing.isBefore(date) ? existing : date;
            await persistence.setLicenseTrialStart(start.millisecondsSinceEpoch);
            _restoredSomething = true;
            state = state.copyWith(trialStart: start, busy: false, clearNotice: true);
          } else {
            _logger.warning('Ignoring purchase of unknown product ${purchase.productID}');
          }
      }
      if (purchase.pendingCompletePurchase) {
        try {
          await _gateway?.complete(purchase);
        } catch (e, st) {
          _logger.warning('Could not complete purchase', e, st);
        }
      }
    }
    refresh();
  }
}
