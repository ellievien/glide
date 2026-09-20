// Home (§3.1): the discovery radar. This is the Glide app's new entry point,
// replacing the legacy tab-based HomePage (see main.dart).
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:glide/config/glide_tokens.dart';
import 'package:glide/config/init.dart';
import 'package:glide/gen/strings.g.dart';
import 'package:glide/model/cross_file.dart';
import 'package:glide/model/persistence/device_visibility.dart';
import 'package:glide/pages/glide/glide_device_list_page.dart';
import 'package:glide/pages/glide/glide_rename_dialog.dart';
import 'package:glide/pages/glide/glide_settings_page.dart';
import 'package:glide/provider/animation_provider.dart';
import 'package:glide/provider/device_visibility_provider.dart';
import 'package:glide/provider/local_ip_provider.dart';
import 'package:glide/provider/network/nearby_devices_provider.dart';
import 'package:glide/provider/network/scan_facade.dart';
import 'package:glide/provider/network/send_provider.dart';
import 'package:glide/provider/selection/selected_sending_files_provider.dart';
import 'package:glide/provider/settings_provider.dart';
import 'package:glide/util/glide/glide_naming.dart';
import 'package:glide/util/native/cross_file_converters.dart';
import 'package:glide/util/native/file_picker.dart';
import 'package:glide/widget/glide/glide_brand.dart';
import 'package:glide/widget/glide/glide_components.dart';
import 'package:glide/widget/glide/glide_icon.dart';
import 'package:glide/widget/glide/glide_tap_target.dart';
import 'package:glide/widget/glide/glide_transfer_widgets.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

const _maxRadarNodes = 8;

/// Static ring diameters and opacities (inner -> outer), §3.1.
const _ringDiameters = [90.0, 170.0, 250.0, 330.0, 410.0];
const _ringOpacities = [0.16, 0.13, 0.11, 0.09, 0.07];

class GlideHomePage extends StatefulWidget {
  /// It is important for the initializing step because the first init
  /// clears the cache.
  final bool appStart;

  const GlideHomePage({required this.appStart, super.key});

  @override
  State<GlideHomePage> createState() => _GlideHomePageState();
}

class _GlideHomePageState extends State<GlideHomePage> with Refena {
  bool _dragIndicator = false;

  /// How often discovery is re-run while nothing has been found yet.
  static const _rescanInterval = Duration(seconds: 5);

  /// Once devices are known, re-scan no more often than this.
  static const _idleRescanInterval = Duration(seconds: 20);

