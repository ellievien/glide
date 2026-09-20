// Sending / Receiving progress (§3.2). One screen mirrored for both
// directions, matching `ProgressPage`'s constructor so it is a drop-in
// replacement at every push site (send_provider.dart, receive_controller.dart).
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:glide/config/glide_tokens.dart';
import 'package:glide/gen/strings.g.dart';
import 'package:glide/model/state/server/receive_session_state.dart';
import 'package:glide/pages/glide/glide_home_page.dart';
import 'package:glide/pages/glide/glide_landed_page.dart';
import 'package:glide/provider/animation_provider.dart';
import 'package:glide/provider/device_info_provider.dart';
import 'package:glide/provider/favorites_provider.dart';
import 'package:glide/provider/file_transfer_provider.dart';
import 'package:glide/provider/network/send_provider.dart';
import 'package:glide/provider/network/server/server_provider.dart';
import 'package:glide/provider/send_history_provider.dart';
import 'package:glide/util/favorites.dart';
import 'package:glide/util/glide/glide_naming.dart';
import 'package:glide/widget/dialogs/cancel_session_dialog.dart';
import 'package:glide/widget/glide/glide_components.dart';
import 'package:glide/widget/glide/glide_icon.dart';
import 'package:glide/widget/glide/glide_transfer_widgets.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/dto/file_dto.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:localsend_isolates/util/file_size_helper.dart';
import 'package:localsend_isolates/util/file_speed_helper.dart';
import 'package:path/path.dart' as p;
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

const _terminalStatuses = {
  SessionStatus.finished,
  SessionStatus.finishedWithErrors,
  SessionStatus.declined,
  SessionStatus.recipientBusy,
  SessionStatus.tooManyAttempts,
  SessionStatus.canceledBySender,
  SessionStatus.canceledByReceiver,
};

class GlideSendingPage extends StatefulWidget {
  /// Kept for API compatibility with the call sites this replaces
  /// (`ProgressPage`/`SendPage`); the Glide screen always draws its own top
  /// bar, so this has no visual effect.
  final bool showAppBar;
  final bool closeSessionOnClose;
  final String sessionId;

  const GlideSendingPage({required this.showAppBar, required this.closeSessionOnClose, required this.sessionId, super.key});

  @override
  State<GlideSendingPage> createState() => _GlideSendingPageState();
}

