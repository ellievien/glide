import 'package:dart_mappable/dart_mappable.dart';
import 'package:localsend_isolates/model/device.dart';

part 'nearby_devices_state.mapper.dart';

@MappableClass()
class NearbyDevicesState with NearbyDevicesStateMappable {
  final bool runningFavoriteScan;
  final Set<String> runningIps; // list of local ips
  final Map<String, Device> devices; // fingerprint -> device

  /// Devices that are discovered via signaling server.
  /// The key is the fingerprint of the device.
  /// We do not trust the fingerprint, so we allow multiple devices with the same fingerprint.
  final Map<String, Set<Device>> signalingDevices;

  /// Devices found over Bluetooth Low Energy (not necessarily on this network).
  /// The key is the fingerprint the device claims; the HTTP client verifies it
  /// against the TLS certificate once the temporary network is up.
  final Map<String, Device> bluetoothDevices;

  const NearbyDevicesState({
    required this.runningFavoriteScan,
    required this.runningIps,
    required this.devices,
    required this.signalingDevices,
    required this.bluetoothDevices,
  });

  Map<String, Device> get allDevices {
    final Map<String, Device> allDevices = {};
    allDevices.addAll(devices);
    for (final device in bluetoothDevices.values) {
      final currentDevice = allDevices[device.fingerprint];
      // A device on this network keeps its address and gains the Bluetooth
      // channel as a fallback for when it is no longer reachable here.
      allDevices[device.fingerprint] = currentDevice != null ? currentDevice.merge(device) : device;
    }
    for (final devices in signalingDevices.values) {
      for (final device in devices) {
        final currentDevice = allDevices[device.fingerprint];
        if (currentDevice != null && currentDevice.alias == device.alias) {
          allDevices[device.fingerprint] = currentDevice.merge(device);
        } else {
          allDevices[device.fingerprint] = device;
        }
      }
    }
    return allDevices;
  }
}

extension on Device {
  Device merge(Device other) {
    return Device(
      signalingId: signalingId ?? other.signalingId,
      ip: ip ?? other.ip,
      version: version,
      port: port,
      https: https,
      fingerprint: fingerprint,
      alias: alias,
      deviceModel: deviceModel,
      deviceType: deviceType,
      download: download,
      channels: [
        ...channels,
        for (final channel in other.channels)
          if (!channels.contains(channel)) channel,
      ],
    );
  }
}
