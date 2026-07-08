import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kylan_connect/core/constants/app_constants.dart';
import 'package:kylan_connect/models/message.dart';
import 'package:kylan_connect/services/image_service.dart';

void main() {
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

  group('Image disk storage', () {
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
      expect(m.isAttachment, isTrue);
      expect(m.isControlMessage, isFalse);
      expect(m.transferId, equals('tx'));
      expect(m.thumbnailBase64, equals('AAAA'));
      expect(m.attachmentName, equals('pic.jpg'));
      expect(m.attachmentSize, equals(1234));
      expect(m.imageWidth, equals(640));
      expect(m.imageHeight, equals(480));
      expect(m.status, equals(AppConstants.messageStatusSending));
    });
  });
}
