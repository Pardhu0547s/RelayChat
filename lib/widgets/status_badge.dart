import 'package:flutter/material.dart';
import '../utils/colors.dart';

class StatusBadge extends StatelessWidget {
  final String label;
  final bool isPositive;
  final IconData? customIcon;
  final Color? customColor;

  const StatusBadge({
    super.key,
    required this.label,
    this.isPositive = true,
    this.customIcon,
    this.customColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = customColor ?? (isPositive ? AppColors.statusGreen : AppColors.statusRed);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (customIcon != null) ...[
            Icon(customIcon, size: 14, color: color),
            const SizedBox(width: 5),
          ] else ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.6),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
