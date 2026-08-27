// lib/domain/repositories/promotion_repository.dart

/// Entidad de promoción.
class PromotionEntity {
  const PromotionEntity({
    required this.id,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.discountType,
    required this.discountValue,
    this.code,
    this.minimumOrderAmount,
    this.expiresAt,
    this.isActive = true,
  });

  final String id;
  final String title;
  final String description;
  final String imageUrl;
  final DiscountType discountType;
  final double discountValue;
  final String? code;
  final double? minimumOrderAmount;
  final DateTime? expiresAt;
  final bool isActive;

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);
}

enum DiscountType {
  percentage,
  fixed;
}

/// Interfaz del repositorio de promociones.
abstract interface class PromotionRepository {
  /// Obtiene las promociones activas.
  Future<List<PromotionEntity>> getActivePromotions();

  /// Valida y aplica un código de promoción.
  /// Retorna el descuento calculado o lanza excepción si es inválido.
  Future<double> applyPromoCode({
    required String code,
    required double orderAmount,
  });
}
