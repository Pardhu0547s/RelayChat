import 'package:flutter/material.dart';

/// AppColors encapsulates the RelayChat color theme for both Dark and Light modes.
class AppColors {
  // --- Dark Mode Palette (Rich Obsidian & Slate) ---
  static const Color darkBackground = Color(0xFF0A0F1D);
  static const Color darkCard = Color(0xFF131B2E);
  static const Color darkCardBorder = Color(0xFF1E293B);
  static const Color darkTextPrimary = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkSubtitle = Color(0xFF64748B);
  static const Color darkDivider = Color(0xFF1E293B);
  static const Color darkOutgoingBubble = Color(0xFF065F46);
  static const Color darkIncomingBubble = Color(0xFF1E293B);

  // --- Light Mode Palette (Clean Porcelain & Slate) ---
  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightCardBorder = Color(0xFFE2E8F0);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF475569);
  static const Color lightSubtitle = Color(0xFF64748B);
  static const Color lightDivider = Color(0xFFE2E8F0);
  static const Color lightOutgoingBubble = Color(0xFFD1FAE5);
  static const Color lightIncomingBubble = Color(0xFFFFFFFF);

  // --- Shared Brand Accents ---
  static const Color primary = Color(0xFF10B981); // Emerald Green
  static const Color primaryDark = Color(0xFF059669);
  static const Color primaryLight = Color(0xFF34D399);
  static const Color secondary = Color(0xFF3B82F6); // Electric Blue
  static const Color secondaryDark = Color(0xFF2563EB);
  static const Color error = Color(0xFFEF4444);

  // --- Dynamic Color Getters based on BuildContext / Brightness ---
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color getBackground(BuildContext context) =>
      isDark(context) ? darkBackground : lightBackground;

  static Color getCard(BuildContext context) =>
      isDark(context) ? darkCard : lightCard;

  static Color getCardBorder(BuildContext context) =>
      isDark(context) ? darkCardBorder : lightCardBorder;

  static Color getTextPrimary(BuildContext context) =>
      isDark(context) ? darkTextPrimary : lightTextPrimary;

  static Color getTextSecondary(BuildContext context) =>
      isDark(context) ? darkTextSecondary : lightTextSecondary;

  static Color getSubtitle(BuildContext context) =>
      isDark(context) ? darkSubtitle : lightSubtitle;

  static Color getDivider(BuildContext context) =>
      isDark(context) ? darkDivider : lightDivider;

  static Color getOutgoingBubble(BuildContext context) =>
      isDark(context) ? darkOutgoingBubble : lightOutgoingBubble;

  static Color getIncomingBubble(BuildContext context) =>
      isDark(context) ? darkIncomingBubble : lightIncomingBubble;

  static const Color statusGreen = Color(0xFF10B981);
  static const Color statusRed = Color(0xFFEF4444);
  static const Color statusOrange = Color(0xFFF59E0B);

  // Backward compatibility static constants
  static const Color background = darkBackground;
  static const Color card = darkCard;
  static const Color cardBorder = darkCardBorder;
  static const Color textPrimary = darkTextPrimary;
  static const Color textSecondary = darkTextSecondary;
  static const Color subtitle = darkSubtitle;
  static const Color divider = darkDivider;
  static const Color outgoingBubble = darkOutgoingBubble;
  static const Color incomingBubble = darkIncomingBubble;
}
