import 'dart:convert';
import 'dart:typed_data';

import 'package:ed25519_edwards/ed25519_edwards.dart' as ed25519;

/// SKU of the paid "Full Version".
const glideFullSku = 'glide_full';

/// Raw 32 byte Ed25519 public key (base64) the license keys are signed with.
const glideLicensePublicKeyBase64 = 'IXonFM6QSFvEz0888tIz64h6VmW8Yw0joPyCzWYEvTE=';

const _keyPrefix = 'GLIDE-';

/// The signed content of a license key.
class LicensePayload {
  final int version;
  final String sku;
  final String sessionId;
  final DateTime issuedAt;

  const LicensePayload({required this.version, required this.sku, required this.sessionId, required this.issuedAt});
}

/// Offline verification of license keys:
/// `GLIDE-` + base64url(payload JSON) + `.` + base64url(Ed25519 signature over the payload bytes), both without padding.
class LicenseKeyVerifier {
  final ed25519.PublicKey _publicKey;

  /// [publicKey] is only meant to be overridden by tests.
  LicenseKeyVerifier({Uint8List? publicKey}) : _publicKey = ed25519.PublicKey(publicKey ?? base64.decode(glideLicensePublicKeyBase64));

  /// Returns the payload if [key] is a valid license key for the Full Version, otherwise `null`.
  LicensePayload? verify(String key) {
    try {
      // Pasted keys often carry whitespace or line breaks.
      final trimmed = key.replaceAll(RegExp(r'\s+'), '');
      if (!trimmed.startsWith(_keyPrefix)) {
        return null;
      }
      final parts = trimmed.substring(_keyPrefix.length).split('.');
      if (parts.length != 2) {
        return null;
      }
      final payloadBytes = _decode(parts[0]);
      final signature = _decode(parts[1]);
      if (signature.length != ed25519.SignatureSize || !ed25519.verify(_publicKey, payloadBytes, signature)) {
        return null;
      }

      final json = jsonDecode(utf8.decode(payloadBytes));
      if (json is! Map<String, dynamic> || json['v'] != 1 || json['sku'] != glideFullSku) {
        return null;
      }
      final sid = json['sid'];
      final iat = json['iat'];
      return LicensePayload(
        version: 1,
        sku: glideFullSku,
        sessionId: sid is String ? sid : '',
        issuedAt: DateTime.fromMillisecondsSinceEpoch(iat is int ? iat * 1000 : 0, isUtc: true),
      );
    } catch (_) {
      return null;
    }
  }

  static Uint8List _decode(String s) => base64Url.decode(base64Url.normalize(s));
}
