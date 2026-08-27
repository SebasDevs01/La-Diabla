// lib/domain/usecases/cart/calculate_cart_total_usecase.dart
import '../../entities/cart_item_entity.dart';

/// Use case para calcular el total del carrito.
/// Esta lógica está en el dominio para poder testearse sin dependencias externas.
class CalculateCartTotalUseCase {
  /// Calcula el subtotal sumando (precio + extras) * cantidad de cada ítem.
  double calculateSubtotal(List<CartItemEntity> items) {
    return items.fold(0.0, (total, item) => total + item.subtotal);
  }

  /// Calcula el total final con entrega y descuento.
  double calculateTotal({
    required List<CartItemEntity> items,
    required double deliveryFee,
    double discount = 0.0,
  }) {
    final subtotal = calculateSubtotal(items);
    final total = subtotal + deliveryFee - discount;
    return total < 0 ? 0.0 : total;
  }

  /// Número total de productos en el carrito.
  int calculateItemCount(List<CartItemEntity> items) {
    return items.fold(0, (count, item) => count + item.quantity);
  }
}
