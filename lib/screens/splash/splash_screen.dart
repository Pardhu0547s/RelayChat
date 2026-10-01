import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/bluetooth_provider.dart';
import '../../providers/chat_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/colors.dart';
import '../../utils/constants.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  String _statusText = 'Loading...';

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );

    _animController.forward();

    // Start connection flow after animation begins
    Future.delayed(const Duration(milliseconds: 1500), _startConnectionFlow);
  }

  void _startConnectionFlow() async {
    if (!mounted) return;

    // Check if profile exists
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey('local_name')) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppConstants.routeProfileSetup);
      return;
    }

    final btProvider = Provider.of<BluetoothProvider>(context, listen: false);
    await btProvider.checkStatusAndPermissions();

    if (!mounted) return;

    // Check permissions first
    if (!btProvider.isPermissionGranted) {
      setState(() => _statusText = 'Requesting permissions...');
      await btProvider.requestPermissions();
      if (!mounted) return;
    }

    // Check bluetooth
    if (!btProvider.isBluetoothEnabled) {
      setState(() => _statusText = 'Enabling Bluetooth...');
      await btProvider.turnOnBluetooth();
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
    }

    // Try auto-connect if we have a saved device
    if (btProvider.hasSavedDevice) {
      setState(() => _statusText = 'Connecting to ESP32...');
      
      final success = await btProvider.autoConnect();
      
      if (!mounted) return;
      
      if (success) {
        setState(() => _statusText = 'Connected!');
        
        // Notify ChatProvider
        Provider.of<ChatProvider>(context, listen: false).onDeviceConnected();
        
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        
        // Go straight to contacts
        Navigator.pushReplacementNamed(context, AppConstants.routeContacts);
        return;
      } else {
        // Auto-connect failed, fall through to scanner
        setState(() => _statusText = 'Auto-connect failed. Scanning...');
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    if (!mounted) return;
    // No saved device or auto-connect failed → go to bluetooth status / scanner
    Navigator.pushReplacementNamed(context, AppConstants.routeBluetoothStatus);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // RelayChat Logo
              Container(
                width: 140,
                height: 140,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.card,
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.5), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Image.asset(
                  AppConstants.logoPath,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.cell_tower,
                      size: 70,
                      color: AppColors.primary,
                    );
                  },
                ),
              ),
              const SizedBox(height: 32),

              // Title
              const Text(
                AppConstants.appName,
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),

              // Subtitle
              const Text(
                AppConstants.appTagline,
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.subtitle,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 60),

              // Loading...
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _statusText,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
