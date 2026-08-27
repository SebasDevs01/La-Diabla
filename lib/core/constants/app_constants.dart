// lib/core/constants/app_constants.dart

/// Constantes globales de la aplicación.
abstract final class AppConstants {
  // ─── App Info ─────────────────────────────────────────────────────────────────
  static const String appName = 'La Diabla';
  static const String appTagline = 'El sabor que te despierta.';
  static const String appDomain = 'ladiabla.app';
  static const String appBaseUrl = 'https://ladiabla.app';
  static const String appDeepLinkScheme = 'ladiabla';
  static const String appDeepLinkPath = '/go';

  // ─── Store Links ──────────────────────────────────────────────────────────────
  static const String googlePlayUrl =
      'https://play.google.com/store/apps/details?id=com.ladiabla.app';
  static const String appStoreUrl =
      'https://apps.apple.com/app/la-diabla/id000000000';

  // ─── Delivery ─────────────────────────────────────────────────────────────────
  static const double defaultDeliveryRadius = 10.0; // km
  static const int estimatedDeliveryMinutes = 35;
  static const double minimumOrderAmount = 20000.0; // COP

  // ─── Cart ─────────────────────────────────────────────────────────────────────
  static const String cartHiveBoxName = 'cart_box';
  static const int maxQuantityPerItem = 20;

  // ─── Pagination ───────────────────────────────────────────────────────────────
  static const int defaultPageSize = 20;

  // ─── Timeouts ─────────────────────────────────────────────────────────────────
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);

  // ─── Niveles de Picante ───────────────────────────────────────────────────────
  static const int spicyNone = 0;
  static const int spicyMild = 1;
  static const int spicyMedium = 2;
  static const int spicyDiabla = 3;

  static String spicyLabel(int level) {
    return switch (level) {
      0 => 'Sin picante',
      1 => 'Suave',
      2 => 'Medio',
      3 => 'Diabla 🌶️',
      _ => 'Desconocido',
    };
  }

  // ─── Roles ────────────────────────────────────────────────────────────────────
  static const String roleCustomer = 'customer';
  static const String roleAdmin = 'admin';
  static const String roleDriver = 'driver';
  static const String roleKitchen = 'kitchen';

  // ─── Tipos de Pedido ──────────────────────────────────────────────────────────
  static const String orderTypeDelivery = 'DELIVERY';
  // static const String orderTypePickup = 'PICKUP'; // Preparado para el futuro

  // ─── Currency ─────────────────────────────────────────────────────────────────
  static const String currencySymbol = '\$';
  static const String currencyCode = 'COP';
}
