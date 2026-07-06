class StorageException implements Exception {
  final String message;
  final Object? originalError;

  StorageException(this.message, [this.originalError]);

  @override
  String toString() =>
      'StorageException: $message${originalError != null ? ' | Original Error: $originalError' : ''}';
}
