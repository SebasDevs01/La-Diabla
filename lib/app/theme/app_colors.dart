// lib/app/theme/app_colors.dart
import 'package:flutter/material.dart';

/// Paleta de colores oficial de La Diabla.
/// NUNCA usar colores directamente en widgets — siempre referenciar desde aquí.
abstract final class AppColors {
  // ─── Marca Principal ─────────────────────────────────────────────────────────
  /// Rojo La Diabla — color primario de marca. Usar con moderación.
  static const Color primary = Color(0xFFC62828);
  static const Color primaryDark = Color(0xFF8E0000);
  static const Color primaryLight = Color(0xFFFF5F52);

  // ─── Secundario ───────────────────────────────────────────────────────────────
  static const Color secondary = Color(0xFF2E7D32);
  static const Color secondaryDark = Color(0xFF1B5E20);
  static const Color secondaryLight = Color(0xFF60AD5E);

  // ─── Acento ────────────────────────────────────────────────────────────────
  static const Color accent = Color(0xFFF9A825);
  static const Color accentDark = Color(0xFFC17900);
  static const Color accentLight = Color(0xFFFFD95A);

  // ─── Fondos ───────────────────────────────────────────────────────────────────
  static const Color backgroundLight = Color(0xFFFFFDF5); // Warm Mexican cream off-white
  static const Color backgroundDark = Color(0xFF141210);
  static const Color surfaceLight = Color(0xFFFFFDF5);
  static const Color surfaceDark = Color(0xFF221E1B);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color cardDark = Color(0xFF2C2622);

  // ─── Texto ────────────────────────────────────────────────────────────────────
  static const Color textDark = Color(0xFF17130F);
  static const Color textLight = Color(0xFFFFFFFF);
  static const Color textMuted = Color(0xFF9E8C7E);
  static const Color textMutedDark = Color(0xFF8D7B6F);

  // ─── Tierra ───────────────────────────────────────────────────────────────────
  static const Color earth = Color(0xFF6D4C41);
  static const Color earthLight = Color(0xFF9C7B72);
  static const Color earthDark = Color(0xFF40211A);

  // ─── Neutrales ────────────────────────────────────────────────────────────────
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color divider = Color(0xFFE8D9C4);
  static const Color dividerDark = Color(0xFF3D3028);

  // ─── Semánticos ──────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFF9A825);
  static const Color error = Color(0xFFB71C1C);
  static const Color info = Color(0xFF1565C0);

  // ─── Nivel de Picante ─────────────────────────────────────────────────────────
  static const Color spicyNone = Color(0xFF9E9E9E);
  static const Color spicyMild = Color(0xFF8BC34A);
  static const Color spicyMedium = Color(0xFFF9A825);
  static const Color spicyDiabla = Color(0xFFC62828);

  // ─── Gradientes ───────────────────────────────────────────────────────────────
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8E0000), Color(0xFFC62828), Color(0xFFE53935)],
  );

  static const LinearGradient darkGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF17130F), Color(0xFF241D18)],
  );

  static const LinearGradient cardOverlay = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.transparent, Color(0xDD17130F)],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF9A825), Color(0xFFFF6F00)],
  );

  static const LinearGradient yellowHeaderGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFC107), Color(0xFFFF9800), Color(0xFFFFFDF5)],
    stops: [0.0, 0.45, 1.0],
  );
}
