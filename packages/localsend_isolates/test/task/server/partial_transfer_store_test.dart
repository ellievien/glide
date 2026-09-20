import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_isolates/rust/frb_generated.dart';
import 'package:localsend_isolates/src/task/server/partial_transfer_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  const store = PartialTransferStore();

  setUpAll(() {
    RustLib.initMock(api: _MockRustLibApi());
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('partial_transfer_store_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  const identity = PartialFileIdentity(
    senderFingerprint: 'sender-a',
    relativeName: 'video.mp4',
    size: 1000,
    modifiedEpochMs: 1700000000000,
  );

  test('nothing to resume when no partial has ever been staged', () async {
    final offset = await store.findResumeOffset(tempDir.path, identity);
    expect(offset, isNull);
  });

  test('finds a resumable partial after some bytes were written to it', () async {
    final partPath = await store.preparePartPath(tempDir.path, identity);
    await File(partPath).writeAsBytes(List.filled(400, 0));

    final offset = await store.findResumeOffset(tempDir.path, identity);
    expect(offset, 400);
  });

  test('does not offer to resume a fully-sized (never promoted) file', () async {
    final partPath = await store.preparePartPath(tempDir.path, identity);
    await File(partPath).writeAsBytes(List.filled(identity.size, 0));

    // Reaching the full size without being promoted looks like a stale/
    // inconsistent entry rather than something safe to append further to.
    final offset = await store.findResumeOffset(tempDir.path, identity);
    expect(offset, isNull);
  });

  test('does not offer to resume when the sender fingerprint differs', () async {
    final partPath = await store.preparePartPath(tempDir.path, identity);
    await File(partPath).writeAsBytes(List.filled(400, 0));

    const otherSender = PartialFileIdentity(
      senderFingerprint: 'sender-b',
      relativeName: 'video.mp4',
      size: 1000,
      modifiedEpochMs: 1700000000000,
    );
    final offset = await store.findResumeOffset(tempDir.path, otherSender);
    expect(offset, isNull);
  });

  test('does not offer to resume when the size differs (source file changed)', () async {
    final partPath = await store.preparePartPath(tempDir.path, identity);
    await File(partPath).writeAsBytes(List.filled(400, 0));

    const changedSize = PartialFileIdentity(
      senderFingerprint: 'sender-a',
      relativeName: 'video.mp4',
      size: 1234,
      modifiedEpochMs: 1700000000000,
    );
    final offset = await store.findResumeOffset(tempDir.path, changedSize);
    expect(offset, isNull);
  });

  test('promote moves the partial to its final name and clears the sidecar', () async {
    final partPath = await store.preparePartPath(tempDir.path, identity);
    await File(partPath).writeAsBytes(List.filled(identity.size, 42));

    final finalPath = await store.promote(
      destinationDirectory: tempDir.path,
      identity: identity,
      saveAsName: 'video.mp4',
      createdDirectories: {},
    );

    expect(finalPath, p.join(tempDir.path, 'video.mp4'));
    expect(File(finalPath).existsSync(), isTrue);
    expect(File(finalPath).readAsBytesSync().length, identity.size);
    expect(File(partPath).existsSync(), isFalse);

    // Nothing left staged for this identity.
    final offset = await store.findResumeOffset(tempDir.path, identity);
    expect(offset, isNull);
  });

  test('promote applies the same numbered-name collision handling as a fresh save', () async {
    // Something else already occupies the plain destination name.
    await File(p.join(tempDir.path, 'video.mp4')).writeAsString('unrelated file');

    final partPath = await store.preparePartPath(tempDir.path, identity);
    await File(partPath).writeAsBytes(List.filled(identity.size, 1));

    final finalPath = await store.promote(
      destinationDirectory: tempDir.path,
      identity: identity,
      saveAsName: 'video.mp4',
      createdDirectories: {},
    );

    // digestFilePathAndPrepareDirectory's counter starts at 1 for the plain
    // name (which collides here), so the first fallback is "(2)", not "(1)".
    expect(finalPath, p.join(tempDir.path, 'video (2).mp4'));
    // The unrelated pre-existing file is untouched.
    expect(File(p.join(tempDir.path, 'video.mp4')).readAsStringSync(), 'unrelated file');
  });

  test('discard removes a staged partial and its sidecar', () async {
    final partPath = await store.preparePartPath(tempDir.path, identity);
    await File(partPath).writeAsBytes(List.filled(400, 0));

    await store.discard(tempDir.path, identity);

    expect(File(partPath).existsSync(), isFalse);
    expect(await store.findResumeOffset(tempDir.path, identity), isNull);
  });

  test('discard on nothing staged does not throw', () async {
    await store.discard(tempDir.path, identity);
  });

  group('cleanupStale', () {
    test('removes an entry whose sidecar says it is older than maxAge', () async {
      final dir = store.stagingDirectoryOf(tempDir.path);
      await Directory(dir).create(recursive: true);
      final oldTimestamp = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
      await File(p.join(dir, 'stale.json')).writeAsString(
        '{"relativeName":"old.bin","size":10,"modifiedEpochMs":null,"senderFingerprint":"x","updatedAt":"$oldTimestamp"}',
      );
      await File(p.join(dir, 'stale.part')).writeAsBytes([1, 2, 3]);

      await store.cleanupStale(tempDir.path, maxAge: const Duration(days: 7));

      expect(File(p.join(dir, 'stale.json')).existsSync(), isFalse);
      expect(File(p.join(dir, 'stale.part')).existsSync(), isFalse);
    });

    test('keeps a recently updated entry', () async {
      final partPath = await store.preparePartPath(tempDir.path, identity);
      await File(partPath).writeAsBytes(List.filled(400, 0));

      await store.cleanupStale(tempDir.path, maxAge: const Duration(days: 7));

      final offset = await store.findResumeOffset(tempDir.path, identity);
      expect(offset, 400);
    });

    test('removes an orphaned .part file with no sidecar', () async {
      final dir = store.stagingDirectoryOf(tempDir.path);
      await Directory(dir).create(recursive: true);
      final orphanPath = p.join(dir, 'orphan.part');
      await File(orphanPath).writeAsBytes([1, 2, 3]);

      await store.cleanupStale(tempDir.path, maxAge: const Duration(days: 7));

      expect(File(orphanPath).existsSync(), isFalse);
    });

    test('does nothing when the staging directory does not exist yet', () async {
      await store.cleanupStale(tempDir.path, maxAge: const Duration(days: 7));
    });
  });
}

/// The filename sanitizer lives in the Rust library, which is not loaded in
/// unit tests; [promote] reaches it indirectly through
/// `digestFilePathAndPrepareDirectory`.
class _MockRustLibApi implements RustLibApi {
  @override
  String crateApiFilenameSanitizeFileName({required String name}) => name;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('Not mocked: ${invocation.memberName}');
}
