import 'dart:convert';
import 'dart:typed_data';

import 'package:ed25519_edwards/ed25519_edwards.dart' as ed25519;
import 'package:glide/util/license_key.dart';
import 'package:test/test.dart';

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

String makeKey(ed25519.PrivateKey privateKey, Map<String, Object?> payload) {
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
  return 'GLIDE-${_b64(bytes)}.${_b64(ed25519.sign(privateKey, bytes))}';
}

void main() {
  final pair = ed25519.generateKey();
  final verifier = LicenseKeyVerifier(publicKey: Uint8List.fromList(pair.publicKey.bytes));
  final payload = {'v': 1, 'sku': 'glide_full', 'sid': 'cs_test_123', 'iat': 1795040842};

  test('accepts a valid key', () {
    final result = verifier.verify(makeKey(pair.privateKey, payload));
    expect(result, isNotNull);
    expect(result!.sku, 'glide_full');
    expect(result.sessionId, 'cs_test_123');
    expect(result.issuedAt.millisecondsSinceEpoch, 1795040842 * 1000);
  });

  test('trims whitespace and line breaks from pasted keys', () {
    final key = makeKey(pair.privateKey, payload);
    expect(verifier.verify('  \n${key.substring(0, 20)}\r\n${key.substring(20)}\n '), isNotNull);
  });

  test('rejects a tampered payload', () {
    final key = makeKey(pair.privateKey, payload);
    final other = makeKey(pair.privateKey, {...payload, 'sid': 'cs_test_999'});
    final tampered = '${other.split('.').first}.${key.split('.').last}';
    expect(verifier.verify(tampered), isNull);
  });

  test('rejects a key signed by another private key', () {
    final other = ed25519.generateKey();
    expect(verifier.verify(makeKey(other.privateKey, payload)), isNull);
  });

  test('rejects a wrong sku or version', () {
    expect(verifier.verify(makeKey(pair.privateKey, {...payload, 'sku': 'other'})), isNull);
    expect(verifier.verify(makeKey(pair.privateKey, {...payload, 'v': 2})), isNull);
  });

  test('rejects garbage', () {
    for (final key in ['', 'GLIDE-', 'GLIDE-abc', 'GLIDE-abc.def', 'GLIDE-!!!.???', 'hello world', 'GLIDE-a.b.c']) {
      expect(verifier.verify(key), isNull, reason: key);
    }
    expect(verifier.verify(makeKey(pair.privateKey, payload).replaceFirst('GLIDE-', 'OTHER-')), isNull);
  });

  test('the embedded public key is a valid 32 byte key', () {
    expect(base64.decode(glideLicensePublicKeyBase64).length, ed25519.PublicKeySize);
    expect(LicenseKeyVerifier().verify('GLIDE-abc.def'), isNull);
  });
}
