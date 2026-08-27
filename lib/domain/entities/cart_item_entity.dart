// lib/domain/entities/cart_item_entity.dart
import 'package:equatable/equatable.dart';
import 'extra_entity.dart';
import 'product_entity.dart';

/// Ítem en el carrito de compras.
class CartItemEntity extends Equatable {
  const CartItemEntity({
    required this.id,
    required this.product,
    required this.quantity,
    this.selectedExtras = const [],
    this.removedIngredients = const [],
    this.selectedOptions = const {},
    this.notes,
  });

  /// ID único del ítem en el carrito (no del producto).
  final String id;
  final ProductEntity product;
  final int quantity;
  final List<ExtraEntity> selectedExtras;
  /// Ingredientes que el usuario decidió remover (ej: 'Cebolla', 'Cilantro')
  final List<String> removedIngredients;
  /// Opciones elegidas por el usuario (ej: {'Licor': 'Con Licor', 'Proteína': 'Camarón'})
  final Map<String, String> selectedOptions;
  final String? notes;

  double get extrasTotal =>
      selectedExtras.fold(0.0, (sum, e) => sum + e.price);

  double get unitPrice => product.price + extrasTotal;

  double get subtotal => unitPrice * quantity;

  CartItemEntity copyWith({
    String? id,
    ProductEntity? product,
    int? quantity,
    List<ExtraEntity>? selectedExtras,
    List<String>? removedIngredients,
    Map<String, String>? selectedOptions,
    String? notes,
  }) {
    return CartItemEntity(
      id: id ?? this.id,
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      selectedExtras: selectedExtras ?? this.selectedExtras,
      removedIngredients: removedIngredients ?? this.removedIngredients,
      selectedOptions: selectedOptions ?? this.selectedOptions,
      notes: notes ?? this.notes,
    );
  }

  @override
  List<Object?> get props => [
        id,
        product,
        quantity,
        selectedExtras,
        removedIngredients,
        selectedOptions,
        notes,
      ];
}
