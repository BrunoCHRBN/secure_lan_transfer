import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../crypto/cipher_suite.dart';
import '../crypto/obfuscation.dart';
import '../crypto/sas_authenticator.dart';
import '../protocol/frame_codec.dart';
import '../protocol/frame_stream_transformer.dart';
import '../protocol/packet_types.dart';

/// Handshake result container containing established session keys, SAS code,
/// and the active decoded frame stream.
class HandshakeResult {
  final Socket socket;
  final SessionKeys sessionKeys;
  final SasCode sasCode;
  final TransferRole role;
  final Uint8List localPublicKey;
  final Uint8List remotePublicKey;
  final Uint8List localNonce;
  final Uint8List remoteNonce;
  final Uint8List transcriptHash;
  final Stream<Frame> incomingFrameStream;

  const HandshakeResult({
    required this.socket,
    required this.sessionKeys,
    required this.sasCode,
    required this.role,
    required this.localPublicKey,
    required this.remotePublicKey,
    required this.localNonce,
    required this.remoteNonce,
    required this.transcriptHash,
    required this.incomingFrameStream,
  });
}

/// Options controlling handshake timeouts and parameters.
class HandshakeOptions {
  final Duration timeout;
  final int minJitter;
  final int maxJitter;
  final CipherType cipherType;

  const HandshakeOptions({
    this.timeout = const Duration(seconds: 60),
    this.minJitter = 32,
    this.maxJitter = 96,
    this.cipherType = CipherType.chacha20Poly1305,
  });
}

/// Exception thrown on handshake failure or cryptographic error.
class HandshakeException implements Exception {
  final String message;
  final dynamic cause;
  const HandshakeException(this.message, [this.cause]);

  @override
  String toString() =>
      'HandshakeException: $message${cause != null ? ' (Cause: $cause)' : ''}';
}

/// Cryptographic 3-Way Handshake Protocol Handler using X25519 ECDH,
/// HKDF-SHA256 session key derivation, and SAS visual/numeric verification.
class HandshakeProtocol {
  final CipherSuite cipherSuite;
  final FrameCodec frameCodec;
  final HandshakeOptions options;

  HandshakeProtocol({
    CipherSuite? cipherSuite,
    FrameCodec? frameCodec,
    HandshakeOptions? options,
  })  : cipherSuite = cipherSuite ?? CipherSuite(),
        frameCodec = frameCodec ?? FrameCodec(),
        options = options ?? const HandshakeOptions();

