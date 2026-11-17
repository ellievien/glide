// The receiving side of Nearby discovery: a GATT server with the info and
// control characteristics, plus an advertisement of its service UUID.
//
// universal_ble provides this on Android, iOS, macOS and Windows. It has no
// peripheral mode on Linux, where it is implemented here directly against
// BlueZ over D-Bus (GattManager1 + LEAdvertisingManager1).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:dbus/dbus.dart';
import 'package:glide/provider/network/nearby/nearby_protocol.dart';
import 'package:logging/logging.dart';
import 'package:universal_ble/universal_ble.dart';

final _logger = Logger('NearbyPeripheral');

/// Returns the full value of [characteristicUuid] for the central
/// [centralId], or `null` for an unknown characteristic.
typedef NearbyReadHandler = Uint8List? Function(String centralId, String characteristicUuid);

/// Receives one write of [value] to [characteristicUuid] from [centralId].
typedef NearbyWriteHandler = void Function(String centralId, String characteristicUuid, Uint8List value);

abstract class NearbyPeripheral {
  /// Registers the GATT service and starts advertising it.
  /// Returns `false` when this device cannot act as a BLE peripheral.
  Future<bool> start({required NearbyReadHandler onRead, required NearbyWriteHandler onWrite});

  Future<void> stop();

  factory NearbyPeripheral.forPlatform() => Platform.isLinux ? BlueZNearbyPeripheral() : _UniversalBleNearbyPeripheral();
}

class _UniversalBleNearbyPeripheral implements NearbyPeripheral {
  @override
  Future<bool> start({required NearbyReadHandler onRead, required NearbyWriteHandler onWrite}) async {
    final capabilities = await UniversalBlePeripheral.getCapabilities();
    if (!capabilities.supportsPeripheralMode) {
      _logger.info('This device cannot act as a BLE peripheral; it can find others but cannot be found.');
      return false;
    }
    final readiness = await UniversalBlePeripheral.getAvailabilityState();
    if (readiness != PeripheralReadinessState.ready) {
      _logger.info('BLE peripheral not ready: $readiness');
      return false;
    }
    UniversalBlePeripheral.setReadRequestHandlers((deviceId, characteristicId, offset, value) {
      final result = onRead(deviceId, BleUuidParser.string(characteristicId));
      return result == null ? null : PeripheralReadRequestResult(value: result);
    });
    UniversalBlePeripheral.setWriteRequestHandlers((deviceId, characteristicId, offset, value) {
      if (value == null) {
        return null;
      }
      onWrite(deviceId, BleUuidParser.string(characteristicId), value);
      return PeripheralWriteRequestResult();
    });
    await UniversalBlePeripheral.clearServices();
    await UniversalBlePeripheral.addService(
      BlePeripheralService(
        uuid: nearbyServiceUuid,
        characteristics: [
          BlePeripheralCharacteristic(
            uuid: nearbyInfoCharacteristicUuid,
            properties: [CharacteristicProperty.read],
            permissions: [PeripheralAttributePermission.readable],
          ),
          BlePeripheralCharacteristic(
            uuid: nearbyControlCharacteristicUuid,
            properties: [CharacteristicProperty.read, CharacteristicProperty.write],
            permissions: [PeripheralAttributePermission.readable, PeripheralAttributePermission.writeable],
          ),
        ],
      ),
    );
    // No local name: on Android it would rename the system Bluetooth device.
    await UniversalBlePeripheral.startAdvertising(services: [nearbyServiceUuid]);
    return true;
  }

  @override
  Future<void> stop() async {
    await UniversalBlePeripheral.stopAdvertising();
    await UniversalBlePeripheral.clearServices();
  }
}

/// Linux: a BlueZ GATT application and LE advertisement exported on the
/// system bus. [client] is injectable for tests.
class BlueZNearbyPeripheral implements NearbyPeripheral {
  static const _bluezName = 'org.bluez';
  static const _basePath = '/org/glideapp/glide/nearby';

  final DBusClient Function() _clientFactory;

  DBusClient? _client;
  DBusObjectPath? _adapter;
  List<DBusObject> _objects = const [];

  BlueZNearbyPeripheral({DBusClient Function()? clientFactory}) : _clientFactory = clientFactory ?? DBusClient.system;

  static final applicationPath = DBusObjectPath('$_basePath/gatt');
  static final advertisementPath = DBusObjectPath('$_basePath/advertisement0');

  @override
  Future<bool> start({required NearbyReadHandler onRead, required NearbyWriteHandler onWrite}) async {
    await stop();
    final client = _clientFactory();
    _client = client;
    try {
      final adapter = await _findAdapter(client);
      if (adapter == null) {
        _logger.info('No BlueZ adapter supports GATT servers and LE advertising');
        await stop();
        return false;
      }
      _adapter = adapter;

      final application = DBusObject(applicationPath, isObjectManager: true);
      final servicePath = DBusObjectPath('${applicationPath.value}/service0');
      final service = _GattService(servicePath, nearbyServiceUuid);
      final info = _GattCharacteristic(
        DBusObjectPath('${servicePath.value}/char0'),
        uuid: nearbyInfoCharacteristicUuid,
        service: servicePath,
        flags: const ['read'],
        onRead: onRead,
        onWrite: onWrite,
      );
      final control = _GattCharacteristic(
        DBusObjectPath('${servicePath.value}/char1'),
        uuid: nearbyControlCharacteristicUuid,
        service: servicePath,
        flags: const ['read', 'write'],
        onRead: onRead,
        onWrite: onWrite,
      );
      final advertisement = _LeAdvertisement(advertisementPath, serviceUuids: const [nearbyServiceUuid]);
      _objects = [application, service, info, control, advertisement];
      for (final object in _objects) {
        await client.registerObject(object);
      }

      await client.callMethod(
        destination: _bluezName,
        path: adapter,
        interface: 'org.bluez.GattManager1',
        name: 'RegisterApplication',
        values: [applicationPath, DBusDict.stringVariant({})],
        replySignature: DBusSignature.empty,
      );
      await client.callMethod(
        destination: _bluezName,
        path: adapter,
        interface: 'org.bluez.LEAdvertisingManager1',
        name: 'RegisterAdvertisement',
        values: [advertisementPath, DBusDict.stringVariant({})],
        replySignature: DBusSignature.empty,
      );
      _logger.info('Advertising over BLE through BlueZ (${adapter.value})');
      return true;
    } catch (e) {
      _logger.warning('BlueZ peripheral failed to start', e);
      await stop();
      return false;
    }
  }

