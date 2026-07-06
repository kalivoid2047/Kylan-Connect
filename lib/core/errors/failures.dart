abstract class Failure {
  final String message;
  final dynamic error;

  const Failure(this.message, [this.error]);

  @override
  String toString() => message;
}

class NetworkFailure extends Failure {
  const NetworkFailure(super.message, [super.error]);
}

class DiscoveryFailure extends Failure {
  const DiscoveryFailure(super.message, [super.error]);
}

class ConnectionFailure extends Failure {
  const ConnectionFailure(super.message, [super.error]);
}

class MessagingFailure extends Failure {
  const MessagingFailure(super.message, [super.error]);
}

class EncryptionFailure extends Failure {
  const EncryptionFailure(super.message, [super.error]);
}

class StorageFailure extends Failure {
  const StorageFailure(super.message, [super.error]);
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message, [super.error]);
}

class AuthenticationFailure extends Failure {
  const AuthenticationFailure(super.message, [super.error]);
}

class ServerFailure extends Failure {
  const ServerFailure(super.message, [super.error]);
}

class UnknownFailure extends Failure {
  const UnknownFailure(super.message, [super.error]);
}
