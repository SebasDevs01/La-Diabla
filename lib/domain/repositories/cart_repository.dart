// lib/domain/repositories/cart_repository.dart
import '../entities/cart_item_entity.dart';
import '../entities/extra_entity.dart';
import '../entities/product_entity.dart';

/// Interfaz del repositorio del carrito de compras.
/// El carrito se persiste localmente con Hive.
abstract interface class CartRepository {
  /// Obtiene todos los ítems actuales del carrito.
  Future<List<CartItemEntity>> getItems();

  /// Stream del carrito para actualización reactiva de la UI.
  Stream<List<CartItemEntity>> watchItems();

  /// Agrega un producto al carrito.
  Future<void> addItem({
    required ProductEntity product,
    required int quantity,
    List<ExtraEntity> selectedExtras,
    List<String> removedIngredients,
    Map<String, String> selectedOptions,
    String? notes,
  });

  /// Elimina un ítem del carrito por su ID de ítem.
  Future<void> removeItem(String itemId);

  /// Actualiza la cantidad de un ítem. Si quantity == 0, elimina el ítem.
  Future<void> updateQuantity(String itemId, int quantity);

  /// Actualiza las notas de un ítem.
  Future<void> updateNotes(String itemId, String? notes);

  /// Limpia el carrito completamente.
  Future<void> clearCart();

  /// Calcula el subtotal del carrito.
  Future<double> getSubtotal();

  /// Número total de ítems (suma de cantidades).
  Future<int> getItemCount();
}
