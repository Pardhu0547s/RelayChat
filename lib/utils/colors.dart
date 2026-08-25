import 'package:flutter/material.dart';

/// AppColors encapsulates the RelayChat color theme for both Dark and Light modes.
class AppColors {
  // --- Dark Mode Palette ---
  static const Color darkBackground = Color(0xFF121212);
  static const Color darkCard = Color(0xFF1E1E1E);
  static const Color darkCardBorder = Color(0xFF2A2A2A);
  static const Color darkTextPrimary = Colors.white;
  static const Color darkTextSecondary = Color(0xFFB0B0B0);
  static const Color darkSubtitle = Color(0xFF9E9E9E);
  static const Color darkDivider = Color(0xFF2C2C2C);
  static const Color darkOutgoingBubble = Color(0xFF1B4D2E);
  static const Color darkIncomingBubble = Color(0xFF252A34);

  // --- Light Mode Palette ---
  static const Color lightBackground = Color(0xFFF4F6F9);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightCardBorder = Color(0xFFE2E8F0);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF475569);
  static const Color lightSubtitle = Color(0xFF64748B);
  static const Color lightDivider = Color(0xFFE2E8F0);
  static const Color lightOutgoingBubble = Color(0xFFDCF8C6);
  static const Color lightIncomingBubble = Color(0xFFF1F5F9);

  // --- Shared Brand Accents ---
  static const Color primary = Color(0xFF00C853);
  static const Color primaryDark = Color(0xFF009624);
  static const Color secondary = Color(0xFF2979FF);
  static const Color secondaryDark = Color(0xFF004ECB);
  static const Color error = Color(0xFFFF5252);

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

  static const Color statusGreen = Color(0xFF00E676);
  static const Color statusRed = Color(0xFFFF5252);
  static const Color statusOrange = Color(0xFFFFAB00);

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
