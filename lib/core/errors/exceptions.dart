abstract class AppException implements Exception {
  final String message;
  final dynamic error;

  const AppException(this.message, [this.error]);

  @override
  String toString() => message;
}

class NetworkException extends AppException {
  const NetworkException(super.message, [super.error]);
}

class DiscoveryException extends AppException {
  const DiscoveryException(super.message, [super.error]);
}

class ConnectionException extends AppException {
  const ConnectionException(super.message, [super.error]);
}

class MessagingException extends AppException {
  const MessagingException(super.message, [super.error]);
}

class EncryptionException extends AppException {
  const EncryptionException(super.message, [super.error]);
}

class ValidationException extends AppException {
  const ValidationException(super.message, [super.error]);
}

class CryptoException extends AppException {
  const CryptoException(super.message, [super.error]);
}
