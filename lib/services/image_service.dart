import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/app_logger.dart';

/// Handles image files on disk and thumbnail generation, plus the pure
/// chunk/reassemble helpers used to move an image over the message channel.
///
/// Full images live on disk under the app documents directory; only a small
/// JPEG thumbnail (base64) travels inside the persisted [Message] payload. The
/// on-disk path is derived deterministically from the transferId + fileName so
/// both peers resolve the same location without storing an absolute path.
class ImageService {
  static final ImageService _instance = ImageService._internal();
  static ImageService get instance => _instance;

  ImageService._internal();

  Directory? _imagesDirCache;

  /// The directory where full images are stored, created on first use.
  /// Overridable in tests via [debugSetImagesDirectory].
  Future<Directory> imagesDirectory() async {
    if (_imagesDirCache != null) return _imagesDirCache!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/images');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _imagesDirCache = dir;
    return dir;
  }

  /// Test hook: point the images directory at a temp location.
  void debugSetImagesDirectory(Directory dir) => _imagesDirCache = dir;

  /// Deterministic on-disk path for a transfer. Sanitizes the file name so a
  /// malicious/odd name can't escape the images directory.
  Future<String> localPathFor(String transferId, String fileName) async {
    final dir = await imagesDirectory();
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return '${dir.path}/${transferId}_$safeName';
  }

  /// True once the full image for this transfer has been written to disk.
  Future<bool> isImageAvailable(String transferId, String fileName) async {
    final path = await localPathFor(transferId, fileName);
    return File(path).exists();
  }

  /// Writes the assembled image bytes to the deterministic path, returning it.
  Future<String> saveImageBytes(
      String transferId, String fileName, List<int> bytes) async {
    final path = await localPathFor(transferId, fileName);
    await File(path).writeAsBytes(bytes, flush: true);
    AppLogger.instance.debug('Saved image to $path (${bytes.length} bytes)');
    return path;
  }

  /// Decodes [bytes], resizes so the longest edge is at most
  /// [AppConstants.thumbnailMaxDimension], and returns a base64 JPEG. Returns
  /// null if the bytes are not a decodable image.
  String? generateThumbnailBase64(List<int> bytes) {
    try {
      final decoded = img.decodeImage(Uint8List.fromList(bytes));
      if (decoded == null) return null;

      final longest =
          decoded.width >= decoded.height ? decoded.width : decoded.height;
      final resized = longest <= AppConstants.thumbnailMaxDimension
          ? decoded
          : img.copyResize(
              decoded,
              width: decoded.width >= decoded.height
                  ? AppConstants.thumbnailMaxDimension
                  : null,
              height: decoded.height > decoded.width
                  ? AppConstants.thumbnailMaxDimension
                  : null,
            );

      final jpg = img.encodeJpg(resized, quality: 70);
      return base64.encode(jpg);
    } catch (e, stackTrace) {
      AppLogger.instance.error('Failed to generate thumbnail', e, stackTrace);
      return null;
    }
  }

  /// Returns the pixel dimensions of [bytes], or (0, 0) if undecodable.
  ({int width, int height}) imageDimensions(List<int> bytes) {
    try {
      final decoded = img.decodeImage(Uint8List.fromList(bytes));
      if (decoded == null) return (width: 0, height: 0);
      return (width: decoded.width, height: decoded.height);
    } catch (_) {
      return (width: 0, height: 0);
    }
  }
}
