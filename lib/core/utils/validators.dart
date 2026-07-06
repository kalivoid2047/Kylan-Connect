import '../constants/app_constants.dart';

class Validators {
  static String? validateDisplayName(String? value) {
    final trimmedValue = value?.trim() ?? '';
    if (trimmedValue.isEmpty) {
      return 'Display name is required';
    }
    if (trimmedValue.length < AppConstants.minDisplayNameLength) {
      return 'Display name must be at least ${AppConstants.minDisplayNameLength} characters';
    }
    if (trimmedValue.length > AppConstants.maxDisplayNameLength) {
      return 'Display name must not exceed ${AppConstants.maxDisplayNameLength} characters';
    }
    return null;
  }
  
  static String? validateMessage(String? value) {
    final trimmedValue = value?.trim() ?? '';
    if (trimmedValue.isEmpty) {
      return 'Message cannot be empty';
    }
    if (trimmedValue.length > AppConstants.maxMessageLength) {
      return 'Message must not exceed ${AppConstants.maxMessageLength} characters';
    }
    return null;
  }
  
  static String? validateIpAddress(String? value) {
    if (value == null || value.isEmpty) {
      return 'IP address is required';
    }
    final ipRegex = RegExp(
      r'^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$',
    );
    if (!ipRegex.hasMatch(value)) {
      return 'Invalid IP address format';
    }
    return null;
  }
  
  static String? validatePort(String? value) {
    if (value == null || value.isEmpty) {
      return 'Port is required';
    }
    final port = int.tryParse(value);
    if (port == null) {
      return 'Port must be a number';
    }
    if (port < 1 || port > 65535) {
      return 'Port must be between 1 and 65535';
    }
    return null;
  }
  
  static bool isValidUuid(String value) {
    final uuidRegex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return uuidRegex.hasMatch(value);
  }
}
