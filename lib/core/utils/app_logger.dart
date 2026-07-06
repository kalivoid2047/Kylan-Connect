import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

class AppLogger {
  static final AppLogger _instance = AppLogger._internal();
  static AppLogger get instance => _instance;

  late final Logger _logger;

  AppLogger._internal() {
    _logger = Logger('KylanConnect');
    _setupLogging();
  }

  void _setupLogging() {
    hierarchicalLoggingEnabled = true;
    _logger.level = Level.ALL;
    _logger.onRecord.listen((record) {
      if (kDebugMode) {
        final prefix = '[${record.level.name}] ${record.loggerName}: ${record.message}';
        debugPrint(prefix);
        if (record.error != null) debugPrint('  Error: ${record.error}');
        if (record.stackTrace != null) debugPrint('  Stack: ${record.stackTrace}');
      }
    });
  }

  void debug(String message) => _logger.fine(message);
  void info(String message) => _logger.info(message);
  void warning(String message) => _logger.warning(message);
  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      _logger.severe(message, error, stackTrace);
}
