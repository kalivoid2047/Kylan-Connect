import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../core/utils/app_logger.dart';

/// Generic on-disk storage for received file attachments, plus the pure
/// chunk/reassemble helpers shared by image and file transfers.
///
/// Files live under the app documents directory at a deterministic
/// `transferId_fileName` path (with the name sanitized) so both peers resolve
/// the same location without storing an absolute path.
class FileService {
  static final FileService _instance = FileService._internal();
  static FileService get instance => _instance;

  FileService._internal();

  Directory? _dirCache;

  /// The directory where received files are stored, created on first use.
  Future<Directory> filesDirectory() async {
    if (_dirCache != null) return _dirCache!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/files');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dirCache = dir;
    return dir;
  }

  /// Test hook: point the files directory at a temp location.
  void debugSetDirectory(Directory dir) => _dirCache = dir;

  /// Deterministic on-disk path for a transfer. Sanitizes the file name so an
  /// odd/malicious name can't escape the files directory.
  Future<String> localPathFor(String transferId, String fileName) async {
    final dir = await filesDirectory();
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return '${dir.path}/${transferId}_$safeName';
  }

  /// True once the full file for this transfer has been written to disk.
  Future<bool> isAvailable(String transferId, String fileName) async {
    final path = await localPathFor(transferId, fileName);
    return File(path).exists();
  }

  /// Writes the assembled bytes to the deterministic path, returning it.
  Future<String> saveBytes(
      String transferId, String fileName, List<int> bytes) async {
    final path = await localPathFor(transferId, fileName);
    await File(path).writeAsBytes(bytes, flush: true);
    AppLogger.instance.debug('Saved file to $path (${bytes.length} bytes)');
    return path;
  }

  // ---- Pure chunk helpers (unit-tested) ----

  /// Splits [bytes] into consecutive chunks of at most [chunkSize] bytes.
  static List<Uint8List> splitIntoChunks(List<int> bytes, int chunkSize) {
    assert(chunkSize > 0);
    final data = Uint8List.fromList(bytes);
    final chunks = <Uint8List>[];
    for (var offset = 0; offset < data.length; offset += chunkSize) {
      final end =
          (offset + chunkSize) < data.length ? offset + chunkSize : data.length;
      chunks.add(Uint8List.sublistView(data, offset, end));
    }
    // An empty input still yields a single empty chunk so `total` is never 0.
    if (chunks.isEmpty) chunks.add(Uint8List(0));
    return chunks;
  }

  /// Concatenates [chunks] (already in index order) back into the full bytes.
  static Uint8List reassembleChunks(List<Uint8List> chunks) {
    final total = chunks.fold<int>(0, (sum, c) => sum + c.length);
    final out = Uint8List(total);
    var offset = 0;
    for (final chunk in chunks) {
      out.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return out;
  }
}
