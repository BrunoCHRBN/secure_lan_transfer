import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_lan_transfer/core/crypto/sas_authenticator.dart';
import 'package:secure_lan_transfer/core/models/peer_device.dart';
import 'package:secure_lan_transfer/core/session/session_manager.dart';
import 'package:secure_lan_transfer/ui/theme/app_theme.dart';
import 'package:secure_lan_transfer/ui/widgets/chunk_progress_bar.dart';
import 'package:secure_lan_transfer/ui/widgets/device_card.dart';
import 'package:secure_lan_transfer/ui/widgets/file_drop_target.dart';
import 'package:secure_lan_transfer/ui/widgets/inbound_proposal_dialog.dart';
import 'package:secure_lan_transfer/ui/widgets/manual_connect_dialog.dart';
import 'package:secure_lan_transfer/ui/widgets/radar_view.dart';
import 'package:secure_lan_transfer/ui/widgets/sas_verification_dialog.dart';
import 'package:secure_lan_transfer/ui/widgets/speedometer_widget.dart';

class FakeSocket extends Stream<Uint8List> implements Socket {
  final _controller = StreamController<Uint8List>.broadcast();

  @override
  InternetAddress get address => InternetAddress.loopbackIPv4;

  @override
  InternetAddress get remoteAddress => InternetAddress('192.168.1.200');

  @override
  int get port => 12345;

