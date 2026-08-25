import 'package:flutter/material.dart';
import '../models/bluetooth_device.dart';
import '../utils/colors.dart';
import 'app_button.dart';
import 'status_badge.dart';

class DeviceCard extends StatelessWidget {
  final RelayDevice device;
  final VoidCallback onConnect;
  final bool isConnecting;

  const DeviceCard({
    super.key,
    required this.device,
    required this.onConnect,
    this.isConnecting = false,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = AppColors.getCard(context);
    final cardBorder = AppColors.getCardBorder(context);
    final textPrimary = AppColors.getTextPrimary(context);
    final textSecondary = AppColors.getTextSecondary(context);
    final subtitleColor = AppColors.getSubtitle(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: AppColors.isDark(context) ? 0.3 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    '📡',
                    style: TextStyle(fontSize: 22),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    device.name,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                ],
              ),
              StatusBadge(
                label: device.isAvailable ? 'Available' : 'Busy',
                isPositive: device.isAvailable,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                'Signal: ',
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 14,
                ),
              ),
              Text(
                device.signalBar,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '(${device.rssi} dBm)',
                style: TextStyle(
                  color: subtitleColor,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: 'Connect',
              onPressed: onConnect,
              isLoading: isConnecting,
              style: AppButtonStyle.primary,
            ),
          ),
        ],
      ),
    );
  }
}
