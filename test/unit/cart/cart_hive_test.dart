// test/unit/cart/cart_hive_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:la_diabla/domain/entities/cart_item_entity.dart';
import 'package:la_diabla/domain/entities/extra_entity.dart';
import 'package:la_diabla/domain/entities/product_entity.dart';
import 'package:la_diabla/features/cart/providers/cart_notifier.dart';

void main() {
  group('CartState', () {
    const product1 = ProductEntity(
      id: 'p1',
      name: 'Tacos al Pastor',
      description: 'Desc',
      price: 85.0,
      imageUrl: 'img',
      categoryId: 'tacos',
      spicyLevel: 2,
    );

    const extraGuacamole = ExtraEntity(
      id: 'ex1',
      name: 'Guacamole',
      price: 25.0,
    );

    test('calcula subtotal y total respetando la tarifa de envío', () {
      final items = [
        const CartItemEntity(
          id: 'item1',
          product: product1,
          quantity: 2,
          selectedExtras: [extraGuacamole], // (85 + 25) * 2 = 220
        ),
      ];

      final cartState = CartState(items: items, deliveryFee: 35.0);

      expect(cartState.subtotal, 220.0);
      expect(cartState.total, 255.0);
      expect(cartState.itemCount, 2);
      expect(cartState.isNotEmpty, isTrue);
    });
  });
}
