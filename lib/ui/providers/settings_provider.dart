import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../theme/app_theme.dart';

/// Provider managing application configuration, security options, theme, and downloads path with SharedPreferences persistence.
class SettingsProvider extends ChangeNotifier {
  static const String _keyDeviceName = 'slft_device_name';
  static const String _keyDeviceId = 'slft_device_id';
  static const String _keyTransferPort = 'slft_transfer_port';
  static const String _keyDownloadDir = 'slft_download_dir';
  static const String _keyThemeMode = 'slft_theme_mode';
  static const String _keyOpenFolder = 'slft_open_folder';
  static const String _keyAutoAccept = 'slft_auto_accept';
  static const String _keyAutoVerify = 'slft_auto_verify';
  static const String _keyTrafficPadding = 'slft_traffic_padding';
  static const String _keySecureWipe = 'slft_secure_wipe';
  static const String _keyZeroMetadata = 'slft_zero_metadata';
  static const String _keyNetworkPermission = 'slft_network_permission';
  static const String _keyCreditWindow = 'slft_credit_window';
  static const String _keyChunkSize = 'slft_chunk_size';

  // Device Identity
  String _deviceName = '';
  String _deviceId = '';
  int _transferPort = 42385;

  // Network Permission
  bool? _networkPermissionGranted;

  // Theme & Appearance
  AppThemeMode _themeMode = AppThemeMode.oled;
  Color _accentColor = AppPalettes.cyberEmerald;

  // Storage & Downloads
  String _downloadDirectoryPath = '';
  bool _openFolderOnComplete = true;

  // Security & Privacy
  bool _autoAcceptPairedDevices = false;
  bool _autoVerifySas = false;
  bool _enableTrafficPadding = true;
  bool _secureWipeOnAbort = true;
  bool _zeroMetadataMode = true;

  // Performance & Rate Limits
  int _maxSpeedLimitBytesPerSec = 0; // 0 = unlimited
  int _creditWindowSize = 16; // 16 slots in-flight
  int _chunkSize = 262144; // 256 KB chunk size for high LAN throughput

  bool _isInitialized = false;

  // Getters
  String get deviceName => _deviceName;
  String get deviceId => _deviceId;
  int get transferPort => _transferPort;
  bool get isNetworkPermissionGranted => _networkPermissionGranted == true;
  bool? get networkPermissionGranted => _networkPermissionGranted;
  bool get hasAnsweredNetworkPermission => _networkPermissionGranted != null;
  AppThemeMode get themeMode => _themeMode;
  Color get accentColor => _accentColor;
  String get downloadDirectoryPath => _downloadDirectoryPath;
  bool get openFolderOnComplete => _openFolderOnComplete;
  bool get autoAcceptPairedDevices => _autoAcceptPairedDevices;
  bool get autoVerifySas => _autoVerifySas;
  bool get enableTrafficPadding => _enableTrafficPadding;
  bool get secureWipeOnAbort => _secureWipeOnAbort;
  bool get zeroMetadataMode => _zeroMetadataMode;
  int get maxSpeedLimitBytesPerSec => _maxSpeedLimitBytesPerSec;
  int get creditWindowSize => _creditWindowSize;
  int get chunkSize => _chunkSize;
  bool get isInitialized => _isInitialized;

  SettingsProvider() {
    _deviceId = const Uuid().v4();
    final osPrefix = Platform.operatingSystem.toUpperCase();
    final shortId = _deviceId.substring(0, 4).toUpperCase();
    _deviceName = '$osPrefix-Node-$shortId';
    _downloadDirectoryPath = Directory.current.path;
  }

  /// Initializes default directories and loads persisted preferences.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      final savedId = prefs.getString(_keyDeviceId);
      if (savedId != null && savedId.isNotEmpty) {
        _deviceId = savedId;
      } else {
        await prefs.setString(_keyDeviceId, _deviceId);
      }

      final savedName = prefs.getString(_keyDeviceName);
      if (savedName != null && savedName.isNotEmpty) {
        _deviceName = savedName;
      }

      final savedPort = prefs.getInt(_keyTransferPort);
      if (savedPort != null && savedPort > 1024) {
        _transferPort = savedPort;
      }

      final savedTheme = prefs.getString(_keyThemeMode);
      if (savedTheme != null) {
        _themeMode = AppThemeMode.values.firstWhere(
          (e) => e.name == savedTheme,
          orElse: () => AppThemeMode.oled,
        );
      }

      _openFolderOnComplete = prefs.getBool(_keyOpenFolder) ?? true;
      _autoAcceptPairedDevices = prefs.getBool(_keyAutoAccept) ?? false;
      _autoVerifySas = prefs.getBool(_keyAutoVerify) ?? false;
      _enableTrafficPadding = prefs.getBool(_keyTrafficPadding) ?? true;
      _secureWipeOnAbort = prefs.getBool(_keySecureWipe) ?? true;
      _zeroMetadataMode = prefs.getBool(_keyZeroMetadata) ?? true;
      _creditWindowSize = prefs.getInt(_keyCreditWindow) ?? 16;
      _chunkSize = prefs.getInt(_keyChunkSize) ?? 262144;

