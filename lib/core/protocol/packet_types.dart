import 'dart:convert';
import 'dart:typed_data';
import 'package:convert/convert.dart';

/// Enumeration of discrete wire frame message types.
enum FrameType {
  handshakeInit(0x01),
  handshakeResp(0x02),
  handshakeAck(0x03),
  fileMeta(0x10),
  metadataAccept(0x11),
  metadataReject(0x12),
  fileChunk(0x20),
  chunkAck(0x21),
  transferComplete(0x30),
  transferVerified(0x31),
  transferPause(0x40),
  transferResume(0x41),
  transferCancel(0x50),
  transferError(0x51),
  ping(0x60),
  pong(0x61);

  final int opcode;
  const FrameType(this.opcode);

  static const FrameType dataChunk = FrameType.fileChunk;

  bool get isHandshake =>
      this == FrameType.handshakeInit ||
      this == FrameType.handshakeResp ||
      this == FrameType.handshakeAck;

  bool get isControl =>
      this == FrameType.fileMeta ||
      this == FrameType.metadataAccept ||
      this == FrameType.metadataReject ||
      this == FrameType.chunkAck ||
      this == FrameType.transferComplete ||
      this == FrameType.transferVerified ||
      this == FrameType.transferPause ||
      this == FrameType.transferResume ||
      this == FrameType.transferCancel ||
      this == FrameType.transferError ||
      this == FrameType.ping ||
      this == FrameType.pong;

  bool get isData => this == FrameType.fileChunk;

  static FrameType fromOpcode(int opcode) {
    for (final type in FrameType.values) {
      if (type.opcode == opcode) return type;
    }
    throw FormatException(
      'Unknown FrameType opcode: 0x${opcode.toRadixString(16).padLeft(2, '0')}',
    );
  }

  static FrameType? tryFromOpcode(int opcode) {
    for (final type in FrameType.values) {
      if (type.opcode == opcode) return type;
    }
    return null;
  }
}

/// Standardized binary frame envelope transmitted over TCP.
class Frame {
  final FrameType type;
  final int streamId;
  final int sequence;
  final Uint8List payload;
  final int paddingLen;
  final Uint8List? authTag;
  final Uint8List? rawHeader;

  const Frame({
    required this.type,
    required this.streamId,
    required this.sequence,
    required this.payload,
    this.paddingLen = 0,
    this.authTag,
    this.rawHeader,
  });

  int get sequenceOrChunkIndex => sequence;

  /// Factory helper to build a FileChunk frame.
  factory Frame.fileChunk({
    required int streamId,
    required int chunkIndex,
    required Uint8List chunkData,
    int paddingLen = 0,
  }) {
    return Frame(
      type: FrameType.fileChunk,
      streamId: streamId,
      sequence: chunkIndex,
      payload: chunkData,
      paddingLen: paddingLen,
    );
  }

  /// Factory helper to build a ChunkAck frame.
  factory Frame.chunkAck({
    required int streamId,
    required int chunkIndex,
    required int creditsGranted,
  }) {
    return Frame(
      type: FrameType.chunkAck,
      streamId: streamId,
      sequence: chunkIndex,
      payload: ChunkAckPayload(
        chunkIndex: chunkIndex,
        creditsGranted: creditsGranted,
      ).toBytes(),
    );
  }

  /// Factory helper to build a FileMeta frame.
  factory Frame.fileMeta({
    required int streamId,
    required FileMetaPayload metadata,
  }) {
    return Frame(
      type: FrameType.fileMeta,
      streamId: streamId,
      sequence: 0,
      payload: metadata.toBytes(),
    );
  }

  /// Factory helper to build a MetadataAccept frame.
  factory Frame.metadataAccept({
    required int streamId,
    int initialCredits = 4,
  }) {
    final data = ByteData(2);
    data.setUint16(0, initialCredits, Endian.big);
    return Frame(
      type: FrameType.metadataAccept,
      streamId: streamId,
      sequence: 0,
      payload: data.buffer.asUint8List(),
    );
  }

