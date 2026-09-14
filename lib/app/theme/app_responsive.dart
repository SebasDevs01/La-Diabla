// lib/app/theme/app_responsive.dart
//
// Sistema central de responsividad para La Diabla.
// Úsalo en cualquier widget para adaptar layout, fuentes y dimensiones
// según el tamaño de pantalla del dispositivo.
//
// Uso típico:
//   final cols  = AppResponsive.gridColumns(context);
//   final h     = AppResponsive.dp(context, 220);
//   final fSize = AppResponsive.sp(context, 16);

import 'package:flutter/material.dart';

/// Breakpoints de ancho de pantalla.
enum ScreenSize { phone, tablet, tabletLarge }

abstract final class AppResponsive {
  // ─── Breakpoints ─────────────────────────────────────────────────────────
  static const double _tabletBreak      = 600;
  static const double _tabletLargeBreak = 900;

  // ─── Ancho máximo del contenido en pantallas grandes ─────────────────────
  static const double maxContentWidth = 720;

  // ─── Clasificación del dispositivo ───────────────────────────────────────

  /// Ancho lógico de la pantalla actual.
  static double screenWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  /// Alto lógico de la pantalla actual.
  static double screenHeight(BuildContext context) =>
      MediaQuery.sizeOf(context).height;

  /// Categoría del dispositivo actual.
  static ScreenSize screenSize(BuildContext context) {
    final w = screenWidth(context);
    if (w >= _tabletLargeBreak) return ScreenSize.tabletLarge;
    if (w >= _tabletBreak) return ScreenSize.tablet;
    return ScreenSize.phone;
  }

  /// true si el dispositivo es tablet o mayor.
  static bool isTablet(BuildContext context) =>
      screenWidth(context) >= _tabletBreak;

  /// true si el dispositivo es tablet grande (≥900dp).
  static bool isTabletLarge(BuildContext context) =>
      screenWidth(context) >= _tabletLargeBreak;

  // ─── Escala de Dimensiones ────────────────────────────────────────────────

  /// Escala una dimensión (padding, altura, etc.) según el tamaño de pantalla.
  ///
  /// El valor base está optimizado para teléfonos (360–420dp).
  /// En tablets se escala proporcionalmente hasta un techo razonable.
  static double dp(BuildContext context, double base) {
    final w = screenWidth(context);
    if (w >= _tabletLargeBreak) return base * 1.35;
    if (w >= _tabletBreak) return base * 1.15;
    // Para teléfonos: escala lineal entre 0.88 (360dp) y 1.0 (420dp)
    final t = ((w - 360) / 60).clamp(0.0, 1.0);
    return base * (0.88 + t * 0.12);
  }

  /// Escala un tamaño de fuente según el tamaño de pantalla.
  static double sp(BuildContext context, double base) {
    final w = screenWidth(context);
    if (w >= _tabletLargeBreak) return base * 1.2;
    if (w >= _tabletBreak) return base * 1.1;
    final t = ((w - 360) / 60).clamp(0.0, 1.0);
    return base * (0.92 + t * 0.08);
  }

  // ─── Grid ─────────────────────────────────────────────────────────────────

  /// Número de columnas para grids de productos.
  static int gridColumns(BuildContext context) {
    final w = screenWidth(context);
    if (w >= _tabletLargeBreak) return 4;
    if (w >= _tabletBreak) return 3;
    return 2;
  }

  /// Número de columnas para grids de categorías.
  static int categoryColumns(BuildContext context) {
    final w = screenWidth(context);
    if (w >= _tabletLargeBreak) return 6;
    if (w >= _tabletBreak) return 5;
    return 4;
  }

  // ─── Padding de Pantalla ──────────────────────────────────────────────────

  /// Padding horizontal de pantalla adaptado al dispositivo.
  static double screenPaddingH(BuildContext context) {
    final w = screenWidth(context);
    if (w >= _tabletLargeBreak) return 48.0;
    if (w >= _tabletBreak) return 32.0;
    return 20.0;
  }

  /// Padding vertical de pantalla adaptado al dispositivo.
  static double screenPaddingV(BuildContext context) => dp(context, 16);

  // ─── Alturas estándar ─────────────────────────────────────────────────────

  /// Altura del banner hero.
  static double bannerHeight(BuildContext context) => dp(context, 210);

  /// Altura de las tarjetas de categoría.
  static double categoryCardSize(BuildContext context) => dp(context, 78);

  /// Altura de botones de acción principal.
  static double buttonHeight(BuildContext context) => dp(context, 52);

  /// Altura de la bottom nav bar.
  static double bottomNavHeight(BuildContext context) => dp(context, 64);

  // ─── Layout Helper ────────────────────────────────────────────────────────

  /// Envuelve [child] en un ConstrainedBox centrado para pantallas grandes.
  /// En teléfonos devuelve [child] sin modificar.
  static Widget constrained(BuildContext context, Widget child) {
    if (!isTablet(context)) return child;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxContentWidth),
        child: child,
      ),
    );
  }

  /// Padding horizontal de pantalla como EdgeInsets.
  static EdgeInsets horizontalPadding(BuildContext context) =>
      EdgeInsets.symmetric(horizontal: screenPaddingH(context));
}
