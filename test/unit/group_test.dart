import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:kylan_connect/models/group.dart';
import 'package:kylan_connect/services/storage_service.dart';

void main() {
  group('Group model', () {
    test('create assigns an id and preserves members', () {
      final g = Group.create(
        name: 'Team',
        memberIds: ['a', 'b', 'c'],
        createdBy: 'a',
        avatarColor: '#FF6B6B',
      );
      expect(g.groupId, isNotEmpty);
      expect(g.name, equals('Team'));
      expect(g.memberIds, equals(['a', 'b', 'c']));
      expect(g.createdBy, equals('a'));
    });

    test('round-trips through JSON', () {
      final g = Group.create(
        name: 'Book Club',
        memberIds: ['x', 'y'],
        createdBy: 'x',
        avatarColor: '#4ECDC4',
      );
      final restored = Group.fromJson(g.toJson());

      expect(restored.groupId, equals(g.groupId));
      expect(restored.name, equals(g.name));
      expect(restored.memberIds, equals(g.memberIds));
      expect(restored.createdBy, equals(g.createdBy));
      expect(restored.avatarColor, equals(g.avatarColor));
      expect(restored.createdAt.toIso8601String(),
          equals(g.createdAt.toIso8601String()));
    });

    test('copyWith updates only the given fields', () {
      final g = Group.create(
        name: 'Old',
        memberIds: ['a'],
        createdBy: 'a',
        avatarColor: '#fff',
      );
      final updated = g.copyWith(name: 'New', memberIds: ['a', 'b']);
      expect(updated.name, equals('New'));
      expect(updated.memberIds, equals(['a', 'b']));
      expect(updated.groupId, equals(g.groupId));
      expect(updated.createdBy, equals('a'));
    });
  });

  group('Group storage', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('kylan_group_test');
      await StorageService.instance.initializeForTest(tempDir.path);
    });

    tearDownAll(() async {
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('saves, reads, lists and deletes groups', () async {
      final g = Group.create(
        name: 'Squad',
        memberIds: ['me', 'you'],
        createdBy: 'me',
        avatarColor: '#45B7D1',
      );

      await StorageService.instance.saveGroup(g);

      final fetched = StorageService.instance.getGroup(g.groupId);
      expect(fetched, isNotNull);
      expect(fetched!.name, equals('Squad'));
      expect(fetched.memberIds, equals(['me', 'you']));

      expect(StorageService.instance.getAllGroups().map((x) => x.groupId),
          contains(g.groupId));

      await StorageService.instance.deleteGroup(g.groupId);
      expect(StorageService.instance.getGroup(g.groupId), isNull);
    });

    test('getGroup returns null for an unknown id', () {
      expect(StorageService.instance.getGroup('nope'), isNull);
    });
  });
}
