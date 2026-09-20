import 'package:flutter/services.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/cancel.dart';
import 'package:localsend_isolates/rust/api/http.dart';
import 'package:localsend_isolates/src/isolate/child/http_provider.dart';
import 'package:localsend_isolates/src/isolate/child/main.dart';
import 'package:localsend_isolates/src/isolate/dto/send_to_isolate_data.dart';
import 'package:localsend_isolates/src/task/upload/http_upload.dart';
import 'package:localsend_isolates/util/android_channel.dart';
import 'package:localsend_isolates/util/rust.dart';
import 'package:pool/pool.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:typed_isolates/typed_isolates.dart';

/// How many files of a [HttpUploadFilesTask] are uploaded in parallel.
const _concurrency = 2;

/// How often a single file is uploaded at most: on a checksum mismatch (HTTP
/// 422, restarting from scratch), a dropped connection mid-transfer (HTTP
/// 500 or a network-level error, resuming where it left off), or any
/// combination of the two.
/// Must not exceed MAX_UPLOAD_ATTEMPTS of the Rust server which stops
/// accepting retries at some point.
const _maxUploadAttempts = 3;

sealed class BaseHttpUploadTask {}

class HttpUploadFile {
  final String remoteFileToken;
  final String fileId;
  final String? filePath;
  final List<int>? fileBytes;
  final int fileSize;

  /// Bytes of this file the receiver already confirmed having, offered in
  /// its prepare-upload response (see `PrepareUploadResponseDto.resumeOffsets`
  /// on the Rust side) -- 0 for a normal, from-scratch upload. By the time
  /// this reaches the isolate, the caller has already re-checked that the
  /// local source file is unchanged since it was offered.
  final int initialResumeOffset;

  HttpUploadFile({
    required this.remoteFileToken,
    required this.fileId,
    required this.filePath,
    required this.fileBytes,
    required this.fileSize,
    this.initialResumeOffset = 0,
  });
}

/// Uploads a list of files as one isolate task.
///
/// This task is intended to replace the file scheduling loop in the parent
/// isolate. Up to [_concurrency] files are uploaded in parallel and progress
/// is reported across the complete list.
class HttpUploadFilesTask implements BaseHttpUploadTask {
  final String? remoteSessionId;
  final List<HttpUploadFile> files;
  final Device device;

  HttpUploadFilesTask({
    required this.remoteSessionId,
    required this.files,
    required this.device,
  });
}

class HttpUploadCancelTask implements BaseHttpUploadTask {
  final int taskId;

  HttpUploadCancelTask({required this.taskId});
}

/// Cancels a single file of a [HttpUploadFilesTask] without affecting the
/// other files it shares the task with (unlike [HttpUploadCancelTask], which
/// aborts every file of the task). Used for a user-initiated pause: the
/// upload of this file stops with a [HttpUploadFilePausedEvent] instead of
/// being retried, but sibling files already in flight keep going.
class HttpUploadCancelFileTask implements BaseHttpUploadTask {
  final int taskId;
  final String fileId;

  HttpUploadCancelFileTask({required this.taskId, required this.fileId});
}

/// A message sent from the upload isolate to the main isolate
/// reporting the state of a single file of a [HttpUploadFilesTask].
sealed class HttpUploadEvent {
  final String fileId;

  HttpUploadEvent({required this.fileId});
}

/// The upload of the file has started.
class HttpUploadFileStartedEvent extends HttpUploadEvent {
  HttpUploadFileStartedEvent({required super.fileId});
}

/// The upload progress of the file in the range [0, 1].
class HttpUploadFileProgressEvent extends HttpUploadEvent {
  final double progress;

  HttpUploadFileProgressEvent({
    required super.fileId,
    required this.progress,
  });
}

/// The file has been uploaded successfully.
class HttpUploadFileFinishedEvent extends HttpUploadEvent {
  HttpUploadFileFinishedEvent({required super.fileId});
}

/// The upload of the file has failed. The next file is still uploaded.
class HttpUploadFileFailedEvent extends HttpUploadEvent {
  final String error;

  HttpUploadFileFailedEvent({
    required super.fileId,
    required this.error,
  });
}

/// The upload of the file was deliberately paused (via
/// [HttpUploadCancelFileTask]), not failed: the next file of the task is
/// still uploaded. [sentBytes] is how far this attempt got, so a later
/// resume can offer it as a starting point the same way an automatic
/// mid-attempt retry does.
class HttpUploadFilePausedEvent extends HttpUploadEvent {
  final int sentBytes;

  HttpUploadFilePausedEvent({
    required super.fileId,
    required this.sentBytes,
  });
}

/// Cancel tokens of the files currently uploading, grouped by task.
/// Task ID -> (File ID -> CancelToken). Cancelling a whole task cancels every
/// token in its inner map; cancelling one file removes just its own entry,
/// leaving siblings untouched.
final _cancelTokenProvider = Provider((ref) => <int, Map<String, RsCancellationToken>>{});

