// test/unit/cart/cart_total_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:la_diabla/domain/entities/cart_item_entity.dart';
import 'package:la_diabla/domain/entities/extra_entity.dart';
import 'package:la_diabla/domain/entities/product_entity.dart';
import 'package:la_diabla/domain/usecases/cart/calculate_cart_total_usecase.dart';

void main() {
  late CalculateCartTotalUseCase useCase;

  setUp(() {
    useCase = CalculateCartTotalUseCase();
  });

  group('CalculateCartTotalUseCase', () {
    const product1 = ProductEntity(
      id: 'p1',
      name: 'Tacos al Pastor',
      description: 'Desc',
      price: 85.0,
      imageUrl: 'img',
      categoryId: 'tacos',
      spicyLevel: 2,
    );

    const product2 = ProductEntity(
      id: 'p2',
      name: 'Burrito Diablo',
      description: 'Desc',
      price: 145.0,
      imageUrl: 'img',
      categoryId: 'burritos',
      spicyLevel: 3,
    );

    const extraGuacamole = ExtraEntity(
      id: 'ex1',
      name: 'Guacamole',
      price: 25.0,
    );

    test('calcula el subtotal correctamente sin extras', () {
      final items = [
        const CartItemEntity(id: 'item1', product: product1, quantity: 2), // 85 * 2 = 170
        const CartItemEntity(id: 'item2', product: product2, quantity: 1), // 145 * 1 = 145
      ];

      final subtotal = useCase.calculateSubtotal(items);
      expect(subtotal, 315.0);
    });

    test('calcula el subtotal sumando extras por ítem', () {
      final items = [
        const CartItemEntity(
          id: 'item1',
          product: product1,
          quantity: 2,
          selectedExtras: [extraGuacamole], // (85 + 25) * 2 = 220
        ),
      ];

      final subtotal = useCase.calculateSubtotal(items);
      expect(subtotal, 220.0);
    });

    test('calcula el total final sumando tarifa de envío y aplicando descuento', () {
      final items = [
        const CartItemEntity(id: 'item1', product: product1, quantity: 2), // 170
      ];

      final total = useCase.calculateTotal(
        items: items,
        deliveryFee: 35.0,
        discount: 20.0,
      );

      expect(total, 185.0); // 170 + 35 - 20 = 185
    });

    test('cuenta la cantidad total de productos en el carrito', () {
      final items = [
        const CartItemEntity(id: 'item1', product: product1, quantity: 3),
        const CartItemEntity(id: 'item2', product: product2, quantity: 2),
      ];

      final count = useCase.calculateItemCount(items);
      expect(count, 5);
    });
  });
}
