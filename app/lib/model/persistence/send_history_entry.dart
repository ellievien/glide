import 'package:localsend_isolates/model/file_type.dart';

/// One completed (or failed) *send*, persisted so the Glide History screen
/// (§3.5 of the design spec) can show "to {device}" rows next to the
/// existing "from {device}" [ReceiveHistoryEntry] rows.
///
/// This mirrors `ReceiveHistoryEntry` but is hand-written (plain
/// `toJson`/`fromJson`, no dart_mappable codegen) since it only needs a
/// handful of primitive fields.
class SendHistoryEntry {
  final String id;
  final String fileName;
  final FileType fileType;
  final int fileSize;
  final String targetAlias;
  final DateTime timestamp;
  final bool success;

  /// A short, human reason shown on the History row when [success] is
  /// false (e.g. "connection lost", "declined on Pixel 9").
  final String? failureReason;

  const SendHistoryEntry({
    required this.id,
    required this.fileName,
    required this.fileType,
    required this.fileSize,
    required this.targetAlias,
    required this.timestamp,
    required this.success,
    required this.failureReason,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fileName': fileName,
      'fileType': fileType.name,
      'fileSize': fileSize,
      'targetAlias': targetAlias,
      'timestamp': timestamp.toIso8601String(),
      'success': success,
      'failureReason': failureReason,
    };
  }

  static SendHistoryEntry fromJson(Map<String, dynamic> json) {
    return SendHistoryEntry(
      id: json['id'] as String,
      fileName: json['fileName'] as String,
      fileType: FileType.values.byName(json['fileType'] as String? ?? FileType.other.name),
      fileSize: json['fileSize'] as int,
      targetAlias: json['targetAlias'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      success: json['success'] as bool? ?? true,
      failureReason: json['failureReason'] as String?,
    );
  }
}
