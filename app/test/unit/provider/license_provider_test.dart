import 'dart:typed_data';

import 'package:ed25519_edwards/ed25519_edwards.dart' as ed25519;
import 'package:glide/provider/license_provider.dart';
import 'package:glide/provider/persistence_provider.dart';
import 'package:glide/util/license_key.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:test/test.dart';

import '../../mocks.mocks.dart';
import '../util/license_key_test.dart' show makeKey;

/// A persistence mock that actually remembers the license values.
MockPersistenceService _persistence({int? trialStart, int? maxSeen, String? unlock, String? key}) {
  final p = MockPersistenceService();
  when(p.getLicenseTrialStart()).thenAnswer((_) => trialStart);
  when(p.getLicenseMaxSeen()).thenAnswer((_) => maxSeen);
  when(p.getLicenseUnlock()).thenAnswer((_) => unlock);
  when(p.getLicenseKey()).thenAnswer((_) => key);
  when(p.setLicenseTrialStart(any)).thenAnswer((i) async => trialStart = i.positionalArguments.first as int);
  when(p.setLicenseMaxSeen(any)).thenAnswer((i) async => maxSeen = i.positionalArguments.first as int);
  when(p.setLicenseUnlock(any)).thenAnswer((i) async => unlock = i.positionalArguments.first as String);
  when(p.setLicenseKey(any)).thenAnswer((i) async => key = i.positionalArguments.first as String);
  return p;
}

class _Clock {
  DateTime now;

  _Clock(this.now);
}

final t0 = DateTime(2026, 1, 1, 12);

(RefenaContainer, LicenseNotifier) _container(MockPersistenceService p, _Clock clock, {bool isApple = false, LicenseKeyVerifier? verifier}) {
  final notifier = LicenseNotifier(clock: () => clock.now, isApple: isApple, verifier: verifier);
  final container = RefenaContainer(
    overrides: [
      persistenceProvider.overrideWithValue(p),
      licenseProvider.overrideWithNotifier((ref) => notifier),
    ],
  );
  container.read(licenseProvider); // providers are lazy
  return (container, notifier);
}

