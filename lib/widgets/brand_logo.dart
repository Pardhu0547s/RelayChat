import 'package:flutter/material.dart';
import '../utils/colors.dart';
import '../utils/constants.dart';

/// Professional RelayChat Logo component with glow and border options.
class BrandLogo extends StatelessWidget {
  final double size;
  final bool showGlow;
  final bool isCircle;
  final double borderRadius;
  final Color? glowColor;

  const BrandLogo({
    super.key,
    this.size = 40,
    this.showGlow = false,
    this.isCircle = true,
    this.borderRadius = 12,
    this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveGlow = glowColor ?? AppColors.primary;
    final isDark = AppColors.isDark(context);

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.08),
      decoration: BoxDecoration(
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(borderRadius),
        color: isDark ? const Color(0xFF131B2E) : Colors.white,
        border: Border.all(
          color: effectiveGlow.withValues(alpha: isDark ? 0.4 : 0.3),
          width: size > 60 ? 2.0 : 1.2,
        ),
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: effectiveGlow.withValues(alpha: isDark ? 0.35 : 0.2),
                  blurRadius: size * 0.25,
                  spreadRadius: 1,
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(isCircle ? size : borderRadius * 0.8),
        child: Image.asset(
          AppConstants.logoPath,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.wifi_tethering_rounded,
            size: size * 0.55,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}
