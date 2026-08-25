import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/bluetooth_device.dart';
import '../../providers/bluetooth_provider.dart';
import '../../utils/colors.dart';
import '../../utils/constants.dart';

class ConnectingScreen extends StatefulWidget {
  const ConnectingScreen({super.key});

  @override
  State<ConnectingScreen> createState() => _ConnectingScreenState();
}

class _ConnectingScreenState extends State<ConnectingScreen> {
  RelayDevice? _targetDevice;
  bool _isInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is RelayDevice) {
        _targetDevice = args;
        _startConnectionProcess();
      }
      _isInit = true;
    }
  }

  void _startConnectionProcess() async {
    if (_targetDevice == null) return;
    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);

    final success = await btProvider.connectDevice(_targetDevice!);

    if (mounted && success) {
      // Transition to Screen 5 (Connected Device)
      Navigator.pushReplacementNamed(
        context,
        AppConstants.routeConnectedDevice,
        arguments: _targetDevice,
      );
    }
  }

  /// Format progress percentage into exact visual bar: ██████████░░░░░░
  String _buildProgressBarString(double progress) {
    const totalBlocks = 16;
    final filledCount = (progress * totalBlocks).clamp(0, totalBlocks).round();
    final emptyCount = totalBlocks - filledCount;
    return '█' * filledCount + '░' * emptyCount;
  }

  @override
  Widget build(BuildContext context) {
    final deviceName = _targetDevice?.name ?? 'ESP32 Device';
    final textPrimary = AppColors.getTextPrimary(context);
    final textSecondary = AppColors.getTextSecondary(context);
    final subtitleColor = AppColors.getSubtitle(context);
    final cardBg = AppColors.getCard(context);
    final cardBorder = AppColors.getCardBorder(context);

    return Scaffold(
      backgroundColor: AppColors.getBackground(context),
      body: Consumer<BluetoothProvider>(
        builder: (context, btProvider, child) {
          final progress = btProvider.connectionProgress;
          final barString = _buildProgressBarString(progress);
          final percentage = (progress * 100).toInt();

          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Icon
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: cardBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.5), width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.bluetooth_searching,
                      size: 60,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Connecting...
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Connecting...',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Device Name
                  Text(
                    deviceName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: AppColors.secondary,
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Visual Progress Bar: ██████████░░░░░░
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cardBorder),
                    ),
                    child: Column(
                      children: [
                        Text(
                          barString,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$percentage%',
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Please wait...
                  Text(
                    'Please wait...',
                    style: TextStyle(
                      fontSize: 16,
                      color: subtitleColor,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
