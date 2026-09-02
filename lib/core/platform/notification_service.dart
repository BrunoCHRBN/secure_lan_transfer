import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Platform-aware notification service for file transfer progress.
///
/// On Android, shows progress and completion notifications using
/// [flutter_local_notifications]. On desktop platforms (Windows, Linux, macOS),
/// all methods are silent no-ops.
class NotificationService {
  static const _channelId = 'slft_transfer';
  static const _channelName = 'File Transfer';
  static const _progressNotificationId = 1;
  static const _completionNotificationId = 2;

  FlutterLocalNotificationsPlugin? _plugin;
  bool _initialized = false;

  /// Whether the current platform supports notifications.
  bool get _isSupported => Platform.isAndroid;

  /// Initialize notification channels and request permissions.
  Future<void> initialize() async {
    if (!_isSupported) return;

    _plugin = FlutterLocalNotificationsPlugin();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin!.initialize(initSettings);

    // Create the notification channel explicitly.
    final androidPlugin =
        _plugin!.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Notifications for file transfer progress and completion',
        importance: Importance.high,
      ),
    );

    _initialized = true;
  }

  /// Show or update a progress notification for an ongoing transfer.
  Future<void> showTransferProgress({
    required String fileName,
    required double progress,
    required String speedText,
  }) async {
    if (!_isSupported || !_initialized) return;

    final percent = (progress * 100).round().clamp(0, 100);

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Notifications for file transfer progress and completion',
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      ongoing: true,
      showProgress: true,
      maxProgress: 100,
      progress: percent,
      subText: speedText,
      category: AndroidNotificationCategory.progress,
    );

    await _plugin!.show(
      _progressNotificationId,
      'Sending $fileName',
      '$percent% • $speedText',
      NotificationDetails(android: androidDetails),
    );
  }

  /// Show a completion notification and cancel the progress notification.
  Future<void> showTransferComplete({
    required String fileName,
    required int totalBytes,
  }) async {
    if (!_isSupported || !_initialized) return;

    // Cancel the ongoing progress notification.
    await _plugin!.cancel(_progressNotificationId);

    final sizeText = _formatBytes(totalBytes);

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Notifications for file transfer progress and completion',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.status,
    );

    await _plugin!.show(
      _completionNotificationId,
      'Transfer Complete',
      '$fileName ($sizeText)',
      NotificationDetails(android: androidDetails),
    );
  }

  /// Show a failure notification and cancel the progress notification.
  Future<void> showTransferFailed({
    required String fileName,
    required String error,
  }) async {
    if (!_isSupported || !_initialized) return;

    // Cancel the ongoing progress notification.
    await _plugin!.cancel(_progressNotificationId);

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Notifications for file transfer progress and completion',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.error,
    );

    await _plugin!.show(
      _completionNotificationId,
      'Transfer Failed',
      '$fileName — $error',
      NotificationDetails(android: androidDetails),
    );
  }

  /// Cancel all active notifications.
  Future<void> cancelAll() async {
    if (!_isSupported || !_initialized) return;
    await _plugin!.cancelAll();
  }

  /// Formats byte counts into a human-readable string.
  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
