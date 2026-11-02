import 'package:flutter/material.dart';
import '../utils/colors.dart';

/// Professional user avatar with gradient background, initials, and status indicator.
class UserAvatar extends StatelessWidget {
  final String name;
  final double size;
  final bool isOnline;
  final bool showStatus;
  final Widget? customBadge;

  const UserAvatar({
    super.key,
    required this.name,
    this.size = 48,
    this.isOnline = true,
    this.showStatus = true,
    this.customBadge,
  });

  // Deterministic gradient colors based on user name
  List<Color> _getGradient(String text) {
    final hash = text.codeUnits.fold(0, (prev, elem) => prev + elem);
    const gradients = [
      [Color(0xFF3B82F6), Color(0xFF1D4ED8)], // Blue
      [Color(0xFF10B981), Color(0xFF047857)], // Emerald
      [Color(0xFF8B5CF6), Color(0xFF6D28D9)], // Purple
      [Color(0xFFF59E0B), Color(0xFFD97706)], // Amber
      [Color(0xFFEC4899), Color(0xFFBE185D)], // Pink
      [Color(0xFF06B6D4), Color(0xFF0E7490)], // Cyan
      [Color(0xFF14B8A6), Color(0xFF0F766E)], // Teal
    ];
    return gradients[hash % gradients.length];
  }

  String _getInitials(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 'U';
    final parts = trimmed.split(' ');
    if (parts.length > 1 && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return trimmed.length > 1 ? trimmed.substring(0, 2).toUpperCase() : trimmed[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final gradient = _getGradient(name);
    final initials = _getInitials(name);
    final isDark = AppColors.isDark(context);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradient,
              ),
              boxShadow: [
                BoxShadow(
                  color: gradient.first.withValues(alpha: isDark ? 0.4 : 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(
                initials,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: size * 0.4,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          if (showStatus)
            Positioned(
              right: 0,
              bottom: 0,
              child: customBadge ??
                  Container(
                    width: size * 0.28,
                    height: size * 0.28,
                    decoration: BoxDecoration(
                      color: isOnline ? AppColors.statusGreen : Colors.grey.shade400,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? const Color(0xFF0A0F1D) : Colors.white,
                        width: 2,
                      ),
                      boxShadow: isOnline
                          ? [
                              BoxShadow(
                                color: AppColors.statusGreen.withValues(alpha: 0.6),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  ),
            ),
        ],
      ),
    );
  }
}