  /// Factory helper to build a MetadataReject frame.
  factory Frame.metadataReject({
    required int streamId,
    required String reason,
  }) {
    return Frame(
      type: FrameType.metadataReject,
      streamId: streamId,
      sequence: 0,
      payload: Uint8List.fromList(utf8.encode(reason)),
    );
  }

  /// Factory helper to build a TransferComplete frame.
  factory Frame.transferComplete({
    required int streamId,
    required int sequence,
    Uint8List? rootSha256,
  }) {
    return Frame(
      type: FrameType.transferComplete,
      streamId: streamId,
      sequence: sequence,
      payload: rootSha256 ?? Uint8List(0),
    );
  }

  /// Factory helper to build a TransferVerified frame.
  factory Frame.transferVerified({
    required int streamId,
    required int sequence,
  }) {
    return Frame(
      type: FrameType.transferVerified,
      streamId: streamId,
      sequence: sequence,
      payload: Uint8List(0),
    );
  }

  /// Factory helper to build a TransferPause frame.
  factory Frame.transferPause({
    required int streamId,
    required int sequence,
  }) {
    return Frame(
      type: FrameType.transferPause,
      streamId: streamId,
      sequence: sequence,
      payload: Uint8List(0),
    );
  }

  /// Factory helper to build a TransferResume frame.
  factory Frame.transferResume({
    required int streamId,
    required int sequence,
  }) {
    return Frame(
      type: FrameType.transferResume,
      streamId: streamId,
      sequence: sequence,
      payload: Uint8List(0),
    );
  }

  /// Factory helper to build a TransferCancel frame.
  factory Frame.transferCancel({
    required int streamId,
    String reason = 'Cancelled by user',
  }) {
    return Frame(
      type: FrameType.transferCancel,
      streamId: streamId,
      sequence: 0,
      payload: Uint8List.fromList(utf8.encode(reason)),
    );
  }

  /// Factory helper to build a TransferError frame.
  factory Frame.transferError({
    required int streamId,
    required int errorCode,
    required String message,
  }) {
    return Frame(
      type: FrameType.transferError,
      streamId: streamId,
      sequence: 0,
      payload: TransferErrorPayload(
        errorCode: errorCode,
        message: message,
      ).toBytes(),
    );
  }

  /// Factory helper to build a Ping frame.
  factory Frame.ping({required int streamId, int? timestamp}) {
    return Frame(
      type: FrameType.ping,
      streamId: streamId,
      sequence: 0,
      payload: PingPongPayload(
        timestamp: timestamp ?? DateTime.now().millisecondsSinceEpoch,
      ).toBytes(),
    );
  }

  /// Factory helper to build a Pong frame.
  factory Frame.pong({required int streamId, required int timestamp}) {
    return Frame(
      type: FrameType.pong,
      streamId: streamId,
      sequence: 0,
      payload: PingPongPayload(timestamp: timestamp).toBytes(),
    );
  }

  @override
  String toString() =>
      'Frame(type: ${type.name}, streamId: $streamId, seq: $sequence, payloadLen: ${payload.length}, paddingLen: $paddingLen)';
}

/// Structured payload model for file transfer metadata manifest.
class FileMetaPayload {
  final String fileName;
  final int totalBytes;
  final Uint8List rootSha256;
  final int chunkSize;
  final int totalChunks;
  final String mimeType;
  final Map<String, dynamic>? customMetadata;

  const FileMetaPayload({
    required this.fileName,
    required this.totalBytes,
    required this.rootSha256,
    this.chunkSize = 65536,
    required this.totalChunks,
    this.mimeType = 'application/octet-stream',
    this.customMetadata,
  });

