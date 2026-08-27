// lib/data/datasources/local/cart_local_datasource.dart
import 'package:hive/hive.dart';
import 'package:logger/logger.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../domain/entities/cart_item_entity.dart';
import '../../models/extra_model.dart';
import '../../models/product_model.dart';

class CartLocalDataSource {
  CartLocalDataSource({Box? box})
      : _box = box ?? (Hive.isBoxOpen(AppConstants.cartHiveBoxName)
            ? Hive.box(AppConstants.cartHiveBoxName)
            : null);

  final Box? _box;
  final Logger _logger = Logger();

  List<CartItemEntity> getCartItems() {
    if (_box == null) return [];
    try {
      final items = <CartItemEntity>[];
      for (final key in _box.keys) {
        final rawMap = _box.get(key);
        if (rawMap != null && rawMap is Map) {
          final map = Map<String, dynamic>.from(rawMap);
          final productMap = Map<String, dynamic>.from(map['product'] as Map);
          final product = ProductModel.fromMap(productMap, id: productMap['id'] as String);

          final extrasRaw = map['selectedExtras'] as List? ?? [];
          final extras = extrasRaw
              .map((e) => ExtraModel.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList();

          final removedIngRaw = map['removedIngredients'] as List? ?? [];
          final removedIngredients = removedIngRaw.map((e) => e.toString()).toList();

          final selectedOptsRaw = map['selectedOptions'] as Map? ?? {};
          final selectedOptions = Map<String, String>.from(
            selectedOptsRaw.map((k, v) => MapEntry(k.toString(), v.toString())),
          );

          items.add(CartItemEntity(
            id: map['id'] as String,
            product: product,
            quantity: map['quantity'] as int,
            selectedExtras: extras,
            removedIngredients: removedIngredients,
            selectedOptions: selectedOptions,
            notes: map['notes'] as String?,
          ));
        }
      }
      return items;
    } catch (e) {
      _logger.e('Error leyendo carrito de Hive', error: e);
      return [];
    }
  }

  Future<void> saveCartItem(CartItemEntity item) async {
    if (_box == null) return;
    try {
      final itemMap = {
        'id': item.id,
        'product': ProductModel.fromEntity(item.product).toMap(),
        'quantity': item.quantity,
        'selectedExtras': item.selectedExtras.map((e) => ExtraModel.fromEntity(e).toMap()).toList(),
        'removedIngredients': item.removedIngredients,
        'selectedOptions': item.selectedOptions,
        'notes': item.notes,
      };
      await _box.put(item.id, itemMap);
    } catch (e) {
      _logger.e('Error guardando ítem de carrito en Hive', error: e);
    }
  }

  Future<void> deleteCartItem(String id) async {
    if (_box == null) return;
    try {
      await _box.delete(id);
    } catch (e) {
      _logger.e('Error eliminando ítem de carrito en Hive', error: e);
    }
  }

  Future<void> clearCart() async {
    if (_box == null) return;
    try {
      await _box.clear();
    } catch (e) {
      _logger.e('Error limpiando carrito en Hive', error: e);
    }
  }
}
