import 'dart:io';
import 'package:flutter/services.dart';
import '../core/utils/app_logger.dart';

/// Thin wrapper around the platform-specific background-execution channel.
///
/// Android: starts/stops a foreground service that holds a PARTIAL_WAKE_LOCK,
///          keeping the Flutter process (and all Dart singletons) alive.
/// iOS:     schedules a BGAppRefreshTask so the OS wakes the app periodically
///          to reconnect to peers and flush pending messages.
class BackgroundService {
  static final BackgroundService _instance = BackgroundService._internal();
  static BackgroundService get instance => _instance;

  static const _channel =
      MethodChannel('com.kylanconnect.app/background');

  BackgroundService._internal();

  Future<void> start() async {
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod<void>('startForegroundService');
        AppLogger.instance.info('Android foreground service started');
      } else if (Platform.isIOS) {
        await _channel.invokeMethod<void>('scheduleAppRefresh');
        AppLogger.instance.info('iOS background refresh scheduled');
      }
    } catch (e, s) {
      AppLogger.instance.error('BackgroundService.start failed', e, s);
    }
  }

  Future<void> stop() async {
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod<void>('stopForegroundService');
        AppLogger.instance.info('Android foreground service stopped');
      }
      // iOS: the BGTask simply won't be re-scheduled after stop() — no
      // explicit cancellation is needed.
    } catch (e, s) {
      AppLogger.instance.error('BackgroundService.stop failed', e, s);
    }
  }
}