      if (prefs.containsKey(_keyNetworkPermission)) {
        _networkPermissionGranted = prefs.getBool(_keyNetworkPermission);
      } else {
        _networkPermissionGranted = null;
      }

      final savedDir = prefs.getString(_keyDownloadDir);
      if (savedDir != null && Directory(savedDir).existsSync()) {
        _downloadDirectoryPath = savedDir;
      } else {
        try {
          final downloadsDir = await getDownloadsDirectory();
          if (downloadsDir != null && downloadsDir.existsSync()) {
            _downloadDirectoryPath = downloadsDir.path;
          } else {
            final appDocs = await getApplicationDocumentsDirectory();
            _downloadDirectoryPath = appDocs.path;
          }
        } catch (_) {
          _downloadDirectoryPath = Directory.current.path;
        }
      }
    } catch (_) {
      _downloadDirectoryPath = Directory.current.path;
    }

    _isInitialized = true;
    notifyListeners();
  }

  Future<void> _persistString(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (_) {}
  }

  Future<void> _persistBool(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }

  Future<void> _persistInt(String key, int value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(key, value);
    } catch (_) {}
  }

  void setDeviceName(String name) {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty && trimmed != _deviceName) {
      _deviceName = trimmed;
      _persistString(_keyDeviceName, trimmed);
      notifyListeners();
    }
  }

  void setTransferPort(int port) {
    if (port > 1024 && port <= 65535 && port != _transferPort) {
      _transferPort = port;
      _persistInt(_keyTransferPort, port);
      notifyListeners();
    }
  }

  void setThemeMode(AppThemeMode mode) {
    if (mode != _themeMode) {
      _themeMode = mode;
      _persistString(_keyThemeMode, mode.name);
      notifyListeners();
    }
  }

  void setAccentColor(Color color) {
    if (color != _accentColor) {
      _accentColor = color;
      notifyListeners();
    }
  }

  void setDownloadDirectory(String path) {
    if (path.trim().isNotEmpty && path != _downloadDirectoryPath) {
      _downloadDirectoryPath = path.trim();
      _persistString(_keyDownloadDir, path.trim());
      notifyListeners();
    }
  }

  void setOpenFolderOnComplete(bool value) {
    if (value != _openFolderOnComplete) {
      _openFolderOnComplete = value;
      _persistBool(_keyOpenFolder, value);
      notifyListeners();
    }
  }

  void setAutoAcceptPairedDevices(bool value) {
    if (value != _autoAcceptPairedDevices) {
      _autoAcceptPairedDevices = value;
      _persistBool(_keyAutoAccept, value);
      notifyListeners();
    }
  }

  void setAutoVerifySas(bool value) {
    if (value != _autoVerifySas) {
      _autoVerifySas = value;
      _persistBool(_keyAutoVerify, value);
      notifyListeners();
    }
  }

  void setEnableTrafficPadding(bool value) {
    if (value != _enableTrafficPadding) {
      _enableTrafficPadding = value;
      _persistBool(_keyTrafficPadding, value);
      notifyListeners();
    }
  }

  void setSecureWipeOnAbort(bool value) {
    if (value != _secureWipeOnAbort) {
      _secureWipeOnAbort = value;
      _persistBool(_keySecureWipe, value);
      notifyListeners();
    }
  }

  void setZeroMetadataMode(bool value) {
    if (value != _zeroMetadataMode) {
      _zeroMetadataMode = value;
      _persistBool(_keyZeroMetadata, value);
      notifyListeners();
    }
  }

  void setSpeedLimit(int bytesPerSec) {
    if (bytesPerSec >= 0 && bytesPerSec != _maxSpeedLimitBytesPerSec) {
      _maxSpeedLimitBytesPerSec = bytesPerSec;
      notifyListeners();
    }
  }

  void setCreditWindowSize(int windowSize) {
    if (windowSize >= 1 && windowSize <= 32 && windowSize != _creditWindowSize) {
      _creditWindowSize = windowSize;
      _persistInt(_keyCreditWindow, windowSize);
      notifyListeners();
    }
  }

  void setChunkSize(int size) {
    if (size >= 1024 && size <= 1048576 && size != _chunkSize) {
      _chunkSize = size;
      _persistInt(_keyChunkSize, size);
      notifyListeners();
    }
  }

  Future<void> setNetworkPermission(bool granted) async {
    _networkPermissionGranted = granted;
    await _persistBool(_keyNetworkPermission, granted);
    notifyListeners();
  }

  /// Resets configuration to default settings.
  void resetToDefaults() {
    _themeMode = AppThemeMode.oled;
    _accentColor = AppPalettes.cyberEmerald;
    _transferPort = 42385;
    _openFolderOnComplete = true;
    _autoAcceptPairedDevices = false;
    _autoVerifySas = false;
    _enableTrafficPadding = true;
    _secureWipeOnAbort = true;
    _zeroMetadataMode = true;
    _maxSpeedLimitBytesPerSec = 0;
    _creditWindowSize = 16;
    _chunkSize = 262144;

    SharedPreferences.getInstance().then((prefs) => prefs.clear()).catchError((_) => false);

    notifyListeners();
  }
}
