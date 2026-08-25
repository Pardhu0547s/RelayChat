import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/bluetooth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../utils/colors.dart';
import '../../utils/constants.dart';
import '../../widgets/app_button.dart';
import '../../widgets/device_card.dart';

class DeviceScannerScreen extends StatefulWidget {
  const DeviceScannerScreen({super.key});

  @override
  State<DeviceScannerScreen> createState() => _DeviceScannerScreenState();
}

class _DeviceScannerScreenState extends State<DeviceScannerScreen> {
  @override
  void initState() {
    super.initState();
    // Auto scan on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<BluetoothProvider>(context, listen: false).startScan();
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final textPrimary = AppColors.getTextPrimary(context);
    final textSecondary = AppColors.getTextSecondary(context);
    final subtitleColor = AppColors.getSubtitle(context);
    final dividerColor = AppColors.getDivider(context);

    return Scaffold(
      backgroundColor: AppColors.getBackground(context),
      appBar: AppBar(
        backgroundColor: AppColors.getBackground(context),
        elevation: 0,
        title: Text(
          'RelayChat',
          style: TextStyle(
            color: textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 22,
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
      body: Consumer<BluetoothProvider>(
        builder: (context, btProvider, child) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header & Scan Button Section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Search Devices',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Discovering RelayChat mesh nodes',
                          style: TextStyle(
                            fontSize: 12,
                            color: subtitleColor,
                          ),
                        ),
                      ],
                    ),
                    AppButton(
                      label: 'Scan',
                      icon: Icons.search_rounded,
                      isLoading: btProvider.isScanning,
                      style: AppButtonStyle.primary,
                      onPressed: () {
                        btProvider.startScan();
                      },
                    ),
                  ],
                ),
              ),

              Divider(color: dividerColor, thickness: 1),

              // Device List
              Expanded(
                child: btProvider.isScanning && btProvider.discoveredDevices.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(color: AppColors.primary),
                            const SizedBox(height: 16),
                            Text(
                              'Scanning for nearby ESP32 nodes...',
                              style: TextStyle(color: textSecondary),
                            ),
                          ],
                        ),
                      )
                    : btProvider.discoveredDevices.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.bluetooth_searching,
                                  size: 60,
                                  color: subtitleColor,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No RelayChat devices found',
                                  style: TextStyle(
                                    color: textSecondary,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                AppButton(
                                  label: 'Scan Again',
                                  style: AppButtonStyle.outline,
                                  onPressed: () => btProvider.startScan(),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(top: 8, bottom: 20),
                            itemCount: btProvider.discoveredDevices.length,
                            itemBuilder: (context, index) {
                              final device = btProvider.discoveredDevices[index];
                              return DeviceCard(
                                device: device,
                                isConnecting: btProvider.isConnecting &&
                                    btProvider.connectedDevice?.id == device.id,
                                onConnect: () async {
                                  // Navigate to Screen 4 (Connecting)
                                  Navigator.pushNamed(
                                    context,
                                    AppConstants.routeConnecting,
                                    arguments: device,
                                  );
                                },
                              );
                            },
                          ),
              ),
            ],
          );
        },
      ),
    );
  }
}
