// lib/app/theme/app_spacing.dart

/// Sistema de espaciado global de La Diabla.
/// Basado en escala de 4pt para consistencia visual.
abstract final class AppSpacing {
  // ─── Base ─────────────────────────────────────────────────────────────────────
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
  static const double xxxl = 64.0;

  // ─── Padding de Pantalla ──────────────────────────────────────────────────────
  static const double screenHorizontal = 20.0;
  static const double screenVertical = 16.0;

  // ─── Cards ────────────────────────────────────────────────────────────────────
  static const double cardPadding = 16.0;
  static const double cardRadius = 16.0;
  static const double cardRadiusLarge = 24.0;

  // ─── Botones ──────────────────────────────────────────────────────────────────
  static const double buttonHeight = 52.0;
  static const double buttonRadius = 14.0;
  static const double buttonPaddingH = 24.0;

  // ─── Iconos ───────────────────────────────────────────────────────────────────
  static const double iconSm = 16.0;
  static const double iconMd = 24.0;
  static const double iconLg = 32.0;
  static const double iconXl = 48.0;

  // ─── Bottom Nav ───────────────────────────────────────────────────────────────
  static const double bottomNavHeight = 72.0;

  // ─── App Bar ──────────────────────────────────────────────────────────────────
  static const double appBarHeight = 60.0;

  // ─── Imágenes ─────────────────────────────────────────────────────────────────
  static const double productCardImageHeight = 160.0;
  static const double heroBannerHeight = 220.0;
  static const double categoryCardSize = 80.0;
}
