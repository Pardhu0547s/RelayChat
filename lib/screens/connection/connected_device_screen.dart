import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/bluetooth_device.dart';
import '../../providers/bluetooth_provider.dart';
import '../../utils/colors.dart';
import '../../utils/constants.dart';
import '../../widgets/app_button.dart';
class ConnectedDeviceScreen extends StatefulWidget {
  const ConnectedDeviceScreen({super.key});

  @override
  State<ConnectedDeviceScreen> createState() => _ConnectedDeviceScreenState();
}

class _ConnectedDeviceScreenState extends State<ConnectedDeviceScreen> {
  StreamSubscription<bool>? _disconnectSub;

  @override
  void initState() {
    super.initState();
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    _disconnectSub = btProvider.deviceDisconnected.listen((_) {
      if (mounted) {
        Navigator.popUntil(context, ModalRoute.withName(AppConstants.routeScanner));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Device disconnected unexpectedly.')),
        );
      }
    });
  }

  @override
  void dispose() {
    _disconnectSub?.cancel();
    super.dispose();
  }

  Widget _buildDetailRow(BuildContext context, String title, String value, {Color? valueColor}) {
    final subtitleColor = AppColors.getSubtitle(context);
    final textPrimary = AppColors.getTextPrimary(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              color: subtitleColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              color: valueColor ?? textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final btProvider = Provider.of<BluetoothProvider>(context);
    final cardBg = AppColors.getCard(context);
    final cardBorder = AppColors.getCardBorder(context);
    final textPrimary = AppColors.getTextPrimary(context);
    final dividerColor = AppColors.getDivider(context);

    final device = btProvider.connectedDevice ??
        RelayDevice(
          id: 'ESP32_01',
          name: 'ESP32_01',
          rssi: -45,
          batteryLevel: 'N/A',
          firmwareVersion: '1.0',
        );

    return Scaffold(
      backgroundColor: AppColors.getBackground(context),
      appBar: AppBar(
        backgroundColor: AppColors.getBackground(context),
        elevation: 0,
        title: Text(
          'Connected Device',
          style: TextStyle(
            color: textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          children: [
            const Spacer(),

            // Success Header Icon
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary, width: 2),
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                size: 50,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Connected',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 32),

            // Device Details Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cardBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: AppColors.isDark(context) ? 0.3 : 0.06,
                    ),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _buildDetailRow(context, 'Device', device.name, valueColor: AppColors.secondary),
                  Divider(color: dividerColor),
                  _buildDetailRow(context, 'RSSI', '${device.rssi} dBm'),
                  Divider(color: dividerColor),
                  _buildDetailRow(context, 'Battery', device.batteryLevel),
                  Divider(color: dividerColor),
                  _buildDetailRow(context, 'Firmware', device.firmwareVersion),
                ],
              ),
            ),

            const Spacer(),

            // Open Chat Button
            AppButton(
              label: 'Open Chat',
              icon: Icons.chat_rounded,
              style: AppButtonStyle.primary,
              width: double.infinity,
              onPressed: () {
                Navigator.pushReplacementNamed(
                  context,
                  AppConstants.routeChat,
                );
              },
            ),
            const SizedBox(height: 12),

            // Disconnect Option
            TextButton(
              onPressed: () async {
                await btProvider.disconnectDevice();
                if (context.mounted) {
                  Navigator.pushReplacementNamed(context, AppConstants.routeScanner);
                }
              },
              child: const Text(
                'Disconnect Device',
                style: TextStyle(color: AppColors.error),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