  String get rootSha256Hex => hex.encode(rootSha256);

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'totalBytes': totalBytes,
        'rootSha256': hex.encode(rootSha256),
        'chunkSize': chunkSize,
        'totalChunks': totalChunks,
        'mimeType': mimeType,
        if (customMetadata != null) 'customMetadata': customMetadata,
      };

  Uint8List toBytes() {
    return Uint8List.fromList(utf8.encode(jsonEncode(toJson())));
  }

  factory FileMetaPayload.fromJson(Map<String, dynamic> map) {
    return FileMetaPayload(
      fileName: map['fileName'] as String,
      totalBytes: (map['totalBytes'] as num).toInt(),
      rootSha256: Uint8List.fromList(hex.decode(map['rootSha256'] as String)),
      chunkSize: (map['chunkSize'] as num?)?.toInt() ?? 65536,
      totalChunks: (map['totalChunks'] as num).toInt(),
      mimeType: (map['mimeType'] as String?) ?? 'application/octet-stream',
      customMetadata: map['customMetadata'] as Map<String, dynamic>?,
    );
  }

  factory FileMetaPayload.fromBytes(Uint8List bytes) {
    final jsonStr = utf8.decode(bytes);
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return FileMetaPayload.fromJson(map);
  }
}

/// Structured payload model for chunk acknowledgement and credit grant.
class ChunkAckPayload {
  final int chunkIndex;
  final int creditsGranted;

  const ChunkAckPayload({
    required this.chunkIndex,
    required this.creditsGranted,
  });

  Uint8List toBytes() {
    final data = ByteData(6);
    data.setUint32(0, chunkIndex, Endian.big);
    data.setUint16(4, creditsGranted, Endian.big);
    return data.buffer.asUint8List();
  }

  factory ChunkAckPayload.fromBytes(Uint8List bytes) {
    if (bytes.length < 6) {
      throw const FormatException('ChunkAckPayload requires at least 6 bytes');
    }
    final data = ByteData.sublistView(bytes);
    return ChunkAckPayload(
      chunkIndex: data.getUint32(0, Endian.big),
      creditsGranted: data.getUint16(4, Endian.big),
    );
  }
}

/// Structured payload model for transfer error frames.
class TransferErrorPayload {
  final int errorCode;
  final String message;

  const TransferErrorPayload({
    required this.errorCode,
    required this.message,
  });

  Uint8List toBytes() {
    final msgBytes = utf8.encode(message);
    final data = ByteData(4 + msgBytes.length);
    data.setUint16(0, errorCode, Endian.big);
    data.setUint16(2, msgBytes.length, Endian.big);
    final bytes = data.buffer.asUint8List();
    bytes.setRange(4, 4 + msgBytes.length, msgBytes);
    return bytes;
  }

  factory TransferErrorPayload.fromBytes(Uint8List bytes) {
    if (bytes.length < 4) {
      throw const FormatException('TransferErrorPayload requires at least 4 bytes');
    }
    final data = ByteData.sublistView(bytes);
    final errorCode = data.getUint16(0, Endian.big);
    final msgLen = data.getUint16(2, Endian.big);
    if (bytes.length < 4 + msgLen) {
      throw const FormatException('TransferErrorPayload message bytes truncated');
    }
    final message = utf8.decode(bytes.sublist(4, 4 + msgLen));
    return TransferErrorPayload(errorCode: errorCode, message: message);
  }
}

/// Structured payload model for ping / pong frames.
class PingPongPayload {
  final int timestamp;

  const PingPongPayload({required this.timestamp});

  Uint8List toBytes() {
    final data = ByteData(8);
    data.setUint64(0, timestamp, Endian.big);
    return data.buffer.asUint8List();
  }

  factory PingPongPayload.fromBytes(Uint8List bytes) {
    if (bytes.length < 8) {
      throw const FormatException('PingPongPayload requires at least 8 bytes');
    }
    final data = ByteData.sublistView(bytes);
    return PingPongPayload(timestamp: data.getUint64(0, Endian.big));
  }
}