  /// Executes the Client (Initiator) side 3-way handshake over [socket].
  Future<HandshakeResult> performClientHandshake(
    Socket socket, {
    Future<bool> Function(SasCode sasCode)? onVerifySas,
  }) async {
    final transformer = FrameStreamTransformer(codec: frameCodec);
    final rawStream = socket.transform(transformer);

    final incomingFrameController = StreamController<Frame>();
    final respCompleter = Completer<Frame>();
    respCompleter.future.ignore();
    final ackCompleter = Completer<Frame>();
    ackCompleter.future.ignore();
    bool inHandshake = true;

    final sub = rawStream.listen(
      (frame) {
        if (inHandshake) {
          if (frame.type == FrameType.handshakeResp &&
              !respCompleter.isCompleted) {
            respCompleter.complete(frame);
          } else if (frame.type == FrameType.handshakeAck &&
              !ackCompleter.isCompleted) {
            ackCompleter.complete(frame);
          } else if (frame.type == FrameType.transferCancel ||
              frame.type == FrameType.transferError) {
            final err = HandshakeException(
                'Peer aborted handshake: ${frame.type.name}');
            if (!respCompleter.isCompleted) respCompleter.completeError(err);
            if (!ackCompleter.isCompleted) ackCompleter.completeError(err);
          }
        } else {
          incomingFrameController.add(frame);
        }
      },
      onError: (e, st) {
        final err = e is HandshakeException
            ? e
            : HandshakeException('Handshake error: $e', e);
        if (!respCompleter.isCompleted) respCompleter.completeError(err, st);
        if (!ackCompleter.isCompleted) ackCompleter.completeError(err, st);
        if (!incomingFrameController.isClosed) {
          if (incomingFrameController.hasListener) {
            incomingFrameController.addError(err, st);
          }
          incomingFrameController.close();
        }
      },
      onDone: () {
        const err =
            HandshakeException('Socket closed prematurely during handshake');
        if (!respCompleter.isCompleted) respCompleter.completeError(err);
        if (!ackCompleter.isCompleted) ackCompleter.completeError(err);
        if (!incomingFrameController.isClosed) {
          incomingFrameController.close();
        }
      },
    );

    try {
      // 1. Generate Client KeyPair & Nonce
      final keyPairData = await cipherSuite.generateEphemeralKeyPair();
      final clientEnvelope = HandshakeEnvelope.create(
        publicKey: keyPairData.publicKeyBytes,
        nonce: keyPairData.nonce,
        customJitterLength: options.minJitter +
            (options.maxJitter > options.minJitter ? 16 : 0),
      );

      // 2. Send handshakeInit Frame (unencrypted)
      final initFrame = Frame(
        type: FrameType.handshakeInit,
        streamId: 0,
        sequence: 0,
        payload: clientEnvelope.rawEnvelopeBytes,
      );
      final encodedInit = await frameCodec.encodeFrame(initFrame, keys: null);
      socket.add(encodedInit);
      await socket.flush();

      // 3. Await handshakeResp Frame from Server
      final respFrame = await respCompleter.future.timeout(
        options.timeout,
        onTimeout: () =>
            throw const HandshakeException('Timed out awaiting handshakeResp'),
      );

      final serverEnvelope = HandshakeEnvelope.parse(respFrame.payload);

      // 4. Compute Shared Secret & Transcript Hash
      final sharedSecret = await cipherSuite.computeSharedSecret(
        localKeyPair: keyPairData.keyPair,
        remotePublicKeyBytes: serverEnvelope.publicKey,
      );

      final transcriptHash = await cipherSuite.computeTranscriptHash(
        initiatorPk: keyPairData.publicKeyBytes,
        receiverPk: serverEnvelope.publicKey,
        initiatorNonce: keyPairData.nonce,
        receiverNonce: serverEnvelope.nonce,
        sharedSecret: sharedSecret,
      );

      // 5. Generate SAS & Derive Session Keys
      final sasCode = SasAuthenticator.generateSas(transcriptHash);
      final sessionKeys = await cipherSuite.deriveSessionKeys(
        sharedSecret: sharedSecret,
        initiatorNonce: keyPairData.nonce,
        receiverNonce: serverEnvelope.nonce,
        transcriptHash: transcriptHash,
        role: TransferRole.initiator,
        cipherType: options.cipherType,
      );

      // 6. SAS Verification Hook
      if (onVerifySas != null) {
        final verified = await onVerifySas(sasCode);
        if (!verified) {
          final cancelFrame =
              Frame.transferCancel(streamId: 0, reason: 'SAS rejected by user');
          socket.add(
              await frameCodec.encodeFrame(cancelFrame, keys: sessionKeys));
          await socket.flush();
          throw const HandshakeException(
              'SAS verification rejected by user');
        }
      }

      // 7. Update Session Keys on Transformer & Send encrypted handshakeAck
      transformer.updateSessionKeys(sessionKeys);

      final clientAckFrame = Frame(
        type: FrameType.handshakeAck,
        streamId: 0,
        sequence: 0,
        payload: Uint8List.fromList(utf8.encode('OK')),
      );
      final encodedAck =
          await frameCodec.encodeFrame(clientAckFrame, keys: sessionKeys);
      socket.add(encodedAck);
      await socket.flush();

      // 8. Await Server encrypted handshakeAck
      await ackCompleter.future.timeout(
        options.timeout,
        onTimeout: () => throw const HandshakeException(
            'Timed out awaiting server handshakeAck'),
      );

      inHandshake = false;

      return HandshakeResult(
        socket: socket,
        sessionKeys: sessionKeys,
        sasCode: sasCode,
        role: TransferRole.initiator,
        localPublicKey: keyPairData.publicKeyBytes,
        remotePublicKey: serverEnvelope.publicKey,
        localNonce: keyPairData.nonce,
        remoteNonce: serverEnvelope.nonce,
        transcriptHash: transcriptHash,
        incomingFrameStream: incomingFrameController.stream,
      );
    } catch (e) {
      await sub.cancel();
      rethrow;
    }
  }

