// History (§3.5): a combined, day-grouped list of sent and received
// transfers, with inline search.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:glide/config/glide_tokens.dart';
import 'package:glide/gen/strings.g.dart';
import 'package:glide/model/persistence/receive_history_entry.dart';
import 'package:glide/pages/glide/glide_home_page.dart';
import 'package:glide/provider/receive_history_provider.dart';
import 'package:glide/provider/send_history_provider.dart';
import 'package:glide/util/native/open_file.dart';
import 'package:glide/widget/dialogs/history_clear_dialog.dart';
import 'package:glide/widget/glide/glide_components.dart';
import 'package:glide/widget/glide/glide_icon.dart';
import 'package:intl/intl.dart';
import 'package:localsend_isolates/util/file_size_helper.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

class _HistoryRow {
  final String id;
  final String fileName;
  final int fileSize;
  final DateTime timestampLocal;
  final bool sent;
  final String otherAlias;
  final bool failed;
  final ReceiveHistoryEntry? receiveEntry;

  const _HistoryRow({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.timestampLocal,
    required this.sent,
    required this.otherAlias,
    required this.failed,
    this.receiveEntry,
  });
}

class GlideHistoryPage extends StatefulWidget {
  const GlideHistoryPage({super.key});

  @override
  State<GlideHistoryPage> createState() => _GlideHistoryPageState();
}

class _GlideHistoryPageState extends State<GlideHistoryPage> {
  bool _searching = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final receiveEntries = context.watch(receiveHistoryProvider);
    final sendEntries = context.watch(sendHistoryProvider);

    final rows = <_HistoryRow>[
      for (final e in receiveEntries)
        if (!e.isMessage)
          _HistoryRow(
            id: 'r-${e.id}',
            fileName: e.fileName,
            fileSize: e.fileSize,
            timestampLocal: e.timestamp.toLocal(),
            sent: false,
            otherAlias: e.senderAlias,
            failed: false,
            receiveEntry: e,
          ),
      for (final e in sendEntries)
        _HistoryRow(
          id: 's-${e.id}',
          fileName: e.fileName,
          fileSize: e.fileSize,
          timestampLocal: e.timestamp.toLocal(),
          sent: true,
          otherAlias: e.targetAlias,
          failed: !e.success,
        ),
    ]..sort((a, b) => b.timestampLocal.compareTo(a.timestampLocal));

    final query = _searchController.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? rows
        : rows.where((r) => r.fileName.toLowerCase().contains(query) || r.otherAlias.toLowerCase().contains(query)).toList();

    return Scaffold(
      backgroundColor: GT.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: GT.desktopWideMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, GT.topBarPaddingTop, 20, 0),
                  child: Row(
                    children: [
                      GlideTopBarButton.back(onTap: () => Navigator.of(context).pop(), semanticLabel: t.general.back),
                      const SizedBox(width: 12),
                      if (_searching)
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            autofocus: true,
                            style: GT.body,
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: t.glide.history.searchHint,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        )
                      else
                        Expanded(child: Text(t.glide.history.title, style: GT.screenTitle)),
                      GlideTopBarButton(
                        icon: _searching ? GlideIconAsset.close : GlideIconAsset.search,
                        iconSize: _searching ? 16 : 17,
                        semanticLabel: _searching ? t.glide.history.closeSearch : t.glide.history.search,
                        onTap: () => setState(() {
                          _searching = !_searching;
                          if (!_searching) {
                            _searchController.clear();
                          }
                        }),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty ? const _EmptyState() : _GroupedList(rows: filtered),
                ),
                if (rows.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GlideTextButton(
                      label: t.dialogs.historyClearDialog.title,
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(context: context, builder: (_) => const HistoryClearDialog());
                        if (confirmed == true && context.mounted) {
                          // ignore: use_build_context_synchronously
                          await context.redux(receiveHistoryProvider).dispatchAsync(RemoveAllHistoryEntriesAction());
                          // ignore: use_build_context_synchronously
                          await context.redux(sendHistoryProvider).dispatchAsync(RemoveAllSendHistoryEntriesAction());
                        }
                      },
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(color: GT.neutralTint, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const GlideIcon(GlideIconAsset.arrowUpRight, size: 14, color: GT.textMuted),
          ),
          const SizedBox(height: 14),
          Text(t.glide.history.emptyTitle, style: GT.rowTitleDense),
          const SizedBox(height: 4),
          Text(
            t.glide.history.emptySubtitle,
            style: GT.secondary,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _GroupedList extends StatelessWidget {
  final List<_HistoryRow> rows;

  const _GroupedList({required this.rows});

  String _dayLabel(DateTime day, DateTime today) {
    final diff = today.difference(day).inDays;
    if (diff == 0) {
      return t.glide.history.today;
    }
    if (diff == 1) {
      return t.glide.history.yesterday;
    }
    return DateFormat.yMMMd().format(day);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final groups = <DateTime, List<_HistoryRow>>{};
    for (final row in rows) {
      final day = DateTime(row.timestampLocal.year, row.timestampLocal.month, row.timestampLocal.day);
      (groups[day] ??= []).add(row);
    }
    final sortedDays = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final day in sortedDays) ...[
          GlideSectionLabel(_dayLabel(day, today)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: GT.screenPadding),
            child: Column(
              children: [for (final row in groups[day]!) _Row(row: row)],
            ),
          ),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final _HistoryRow row;

  const _Row({required this.row});

  @override
  Widget build(BuildContext context) {
    final icon = row.sent ? GlideIconAsset.arrowUpRight : GlideIconAsset.arrowDownLeft;
    final subtitle = row.failed
        ? t.glide.history.failedSubtitle
        : (row.sent
              ? t.glide.history.toDeviceSize(device: row.otherAlias, size: row.fileSize.asReadableFileSize)
              : t.glide.history.fromDeviceSize(device: row.otherAlias, size: row.fileSize.asReadableFileSize));
    final time = DateFormat.jm().format(row.timestampLocal);

    return Semantics(
      button: true,
      label: '${row.fileName}, $subtitle, $time',
      child: InkWell(
        onTap: () async {
          if (row.failed) {
            unawaited(Routerino.context.pushRootImmediately(() => const GlideHomePage(appStart: false)));
            return;
          }
          if (!row.sent && row.receiveEntry?.path != null) {
            await openFile(context, row.receiveEntry!.fileType, row.receiveEntry!.path!);
          }
        },
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: GT.rowPaddingVertical),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: row.failed ? GT.dangerSoft : GT.neutralTint, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: GlideIcon(icon, size: 14, color: row.failed ? GT.danger : GT.textMuted),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(row.fileName, style: GT.rowTitleDense, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle,
                          style: GT.caption.copyWith(color: row.failed ? GT.danger : GT.textMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(time, style: GT.captionFaint),
                    const SizedBox(height: 6),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(color: row.failed ? GT.danger : GT.success, shape: BoxShape.circle),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