  Timer? _rescanTimer;
  AppLifecycleListener? _lifecycleListener;
  DateTime? _lastScan;
  bool _scanning = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(onResume: () => unawaited(_rescan()));
    ensureRef((ref) async {
      await postInit(context, ref, widget.appStart);
      _ready = true;
      await _rescan();
      _rescanTimer = Timer.periodic(_rescanInterval, (_) => unawaited(_rescan()));
    });
  }

  /// Re-runs discovery on a timer and whenever the app returns to the
  /// foreground, rather than once when the page opens.
  ///
  /// Multicast is the only mechanism that pushes a late-joining device into an
  /// already-open list, and it is unavailable on iOS (see [StartSmartScan]).
  /// Without repeating the http scan, a device that comes online after the
  /// first scan stays invisible until the page is reopened -- which reads to
  /// the user as "the two devices cannot see each other".
  Future<void> _rescan() async {
    if (!_ready || _scanning || !mounted) {
      return;
    }

    // Scanning every few seconds is only worth it while the radar is empty.
    final lastScan = _lastScan;
    if (lastScan != null && ref.read(nearbyDevicesProvider).allDevices.isNotEmpty && DateTime.now().difference(lastScan) < _idleRescanInterval) {
      return;
    }

    _scanning = true;
    _lastScan = DateTime.now();
    try {
      await ref.global.dispatchAsync(StartSmartScan());
    } catch (e) {
      // A scan that fails (no interface up yet, permission not granted) must
      // not prevent the following ones from running.
    } finally {
      _scanning = false;
    }
  }

  @override
  void dispose() {
    _rescanTimer?.cancel();
    _lifecycleListener?.dispose();
    super.dispose();
  }

  Future<void> _onDeviceTap(Device device) async {
    var files = ref.read(selectedSendingFilesProvider);
    if (files.isEmpty) {
      await ref.global.dispatchAsync(PickFileAction(option: FilePickerOption.file, context: context));
    }
    files = ref.read(selectedSendingFilesProvider);
    if (files.isEmpty || !mounted) {
      return;
    }
    await ref.notifier(sendProvider).startSession(target: device, files: files, background: false);
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(nearbyDevicesProvider.select((s) => s.allDevices)).values.toList();
    final alias = ref.watch(settingsProvider.select((s) => s.alias));
    final visibility = ref.watch(deviceVisibilityProvider);
    final network = ref.watch(localIpProvider);
    final offline = network.initialized && network.localIps.isEmpty;
    final queuedFiles = ref.watch(selectedSendingFilesProvider);
    final reduceMotion = !ref.watch(animationProvider) || MediaQuery.of(context).disableAnimations;

    final String headline;
    final Widget subtext;
    if (offline) {
      headline = t.glide.home.offlineHeadline;
      subtext = Padding(
        padding: const EdgeInsets.only(top: 8),
        child: GestureDetector(
          onTap: () async {
            try {
              await openAppSettings();
            } catch (_) {
              // Not supported on this platform (e.g. desktop); nothing to do.
            }
          },
          child: Text(
            t.glide.home.openSystemSettings,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: GT.blue),
          ),
        ),
      );
    } else if (devices.isEmpty) {
      headline = t.glide.home.headline;
      subtext = Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t.glide.home.emptySubtext,
              style: GT.secondary,
              textAlign: TextAlign.center,
            ),
            // On iOS every connection to a local address is gated behind the
            // "Local Network" permission and the system only ever asks once.
            // If that prompt was dismissed, discovery silently finds nothing
            // and there is no in-app way back, so offer the route to Settings.
            if (Platform.isIOS)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: GestureDetector(
                  onTap: () async {
                    try {
                      await openAppSettings();
                    } catch (_) {
                      // Nothing to open on this platform.
                    }
                  },
                  child: Text(
                    t.glide.home.openSystemSettings,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: GT.blue),
                  ),
                ),
              ),
          ],
        ),
      );
    } else {
      headline = t.glide.home.headline;
      subtext = Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          t.glide.home.subtext,
          style: GT.secondary,
          textAlign: TextAlign.center,
        ),
      );
    }

    final pillDot = visibility == DeviceVisibility.hidden ? GT.textFaint : GT.blue;

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragIndicator = true),
      onDragExited: (_) => setState(() => _dragIndicator = false),
      onDragDone: (event) async {
        setState(() => _dragIndicator = false);
        final droppedDirectories = event.files.where((file) => Directory(file.path).existsSync()).toList();
        final droppedFiles = event.files.where((file) => !Directory(file.path).existsSync()).toList();
        for (final directory in droppedDirectories) {
          await ref.redux(selectedSendingFilesProvider).dispatchAsync(AddDirectoryAction(directory.path));
        }
        if (droppedFiles.isNotEmpty) {
          await ref
              .redux(selectedSendingFilesProvider)
              .dispatchAsync(AddFilesAction(files: droppedFiles, converter: CrossFileConverters.convertXFile));
        }
      },
      child: Scaffold(
        backgroundColor: GT.bg,
        body: Stack(
          children: [
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: GT.desktopMaxWidth),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, GT.topBarPaddingTopHome, 24, 0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const GlideWordmark(height: 24),
                            GlideTopBarButton(
                              icon: GlideIconAsset.sliders,
                              semanticLabel: t.general.settings,
                              onTap: () async => context.push(() => const GlideSettingsPage()),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(30, 30, 30, 0),
                        child: Column(
                          children: [
                            Text(headline, style: GT.hero, textAlign: TextAlign.center),
                            subtext,
                          ],
                        ),
                      ),
                      Expanded(
                        child: _Radar(
                          devices: devices,
                          offline: offline,
                          reduceMotion: reduceMotion,
                          queuedFiles: queuedFiles,
                          onDeviceTap: _onDeviceTap,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
                        child: Column(
                          children: [
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Text(t.glide.home.knownAs, style: GT.caption),
                                _IdentityChip(alias: alias),
                              ],
                            ),
                            const SizedBox(height: 14),
                            GlideStatusPill(
                              label: visibility.pillLabel,
                              dotColor: pillDot,
                              onTap: () async => context.push(() => const GlideSettingsPage()),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_dragIndicator)
              Positioned.fill(
                child: ColoredBox(
                  color: GT.bg.withValues(alpha: 0.94),
                  child: Center(
                    child: Text(t.glide.home.dropToQueue, style: GT.hero, textAlign: TextAlign.center),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _IdentityChip extends StatelessWidget {
  final String alias;

  const _IdentityChip({required this.alias});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 5, 6, 5),
      decoration: BoxDecoration(
        color: GT.surface,
        border: Border.all(color: GT.border),
        borderRadius: BorderRadius.circular(GT.radiusPill),
        boxShadow: GT.shadowIconButton,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              alias,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: GT.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          GlideTapTarget(
            visualSize: 24,
            semanticLabel: t.glide.common.renameDevice,
            onTap: () async => showDialog(context: context, builder: (_) => const GlideRenameDialog()),
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(color: GT.neutralTint, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const GlideIcon(GlideIconAsset.pencil, size: 12, color: GT.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// The radar: static rings, ping rings, the center badge and device nodes,
/// laid out per the dynamic placement rule (§3.1).
class _Radar extends StatefulWidget {
  final List<Device> devices;
  final bool offline;
  final bool reduceMotion;
  final List<CrossFile> queuedFiles;
  final Future<void> Function(Device device) onDeviceTap;

  const _Radar({
    required this.devices,
    required this.offline,
    required this.reduceMotion,
    required this.queuedFiles,
    required this.onDeviceTap,
  });

  @override
  State<_Radar> createState() => _RadarState();
}

class _RadarState extends State<_Radar> with SingleTickerProviderStateMixin {
  late final AnimationController _pingController = AnimationController(vsync: this, duration: const Duration(milliseconds: 3400));

  /// Fingerprints in stable, append-only order (kept briefly after a device
  /// disappears so [GlideDeviceNode] can fade it out in place).
  final List<String> _order = [];
  final Map<String, Device> _known = {};
  final Map<String, Offset> _lastOffset = {};
  final Set<String> _removing = {};

  @override
  void initState() {
    super.initState();
    if (!widget.reduceMotion) {
      unawaited(_pingController.repeat());
    }
    _sync();
  }

  @override
  void didUpdateWidget(covariant _Radar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion != oldWidget.reduceMotion) {
      if (widget.reduceMotion) {
        _pingController.stop();
      } else {
        unawaited(_pingController.repeat());
      }
    }
    _sync();
  }

  void _sync() {
    final liveKeys = widget.devices.map((d) => d.fingerprint).toSet();
    for (final device in widget.devices) {
      _known[device.fingerprint] = device;
      if (!_order.contains(device.fingerprint)) {
        _order.add(device.fingerprint);
      }
    }
    for (final key in _order.where((k) => !liveKeys.contains(k)).toList()) {
      if (_removing.contains(key)) {
        continue;
      }
      _removing.add(key);
      Future.delayed(const Duration(milliseconds: 220), () {
        if (mounted) {
          setState(() {
            _order.remove(key);
            _removing.remove(key);
            _known.remove(key);
            _lastOffset.remove(key);
          });
        }
      });
    }
  }

  int get _visibleCount {
    final liveCount = widget.devices.length > _maxRadarNodes ? _maxRadarNodes : widget.devices.length;
    return liveCount == 0 ? 1 : liveCount;
  }

  Offset _position(int index) {
    final angleDeg = 90 + index * (360 / _visibleCount);
    final angleRad = angleDeg * (math.pi / 180);
    final r = index.isEven ? 160.0 : 172.0;
    return Offset(r * math.cos(angleRad), r * math.sin(angleRad));
  }

  String? _queuedLabel(Device device) {
    if (widget.queuedFiles.isEmpty) {
      return null;
    }
    final fileNoun = widget.queuedFiles.length == 1 ? widget.queuedFiles.first.name : '${widget.queuedFiles.length} files';
    return t.glide.home.sendFileTo(file: fileNoun, device: shortDeviceName(device.alias));
  }

  @override
  Widget build(BuildContext context) {
    final ringOpacityScale = widget.offline ? 0.5 : 1.0;

    // Cap at 8 visible slots: 7 devices + 1 "+N" overflow node.
    final overflowCount = widget.devices.length > _maxRadarNodes ? widget.devices.length - (_maxRadarNodes - 1) : 0;
    final liveNodeDevices = overflowCount > 0 ? widget.devices.take(_maxRadarNodes - 1).toList() : widget.devices;

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        for (var i = 0; i < _ringDiameters.length; i++)
          Opacity(
            opacity: _ringOpacities[i] * ringOpacityScale,
            child: Container(
              width: _ringDiameters[i],
              height: _ringDiameters[i],
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: GT.blue, width: 1),
              ),
            ),
          ),
        if (!widget.offline && !widget.reduceMotion) ...[
          _PingRing(controller: _pingController, phase: 0),
          _PingRing(controller: _pingController, phase: 0.5),
        ],
        for (final key in _order)
          if (_known[key] != null)
            Builder(
              key: ValueKey(key),
              builder: (context) {
                final device = _known[key]!;
                final liveIndex = liveNodeDevices.indexWhere((d) => d.fingerprint == key);
                final isLive = liveIndex != -1 && !_removing.contains(key);
                final offset = isLive ? _position(liveIndex) : (_lastOffset[key] ?? Offset.zero);
                if (isLive) {
                  _lastOffset[key] = offset;
                }
                return Transform.translate(
                  offset: offset,
                  child: GlideDeviceNode(
                    key: ValueKey('node-$key'),
                    deviceType: device.deviceType,
                    deviceModel: device.deviceModel,
                    label: shortDeviceName(device.alias),
                    visible: isLive,
                    reduceMotion: widget.reduceMotion,
                    semanticLabel: _queuedLabel(device),
                    onTap: () => widget.onDeviceTap(device),
                  ),
                );
              },
            ),
        if (overflowCount > 0)
          Transform.translate(
            offset: _position(_maxRadarNodes - 1),
            child: _OverflowNode(count: overflowCount, devices: widget.devices, onDeviceTap: widget.onDeviceTap),
          ),
        if (!widget.offline)
          const GlideCenterBadge(offline: false, symbol: GlideSymbol(width: 38))
        else
          const GlideCenterBadge(offline: true, symbol: SizedBox.shrink()),
      ],
    );
  }

  @override
  void dispose() {
    _pingController.dispose();
    super.dispose();
  }
}

class _PingRing extends StatelessWidget {
  final AnimationController controller;
  final double phase;

  const _PingRing({required this.controller, required this.phase});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = (controller.value + phase) % 1.0;
        final eased = Curves.easeOut.transform(t);
        final scale = 0.22 + (1.0 - 0.22) * eased;
        double opacity;
        if (t < 0.7) {
          opacity = 0.45 + (0.10 - 0.45) * (t / 0.7);
        } else {
          opacity = 0.10 - 0.10 * ((t - 0.7) / 0.3);
        }
        return IgnorePointer(
          child: Opacity(
            opacity: opacity.clamp(0, 1),
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: 410,
                height: 410,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: GT.blue, width: 1.5),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OverflowNode extends StatelessWidget {
  final int count;
  final List<Device> devices;
  final Future<void> Function(Device device) onDeviceTap;

  const _OverflowNode({required this.count, required this.devices, required this.onDeviceTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: t.glide.home.moreDevices(count: count),
      child: GestureDetector(
        onTap: () async => context.push(() => GlideDeviceListPage(devices: devices, onDeviceTap: onDeviceTap)),
        child: ExcludeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: GT.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: GT.border),
                  boxShadow: GT.shadowNode,
                ),
                alignment: Alignment.center,
                child: Text(
                  '+$count',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: GT.blue),
                ),
              ),
              const SizedBox(height: 6),
              Text(t.glide.home.more, style: GT.nodeLabel),
            ],
          ),
        ),
      ),
    );
  }
}
