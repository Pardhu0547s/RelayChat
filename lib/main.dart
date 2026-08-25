import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'providers/bluetooth_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/bluetooth/bluetooth_status_screen.dart';
import 'screens/chat/chat_screen.dart';
import 'screens/connection/connected_device_screen.dart';
import 'screens/connection/connecting_screen.dart';
import 'screens/scanner/device_scanner_screen.dart';
import 'screens/splash/splash_screen.dart';
import 'utils/colors.dart';
import 'utils/constants.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RelayChatApp());
}

class RelayChatApp extends StatelessWidget {
  const RelayChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => BluetoothProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: AppConstants.appName,
            debugShowCheckedModeBanner: false,
            themeMode: themeProvider.themeMode,

            // --- Light Theme ---
            theme: ThemeData.light().copyWith(
              brightness: Brightness.light,
              scaffoldBackgroundColor: AppColors.lightBackground,
              colorScheme: const ColorScheme.light(
                primary: AppColors.primary,
                secondary: AppColors.secondary,
                surface: AppColors.lightCard,
                error: AppColors.error,
              ),
              textTheme: GoogleFonts.interTextTheme(
                ThemeData.light().textTheme,
              ),
            ),

            // --- Dark Theme ---
            darkTheme: ThemeData.dark().copyWith(
              brightness: Brightness.dark,
              scaffoldBackgroundColor: AppColors.darkBackground,
              colorScheme: const ColorScheme.dark(
                primary: AppColors.primary,
                secondary: AppColors.secondary,
                surface: AppColors.darkCard,
                error: AppColors.error,
              ),
              textTheme: GoogleFonts.interTextTheme(
                ThemeData.dark().textTheme,
              ),
            ),

            initialRoute: AppConstants.routeSplash,
            routes: {
              AppConstants.routeSplash: (context) => const SplashScreen(),
              AppConstants.routeBluetoothStatus: (context) => const BluetoothStatusScreen(),
              AppConstants.routeScanner: (context) => const DeviceScannerScreen(),
              AppConstants.routeConnecting: (context) => const ConnectingScreen(),
              AppConstants.routeConnectedDevice: (context) => const ConnectedDeviceScreen(),
              AppConstants.routeChat: (context) => const ChatScreen(),
            },
          );
        },
      ),
    );
  }
}