void main() {
  group('trial', () {
    test('starts on first launch and lasts 3 days', () {
      final p = _persistence();
      final clock = _Clock(t0);
      final (container, notifier) = _container(p, clock);
      addTearDown(() => container.dispose(licenseProvider));

      expect(container.read(licenseProvider).trialStart, t0);
      verify(p.setLicenseTrialStart(t0.millisecondsSinceEpoch)).called(1);
      expect(notifier.canSendNow(), isTrue);

      clock.now = t0.add(const Duration(days: 3) - const Duration(seconds: 1));
      expect(notifier.canSendNow(), isTrue);
      expect(container.read(licenseProvider).trialRemaining, const Duration(seconds: 1));

      clock.now = t0.add(const Duration(days: 3));
      expect(notifier.canSendNow(), isFalse);
      expect(container.read(licenseProvider).trialActive, isFalse);
    });

    test('keeps an existing trial start', () {
      final p = _persistence(trialStart: t0.millisecondsSinceEpoch);
      final (container, notifier) = _container(p, _Clock(t0.add(const Duration(days: 4))));
      addTearDown(() => container.dispose(licenseProvider));

      expect(container.read(licenseProvider).trialStart, t0);
      expect(notifier.canSendNow(), isFalse);
      verifyNever(p.setLicenseTrialStart(any));
    });

    test('a clock set back does not extend the trial', () {
      final p = _persistence(trialStart: t0.millisecondsSinceEpoch, maxSeen: t0.add(const Duration(days: 5)).millisecondsSinceEpoch);
      final clock = _Clock(t0.add(const Duration(days: 1))); // set back from day 5
      final (container, notifier) = _container(p, clock);
      addTearDown(() => container.dispose(licenseProvider));

      expect(notifier.canSendNow(), isFalse);
      expect(container.read(licenseProvider).now, t0.add(const Duration(days: 5)));
    });

    test('moves the high-water mark forward', () {
      final p = _persistence();
      final clock = _Clock(t0);
      final (container, notifier) = _container(p, clock);
      addTearDown(() => container.dispose(licenseProvider));

      clock.now = t0.add(const Duration(hours: 2));
      notifier.refresh();
      verify(p.setLicenseMaxSeen(clock.now.millisecondsSinceEpoch)).called(1);
    });

    test('Apple: no trial until the store purchase exists', () {
      final p = _persistence();
      final (container, notifier) = _container(p, _Clock(t0), isApple: true);
      addTearDown(() => container.dispose(licenseProvider));

      expect(container.read(licenseProvider).trialStart, isNull);
      expect(notifier.canSendNow(), isFalse);
      verifyNever(p.setLicenseTrialStart(any));
    });
  });

  group('unlock', () {
    test('a stored valid license key overrides an ended trial', () {
      final pair = ed25519.generateKey();
      final verifier = LicenseKeyVerifier(publicKey: Uint8List.fromList(pair.publicKey.bytes));
      final key = makeKey(pair.privateKey, {'v': 1, 'sku': 'glide_full', 'sid': 'cs', 'iat': 1});
      final p = _persistence(trialStart: t0.millisecondsSinceEpoch, unlock: 'licenseKey', key: key);
      final (container, notifier) = _container(p, _Clock(t0.add(const Duration(days: 30))), verifier: verifier);
      addTearDown(() => container.dispose(licenseProvider));

      expect(container.read(licenseProvider).unlock, UnlockSource.licenseKey);
      expect(notifier.canSendNow(), isTrue);
    });

    test('a stored key that no longer verifies does not unlock', () {
      final p = _persistence(trialStart: t0.millisecondsSinceEpoch, unlock: 'licenseKey', key: 'GLIDE-abc.def');
      final (container, notifier) = _container(p, _Clock(t0.add(const Duration(days: 30))));
      addTearDown(() => container.dispose(licenseProvider));

      expect(notifier.canSendNow(), isFalse);
    });

    test('submitLicenseKey unlocks and persists a valid key, rejects an invalid one', () async {
      final pair = ed25519.generateKey();
      final verifier = LicenseKeyVerifier(publicKey: Uint8List.fromList(pair.publicKey.bytes));
      final p = _persistence(trialStart: t0.millisecondsSinceEpoch);
      final (container, notifier) = _container(p, _Clock(t0.add(const Duration(days: 30))), verifier: verifier);
      addTearDown(() => container.dispose(licenseProvider));

      expect(await notifier.submitLicenseKey('nope'), isFalse);
      expect(container.read(licenseProvider).notice, LicenseNotice.invalidKey);
      expect(notifier.canSendNow(), isFalse);

      final key = makeKey(pair.privateKey, {'v': 1, 'sku': 'glide_full', 'sid': 'cs', 'iat': 1});
      expect(await notifier.submitLicenseKey('  $key\n'), isTrue);
      expect(notifier.canSendNow(), isTrue);
      verify(p.setLicenseKey(key)).called(1);
      verify(p.setLicenseUnlock('licenseKey')).called(1);
    });

    test('Apple: purchases of the trial and the full version', () async {
      final p = _persistence();
      final clock = _Clock(t0.add(const Duration(days: 10)));
      final (container, notifier) = _container(p, clock, isApple: true);
      addTearDown(() => container.dispose(licenseProvider));

      final trialDate = t0.add(const Duration(days: 9)).millisecondsSinceEpoch;
      await notifier.handlePurchases([_purchase(glideTrialProductId, trialDate)]);
      expect(container.read(licenseProvider).trialStart, DateTime.fromMillisecondsSinceEpoch(trialDate));
      expect(notifier.canSendNow(), isTrue); // day 1 of the trial

      clock.now = t0.add(const Duration(days: 13));
      expect(notifier.canSendNow(), isFalse);

      // Unknown products are ignored.
      await notifier.handlePurchases([_purchase('something_else', trialDate)]);
      expect(notifier.canSendNow(), isFalse);

      await notifier.handlePurchases([_purchase(glideFullProductId, trialDate)]);
      expect(notifier.canSendNow(), isTrue);
      verify(p.setLicenseUnlock('iap')).called(1);
    });
  });
}

PurchaseDetails _purchase(String productId, int date) {
  return PurchaseDetails(
    productID: productId,
    verificationData: PurchaseVerificationData(localVerificationData: '', serverVerificationData: '', source: 'app_store'),
    transactionDate: date.toString(),
    status: PurchaseStatus.purchased,
  );
}