  /// Executes the Server (Responder) side 3-way handshake over [socket].
  Future<HandshakeResult> performServerHandshake(
    Socket socket, {
    Future<bool> Function(SasCode sasCode)? onVerifySas,
  }) async {
    final transformer = FrameStreamTransformer(codec: frameCodec);
    final rawStream = socket.transform(transformer);

    final incomingFrameController = StreamController<Frame>();
    final initCompleter = Completer<Frame>();
    initCompleter.future.ignore();
    final ackCompleter = Completer<Frame>();
    ackCompleter.future.ignore();
    bool inHandshake = true;

    final sub = rawStream.listen(
      (frame) {
        if (inHandshake) {
          if (frame.type == FrameType.handshakeInit &&
              !initCompleter.isCompleted) {
            initCompleter.complete(frame);
          } else if (frame.type == FrameType.handshakeAck &&
              !ackCompleter.isCompleted) {
            ackCompleter.complete(frame);
          } else if (frame.type == FrameType.transferCancel ||
              frame.type == FrameType.transferError) {
            final err = HandshakeException(
                'Peer aborted handshake: ${frame.type.name}');
            if (!initCompleter.isCompleted) initCompleter.completeError(err);
            if (!ackCompleter.isCompleted) ackCompleter.completeError(err);
          }
        } else {
          incomingFrameController.add(frame);
        }
      },
      onError: (e, st) {
        final err = e is HandshakeException
            ? e
            : HandshakeException('Handshake error: $e', e);
        if (!initCompleter.isCompleted) initCompleter.completeError(err, st);
        if (!ackCompleter.isCompleted) ackCompleter.completeError(err, st);
        if (!incomingFrameController.isClosed) {
          if (incomingFrameController.hasListener) {
            incomingFrameController.addError(err, st);
          }
          incomingFrameController.close();
        }
      },
      onDone: () {
        const err =
            HandshakeException('Socket closed prematurely during handshake');
        if (!initCompleter.isCompleted) initCompleter.completeError(err);
        if (!ackCompleter.isCompleted) ackCompleter.completeError(err);
        if (!incomingFrameController.isClosed) {
          incomingFrameController.close();
        }
      },
    );

    try {
      // 1. Await handshakeInit Frame from Client
      final initFrame = await initCompleter.future.timeout(
        options.timeout,
        onTimeout: () =>
            throw const HandshakeException('Timed out awaiting handshakeInit'),
      );

      final clientEnvelope = HandshakeEnvelope.parse(initFrame.payload);

      // 2. Generate Server KeyPair & Nonce
      final keyPairData = await cipherSuite.generateEphemeralKeyPair();
      final serverEnvelope = HandshakeEnvelope.create(
        publicKey: keyPairData.publicKeyBytes,
        nonce: keyPairData.nonce,
        customJitterLength: options.minJitter +
            (options.maxJitter > options.minJitter ? 16 : 0),
      );

      // 3. Compute Shared Secret & Transcript Hash
      final sharedSecret = await cipherSuite.computeSharedSecret(
        localKeyPair: keyPairData.keyPair,
        remotePublicKeyBytes: clientEnvelope.publicKey,
      );

      final transcriptHash = await cipherSuite.computeTranscriptHash(
        initiatorPk: clientEnvelope.publicKey,
        receiverPk: keyPairData.publicKeyBytes,
        initiatorNonce: clientEnvelope.nonce,
        receiverNonce: keyPairData.nonce,
        sharedSecret: sharedSecret,
      );

      // 4. Generate SAS & Derive Session Keys
      final sasCode = SasAuthenticator.generateSas(transcriptHash);
      final sessionKeys = await cipherSuite.deriveSessionKeys(
        sharedSecret: sharedSecret,
        initiatorNonce: clientEnvelope.nonce,
        receiverNonce: keyPairData.nonce,
        transcriptHash: transcriptHash,
        role: TransferRole.receiver,
        cipherType: options.cipherType,
      );

      // 5. Send handshakeResp Frame (unencrypted)
      final respFrame = Frame(
        type: FrameType.handshakeResp,
        streamId: 0,
        sequence: 0,
        payload: serverEnvelope.rawEnvelopeBytes,
      );
      final encodedResp = await frameCodec.encodeFrame(respFrame, keys: null);
      socket.add(encodedResp);
      await socket.flush();

      // 6. Update Session Keys on Transformer before reading Client encrypted frames
      transformer.updateSessionKeys(sessionKeys);

      // 7. SAS Verification Hook
      if (onVerifySas != null) {
        final verified = await onVerifySas(sasCode);
        if (!verified) {
          final cancelFrame =
              Frame.transferCancel(streamId: 0, reason: 'SAS rejected by user');
          socket.add(
              await frameCodec.encodeFrame(cancelFrame, keys: sessionKeys));
          await socket.flush();
          throw const HandshakeException(
              'SAS verification rejected by user');
        }
      }

      // 8. Await Client encrypted handshakeAck
      await ackCompleter.future.timeout(
        options.timeout,
        onTimeout: () => throw const HandshakeException(
            'Timed out awaiting client handshakeAck'),
      );

      // 9. Send Server encrypted handshakeAck confirmation
      final serverAckFrame = Frame(
        type: FrameType.handshakeAck,
        streamId: 0,
        sequence: 0,
        payload: Uint8List.fromList(utf8.encode('ACK')),
      );
      final encodedAck =
          await frameCodec.encodeFrame(serverAckFrame, keys: sessionKeys);
      socket.add(encodedAck);
      await socket.flush();

      inHandshake = false;

      return HandshakeResult(
        socket: socket,
        sessionKeys: sessionKeys,
        sasCode: sasCode,
        role: TransferRole.receiver,
        localPublicKey: keyPairData.publicKeyBytes,
        remotePublicKey: clientEnvelope.publicKey,
        localNonce: keyPairData.nonce,
        remoteNonce: clientEnvelope.nonce,
        transcriptHash: transcriptHash,
        incomingFrameStream: incomingFrameController.stream,
      );
    } catch (e) {
      await sub.cancel();
      rethrow;
    }
  }
}