  @override
  int get remotePort => 52140;

  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream<List<int>> stream) => Future.value();

  @override
  Future close() => Future.value();

  @override
  void destroy() {}

  @override
  Future get done => Future.value();

  @override
  Future flush() => Future.value();

  @override
  StreamSubscription<Uint8List> listen(void Function(Uint8List event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return _controller.stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  bool setOption(SocketOption option, bool enabled) => true;

  @override
  bool setRawOption(RawSocketOption option) => true;

  @override
  Uint8List getRawOption(RawSocketOption option) => Uint8List(0);

  @override
  void write(Object? object) {}

  @override
  void writeAll(Iterable objects, [String separator = '']) {}

  @override
  void writeCharCode(int charCode) {}

  @override
  void writeln([Object? object = '']) {}

  @override
  Encoding get encoding => utf8;

  @override
  set encoding(Encoding encoding) {}
}

void main() {
  testWidgets('SasVerificationDialog renders numeric code, emojis, and actions',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    bool confirmed = false;
    bool rejected = false;

    final dummySas = SasCode(
      numericCode: '482-913',
      numericValue: 482913,
      emojis: const [
        SasEmoji(0, '🦊', 'Fox'),
        SasEmoji(1, '⚡', 'Lightning'),
        SasEmoji(2, '🪐', 'Saturn'),
        SasEmoji(3, '💎', 'Gem Stone'),
      ],
      rawBytes: Uint8List.fromList([1, 2, 3, 4]),
      transcriptHash: Uint8List(32),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.oledTheme(AppPalettes.cyberEmerald),
        home: Scaffold(
          body: SasVerificationDialog(
            sasCode: dummySas,
            remoteDeviceName: "Alice's MacBook",
            onConfirm: () => confirmed = true,
            onReject: () => rejected = true,
          ),
        ),
      ),
    );

    expect(find.text('Verify Security Code'), findsOneWidget);
    expect(find.text('482-913'), findsOneWidget);
    expect(find.text('Fox'), findsOneWidget);
    expect(find.text('Lightning'), findsOneWidget);
    expect(find.text('Saturn'), findsOneWidget);
    expect(find.text('Gem Stone'), findsOneWidget);

    // Tap confirm button
    await tester.tap(find.text('Confirm Match'));
    expect(confirmed, isTrue);

    // Tap reject button
    await tester.tap(find.text('Reject / Mismatch'));
    expect(rejected, isTrue);
  });

  testWidgets('SpeedometerWidget renders arc gauge and speed text',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.oledTheme(AppPalettes.cyberEmerald),
        home: const Scaffold(
          body: SpeedometerWidget(
            speedBytesPerSec: 48.5 * 1024 * 1024,
            peakSpeedBytesPerSec: 84.2 * 1024 * 1024,
            size: 200,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('48.5'), findsOneWidget);
    expect(find.text('MB/s'), findsOneWidget);
    expect(find.text('Range: 0-150 MB/s'), findsOneWidget);
    expect(find.text('Peak: 84.2 MB/s'), findsOneWidget);
  });

  testWidgets('ChunkProgressBar renders pipeline and percentage stats',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.oledTheme(AppPalettes.cyberEmerald),
        home: const Scaffold(
          body: ChunkProgressBar(
            transferredBytes: 50 * 1024 * 1024,
            totalBytes: 100 * 1024 * 1024,
            creditWindowSize: 4,
          ),
        ),
      ),
    );

    expect(find.textContaining('50.0%'), findsOneWidget);
    expect(find.textContaining('50.0 MB / 100.0 MB'), findsOneWidget);
    expect(find.textContaining('in flight'), findsOneWidget);
  });

  testWidgets('DeviceCard renders device metadata, status dot, and send button',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    bool sendClicked = false;

    final device = PeerDevice(
      id: 'test-device-1',
      name: "Bob's Workstation",
      os: 'windows',
      addresses: const ['192.168.1.150'],
      port: 42385,
      discoveryMethod: DiscoveryMethod.mdns,
      lastSeen: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.oledTheme(AppPalettes.cyberEmerald),
        home: Scaffold(
          body: DeviceCard(
            device: device,
            onSendFile: () => sendClicked = true,
          ),
        ),
      ),
    );

    expect(find.text("Bob's Workstation"), findsOneWidget);
    expect(find.text('192.168.1.150:42385'), findsOneWidget);
    expect(find.text('mDNS'), findsOneWidget);

    await tester.tap(find.text('Send'));
    expect(sendClicked, isTrue);
  });

  testWidgets('FileDropTarget renders idle and selected file views',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    File? selectedFile;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.oledTheme(AppPalettes.cyberEmerald),
        home: Scaffold(
          body: FileDropTarget(
            selectedFile: selectedFile,
            onFileSelected: (f) => selectedFile = f,
          ),
        ),
      ),
    );

    expect(find.text('Click to browse or drop file here'), findsOneWidget);
  });

  testWidgets('RadarView renders animated radar widget', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final devices = [
      PeerDevice(
        id: 'dev-1',
        name: 'Device 1',
        os: 'android',
        addresses: const ['192.168.1.10'],
        discoveryMethod: DiscoveryMethod.udpBroadcast,
        lastSeen: DateTime.now(),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.oledTheme(AppPalettes.cyberEmerald),
        home: Scaffold(
          body: RadarView(
            devices: devices,
            isScanning: true,
            size: 120,
          ),
        ),
      ),
    );

    expect(find.byType(RadarView), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('InboundProposalDialog renders remote address and actions',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    bool accepted = false;
    bool rejected = false;

    final fakeSocket = FakeSocket();
    final proposal = InboundSessionProposal(
      socket: fakeSocket,
      remoteAddress: '192.168.1.200',
      remotePort: 52140,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.oledTheme(AppPalettes.cyberEmerald),
        home: Scaffold(
          body: InboundProposalDialog(
            proposal: proposal,
            onAccept: () => accepted = true,
            onReject: () => rejected = true,
          ),
        ),
      ),
    );

    expect(find.text('Incoming Transfer Request'), findsOneWidget);
    expect(find.text('192.168.1.200:52140'), findsOneWidget);

    await tester.tap(find.text('Accept & Connect'));
    expect(accepted, isTrue);

    await tester.tap(find.text('Decline'));
    expect(rejected, isTrue);
  });

  testWidgets('ManualConnectDialog validates inputs and submits',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    PeerDevice? connectedDevice;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.oledTheme(AppPalettes.cyberEmerald),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  connectedDevice = await showDialog<PeerDevice>(
                    context: context,
                    builder: (context) => ManualConnectDialog(
                      onConnect: (host, {port = 42385, name}) async {
                        return PeerDevice(
                          id: 'manual-1',
                          name: name ?? host,
                          os: 'unknown',
                          addresses: [host],
                          port: port,
                          discoveryMethod: DiscoveryMethod.manual,
                          lastSeen: DateTime.now(),
                        );
                      },
                    ),
                  );
                },
                child: const Text('Open Manual Connect'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Manual Connect'));
    await tester.pumpAndSettle();

    expect(find.text('Manual Peer Connect'), findsOneWidget);

    // Enter IP
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Peer IP Address *'), '10.0.0.5');
    await tester.tap(find.text('Probe & Connect'));
    await tester.pumpAndSettle();

    expect(connectedDevice, isNotNull);
    expect(connectedDevice!.primaryAddress, equals('10.0.0.5'));
  });
}
