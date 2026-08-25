import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/bluetooth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../utils/colors.dart';
import '../../utils/constants.dart';
import '../../widgets/app_button.dart';
import '../../widgets/status_badge.dart';

class BluetoothStatusScreen extends StatefulWidget {
  const BluetoothStatusScreen({super.key});

  @override
  State<BluetoothStatusScreen> createState() => _BluetoothStatusScreenState();
}

class _BluetoothStatusScreenState extends State<BluetoothStatusScreen> with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Auto-trigger permission request popup on first load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoRequestPermissions();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check permissions when user returns from App Settings
    if (state == AppLifecycleState.resumed) {
      final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
      btProvider.checkStatusAndPermissions();
    }
  }

  Future<void> _autoRequestPermissions() async {
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    if (!btProvider.isPermissionGranted) {
      await btProvider.requestPermissions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final cardBg = AppColors.getCard(context);
    final cardBorder = AppColors.getCardBorder(context);
    final textPrimary = AppColors.getTextPrimary(context);
    final dividerColor = AppColors.getDivider(context);

    return Consumer<BluetoothProvider>(
      builder: (context, btProvider, child) {
        final isEnabled = btProvider.isBluetoothEnabled;
        final isGranted = btProvider.isPermissionGranted;
        final canProceed = isEnabled && isGranted;

        return Scaffold(
          backgroundColor: AppColors.getBackground(context),
          appBar: AppBar(
            backgroundColor: AppColors.getBackground(context),
            elevation: 0,
            title: Text(
              'Bluetooth Status',
              style: TextStyle(
                color: textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            centerTitle: true,
            actions: [
              IconButton(
                tooltip: 'Toggle Light / Dark Mode',
                icon: Icon(
                  themeProvider.isDarkMode
                      ? Icons.wb_sunny_rounded
                      : Icons.nightlight_round,
                  color: themeProvider.isDarkMode
                      ? Colors.amber
                      : AppColors.primary,
                ),
                onPressed: () {
                  themeProvider.toggleTheme();
                },
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                
                // Status Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cardBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: themeProvider.isDarkMode ? 0.3 : 0.08,
                        ),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Bluetooth Section
                      Text(
                        'Bluetooth',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      StatusBadge(
                        label: isEnabled ? 'Enabled' : 'OFF',
                        isPositive: isEnabled,
                      ),
                      
                      const SizedBox(height: 24),
                      Divider(color: dividerColor),
                      const SizedBox(height: 16),

                      // Permissions Section
                      Text(
                        'Permissions',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      StatusBadge(
                        label: isGranted ? 'Granted' : 'Denied',
                        isPositive: isGranted,
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Turn On Bluetooth button — actually tries to turn on adapter
                if (!isEnabled) ...[
                  AppButton(
                    label: 'Turn On Bluetooth',
                    icon: Icons.bluetooth_rounded,
                    style: AppButtonStyle.secondary,
                    onPressed: () async {
                      await btProvider.turnOnBluetooth();
                    },
                  ),
                  const SizedBox(height: 12),
                ],

                // Grant Permissions button — triggers the OS permission popup
                if (!isGranted) ...[
                  AppButton(
                    label: 'Grant Permissions',
                    icon: Icons.security_rounded,
                    style: AppButtonStyle.outline,
                    onPressed: () async {
                      await btProvider.requestPermissions();
                    },
                  ),
                  const SizedBox(height: 12),
                ],

                // Continue button
                AppButton(
                  label: canProceed ? 'Continue' : 'Continue',
                  icon: Icons.arrow_forward_rounded,
                  style: AppButtonStyle.primary,
                  onPressed: canProceed
                      ? () {
                          Navigator.pushReplacementNamed(
                            context,
                            AppConstants.routeScanner,
                          );
                        }
                      : null,
                ),
                if (!canProceed) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Please enable Bluetooth and grant permissions to continue',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.getSubtitle(context),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}
