import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'ui/providers/device_discovery_provider.dart';
import 'ui/providers/settings_provider.dart';
import 'ui/providers/transfer_session_provider.dart';
import 'ui/screens/discovery_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/transfer_history_screen.dart';
import 'ui/screens/transfer_screen.dart';
import 'ui/theme/app_theme.dart';
import 'ui/theme/breakpoints.dart';
import 'ui/widgets/inbound_proposal_dialog.dart';
import 'ui/widgets/network_permission_gate.dart';
import 'ui/widgets/sas_verification_dialog.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    return true; // Prevent app exit on unhandled async error
  };

  final settingsProvider = SettingsProvider();
  await settingsProvider.initialize();

  final discoveryProvider = DeviceDiscoveryProvider();
  if (settingsProvider.isNetworkPermissionGranted) {
    await discoveryProvider.initialize(settingsProvider);
  }

  final transferSessionProvider = TransferSessionProvider(
    settings: settingsProvider,
  );
  if (settingsProvider.isNetworkPermissionGranted) {
    await transferSessionProvider.startServer();
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settingsProvider),
        ChangeNotifierProvider<DeviceDiscoveryProvider>.value(
            value: discoveryProvider),
        ChangeNotifierProvider<TransferSessionProvider>.value(
            value: transferSessionProvider),
      ],
      child: const SecureLanTransferApp(),
    ),
  );
}

/// Root Application Widget.
class SecureLanTransferApp extends StatelessWidget {
  const SecureLanTransferApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return MaterialApp(
      title: 'Secure LAN Transfer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(settings.accentColor),
      darkTheme: settings.themeMode == AppThemeMode.oled
          ? AppTheme.oledTheme(settings.accentColor)
          : AppTheme.darkTheme(settings.accentColor),
      themeMode: settings.themeMode == AppThemeMode.light
          ? ThemeMode.light
          : settings.themeMode == AppThemeMode.dark ||
                  settings.themeMode == AppThemeMode.oled
              ? ThemeMode.dark
              : ThemeMode.system,
      home: const NetworkPermissionGate(
        child: MainShell(),
      ),
    );
  }
}

/// Main Responsive Navigation Shell.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  bool _isSasDialogShowing = false;
  bool _isProposalDialogShowing = false;

  void _onDestinationSelected(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _checkAndShowModals(BuildContext context) {
    final session = context.watch<TransferSessionProvider>();

    // 1. Pending Inbound Connection Proposal Modal
    if (session.pendingProposal != null && !_isProposalDialogShowing) {
      final proposal = session.pendingProposal!;
      _isProposalDialogShowing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => InboundProposalDialog(
            proposal: proposal,
            onAccept: () {
              session.acceptProposal();
              _isProposalDialogShowing = false;
              Navigator.pop(context);
              setState(() {
                _selectedIndex = 1; // Switch to transfer screen
              });
            },
            onReject: () {
              session.rejectProposal();
              _isProposalDialogShowing = false;
              Navigator.pop(context);
            },
          ),
        ).then((_) => _isProposalDialogShowing = false);
      });
    }

    // 2. Pending SAS Verification Request Modal
    if (session.pendingSasRequest != null && !_isSasDialogShowing) {
      final req = session.pendingSasRequest!;
      _isSasDialogShowing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => SasVerificationDialog(
            sasCode: req.sasCode,
            remoteDeviceName: req.remoteAddress,
            onConfirm: () {
              session.confirmSas();
              _isSasDialogShowing = false;
              Navigator.pop(context);
            },
            onReject: () {
              session.rejectSas();
              _isSasDialogShowing = false;
              Navigator.pop(context);
            },
          ),
        ).then((_) => _isSasDialogShowing = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    _checkAndShowModals(context);

    final isCompact = context.isCompact;
    final isExpanded = context.isExpanded;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final session = context.watch<TransferSessionProvider>();

    final screens = [
      DiscoveryScreen(
        onNavigateToTransfer: () => _onDestinationSelected(1),
      ),
      TransferScreen(
        onNavigateToDiscovery: () => _onDestinationSelected(0),
      ),
      const TransferHistoryScreen(),
      const SettingsScreen(),
    ];

    if (isCompact) {
      // Mobile Bottom Navigation Bar Layout
      return Scaffold(
        body: IndexedStack(
          index: _selectedIndex,
          children: screens,
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _onDestinationSelected,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.radar_rounded),
              label: 'Discover',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: session.hasActiveTransfer,
                smallSize: 8,
                child: const Icon(Icons.swap_horizontal_circle_rounded),
              ),
              label: 'Transfer',
            ),
            const NavigationDestination(
              icon: Icon(Icons.history_rounded),
              label: 'History',
            ),
            const NavigationDestination(
              icon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ],
        ),
      );
    }

    // Tablet / Desktop Navigation Rail Layout
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: isExpanded,
            minExtendedWidth: 180,
            selectedIndex: _selectedIndex,
            onDestinationSelected: _onDestinationSelected,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.shield_rounded,
                      color: colorScheme.primary,
                      size: 24,
                    ),
                  ),
                  if (isExpanded) ...[
                    const SizedBox(width: 10),
                    Text(
                      'SLFT',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            destinations: [
              const NavigationRailDestination(
                icon: Icon(Icons.radar_rounded),
                label: Text('Discover'),
              ),
              NavigationRailDestination(
                icon: Badge(
                  isLabelVisible: session.hasActiveTransfer,
                  smallSize: 8,
                  child: const Icon(Icons.swap_horizontal_circle_rounded),
                ),
                label: const Text('Transfer'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.history_rounded),
                label: Text('History'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.settings_rounded),
                label: Text('Settings'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: screens,
            ),
          ),
        ],
      ),
    );
  }
}
