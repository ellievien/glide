import 'dart:convert';
import 'dart:typed_data';

import 'package:glide/model/state/nearby_devices_state.dart';
import 'package:glide/provider/network/nearby/nearby_protocol.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:test/test.dart';

void main() {
  group('NearbyPeerInfo', () {
    test('round-trips through bytes', () {
      const info = NearbyPeerInfo(
        version: nearbyProtocolVersion,
        alias: 'Swift Otter',
        fingerprint: 'ABCDEF0123456789',
        deviceModel: 'Pixel 9',
        deviceType: DeviceType.mobile,
        port: 53317,
        https: true,
        wifi: NearbyWifiCapabilities(canHost: true, canJoin: true),
      );

      final decoded = NearbyPeerInfo.fromBytes(info.toBytes());

      expect(decoded.version, nearbyProtocolVersion);
      expect(decoded.alias, 'Swift Otter');
      expect(decoded.fingerprint, 'ABCDEF0123456789');
      expect(decoded.deviceModel, 'Pixel 9');
      expect(decoded.deviceType, DeviceType.mobile);
      expect(decoded.port, 53317);
      expect(decoded.https, isTrue);
      expect(decoded.wifi, const NearbyWifiCapabilities(canHost: true, canJoin: true));
    });

    test('stays small enough for a single long read', () {
      const info = NearbyPeerInfo(
        version: nearbyProtocolVersion,
        alias: 'A rather long device name for testing',
        fingerprint: '0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF',
        deviceModel: 'MacBook Pro',
        deviceType: DeviceType.desktop,
        port: 53317,
        https: true,
        wifi: NearbyWifiCapabilities(canHost: false, canJoin: true),
      );

      // ATT values are limited to 512 bytes.
      expect(info.toBytes().length, lessThan(512));
    });

    test('rejects payloads without a fingerprint or with an invalid port', () {
      expect(() => NearbyPeerInfo.fromBytes(utf8.encode('{"v":1,"a":"x","p":1}')), throwsFormatException);
      expect(() => NearbyPeerInfo.fromBytes(utf8.encode('{"v":1,"a":"x","f":"F","p":70000}')), throwsFormatException);
      expect(() => NearbyPeerInfo.fromBytes(utf8.encode('not json')), throwsFormatException);
      expect(() => NearbyPeerInfo.fromBytes([0xff, 0xfe]), throwsFormatException);
    });

    test('falls back to desktop for unknown device types', () {
      final info = NearbyPeerInfo.fromBytes(utf8.encode('{"v":2,"a":"x","f":"F","t":"toaster","p":1}'));
      expect(info.deviceType, DeviceType.desktop);
      expect(info.wifi, NearbyWifiCapabilities.none);
    });
  });

  group('NearbyRequest / NearbyResponse', () {
    test('requests round-trip', () {
      const join = NearbyJoinRequest(fingerprint: 'F', alias: 'A', ssid: 'DIRECT-ab-Glide', passphrase: 'secret123', hostIp: '192.168.49.1');
      final decodedJoin = NearbyRequest.fromBytes(join.toBytes()) as NearbyJoinRequest;
      expect(decodedJoin.ssid, 'DIRECT-ab-Glide');
      expect(decodedJoin.passphrase, 'secret123');
      expect(decodedJoin.hostIp, '192.168.49.1');

      final decodedHost = NearbyRequest.fromBytes(const NearbyHostRequest(fingerprint: 'F', alias: 'A').toBytes()) as NearbyHostRequest;
      expect(decodedHost.fingerprint, 'F');
      expect(decodedHost.alias, 'A');

      final decodedEnd = NearbyRequest.fromBytes(const NearbyEndRequest(fingerprint: 'F').toBytes()) as NearbyEndRequest;
      expect(decodedEnd.fingerprint, 'F');
      expect(() => NearbyRequest.fromBytes(utf8.encode('{"op":"format"}')), throwsFormatException);
    });

    test('responses round-trip', () {
      const hosting = NearbyHostingResponse(ssid: 'DIRECT-ab-Glide', passphrase: 'secret123', ip: '192.168.49.1', port: 53317, https: true);
      final decodedHosting = NearbyResponse.fromBytes(hosting.toBytes()) as NearbyHostingResponse;
      expect(decodedHosting.ssid, hosting.ssid);
      expect(decodedHosting.passphrase, hosting.passphrase);
      expect(decodedHosting.ip, hosting.ip);
      expect(decodedHosting.port, hosting.port);
      expect(decodedHosting.https, isTrue);

      final decodedJoined = NearbyResponse.fromBytes(const NearbyJoinedResponse(ip: '192.168.49.23', port: 53317, https: false).toBytes());
      expect((decodedJoined as NearbyJoinedResponse).ip, '192.168.49.23');
      expect(decodedJoined.https, isFalse);

      expect(NearbyResponse.fromBytes(const NearbyIdleResponse().toBytes()), isA<NearbyIdleResponse>());
      expect(NearbyResponse.fromBytes(const NearbyPendingResponse().toBytes()), isA<NearbyPendingResponse>());
      expect(NearbyResponse.fromBytes(const NearbyEndedResponse().toBytes()), isA<NearbyEndedResponse>());
      expect((NearbyResponse.fromBytes(const NearbyErrorResponse('nope').toBytes()) as NearbyErrorResponse).message, 'nope');
    });
  });

  group('decideWifiHost', () {
    const android = NearbyWifiCapabilities(canHost: true, canJoin: true);
    const joinOnly = NearbyWifiCapabilities(canHost: false, canJoin: true);

    test('prefers the receiver as host', () {
      expect(decideWifiHost(sender: android, receiver: android), NearbyWifiHost.receiver);
      expect(decideWifiHost(sender: joinOnly, receiver: android), NearbyWifiHost.receiver);
    });

    test('lets the sender host when the receiver can only join', () {
      expect(decideWifiHost(sender: android, receiver: joinOnly), NearbyWifiHost.sender);
    });

    test('gives up when nobody can host', () {
      expect(decideWifiHost(sender: joinOnly, receiver: joinOnly), isNull);
      expect(decideWifiHost(sender: NearbyWifiCapabilities.none, receiver: android), isNull);
    });
  });

  group('frames', () {
    test('a payload survives framing at any frame size', () {
      final payload = Uint8List.fromList(List.generate(300, (i) => i % 251));
      for (final size in [2, 20, 182, 512]) {
        final frames = encodeFrames(payload, size);
        expect(frames.every((f) => f.length <= size), isTrue, reason: 'frame size $size');
        final assembler = FrameAssembler();
        Uint8List? result;
        for (final frame in frames) {
          expect(result, isNull, reason: 'completed before the last frame');
          result = assembler.add(frame);
        }
        expect(result, payload, reason: 'frame size $size');
      }
    });

    test('an empty payload is one frame', () {
      final frames = encodeFrames(const [], 20);
      expect(frames, hasLength(1));
      expect(FrameAssembler().add(frames.single), isEmpty);
    });

    test('a new first frame discards an interrupted payload', () {
      final assembler = FrameAssembler();
      final first = encodeFrames(List.filled(50, 1), 20);
      assembler.add(first[0]);
      final second = encodeFrames([7, 8, 9], 20);
      expect(assembler.add(second.single), [7, 8, 9]);
    });

    test('rejects continuation frames without a start and oversized payloads', () {
      expect(() => FrameAssembler().add([0x00, 1, 2]), throwsFormatException);
      expect(() => FrameAssembler().add(const []), throwsFormatException);
      expect(() => encodeFrames(List.filled(nearbyMaxPayloadSize + 1, 0), 20), throwsArgumentError);

      final assembler = FrameAssembler()..add([0x01, ...List.filled(nearbyMaxPayloadSize, 0)]);
      expect(() => assembler.add([0x00, 1]), throwsFormatException);
    });
  });

  test('isSameIpv4Subnet24', () {
    expect(isSameIpv4Subnet24('192.168.49.23', '192.168.49.1'), isTrue);
    expect(isSameIpv4Subnet24('192.168.1.23', '192.168.49.1'), isFalse);
    expect(isSameIpv4Subnet24('fe80::1', '192.168.49.1'), isFalse);
  });

  group('NearbyDevicesState.allDevices', () {
    Device device({String? ip, required List<DeviceChannel> channels}) => Device(
      signalingId: null,
      ip: ip,
      version: '2.1',
      port: 53317,
      https: true,
      fingerprint: 'F',
      alias: 'Phone',
      deviceModel: null,
      deviceType: DeviceType.mobile,
      download: false,
      channels: channels,
    );

    const bluetooth = BluetoothChannel(bleId: 'AA:BB', canHost: true, canJoin: true);
    const http = HttpChannel(host: '10.0.0.2', port: 53317, https: true);

    test('lists a device found only over Bluetooth', () {
      final state = NearbyDevicesState(
        runningFavoriteScan: false,
        runningIps: const {},
        devices: const {},
        signalingDevices: const {},
        bluetoothDevices: {
          'F': device(channels: const [bluetooth]),
        },
      );
      final listed = state.allDevices['F']!;
      expect(listed.ip, isNull);
      expect(listed.transmissionMethods, {TransmissionMethod.bluetooth});
    });

    test('keeps the address of a device that is also on this network', () {
      final state = NearbyDevicesState(
        runningFavoriteScan: false,
        runningIps: const {},
        devices: {
          'F': device(ip: '10.0.0.2', channels: const [http]),
        },
        signalingDevices: const {},
        bluetoothDevices: {
          'F': device(channels: const [bluetooth]),
        },
      );
      final listed = state.allDevices['F']!;
      expect(listed.ip, '10.0.0.2');
      expect(listed.channels, [http, bluetooth]);
    });
  });
}
