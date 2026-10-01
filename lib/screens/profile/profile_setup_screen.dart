import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/chat_provider.dart';
import '../../utils/colors.dart';
import '../../utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final TextEditingController _nameController = TextEditingController();

  void _saveProfile() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    // Save name via ChatProvider
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    await chatProvider.setLocalName(name);

    if (mounted) {
      // Continue to Bluetooth setup
      Navigator.pushReplacementNamed(context, AppConstants.routeBluetoothStatus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.getTextPrimary(context);
    final subtitleColor = AppColors.getSubtitle(context);
    
    return Scaffold(
      backgroundColor: AppColors.getBackground(context),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.person_pin_rounded,
                  size: 100,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 32),
                Text(
                  'Create Profile',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'What should other mesh nodes call you?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: subtitleColor,
                  ),
                ),
                const SizedBox(height: 48),
                TextField(
                  controller: _nameController,
                  maxLength: 20,
                  textCapitalization: TextCapitalization.words,
                  style: TextStyle(color: textPrimary, fontSize: 18),
                  decoration: InputDecoration(
                    hintText: 'Enter Display Name',
                    hintStyle: TextStyle(color: subtitleColor),
                    filled: true,
                    fillColor: AppColors.getCard(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: AppColors.primary, width: 2),
                    ),
                    prefixIcon: const Icon(Icons.badge, color: AppColors.primary),
                  ),
                  onSubmitted: (_) => _saveProfile(),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                    ),
                    child: const Text(
                      'Continue',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
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
