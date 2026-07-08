import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kylan_connect/core/constants/app_constants.dart';
import 'package:kylan_connect/models/message.dart';
import 'package:kylan_connect/services/file_service.dart';

void main() {
  group('Chunking', () {
    test('splits and reassembles to the original bytes', () {
      final data =
          Uint8List.fromList(List<int>.generate(100, (i) => i % 256));
      final chunks = FileService.splitIntoChunks(data, 32);

      expect(chunks.length, equals(4)); // 32 + 32 + 32 + 4
      expect(chunks.last.length, equals(4));
      expect(FileService.reassembleChunks(chunks), equals(data));
    });

    test('handles an exact multiple of the chunk size', () {
      final data = Uint8List.fromList(List<int>.generate(64, (i) => i));
      final chunks = FileService.splitIntoChunks(data, 32);
      expect(chunks.length, equals(2));
      expect(FileService.reassembleChunks(chunks), equals(data));
    });

    test('a chunk size larger than the data yields one chunk', () {
      final data = Uint8List.fromList([1, 2, 3]);
      final chunks = FileService.splitIntoChunks(data, 1024);
      expect(chunks.length, equals(1));
      expect(FileService.reassembleChunks(chunks), equals(data));
    });

    test('empty input yields a single empty chunk', () {
      final chunks = FileService.splitIntoChunks(<int>[], 32);
      expect(chunks.length, equals(1));
      expect(chunks.first, isEmpty);
      expect(FileService.reassembleChunks(chunks), isEmpty);
    });

    test('survives a base64 round-trip per chunk (wire encoding)', () {
      final data =
          Uint8List.fromList(List<int>.generate(500, (i) => (i * 7) % 256));
      final chunks = FileService.splitIntoChunks(data, 64);

      final decoded = chunks
          .map((c) => Uint8List.fromList(base64.decode(base64.encode(c))))
          .toList();
      expect(FileService.reassembleChunks(decoded), equals(data));
    });
  });

  group('File disk storage', () {
    late Directory tempDir;

    setUpAll(() {
      tempDir = Directory.systemTemp.createTempSync('kylan_file_test');
      FileService.instance.debugSetDirectory(tempDir);
    });

    tearDownAll(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('saves and resolves files by transferId + name', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5, 6]);
      final path =
          await FileService.instance.saveBytes('tx1', 'doc.pdf', bytes);

      expect(await File(path).exists(), isTrue);
      expect(await File(path).readAsBytes(), equals(bytes));
      expect(await FileService.instance.isAvailable('tx1', 'doc.pdf'), isTrue);
      expect(
          await FileService.instance.isAvailable('tx1', 'nope.pdf'), isFalse);
    });

    test('strips path separators from file names (no traversal)', () async {
      final path =
          await FileService.instance.localPathFor('tx2', '../../etc/passwd');
      final base = path.split(RegExp(r'[/\\]')).last;
      expect(base, equals('tx2_.._.._etc_passwd'));
      expect(base.contains('/'), isFalse);
      expect(base.contains('\\'), isFalse);
    });
  });

  group('File message model', () {
    test('createFileMessage exposes metadata and is not a control message', () {
      final m = Message.createFileMessage(
        senderId: 'a',
        receiverId: 'b',
        transferId: 'tx',
        fileName: 'report.pdf',
        fileSize: 4096,
      );

      expect(m.type, equals(AppConstants.messageTypeFile));
      expect(m.isFile, isTrue);
      expect(m.isImage, isFalse);
      expect(m.isAttachment, isTrue);
      expect(m.isControlMessage, isFalse);
      expect(m.transferId, equals('tx'));
      expect(m.attachmentName, equals('report.pdf'));
      expect(m.attachmentSize, equals(4096));
    });

    test('createFileChunk is an (ephemeral) control message', () {
      final c = Message.createFileChunk(
        senderId: 'a',
        receiverId: 'b',
        transferId: 'tx',
        index: 2,
        total: 5,
        dataBase64: 'Zm9v',
      );

      expect(c.type, equals(AppConstants.messageTypeFileChunk));
      expect(c.isControlMessage, isTrue);
      expect(c.payload['index'], equals(2));
      expect(c.payload['total'], equals(5));
      expect(c.payload['data'], equals('Zm9v'));
    });
  });

  group('Voice message model', () {
    test('createVoiceMessage carries duration and is an attachment', () {
      final m = Message.createVoiceMessage(
        senderId: 'a',
        receiverId: 'b',
        transferId: 'tx',
        fileName: 'voice_abc.m4a',
        fileSize: 20480,
        durationMs: 4200,
      );

      expect(m.type, equals(AppConstants.messageTypeVoice));
      expect(m.isVoice, isTrue);
      expect(m.isFile, isFalse);
      expect(m.isImage, isFalse);
      expect(m.isAttachment, isTrue);
      expect(m.isControlMessage, isFalse);
      expect(m.transferId, equals('tx'));
      expect(m.attachmentName, equals('voice_abc.m4a'));
      expect(m.attachmentSize, equals(20480));
      expect(m.voiceDurationMs, equals(4200));
      expect(m.status, equals(AppConstants.messageStatusSending));
    });
  });
}
