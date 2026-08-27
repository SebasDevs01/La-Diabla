// lib/data/repositories/cart_repository_impl.dart
import 'dart:async';
import 'package:uuid/uuid.dart';
import '../../domain/entities/cart_item_entity.dart';
import '../../domain/entities/extra_entity.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/repositories/cart_repository.dart';
import '../datasources/local/cart_local_datasource.dart';

class CartRepositoryImpl implements CartRepository {
  CartRepositoryImpl({CartLocalDataSource? localDataSource})
    : _localDataSource = localDataSource ?? CartLocalDataSource() {
    _loadFromLocal();
  }

  final CartLocalDataSource _localDataSource;
  final List<CartItemEntity> _items = [];
  final StreamController<List<CartItemEntity>> _cartController =
      StreamController<List<CartItemEntity>>.broadcast();

  final _uuid = const Uuid();

  void _loadFromLocal() {
    final localItems = _localDataSource.getCartItems();
    _items.clear();
    _items.addAll(localItems);
  }

  void _notify() {
    _cartController.add(List.unmodifiable(_items));
  }

  @override
  Future<List<CartItemEntity>> getItems() async {
    return List.unmodifiable(_items);
  }

  @override
  Stream<List<CartItemEntity>> watchItems() async* {
    yield List.unmodifiable(_items);
    yield* _cartController.stream;
  }

  @override
  Future<void> addItem({
    required ProductEntity product,
    required int quantity,
    List<ExtraEntity> selectedExtras = const [],
    List<String> removedIngredients = const [],
    Map<String, String> selectedOptions = const {},
    String? notes,
  }) async {
    final existingIndex = _items.indexWhere((item) {
      if (item.product.id != product.id) return false;
      if (item.selectedExtras.length != selectedExtras.length) return false;
      if (item.removedIngredients.length != removedIngredients.length) {
        return false;
      }
      if (item.selectedOptions.length != selectedOptions.length) return false;

      final existingExtraIds = item.selectedExtras.map((e) => e.id).toSet();
      final newExtraIds = selectedExtras.map((e) => e.id).toSet();
      if (!existingExtraIds.containsAll(newExtraIds)) return false;

      final existingRemoved = item.removedIngredients.toSet();
      final newRemoved = removedIngredients.toSet();
      if (!existingRemoved.containsAll(newRemoved)) return false;

      for (final entry in selectedOptions.entries) {
        if (item.selectedOptions[entry.key] != entry.value) return false;
      }

      return (item.notes ?? '') == (notes ?? '');
    });

    if (existingIndex != -1) {
      final existing = _items[existingIndex];
      final updated = existing.copyWith(quantity: existing.quantity + quantity);
      _items[existingIndex] = updated;
      await _localDataSource.saveCartItem(updated);
    } else {
      final newItem = CartItemEntity(
        id: _uuid.v4(),
        product: product,
        quantity: quantity,
        selectedExtras: selectedExtras,
        removedIngredients: removedIngredients,
        selectedOptions: selectedOptions,
        notes: notes,
      );
      _items.add(newItem);
      await _localDataSource.saveCartItem(newItem);
    }

    _notify();
  }

  @override
  Future<void> removeItem(String itemId) async {
    _items.removeWhere((item) => item.id == itemId);
    await _localDataSource.deleteCartItem(itemId);
    _notify();
  }

  @override
  Future<void> updateQuantity(String itemId, int quantity) async {
    if (quantity <= 0) {
      await removeItem(itemId);
      return;
    }

    final index = _items.indexWhere((item) => item.id == itemId);
    if (index != -1) {
      final updated = _items[index].copyWith(quantity: quantity);
      _items[index] = updated;
      await _localDataSource.saveCartItem(updated);
      _notify();
    }
  }

  @override
  Future<void> updateNotes(String itemId, String? notes) async {
    final index = _items.indexWhere((item) => item.id == itemId);
    if (index != -1) {
      final updated = _items[index].copyWith(notes: notes);
      _items[index] = updated;
      await _localDataSource.saveCartItem(updated);
      _notify();
    }
  }

  @override
  Future<void> clearCart() async {
    _items.clear();
    await _localDataSource.clearCart();
    _notify();
  }

  @override
  Future<double> getSubtotal() async {
    return _items.fold<double>(0.0, (double sum, item) => sum + item.subtotal);
  }

  @override
  Future<int> getItemCount() async {
    return _items.fold<int>(0, (int sum, item) => sum + item.quantity);
  }
}
