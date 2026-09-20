// Incoming request (§3.4). A modal bottom sheet over a dimmed Home; on
// desktop widths it becomes a centered dialog card (§8).
//
// Implemented as a full page (not `showModalBottomSheet`) so it participates
// in the same Routerino navigation stack as the rest of the receive flow -
// see the `removeUntil: GlideIncomingSheetPage` swap in `receive_controller.dart`.
import 'package:flutter/material.dart';
import 'package:glide/config/glide_tokens.dart';
import 'package:glide/gen/strings.g.dart';
import 'package:glide/pages/receive_page.dart' show ReceivePageVm;
import 'package:glide/provider/favorites_provider.dart';
import 'package:glide/util/favorites.dart';
import 'package:glide/widget/animations/initial_fade_transition.dart';
import 'package:glide/widget/animations/initial_slide_transition.dart';
import 'package:glide/widget/glide/glide_brand.dart';
import 'package:glide/widget/glide/glide_components.dart';
import 'package:glide/widget/glide/glide_icon.dart';
import 'package:glide/widget/glide/glide_transfer_widgets.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:localsend_isolates/util/file_size_helper.dart';
import 'package:refena_flutter/refena_flutter.dart';

class GlideIncomingSheetPage extends StatefulWidget {
  final ViewProvider<ReceivePageVm> vm;

  const GlideIncomingSheetPage(this.vm, {super.key});

  @override
  State<GlideIncomingSheetPage> createState() => _GlideIncomingSheetPageState();
}

class _GlideIncomingSheetPageState extends State<GlideIncomingSheetPage> with Refena {
  @override
  Widget build(BuildContext context) {
    final vm = context.watch(widget.vm);
    final senderFavoriteEntry = ref.watch(favoritesProvider.select((state) => state.findDevice(vm.sender)));
    final senderName = senderFavoriteEntry?.alias ?? vm.sender.alias;

    final totalSize = vm.files.fold<int>(0, (prev, curr) => prev + curr.size);
    final allImages = vm.files.isNotEmpty && vm.files.every((f) => f.fileType == FileType.image);
    final fileNoun = allImages ? t.glide.incoming.photo : t.glide.incoming.file;
    final fileCountLabel = '${vm.files.length} $fileNoun${vm.files.length == 1 ? '' : 's'}';
    final fileTitle = vm.files.length == 1 ? vm.files.first.fileName : '${vm.files.length} files';

    final isDesktop = MediaQuery.sizeOf(context).width >= 700;

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          vm.onDecline();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // The dimmed Home behind the sheet.
            Positioned.fill(
              child: ColoredBox(
                color: GT.bg,
                child: Stack(
                  children: [
                    // Symbol viewBox is 132x104; 20px tall => ~25.4px wide.
                    const Positioned(left: 24, top: 30, child: GlideSymbol(width: 25.4, opacity: 0.55)),
                    InitialFadeTransition(
                      duration: const Duration(milliseconds: 350),
                      child: Container(color: GT.ink.withValues(alpha: 0.4)),
                    ),
                  ],
                ),
              ),
            ),
            Align(
              alignment: isDesktop ? Alignment.center : Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isDesktop ? 420 : double.infinity),
                child: InitialSlideTransition(
                  origin: isDesktop ? Offset.zero : const Offset(0, 1),
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOut,
                  child: isDesktop
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(GT.radiusCard),
                          child: _SheetContent(
                            vm: vm,
                            senderName: senderName,
                            totalSize: totalSize,
                            fileCountLabel: fileCountLabel,
                            fileTitle: fileTitle,
                          ),
                        )
                      : GlideBottomSheetShell(
                          child: _SheetBody(
                            vm: vm,
                            senderName: senderName,
                            totalSize: totalSize,
                            fileCountLabel: fileCountLabel,
                            fileTitle: fileTitle,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetContent extends StatelessWidget {
  final ReceivePageVm vm;
  final String senderName;
  final int totalSize;
  final String fileCountLabel;
  final String fileTitle;

  const _SheetContent({
    required this.vm,
    required this.senderName,
    required this.totalSize,
    required this.fileCountLabel,
    required this.fileTitle,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: GT.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
        child: _SheetBody(vm: vm, senderName: senderName, totalSize: totalSize, fileCountLabel: fileCountLabel, fileTitle: fileTitle),
      ),
    );
  }
}

class _SheetBody extends StatelessWidget {
  final ReceivePageVm vm;
  final String senderName;
  final int totalSize;
  final String fileCountLabel;
  final String fileTitle;

  const _SheetBody({
    required this.vm,
    required this.senderName,
    required this.totalSize,
    required this.fileCountLabel,
    required this.fileTitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(color: GT.blueTint, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: GlideIcon(deviceIconFor(vm.sender.deviceType, deviceModel: vm.sender.deviceModel), size: 24, color: GT.blue),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      senderName,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: GT.ink),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(t.glide.incoming.wantsToSend, style: GT.secondary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 22),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: GT.bg,
              border: Border.all(color: const Color(0x0F11182F)),
              borderRadius: BorderRadius.circular(GT.radiusCard),
            ),
            child: Row(
              children: [
                const GlideFileThumbnail(onTintedCard: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(fileTitle, style: GT.rowTitleDense, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${totalSize.asReadableFileSize} · $fileCountLabel',
                          style: GT.caption,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Row(
            children: [
              const GlideIcon(GlideIconAsset.network, size: 16, color: GT.textFaint),
              const SizedBox(width: 7),
              Expanded(
                child: Text(t.glide.incoming.networkTrust, style: GT.captionFaint),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        GlidePrimaryButton(
          label: t.general.accept,
          // `selectedReceivingFilesProvider` was seeded with every file (selecting
          // all of them) right before this page was pushed - see onPrepareUpload.
          onPressed: vm.onAccept,
        ),
        const SizedBox(height: 10),
        GlideOutlineButton(
          label: t.general.decline,
          destructive: true,
          onPressed: () {
            vm.onDecline();
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
