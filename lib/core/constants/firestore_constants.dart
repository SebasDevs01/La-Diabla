// lib/core/constants/firestore_constants.dart

/// Constantes para las colecciones y campos de Cloud Firestore.
/// Centralizar aquí evita errores de tipeo en strings distribuidos.
abstract final class FirestoreConstants {
  // ─── Colecciones ──────────────────────────────────────────────────────────────
  static const String usersCollection = 'users';
  static const String categoriesCollection = 'categories';
  static const String productsCollection = 'products';
  static const String extrasCollection = 'extras';
  static const String ordersCollection = 'orders';
  static const String addressesCollection = 'addresses';
  static const String deliveriesCollection = 'deliveries';
  static const String driversCollection = 'drivers';
  static const String promotionsCollection = 'promotions';
  static const String notificationsCollection = 'notifications';
  static const String reviewsCollection = 'reviews';
  static const String settingsCollection = 'settings';

  // ─── Documento de Configuración Global ────────────────────────────────────────
  static const String globalSettingsDoc = 'global';

  // ─── Campos Comunes ───────────────────────────────────────────────────────────
  static const String fieldId = 'id';
  static const String fieldCreatedAt = 'createdAt';
  static const String fieldUpdatedAt = 'updatedAt';
  static const String fieldUserId = 'userId';
  static const String fieldStatus = 'status';
  static const String fieldAvailable = 'available';

  // ─── Campos de User ───────────────────────────────────────────────────────────
  static const String fieldName = 'name';
  static const String fieldEmail = 'email';
  static const String fieldPhone = 'phone';
  static const String fieldRole = 'role';
  static const String fieldPhotoUrl = 'photoUrl';
  static const String fieldFcmToken = 'fcmToken';

  // ─── Campos de Product ────────────────────────────────────────────────────────
  static const String fieldCategoryId = 'categoryId';
  static const String fieldPrice = 'price';
  static const String fieldSpicyLevel = 'spicyLevel';
  static const String fieldImageUrl = 'imageUrl';
  static const String fieldDescription = 'description';
  static const String fieldIngredients = 'ingredients';
  static const String fieldExtras = 'extras';

  // ─── Campos de Order ──────────────────────────────────────────────────────────
  static const String fieldSubtotal = 'subtotal';
  static const String fieldDeliveryFee = 'deliveryFee';
  static const String fieldDiscount = 'discount';
  static const String fieldTotal = 'total';
  static const String fieldItems = 'items';
  static const String fieldPaymentMethod = 'paymentMethod';
  static const String fieldPaymentStatus = 'paymentStatus';
  static const String fieldAddressId = 'addressId';
  static const String fieldAddress = 'address';
  static const String fieldLatitude = 'latitude';
  static const String fieldLongitude = 'longitude';
  static const String fieldPlaceId = 'placeId';

  // ─── Campos de Address ────────────────────────────────────────────────────────
  static const String fieldLabel = 'label';
  static const String fieldFormattedAddress = 'formattedAddress';
  static const String fieldReference = 'reference';
  static const String fieldIsDefault = 'isDefault';

  // ─── Campos de Driver ─────────────────────────────────────────────────────────
  static const String fieldDriverId = 'driverId';
  static const String fieldCurrentLat = 'currentLat';
  static const String fieldCurrentLng = 'currentLng';
  static const String fieldIsOnline = 'isOnline';
}