  @override
  Future<void> stop() async {
    final client = _client;
    if (client == null) {
      return;
    }
    _client = null;
    final adapter = _adapter;
    _adapter = null;
    if (adapter != null) {
      for (final (interface, method, path) in [
        ('org.bluez.LEAdvertisingManager1', 'UnregisterAdvertisement', advertisementPath),
        ('org.bluez.GattManager1', 'UnregisterApplication', applicationPath),
      ]) {
        try {
          await client.callMethod(
            destination: _bluezName,
            path: adapter,
            interface: interface,
            name: method,
            values: [path],
            replySignature: DBusSignature.empty,
          );
        } catch (e) {
          // Not registered (anymore), e.g. after bluetoothd restarted.
          _logger.fine('$method failed', e);
        }
      }
    }
    _objects = const [];
    await client.close();
  }

  /// The first adapter that can serve GATT and advertise.
  static Future<DBusObjectPath?> _findAdapter(DBusClient client) async {
    final manager = DBusRemoteObjectManager(client, name: _bluezName, path: DBusObjectPath('/'));
    final objects = await manager.getManagedObjects();
    return objects.entries
        .where((e) => e.value.containsKey('org.bluez.GattManager1') && e.value.containsKey('org.bluez.LEAdvertisingManager1'))
        .map((e) => e.key)
        .sorted((a, b) => a.value.compareTo(b.value))
        .firstOrNull;
  }
}

class _GattService extends DBusObject {
  final String uuid;

  _GattService(super.path, this.uuid);

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
    'org.bluez.GattService1': {
      'UUID': DBusString(uuid),
      'Primary': const DBusBoolean(true),
    },
  };

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async => DBusGetAllPropertiesResponse(interfacesAndProperties[interface] ?? {});
}

class _GattCharacteristic extends DBusObject {
  static const _interface = 'org.bluez.GattCharacteristic1';

  final String uuid;
  final DBusObjectPath service;
  final List<String> flags;
  final NearbyReadHandler onRead;
  final NearbyWriteHandler onWrite;

  _GattCharacteristic(
    super.path, {
    required this.uuid,
    required this.service,
    required this.flags,
    required this.onRead,
    required this.onWrite,
  });

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {
    _interface: {
      'UUID': DBusString(uuid),
      'Service': service,
      'Flags': DBusArray.string(flags),
    },
  };

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async => DBusGetAllPropertiesResponse(interfacesAndProperties[interface] ?? {});

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != _interface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    switch (methodCall.name) {
      case 'ReadValue':
        if (methodCall.signature != DBusSignature('a{sv}')) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        final options = methodCall.values[0].asStringVariantDict();
        final value = onRead(_central(options), uuid);
        if (value == null) {
          return DBusMethodErrorResponse('org.bluez.Error.NotPermitted');
        }
        // BlueZ reads long values in pieces, passing where to continue.
        final offset = options['offset']?.asUint16() ?? 0;
        if (offset > value.length) {
          return DBusMethodErrorResponse('org.bluez.Error.InvalidOffset');
        }
        return DBusMethodSuccessResponse([DBusArray.byte(value.sublist(offset))]);
      case 'WriteValue':
        if (!flags.contains('write') || methodCall.signature != DBusSignature('aya{sv}')) {
          return DBusMethodErrorResponse('org.bluez.Error.NotPermitted');
        }
        final value = Uint8List.fromList(methodCall.values[0].asByteArray().toList());
        final options = methodCall.values[1].asStringVariantDict();
        onWrite(_central(options), uuid, value);
        return DBusMethodSuccessResponse();
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }

  /// The central's device object, e.g. /org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF.
  static String _central(Map<String, DBusValue> options) => options['device']?.asObjectPath().value ?? 'unknown';
}

class _LeAdvertisement extends DBusObject {
  static const _interface = 'org.bluez.LEAdvertisement1';

  final List<String> serviceUuids;

  _LeAdvertisement(super.path, {required this.serviceUuids});

  Map<String, DBusValue> get _properties => {
    'Type': const DBusString('peripheral'),
    'ServiceUUIDs': DBusArray.string(serviceUuids),
  };

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => {_interface: _properties};

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async => DBusGetAllPropertiesResponse(interface == _interface ? _properties : {});

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final value = interface == _interface ? _properties[name] : null;
    return value == null ? DBusMethodErrorResponse.unknownProperty() : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface == _interface && methodCall.name == 'Release') {
      // BlueZ dropped the advertisement (e.g. the adapter went away).
      return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.unknownMethod();
  }
}