class _GlideSendingPageState extends State<GlideSendingPage> with Refena {
  List<FileDto> _files = [];
  int _totalBytes = 0;
  int _lastRemainingUpdate = 0;
  int? _remainingSeconds;
  SessionStatus? _navigatedFor;
  Timer? _cycleTimer;
  int _cycleIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final receiveSession = ref.read(serverProvider)?.session;
      final sendSession = ref.read(sendProvider)[widget.sessionId];
      setState(() {
        if (receiveSession != null) {
          _files = receiveSession.files.values.map((f) => f.file).toList();
        } else if (sendSession != null) {
          _files = sendSession.files.values.map((f) => f.file).toList();
        }
        _totalBytes = _files.fold(0, (prev, curr) => prev + curr.size);
      });
      if (_files.length > 1) {
        _cycleTimer = Timer.periodic(const Duration(milliseconds: 2600), (_) {
          if (mounted) {
            setState(() => _cycleIndex = (_cycleIndex + 1) % _files.length);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _cycleTimer?.cancel();
    super.dispose();
  }

  void _cancel(SessionStatus? status) {
    final receiveSession = ref.read(serverProvider)?.session;
    if (receiveSession != null) {
      if (receiveSession.status == SessionStatus.sending) {
        ref.notifier(serverProvider).cancelSession();
      } else {
        ref.notifier(serverProvider).closeSession();
      }
      return;
    }
    if (status == SessionStatus.sending) {
      ref.notifier(sendProvider).cancelSession(widget.sessionId);
    } else {
      ref.notifier(sendProvider).closeSession(widget.sessionId);
    }
  }

  Future<void> _onCancelPressed(SessionStatus? status) async {
    if (status == SessionStatus.sending) {
      final result = await context.pushBottomSheet(() => const CancelSessionDialog());
      if (result != true) {
        return;
      }
    }
    _cancel(status);
    if (mounted) {
      context.global.dispatch(NavigateAction.popUntilRoot());
    }
  }

  String _failureReason(SessionStatus status, String otherLabel) {
    switch (status) {
      case SessionStatus.declined:
        return t.glide.sending.declinedOn(device: otherLabel);
      case SessionStatus.recipientBusy:
        return t.glide.sending.busy(device: otherLabel);
      case SessionStatus.tooManyAttempts:
        return t.glide.sending.tooManyAttempts;
      case SessionStatus.canceledBySender:
      case SessionStatus.canceledByReceiver:
        return t.glide.sending.canceled;
      case SessionStatus.waiting:
      case SessionStatus.sending:
      case SessionStatus.finished:
      case SessionStatus.finishedWithErrors:
        return t.glide.common.connectionLost;
    }
  }

  void _navigateToResult({
    required bool receiving,
    required SessionStatus status,
    required int? startTime,
    required int? endTime,
    required Device otherDevice,
    required String otherAlias,
    required String? filePath,
  }) {
    if (_navigatedFor == status) {
      return;
    }
    _navigatedFor = status;

    final success = status == SessionStatus.finished;
    final otherLabel = shortDeviceName(otherAlias);
    final fileLabel = _files.length == 1 ? _files.first.fileName : '${_files.length} files';
    final durationSeconds = (startTime != null && endTime != null) ? (endTime - startTime) / 1000 : null;
    final reason = success ? null : _failureReason(status, otherLabel);
    final myDeviceType = ref.read(deviceFullInfoProvider).deviceType;
    final myDeviceModel = ref.read(deviceFullInfoProvider).deviceModel;

    // Deferred to after this build: dispatching (a state write) or navigating
    // synchronously from within build() is not safe.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      // Close the now-terminal session. For a fully successful *send*, this
      // also clears `selectedSendingFilesProvider` (see closeSession); for a
      // failed send, the files stay selected so "Try again" can re-send them.
      if (receiving) {
        ref.notifier(serverProvider).closeSession();
      } else {
        ref.notifier(sendProvider).closeSession(widget.sessionId);
      }
      if (!receiving) {
        // Persist send history (receive history is already written by receive_controller.dart).
        unawaited(
          ref
              .redux(sendHistoryProvider)
              .dispatchAsync(
                AddSendHistoryEntryAction(
                  entryId: '${widget.sessionId}-${DateTime.now().microsecondsSinceEpoch}',
                  fileName: fileLabel,
                  fileType: _files.isNotEmpty ? _files.first.fileType : FileType.other,
                  fileSize: _totalBytes,
                  targetAlias: otherLabel,
                  timestamp: DateTime.now().toUtc(),
                  success: success,
                  failureReason: reason,
                ),
              ),
        );
      }
      unawaited(
        Routerino.context.pushAndRemoveUntilImmediately(
          removeUntil: GlideHomePage,
          builder: () => GlideLandedPage(
            receiving: receiving,
            success: success,
            thisDeviceLabel: thisDeviceLabel(),
            thisDeviceType: myDeviceType,
            thisDeviceModel: myDeviceModel,
            otherDevice: otherDevice,
            otherDeviceLabel: otherLabel,
            fileLabel: fileLabel,
            sizeLabel: _totalBytes.asReadableFileSize,
            durationSeconds: durationSeconds,
            failureReason: reason,
            filePath: filePath,
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final receiveSession = ref.watch(serverProvider)?.session;
    final sendSession = ref.watch(sendProvider)[widget.sessionId];
    final receiving = receiveSession != null;
    final SessionState? common = receiveSession ?? sendSession;

    if (common == null) {
      return const ColoredBox(color: GT.bg);
    }

    final status = common.status;
    final myDeviceType = ref.watch(deviceFullInfoProvider).deviceType;
    final myDeviceModel = ref.watch(deviceFullInfoProvider).deviceModel;
    final otherDevice = receiving ? receiveSession.sender : sendSession!.target;
    final otherFavorite = ref.watch(favoritesProvider.select((s) => s.findDevice(otherDevice)));
    final otherAlias = otherFavorite?.alias ?? otherDevice.alias;
    final otherLabel = shortDeviceName(otherAlias);

    if (_terminalStatuses.contains(status)) {
      // Captured now (not after closeSession, which can clear it) so Landed
      // can offer "Show in folder"/"Open".
      final filePath = receiving ? receiveSession.files.values.firstOrNull?.path : sendSession!.files.values.firstOrNull?.path;
      _navigateToResult(
        receiving: receiving,
        status: status,
        startTime: common.startTime,
        endTime: common.endTime,
        otherDevice: otherDevice,
        otherAlias: otherAlias,
        filePath: filePath,
      );
    }

    final transferNotifier = ref.watch(fileTransferProvider);
    final currBytes = _files.fold<int>(
      0,
      (prev, curr) => prev + ((transferNotifier.getProgress(sessionId: widget.sessionId, fileId: curr.id) * curr.size).round()),
    );
    final progress = _totalBytes == 0 ? 0.0 : (currBytes / _totalBytes).clamp(0.0, 1.0);

    int? speedBytesPerSec;
    if (common.startTime != null && status == SessionStatus.sending && currBytes >= 500 * 1024) {
      speedBytesPerSec = getFileSpeed(start: common.startTime!, end: common.endTime ?? DateTime.now().millisecondsSinceEpoch, bytes: currBytes);
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastRemainingUpdate >= 1000 || _remainingSeconds == null) {
        _remainingSeconds = speedBytesPerSec > 0 ? ((_totalBytes - currBytes) / speedBytesPerSec).ceil() : null;
        _lastRemainingUpdate = now;
      }
    }

    final reduceMotion = !ref.watch(animationProvider) || MediaQuery.of(context).disableAnimations;
    final currentFile = _files.isNotEmpty ? _files[_cycleIndex % _files.length] : null;
    final extension = currentFile != null ? p.extension(currentFile.fileName) : '';
    final isWaiting = status == SessionStatus.waiting;

    final title = receiving ? t.glide.sending.receivingFrom(device: otherLabel) : t.glide.sending.sendingTo(device: otherLabel);
    final cancelLabel = receiving ? t.glide.sending.stopReceiving : t.glide.sending.cancelTransfer;

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && widget.closeSessionOnClose) {
          _cancel(status);
        }
      },
      child: Scaffold(
        backgroundColor: GT.bg,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: GT.desktopMaxWidth),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GlideTopBarButton.back(onTap: () => _onCancelPressed(status), semanticLabel: t.general.back),
                        Expanded(
                          child: Text(title, style: GT.barTitle, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        GlideTopBarButton(
                          icon: GlideIconAsset.close,
                          iconSize: 16,
                          semanticLabel: t.general.cancel,
                          onTap: () => _onCancelPressed(status),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        children: [
                          _SendingHero(
                            reduceMotion: reduceMotion,
                            receiving: receiving,
                            thisType: myDeviceType,
                            thisModel: myDeviceModel,
                            otherType: otherDevice.deviceType,
                            otherModel: otherDevice.deviceModel,
                            thisLabel: thisDeviceLabel(),
                            otherLabel: otherLabel,
                            extension: extension.isEmpty ? '' : extension,
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                            child: GlideCard(
                              child: Row(
                                children: [
                                  const GlideFileThumbnail(),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          currentFile?.fileName ?? '',
                                          style: GT.rowTitleDense,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text(_totalBytes.asReadableFileSize, style: GT.caption),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(isWaiting ? '0%' : '${(progress * 100).round()}%', style: GT.bigNumber),
                                    Text(
                                      isWaiting
                                          ? t.glide.sending.waitingToAccept
                                          : (_remainingSeconds != null ? t.glide.sending.secondsLeft(seconds: _remainingSeconds!) : ' '),
                                      style: GT.secondary,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                GlideProgressBar(progress: isWaiting ? 0 : progress, reduceMotion: reduceMotion),
                                const SizedBox(height: 8),
                                Text(
                                  speedBytesPerSec != null && speedBytesPerSec > 0
                                      ? t.glide.sending.speedAverage(speed: (speedBytesPerSec / (1024 * 1024)).toStringAsFixed(1))
                                      : ' ',
                                  style: GT.secondary,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                    child: GlideOutlineButton(label: cancelLabel, onPressed: () => _onCancelPressed(status)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The bezier "glide" hero: two device circles joined by a dashed path, with
/// a file chip (and a trailing echo chip) traveling along it.
class _SendingHero extends StatefulWidget {
  final bool reduceMotion;
  final bool receiving;
  final DeviceType thisType;
  final String? thisModel;
  final DeviceType otherType;
  final String? otherModel;
  final String thisLabel;
  final String otherLabel;
  final String extension;

  const _SendingHero({
    required this.reduceMotion,
    required this.receiving,
    required this.thisType,
    this.thisModel,
    required this.otherType,
    this.otherModel,
    required this.thisLabel,
    required this.otherLabel,
    required this.extension,
  });

  @override
  State<_SendingHero> createState() => _SendingHeroState();
}

class _SendingHeroState extends State<_SendingHero> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));

  @override
  void initState() {
    super.initState();
    if (!widget.reduceMotion) {
      unawaited(_controller.repeat());
    }
  }

  @override
  void didUpdateWidget(covariant _SendingHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion != oldWidget.reduceMotion) {
      if (widget.reduceMotion) {
        _controller.stop();
      } else {
        unawaited(_controller.repeat());
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static Offset _pathPoint(double t) {
    const p0 = Offset(40, 140);
    const p1 = Offset(171, 60);
    const p2 = Offset(302, 140);
    final mt = 1 - t;
    return Offset(
      mt * mt * p0.dx + 2 * mt * t * p1.dx + t * t * p2.dx,
      mt * mt * p0.dy + 2 * mt * t * p1.dy + t * t * p2.dy,
    );
  }

  /// Approximates the spec's glideMove keyframes (0%: dist 0 opacity 0,
  /// 6%: opacity 1, 46%: dist 100% opacity 1, 54%: opacity 0, 100%: parked,
  /// opacity 0) with a single eased travel segment followed by a fade.
  (Offset, double) _chipState(double raw) {
    final travelT = (raw / 0.46).clamp(0.0, 1.0);
    final eased = Curves.easeOutCubic.transform(travelT);
    final t = widget.receiving ? 1 - eased : eased;
    final point = _pathPoint(t);
    double opacity;
    if (raw < 0.06) {
      opacity = raw / 0.06;
    } else if (raw < 0.46) {
      opacity = 1;
    } else if (raw < 0.54) {
      opacity = 1 - (raw - 0.46) / 0.08;
    } else {
      opacity = 0;
    }
    return (point, opacity);
  }

  @override
  Widget build(BuildContext context) {
    final leftType = widget.receiving ? widget.otherType : widget.thisType;
    final rightType = widget.receiving ? widget.thisType : widget.otherType;
    final leftModel = widget.receiving ? widget.otherModel : widget.thisModel;
    final rightModel = widget.receiving ? widget.thisModel : widget.otherModel;
    final leftLabel = widget.receiving ? widget.otherLabel : widget.thisLabel;
    final rightLabel = widget.receiving ? widget.thisLabel : widget.otherLabel;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: SizedBox(
        height: 210,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = constraints.maxWidth / 342;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                CustomPaint(
                  size: Size(constraints.maxWidth, 150 * scale),
                  painter: _DashedPathPainter(scale: scale),
                ),
                Positioned(
                  left: 12 * scale,
                  top: 112 * scale,
                  child: _DeviceEndpoint(type: leftType, deviceModel: leftModel, label: leftLabel, scale: scale),
                ),
                Positioned(
                  left: 274 * scale,
                  top: 112 * scale,
                  child: _DeviceEndpoint(type: rightType, deviceModel: rightModel, label: rightLabel, scale: scale),
                ),
                if (widget.reduceMotion)
                  _Chip(point: _pathPoint(1) * scale, opacity: 1, scale: scale, extension: widget.extension, echo: false)
                else
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      final echoRaw = (_controller.value - (260 / 2600)) % 1.0;
                      final (echoPoint, echoOpacity) = _chipState(echoRaw < 0 ? echoRaw + 1 : echoRaw);
                      final (mainPoint, mainOpacity) = _chipState(_controller.value);
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _Chip(point: echoPoint * scale, opacity: echoOpacity, scale: scale, extension: widget.extension, echo: true),
                          _Chip(point: mainPoint * scale, opacity: mainOpacity, scale: scale, extension: widget.extension, echo: false),
                        ],
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DashedPathPainter extends CustomPainter {
  final double scale;

  const _DashedPathPainter({required this.scale});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(40 * scale, 140 * scale);
    path.quadraticBezierTo(171 * scale, 60 * scale, 302 * scale, 140 * scale);

    final paint = Paint()
      ..color = const Color(0x59355CF5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * scale
      ..strokeCap = StrokeCap.round;

    const dashWidth = 1.0;
    const dashGap = 9.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashWidth * scale;
        canvas.drawPath(metric.extractPath(distance, next.clamp(0, metric.length)), paint);
        distance = next + dashGap * scale;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPathPainter oldDelegate) => oldDelegate.scale != scale;
}

class _DeviceEndpoint extends StatelessWidget {
  final DeviceType type;
  final String? deviceModel;
  final String label;
  final double scale;

  const _DeviceEndpoint({required this.type, this.deviceModel, required this.label, required this.scale});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104 * scale,
      child: Column(
        children: [
          GlideDeviceCircle(deviceType: type, deviceModel: deviceModel, size: 56 * scale),
          SizedBox(height: 8 * scale),
          Text(label, style: GT.caption, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final Offset point;
  final double opacity;
  final double scale;
  final String extension;
  final bool echo;

  const _Chip({required this.point, required this.opacity, required this.scale, required this.extension, required this.echo});

  @override
  Widget build(BuildContext context) {
    final width = 66 * scale;
    final height = 30 * scale;
    return Positioned(
      left: point.dx - width / 2,
      top: point.dy - height / 2,
      child: Opacity(
        opacity: opacity.clamp(0, 1),
        child: Transform.scale(
          scale: echo ? 0.82 : 1,
          child: Container(
            width: width,
            height: height,
            padding: EdgeInsets.symmetric(horizontal: 8 * scale),
            decoration: BoxDecoration(
              color: GT.surface,
              borderRadius: BorderRadius.circular(GT.radiusChip),
              border: Border.all(color: echo ? GT.border : GT.blue, width: echo ? 1 : 1.5),
              boxShadow: echo ? null : GT.shadowChip,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GlideIcon(GlideIconAsset.file, size: 12 * scale, color: GT.blue),
                SizedBox(width: 5 * scale),
                Flexible(
                  child: Text(
                    extension.isEmpty ? t.glide.sending.fileFallback : extension,
                    style: TextStyle(fontSize: 10 * scale, fontWeight: FontWeight.w600, color: echo ? GT.textMuted : GT.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
