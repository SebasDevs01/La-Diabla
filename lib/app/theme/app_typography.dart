// lib/app/theme/app_typography.dart
import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Sistema tipográfico global de La Diabla.
///
/// Bangers  → display / títulos / branding (asset local)
/// Poppins  → interfaz / textos funcionales (asset local)
abstract final class AppTypography {
  // ─── Familias ─────────────────────────────────────────────────────────────────
  /// Usar en títulos principales, branding y botones de acción destacados.
  static const String displayFamily = 'Bangers';

  /// Usar en textos secundarios, descripciones, formularios, precios y nav.
  static const String bodyFamily = 'Poppins';

  // ─── TextTheme Light ──────────────────────────────────────────────────────────
  static TextTheme get textThemeLight => _buildTextTheme(AppColors.textDark);

  // ─── TextTheme Dark ───────────────────────────────────────────────────────────
  static TextTheme get textThemeDark => _buildTextTheme(AppColors.textLight);

  static TextTheme _buildTextTheme(Color textColor) {
    return TextTheme(
      // ─── Display — Bangers ────────────────────────────────────────────────────
      // Uso: encabezados hero, banners de branding, sección principal
      displayLarge: TextStyle(
        fontFamily: displayFamily,
        fontSize: 57,
        fontWeight: FontWeight.w400,
        letterSpacing: 1.5,
        color: textColor,
      ),
      displayMedium: TextStyle(
        fontFamily: displayFamily,
        fontSize: 45,
        fontWeight: FontWeight.w400,
        letterSpacing: 1.2,
        color: textColor,
      ),
      displaySmall: TextStyle(
        fontFamily: displayFamily,
        fontSize: 36,
        fontWeight: FontWeight.w400,
        letterSpacing: 1.0,
        color: textColor,
      ),

      // ─── Headline — Bangers ───────────────────────────────────────────────────
      // Uso: títulos de sección (MENÚ, PEDIDOS, POPULARES, MI PERFIL…)
      headlineLarge: TextStyle(
        fontFamily: displayFamily,
        fontSize: 32,
        fontWeight: FontWeight.w400,
        letterSpacing: 1.0,
        color: textColor,
      ),
      headlineMedium: TextStyle(
        fontFamily: displayFamily,
        fontSize: 28,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.8,
        color: textColor,
      ),
      headlineSmall: TextStyle(
        fontFamily: displayFamily,
        fontSize: 24,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.6,
        color: textColor,
      ),

      // ─── Title — Poppins ──────────────────────────────────────────────────────
      // Uso: subtítulos de card, nombres de producto, encabezados de pantalla
      titleLarge: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
      titleMedium: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
        color: textColor,
      ),
      titleSmall: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: textColor,
      ),

      // ─── Body — Poppins ───────────────────────────────────────────────────────
      // Uso: descripciones, ingredientes, textos informativos
      bodyLarge: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.5,
        color: textColor,
      ),
      bodyMedium: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.25,
        color: textColor,
      ),
      bodySmall: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.4,
        color: textColor,
      ),

      // ─── Label — Poppins ──────────────────────────────────────────────────────
      // Uso: etiquetas de campo, chips, nav items, precios
      labelLarge: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
        color: textColor,
      ),
      labelMedium: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: textColor,
      ),
      labelSmall: TextStyle(
        fontFamily: bodyFamily,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: textColor,
      ),
    );
  }
}
