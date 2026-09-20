/// Status of one single file during file transfer.
/// Both receiver and sender should share the same information.
enum FileStatus {
  queue,
  skipped,
  sending,
  failed,
  finished,

  /// Deliberately paused by the user (send side only), distinct from
  /// [failed]: the upload can be resumed from where it stopped instead of
  /// being retried from scratch. A session with a paused file is not
  /// considered done -- see [FileStatusIterable].
  paused,
}

extension FileStatusIterable on Iterable<FileStatus> {
  /// A [paused] file is not "finished or error": the user chose to stop it,
  /// not the transfer failing, and it is expected to still be resumed or
  /// explicitly cancelled.
  bool get isFinishedOrError => every((status) => const {FileStatus.skipped, FileStatus.failed, FileStatus.finished}.contains(status));
  bool get isFinishedOrSkipped => every((status) => const {FileStatus.skipped, FileStatus.finished}.contains(status));
}
