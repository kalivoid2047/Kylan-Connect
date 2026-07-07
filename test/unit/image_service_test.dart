import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kylan_connect/core/constants/app_constants.dart';
import 'package:kylan_connect/models/message.dart';
import 'package:kylan_connect/services/image_service.dart';

void main() {
  group('Chunking', () {
    test('splits and reassembles to the original bytes', () {
      final data =
          Uint8List.fromList(List<int>.generate(100, (i) => i % 256));
      final chunks = ImageService.splitIntoChunks(data, 32);

      expect(chunks.length, equals(4)); // 32 + 32 + 32 + 4
      expect(chunks.last.length, equals(4));

      final rebuilt = ImageService.reassembleChunks(chunks);
      expect(rebuilt, equals(data));
    });

    test('handles an exact multiple of the chunk size', () {
      final data = Uint8List.fromList(List<int>.generate(64, (i) => i));
      final chunks = ImageService.splitIntoChunks(data, 32);
      expect(chunks.length, equals(2));
      expect(ImageService.reassembleChunks(chunks), equals(data));
    });

    test('a chunk size larger than the data yields one chunk', () {
      final data = Uint8List.fromList([1, 2, 3]);
      final chunks = ImageService.splitIntoChunks(data, 1024);
      expect(chunks.length, equals(1));
      expect(ImageService.reassembleChunks(chunks), equals(data));
    });

    test('empty input yields a single empty chunk', () {
      final chunks = ImageService.splitIntoChunks(<int>[], 32);
      expect(chunks.length, equals(1));
      expect(chunks.first, isEmpty);
      expect(ImageService.reassembleChunks(chunks), isEmpty);
    });

    test('survives a base64 round-trip per chunk (wire encoding)', () {
      final data =
          Uint8List.fromList(List<int>.generate(500, (i) => (i * 7) % 256));
      final chunks = ImageService.splitIntoChunks(data, 64);

      final decoded = chunks
          .map((c) => Uint8List.fromList(base64.decode(base64.encode(c))))
          .toList();
      expect(ImageService.reassembleChunks(decoded), equals(data));
    });
  });

  group('Thumbnails', () {
    late Uint8List pngBytes;

    setUpAll(() {
      final src = img.Image(width: 640, height: 480);
      img.fill(src, color: img.ColorRgb8(10, 120, 220));
      pngBytes = Uint8List.fromList(img.encodePng(src));
    });

    test('resizes so the longest edge fits the max dimension', () {
      final b64 = ImageService.instance.generateThumbnailBase64(pngBytes);
      expect(b64, isNotNull);

      final thumb = img.decodeImage(base64.decode(b64!))!;
      final longest =
          thumb.width >= thumb.height ? thumb.width : thumb.height;
      expect(longest, lessThanOrEqualTo(AppConstants.thumbnailMaxDimension));
      // Aspect ratio preserved (640x480 -> 320x240).
      expect(thumb.width, equals(320));
      expect(thumb.height, equals(240));
    });

    test('reports source dimensions', () {
      final dims = ImageService.instance.imageDimensions(pngBytes);
      expect(dims.width, equals(640));
      expect(dims.height, equals(480));
    });

    test('returns null for non-image bytes', () {
      final b64 =
          ImageService.instance.generateThumbnailBase64([0, 1, 2, 3, 4, 5]);
      expect(b64, isNull);
    });
  });

  group('Disk storage', () {
    late Directory tempDir;

    setUpAll(() {
      tempDir = Directory.systemTemp.createTempSync('kylan_image_test');
      ImageService.instance.debugSetImagesDirectory(tempDir);
    });

    tearDownAll(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('saves and resolves images by transferId + name', () async {
      final bytes = Uint8List.fromList([9, 8, 7, 6, 5]);
      final path =
          await ImageService.instance.saveImageBytes('tx1', 'photo.jpg', bytes);

      expect(await File(path).exists(), isTrue);
      expect(await File(path).readAsBytes(), equals(bytes));
      expect(
        await ImageService.instance.isImageAvailable('tx1', 'photo.jpg'),
        isTrue,
      );
      expect(
        await ImageService.instance.isImageAvailable('tx1', 'missing.jpg'),
        isFalse,
      );
    });

    test('strips path separators from file names (no traversal)', () async {
      final path =
          await ImageService.instance.localPathFor('tx2', '../../etc/passwd');
      // The name portion keeps within the images dir: separators are removed,
      // so it resolves to a single file rather than escaping upward.
      final base = path.split(RegExp(r'[/\\]')).last;
      expect(base, equals('tx2_.._.._etc_passwd'));
      expect(base.contains('/'), isFalse);
      expect(base.contains('\\'), isFalse);
    });
  });

  group('Image message model', () {
    test('createImageMessage exposes metadata and is not a control message', () {
      final m = Message.createImageMessage(
        senderId: 'a',
        receiverId: 'b',
        transferId: 'tx',
        thumbnailBase64: 'AAAA',
        fileName: 'pic.jpg',
        fileSize: 1234,
        width: 640,
        height: 480,
      );

      expect(m.type, equals(AppConstants.messageTypeImage));
      expect(m.isImage, isTrue);
      expect(m.isControlMessage, isFalse);
      expect(m.imageTransferId, equals('tx'));
      expect(m.thumbnailBase64, equals('AAAA'));
      expect(m.imageFileName, equals('pic.jpg'));
      expect(m.imageFileSize, equals(1234));
      expect(m.imageWidth, equals(640));
      expect(m.imageHeight, equals(480));
      expect(m.status, equals(AppConstants.messageStatusSending));
    });

    test('createImageChunk is an (ephemeral) control message', () {
      final c = Message.createImageChunk(
        senderId: 'a',
        receiverId: 'b',
        transferId: 'tx',
        index: 2,
        total: 5,
        dataBase64: 'Zm9v',
      );

      expect(c.type, equals(AppConstants.messageTypeImageChunk));
      expect(c.isControlMessage, isTrue);
      expect(c.payload['index'], equals(2));
      expect(c.payload['total'], equals(5));
      expect(c.payload['data'], equals('Zm9v'));
    });
  });
}
