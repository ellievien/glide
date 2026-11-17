import 'dart:io';
import 'dart:typed_data';

import 'package:dbus/dbus.dart';
import 'package:glide/provider/network/nearby/nearby_peripheral.dart';
import 'package:glide/provider/network/nearby/nearby_protocol.dart';
import 'package:test/test.dart';

/// Plays bluetoothd: an adapter with GattManager1 and LEAdvertisingManager1
/// that, like BlueZ, reads the application back when it is registered.
class _FakeAdapter extends DBusObject {
  final DBusClient bluez;
  final calls = <String>[];
  Map<DBusObjectPath, Map<String, Map<String, DBusValue>>>? application;
  Map<String, DBusValue>? advertisement;
  String? appOwner;

  _FakeAdapter(this.bluez) : super(DBusObjectPath('/org/bluez/hci0'));

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
    'org.bluez.Adapter1': {'Powered': const DBusBoolean(true)},
    'org.bluez.GattManager1': {},
    'org.bluez.LEAdvertisingManager1': {},
  };

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    calls.add('${methodCall.interface}.${methodCall.name}');
    final path = methodCall.values[0].asObjectPath();
    switch (methodCall.name) {
      case 'RegisterApplication':
        appOwner = methodCall.sender;
        application = await DBusRemoteObjectManager(bluez, name: methodCall.sender!, path: path).getManagedObjects();
      case 'RegisterAdvertisement':
        advertisement = await DBusRemoteObject(bluez, name: methodCall.sender!, path: path).getAllProperties('org.bluez.LEAdvertisement1');
    }
    return DBusMethodSuccessResponse();
  }
}

void main() {
  late Directory tempDir;
  late DBusServer server;
  late DBusAddress address;
  late DBusClient bluez;
  late _FakeAdapter adapter;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('glide-bluez-test');
    server = DBusServer();
    address = await server.listenAddress(DBusAddress.unix(dir: tempDir));
    bluez = DBusClient(address);
    await bluez.requestName('org.bluez');
    adapter = _FakeAdapter(bluez);
    await bluez.registerObject(DBusObject(DBusObjectPath('/'), isObjectManager: true));
    await bluez.registerObject(adapter);
  });

  tearDown(() async {
    await bluez.close();
    await server.close();
    await tempDir.delete(recursive: true);
  });

  test('registers a GATT application and advertisement that BlueZ can use', () async {
    final info = Uint8List.fromList(List.generate(300, (i) => i % 256));
    final writes = <(String, String, List<int>)>[];
    final peripheral = BlueZNearbyPeripheral(clientFactory: () => DBusClient(address));

    final started = await peripheral.start(
      onRead: (central, uuid) => uuid == nearbyInfoCharacteristicUuid ? info : Uint8List.fromList([1, 2, 3]),
      onWrite: (central, uuid, value) => writes.add((central, uuid, value)),
    );
    expect(started, isTrue);
    expect(adapter.calls, ['org.bluez.GattManager1.RegisterApplication', 'org.bluez.LEAdvertisingManager1.RegisterAdvertisement']);

    // The application as BlueZ sees it.
    final objects = adapter.application!;
    final services = objects.values.where((o) => o.containsKey('org.bluez.GattService1')).toList();
    expect(services, hasLength(1));
    expect(services.single['org.bluez.GattService1']!['UUID'], const DBusString(nearbyServiceUuid));
    final characteristics = {
      for (final entry in objects.entries)
        if (entry.value['org.bluez.GattCharacteristic1'] case final c?) (c['UUID']! as DBusString).value: (entry.key, c),
    };
    expect(characteristics.keys, unorderedEquals([nearbyInfoCharacteristicUuid, nearbyControlCharacteristicUuid]));
    expect(characteristics[nearbyInfoCharacteristicUuid]!.$2['Flags']!.asStringArray(), ['read']);
    expect(characteristics[nearbyControlCharacteristicUuid]!.$2['Flags']!.asStringArray(), ['read', 'write']);

    expect(adapter.advertisement!['Type'], const DBusString('peripheral'));
    expect(adapter.advertisement!['ServiceUUIDs']!.asStringArray(), [nearbyServiceUuid]);

    // Reads, including the follow-up read of a long value at an offset.
    final infoPath = characteristics[nearbyInfoCharacteristicUuid]!.$1;
    final central = DBusObjectPath('/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF');
    Future<List<int>> read(DBusObjectPath path, int offset) async {
      final response = await bluez.callMethod(
        destination: adapter.appOwner,
        path: path,
        interface: 'org.bluez.GattCharacteristic1',
        name: 'ReadValue',
        values: [
          DBusDict.stringVariant({'device': central, 'offset': DBusUint16(offset)}),
        ],
        replySignature: DBusSignature('ay'),
      );
      return response.values.single.asByteArray().toList();
    }

    expect(await read(infoPath, 0), info);
    expect(await read(infoPath, 200), info.sublist(200));

    // A write to the control characteristic reaches the handler with the central.
    final controlPath = characteristics[nearbyControlCharacteristicUuid]!.$1;
    await bluez.callMethod(
      destination: adapter.appOwner,
      path: controlPath,
      interface: 'org.bluez.GattCharacteristic1',
      name: 'WriteValue',
      values: [
        DBusArray.byte([7, 8, 9]),
        DBusDict.stringVariant({'device': central}),
      ],
      replySignature: DBusSignature.empty,
    );
    expect(writes, hasLength(1));
    expect(writes.single.$1, central.value);
    expect(writes.single.$2, nearbyControlCharacteristicUuid);
    expect(writes.single.$3, [7, 8, 9]);

    // The info characteristic is read-only.
    await expectLater(
      bluez.callMethod(
        destination: adapter.appOwner,
        path: infoPath,
        interface: 'org.bluez.GattCharacteristic1',
        name: 'WriteValue',
        values: [
          DBusArray.byte([1]),
          DBusDict.stringVariant({}),
        ],
      ),
      throwsA(isA<DBusMethodResponseException>()),
    );

    await peripheral.stop();
    expect(adapter.calls.skip(2), ['org.bluez.LEAdvertisingManager1.UnregisterAdvertisement', 'org.bluez.GattManager1.UnregisterApplication']);
  });

  test('reports no peripheral when no adapter can advertise', () async {
    await bluez.unregisterObject(adapter);
    final peripheral = BlueZNearbyPeripheral(clientFactory: () => DBusClient(address));
    expect(await peripheral.start(onRead: (_, _) => null, onWrite: (_, _, _) {}), isFalse);
  });
}
