import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:secure_lan_transfer/main.dart';
import 'package:secure_lan_transfer/ui/providers/device_discovery_provider.dart';
import 'package:secure_lan_transfer/ui/providers/settings_provider.dart';
import 'package:secure_lan_transfer/ui/providers/transfer_session_provider.dart';
import 'package:secure_lan_transfer/ui/screens/discovery_screen.dart';
import 'package:secure_lan_transfer/ui/screens/settings_screen.dart';
import 'package:secure_lan_transfer/ui/screens/transfer_history_screen.dart';
import 'package:secure_lan_transfer/ui/screens/transfer_screen.dart';
import 'package:secure_lan_transfer/ui/theme/app_theme.dart';

Widget _buildTestApp({
  required Widget child,
  required SettingsProvider settings,
  required DeviceDiscoveryProvider discovery,
  required TransferSessionProvider session,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ChangeNotifierProvider<DeviceDiscoveryProvider>.value(value: discovery),
      ChangeNotifierProvider<TransferSessionProvider>.value(value: session),
    ],
    child: MaterialApp(
      theme: AppTheme.oledTheme(AppPalettes.cyberEmerald),
      home: child,
    ),
  );
}

void main() {
  testWidgets('DiscoveryScreen renders header, search, and empty state',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final settings = SettingsProvider();
    final discovery = DeviceDiscoveryProvider();
    final session = TransferSessionProvider(settings: settings);

    await tester.pumpWidget(
      _buildTestApp(
        child: DiscoveryScreen(onNavigateToTransfer: () {}),
        settings: settings,
        discovery: discovery,
        session: session,
      ),
    );

    expect(find.textContaining('Node-'), findsOneWidget);
    expect(find.text('Manual IP'), findsOneWidget);
    expect(find.text('Click to browse or drop file here'), findsOneWidget);
    expect(find.textContaining('Searching for peers'), findsOneWidget);

    discovery.dispose();
    session.dispose();
  });

  testWidgets('TransferScreen renders idle view when no transfer is active',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final settings = SettingsProvider();
    final discovery = DeviceDiscoveryProvider();
    final session = TransferSessionProvider(settings: settings);

    await tester.pumpWidget(
      _buildTestApp(
        child: TransferScreen(onNavigateToDiscovery: () {}),
        settings: settings,
        discovery: discovery,
        session: session,
      ),
    );

    expect(find.text('No Active Transfer Session'), findsOneWidget);
    expect(find.text('Open Peer Discovery'), findsOneWidget);

    discovery.dispose();
    session.dispose();
  });

  testWidgets('TransferHistoryScreen renders zero-metadata banner and empty state',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final settings = SettingsProvider();
    final discovery = DeviceDiscoveryProvider();
    final session = TransferSessionProvider(settings: settings);

    await tester.pumpWidget(
      _buildTestApp(
        child: const TransferHistoryScreen(),
        settings: settings,
        discovery: discovery,
        session: session,
      ),
    );

    expect(find.text('Transfer History'), findsOneWidget);
    expect(find.textContaining('Zero-Metadata Mode Active'), findsOneWidget);
    expect(find.text('No transfer history recorded'), findsOneWidget);

    discovery.dispose();
    session.dispose();
  });

  testWidgets('SettingsScreen renders configuration sections and theme options',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final settings = SettingsProvider();
    final discovery = DeviceDiscoveryProvider();
    final session = TransferSessionProvider(settings: settings);

    await tester.pumpWidget(
      _buildTestApp(
        child: const SettingsScreen(),
        settings: settings,
        discovery: discovery,
        session: session,
      ),
    );

    expect(find.text('Settings & Preferences'), findsOneWidget);
    expect(find.text('Device Identity'), findsOneWidget);
    expect(find.text('Storage & Staging'), findsOneWidget);
    expect(find.text('Security & Zero-Metadata Privacy'), findsOneWidget);
    expect(find.text('Network & Performance'), findsOneWidget);
    expect(find.text('Appearance & Themes'), findsOneWidget);

    // Switch theme mode
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(settings.themeMode, equals(AppThemeMode.light));

    discovery.dispose();
    session.dispose();
  });

  testWidgets('SecureLanTransferApp boots and renders navigation destinations',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final settings = SettingsProvider();
    final discovery = DeviceDiscoveryProvider();
    final session = TransferSessionProvider(settings: settings);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<DeviceDiscoveryProvider>.value(
              value: discovery),
          ChangeNotifierProvider<TransferSessionProvider>.value(value: session),
        ],
        child: const SecureLanTransferApp(),
      ),
    );

    await tester.pumpAndSettle();

    // Verify main destinations exist
    expect(find.text('Discover'), findsWidgets);
    expect(find.text('Transfer'), findsWidgets);
    expect(find.text('History'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);

    discovery.dispose();
    session.dispose();
  });
}
