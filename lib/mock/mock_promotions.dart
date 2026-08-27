// lib/mock/mock_promotions.dart
import '../domain/repositories/promotion_repository.dart';

final List<PromotionEntity> mockPromotions = [
  PromotionEntity(
    id: 'promo_combo_diabla',
    title: '🔥 COMBO LA DIABLA',
    description: r'3 Tacos Pastor + Burrito El Diablo + Agua de Horchata 1L con 25% OFF',
    imageUrl: 'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=800',
    discountType: DiscountType.percentage,
    discountValue: 25.0,
    code: 'DIABLA25',
    minimumOrderAmount: 40000.0,
    expiresAt: DateTime.now().add(const Duration(days: 15)),
  ),
  PromotionEntity(
    id: 'promo_envio_gratis',
    title: '🚀 ENVÍO GRATIS EN TU PRIMER PEDIDO',
    description: r'Aplica en compras mayores a $30.000 COP.',
    imageUrl: 'https://images.unsplash.com/photo-1626700051175-6818013e1d4f?w=800',
    discountType: DiscountType.fixed,
    discountValue: 8000.0,
    code: 'PRIMERPASO',
    minimumOrderAmount: 30000.0,
    expiresAt: DateTime.now().add(const Duration(days: 30)),
  ),
];
