import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:secure_lan_transfer/main.dart';
import 'package:secure_lan_transfer/ui/providers/device_discovery_provider.dart';
import 'package:secure_lan_transfer/ui/providers/settings_provider.dart';
import 'package:secure_lan_transfer/ui/providers/transfer_session_provider.dart';

void main() {
  testWidgets('SecureLanTransferApp boots and renders navigation destinations',
      (WidgetTester tester) async {
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

    expect(find.text('Discover'), findsWidgets);
    expect(find.text('Transfer'), findsWidgets);
    expect(find.text('History'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);

    discovery.dispose();
    session.dispose();
  });
}
