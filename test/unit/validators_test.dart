import 'package:flutter_test/flutter_test.dart';
import 'package:kylan_connect/core/utils/validators.dart';

void main() {
  group('Validators', () {
    group('validateDisplayName', () {
      test('should return null for valid display name', () {
        const displayName = 'John Doe';
        final result = Validators.validateDisplayName(displayName);
        expect(result, isNull);
      });

      test('should return error for empty display name', () {
        const displayName = '';
        final result = Validators.validateDisplayName(displayName);
        expect(result, isNotNull);
        expect(result, contains('required'));
      });

      test('should return error for display name that is too short', () {
        const displayName = 'J';
        final result = Validators.validateDisplayName(displayName);
        expect(result, isNotNull);
        expect(result, contains('at least'));
      });

      test('should return error for display name that is too long', () {
        final displayName = 'A' * 31;
        final result = Validators.validateDisplayName(displayName);
        expect(result, isNotNull);
        expect(result, contains('exceed'));
      });
    });

    group('validateMessage', () {
      test('should return null for valid message', () {
        const message = 'Hello, how are you?';
        final result = Validators.validateMessage(message);
        expect(result, isNull);
      });

      test('should return error for empty message', () {
        const message = '';
        final result = Validators.validateMessage(message);
        expect(result, isNotNull);
        expect(result, contains('empty'));
      });

      test('should return error for message that is too long', () {
        final message = 'A' * 1001;
        final result = Validators.validateMessage(message);
        expect(result, isNotNull);
        expect(result, contains('exceed'));
      });
    });

    group('validateIpAddress', () {
      test('should return null for valid IP address', () {
        const ipAddress = '192.168.1.1';
        final result = Validators.validateIpAddress(ipAddress);
        expect(result, isNull);
      });

      test('should return error for empty IP address', () {
        const ipAddress = '';
        final result = Validators.validateIpAddress(ipAddress);
        expect(result, isNotNull);
        expect(result, contains('required'));
      });

      test('should return error for invalid IP address', () {
        const ipAddress = 'invalid-ip';
        final result = Validators.validateIpAddress(ipAddress);
        expect(result, isNotNull);
        expect(result, contains('Invalid'));
      });
    });

    group('isValidUuid', () {
      test('should return true for valid UUID', () {
        const uuid = '550e8400-e29b-41d4-a716-446655440000';
        final result = Validators.isValidUuid(uuid);
        expect(result, isTrue);
      });

      test('should return false for invalid UUID', () {
        const uuid = 'not-a-uuid';
        final result = Validators.isValidUuid(uuid);
        expect(result, isFalse);
      });
    });
  });
}
