import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/bluetooth_provider.dart';
import '../../providers/chat_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/colors.dart';
import '../../utils/constants.dart';
import '../../widgets/brand_logo.dart';

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
    final isDark = AppColors.isDark(context);
    final bg = AppColors.getBackground(context);
    final textPrimary = AppColors.getTextPrimary(context);
    final subtitleColor = AppColors.getSubtitle(context);

    return Scaffold(
      backgroundColor: bg,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [
                    const Color(0xFF0F172A),
                    const Color(0xFF0A0F1D),
                    const Color(0xFF050811),
                  ]
                : [
                    const Color(0xFFFFFFFF),
                    const Color(0xFFF1F5F9),
                    const Color(0xFFE2E8F0),
                  ],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // RelayChat Glowing Brand Logo
                const BrandLogo(
                  size: 130,
                  showGlow: true,
                ),
                const SizedBox(height: 28),

                // Title
                Text(
                  AppConstants.appName,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),

                // Tagline with sleek pill badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: const Text(
                    'OFF-GRID MESH NETWORK',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  AppConstants.appTagline,
                  style: TextStyle(
                    fontSize: 14,
                    color: subtitleColor,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 50),

                // Loading...
                Container(
                  width: 32,
                  height: 32,
                  padding: const EdgeInsets.all(4),
                  child: const CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _statusText,
                  style: TextStyle(
                    color: subtitleColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