Future<void> setupHttpUploadIsolate(
  Stream<SendToIsolateData<IsolateTask<BaseHttpUploadTask>>> receiveFromMain,
  void Function(IsolateTaskStreamResult<HttpUploadEvent>) sendToMain,
  InitialData initialData,
) async {
  await setupChildIsolateHelper(
    debugLabel: 'HttpUploadIsolate',
    receiveFromMain: receiveFromMain,
    sendToMain: sendToMain,
    initialData: initialData,
    init: (ref) async {
      // Initialize the platform method channel so getFileDescriptorAndroid
      // (used to resolve "content://" files) works inside this isolate.
      BackgroundIsolateBinaryMessenger.ensureInitialized(
        ref.read(syncProvider).rootIsolateToken as RootIsolateToken,
      );
    },
    handler: (ref, task) async {
      final HttpUploadFilesTask uploadTask;
      switch (task.data) {
        case HttpUploadFilesTask task:
          uploadTask = task;
          break;
        case HttpUploadCancelTask task:
          final fileTokens = ref.read(_cancelTokenProvider).remove(task.taskId);
          if (fileTokens != null) {
            for (final cancelToken in fileTokens.values) {
              cancelToken.cancel();
            }
          }
          return;
        case HttpUploadCancelFileTask task:
          final cancelToken = ref.read(_cancelTokenProvider)[task.taskId]?.remove(task.fileId);
          cancelToken?.cancel();
          return;
      }

      // One client for the whole task: pinned to the receiver, so no file
      // content can be streamed to a different peer, and shared by all files
      // of the task so the connection is reused.
      final client = ref.read(httpProvider).pinnedTo(uploadTask.device.fingerprint);

      final taskTokens = ref.read(_cancelTokenProvider).putIfAbsent(task.id, () => {});
      try {
        await Pool(_concurrency).forEach<HttpUploadFile, void>(uploadTask.files, (file) async {
          if (!ref.read(_cancelTokenProvider).containsKey(task.id)) {
            // the whole task was canceled, do not upload the remaining files
            return;
          }

          // Each file gets its own token so pausing one file (removing and
          // cancelling just its entry here) does not affect the others this
          // task is concurrently uploading.
          final cancelToken = createCancellationToken();
          taskTokens[file.fileId] = cancelToken;

          sendToMain(
            IsolateTaskStreamResult.event(
              id: task.id,
              data: HttpUploadFileStartedEvent(fileId: file.fileId),
            ),
          );

          // How much of the file to try to resume from: initially the
          // receiver's own offer (if any -- e.g. from a previous attempt
          // before this app was killed and restarted), then updated after
          // every attempt within this task to how far the outgoing stream
          // actually got before it failed or was paused. The receiver
          // independently verifies this against what it actually has on disk
          // and only honors it if it matches exactly (see
          // `save::save_req_to_target` on the Rust side), so a stale or
          // wrong value here just falls back to a fresh write rather than
          // corrupting anything. Declared outside the try below so the
          // cancellation handler can report it too.
          var resumeOffset = file.initialResumeOffset;

          try {
            final filePath = file.filePath;
            final isContentUri = filePath?.startsWith('content://') ?? false;

            for (var attempt = 1; ; attempt++) {
              // The file descriptor is consumed by the upload, so a fresh one
              // is needed for every attempt.
              final fileDescriptor = isContentUri ? await getFileDescriptorAndroid(uri: filePath!) : null;

              try {
                await ref
                    .read(httpUploadProvider)
                    .upload(
                      client: client,
                      stream: filePath == null && file.fileBytes != null ? Stream.value(file.fileBytes!) : null,
                      path: !isContentUri ? filePath : null,
                      fileDescriptor: fileDescriptor,
                      contentLength: file.fileSize,
                      target: uploadTask.device,
                      remoteSessionId: uploadTask.remoteSessionId,
                      fileId: file.fileId,
                      token: file.remoteFileToken,
                      resumeOffset: resumeOffset,
                      onSendProgress: (progress, sentBytes) {
                        resumeOffset = sentBytes;
                        sendToMain(
                          IsolateTaskStreamResult.event(
                            id: task.id,
                            data: HttpUploadFileProgressEvent(
                              fileId: file.fileId,
                              progress: progress,
                            ),
                          ),
                        );
                      },
                      cancelToken: cancelToken,
                    );
                break;
              } on RsHttpClientError_StatusCode catch (e) {
                if (attempt >= _maxUploadAttempts) {
                  rethrow;
                }
                if (e.status == 422) {
                  // The receiver discarded the file because its checksum did
                  // not match (e.g. the file changed while being read).
                  // Resuming a file that may have changed underneath us
                  // would risk mixing old and new content, so start over.
                  resumeOffset = 0;
                } else if (e.status != 500) {
                  // Any other status (403 rejected, 409 blocked, ...) is not
                  // something a retry can fix.
                  rethrow;
                }
                // A 500 (e.g. the connection dropped mid-transfer -- see
                // `save::save_req_to_target`) is retried resuming from
                // [resumeOffset], the last progress this attempt reported.
              } on RsHttpClientError_Reqwest catch (_) {
                // A network-level failure (connection reset, timeout, DNS,
                // ...): retryable the same way, resuming from [resumeOffset].
                if (attempt >= _maxUploadAttempts) {
                  rethrow;
                }
              } on RsHttpClientError_Io catch (_) {
                if (attempt >= _maxUploadAttempts) {
                  rethrow;
                }
              }
            }

            sendToMain(
              IsolateTaskStreamResult.event(
                id: task.id,
                data: HttpUploadFileFinishedEvent(fileId: file.fileId),
              ),
            );
          } on RsHttpClientError_Cancelled catch (_) {
            // A deliberate pause of this file (or the whole task), never a
            // network/server error: not retried, and reported distinctly so
            // the app does not show it as a failure.
            sendToMain(
              IsolateTaskStreamResult.event(
                id: task.id,
                data: HttpUploadFilePausedEvent(fileId: file.fileId, sentBytes: resumeOffset),
              ),
            );
          } catch (e) {
            sendToMain(
              IsolateTaskStreamResult.event(
                id: task.id,
                data: HttpUploadFileFailedEvent(
                  fileId: file.fileId,
                  error: e.humanErrorMessage,
                ),
              ),
            );
          }
        }).drain<void>();

        sendToMain(
          IsolateTaskStreamResult.done(
            id: task.id,
          ),
        );
      } finally {
        ref.read(_cancelTokenProvider).remove(task.id);
      }
    },
  );
}
