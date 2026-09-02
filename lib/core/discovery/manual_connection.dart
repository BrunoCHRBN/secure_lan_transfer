import 'dart:async';
import 'dart:io';
import '../models/peer_device.dart';
import '../protocol/frame_codec.dart';
import '../protocol/packet_types.dart';

/// Error categories for manual IP/Port connection attempts.
enum ManualConnectionErrorCode {
  invalidAddress,
  invalidPort,
  connectionTimeout,
  connectionRefused,
  networkUnreachable,
  handshakeFailed,
  unknown;
}

/// Exception thrown when manual device probing fails.
class ManualConnectionException implements Exception {
  final ManualConnectionErrorCode code;
  final String message;
  final dynamic underlyingError;

  const ManualConnectionException({
    required this.code,
    required this.message,
    this.underlyingError,
  });

  @override
  String toString() => 'ManualConnectionException($code): $message';
}

/// Tertiary fallback prober validating user-entered IP:Port via TCP socket ping checks.
class ManualConnectionProber {
  final FrameCodec _codec;

  ManualConnectionProber({FrameCodec? codec}) : _codec = codec ?? FrameCodec();

  /// Validates IP address / hostname and port, performs TCP ping check,
  /// and constructs a valid [PeerDevice] instance.
  Future<PeerDevice> probe(
    String host, {
    int port = 42385,
    Duration timeout = const Duration(seconds: 3),
    String? deviceName,
  }) async {
    final sanitizedHost = host.trim();
    if (sanitizedHost.isEmpty) {
      throw const ManualConnectionException(
        code: ManualConnectionErrorCode.invalidAddress,
        message: 'Host address cannot be empty',
      );
    }

    if (port <= 0 || port > 65535) {
      throw const ManualConnectionException(
        code: ManualConnectionErrorCode.invalidPort,
        message: 'Port must be between 1 and 65535',
      );
    }

    Socket? socket;
    try {
      socket = await Socket.connect(
        sanitizedHost,
        port,
        timeout: timeout,
      );

      // Perform optional TCP ping frame probe
      try {
        final pingFrame = Frame.ping(streamId: 0);
        final encodedPing = await _codec.encodeFrame(pingFrame);
        socket.add(encodedPing);
        await socket.flush();
      } catch (_) {
        // Ping frame optional if remote is raw TCP socket
      }

      final resolvedIp = socket.remoteAddress.address;
      final id = 'manual-$resolvedIp-$port';
      final name = deviceName ?? 'Device ($sanitizedHost)';

      return PeerDevice(
        id: id,
        name: name,
        os: 'unknown',
        addresses: [resolvedIp],
        port: port,
        discoveryMethod: DiscoveryMethod.manual,
        lastSeen: DateTime.now(),
        isStale: false,
      );
    } on SocketException catch (e) {
      if (e.osError?.errorCode == 10061 ||
          e.osError?.errorCode == 111 ||
          e.osError?.errorCode == 61) {
        throw ManualConnectionException(
          code: ManualConnectionErrorCode.connectionRefused,
          message:
              'Connection refused at $sanitizedHost:$port. Ensure receiver is running.',
          underlyingError: e,
        );
      }
      throw ManualConnectionException(
        code: ManualConnectionErrorCode.networkUnreachable,
        message: 'Network error reaching $sanitizedHost:$port: ${e.message}',
        underlyingError: e,
      );
    } on TimeoutException catch (e) {
      throw ManualConnectionException(
        code: ManualConnectionErrorCode.connectionTimeout,
        message:
            'Connection timed out after ${timeout.inSeconds}s to $sanitizedHost:$port',
        underlyingError: e,
      );
    } catch (e) {
      throw ManualConnectionException(
        code: ManualConnectionErrorCode.unknown,
        message: 'Unexpected error probing $sanitizedHost:$port: $e',
        underlyingError: e,
      );
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
  }
}
