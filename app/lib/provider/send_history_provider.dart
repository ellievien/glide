import 'package:glide/model/persistence/send_history_entry.dart';
import 'package:glide/provider/persistence_provider.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:refena_flutter/refena_flutter.dart';

const _maxHistoryEntries = 30;

/// This provider stores the history of *sent* files, so the Glide History
/// screen (§3.5) can show "to {device}" rows next to the existing
/// "from {device}" [receiveHistoryProvider] rows. Mirrors
/// `receiveHistoryProvider`.
final sendHistoryProvider = ReduxProvider<SendHistoryService, List<SendHistoryEntry>>((ref) {
  return SendHistoryService(ref.read(persistenceProvider));
});

class SendHistoryService extends ReduxNotifier<List<SendHistoryEntry>> {
  final PersistenceService _persistence;

  SendHistoryService(this._persistence);

  @override
  List<SendHistoryEntry> init() => _persistence.getSendHistory();
}

/// Adds a history entry. Respects Settings > "Keep transfer history".
class AddSendHistoryEntryAction extends AsyncReduxAction<SendHistoryService, List<SendHistoryEntry>> {
  final String entryId;
  final String fileName;
  final FileType fileType;
  final int fileSize;
  final String targetAlias;
  final DateTime timestamp;
  final bool success;
  final String? failureReason;

  AddSendHistoryEntryAction({
    required this.entryId,
    required this.fileName,
    required this.fileType,
    required this.fileSize,
    required this.targetAlias,
    required this.timestamp,
    required this.success,
    required this.failureReason,
  });

  @override
  Future<List<SendHistoryEntry>> reduce() async {
    if (!notifier._persistence.isSaveToHistory()) {
      return state;
    }

    final updated = [
      SendHistoryEntry(
        id: entryId,
        fileName: fileName,
        fileType: fileType,
        fileSize: fileSize,
        targetAlias: targetAlias,
        timestamp: timestamp,
        success: success,
        failureReason: failureReason,
      ),
      ...state,
    ].take(_maxHistoryEntries).toList();
    await notifier._persistence.setSendHistory(updated);
    return updated;
  }
}

/// Removes all history entries. Called together with
/// `RemoveAllHistoryEntriesAction` (receive side) when the user clears
/// history.
class RemoveAllSendHistoryEntriesAction extends AsyncReduxAction<SendHistoryService, List<SendHistoryEntry>> {
  @override
  Future<List<SendHistoryEntry>> reduce() async {
    await notifier._persistence.setSendHistory([]);
    return [];
  }
}
