import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_diabla/features/cart/providers/cart_notifier.dart';
import 'package:la_diabla/features/checkout/presentation/screens/checkout_screen.dart';
import 'package:la_diabla/domain/entities/cart_item_entity.dart';
import 'package:la_diabla/domain/entities/product_entity.dart';

void main() {
  testWidgets('CheckoutScreen renders without throwing exceptions', (WidgetTester tester) async {
    const testProduct = ProductEntity(
      id: 'prod_1',
      name: 'Tacos Al Pastor',
      description: 'Tacos deliciosos',
      price: 25000,
      imageUrl: '',
      categoryId: 'tacos',
      spicyLevel: 2,
    );

    final item = const CartItemEntity(
      id: 'item_1',
      product: testProduct,
      quantity: 1,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cartNotifierProvider.overrideWith((ref) => CartNotifier(ref)..state = CartState(items: [item])),
        ],
        child: const MaterialApp(
          home: CheckoutScreen(),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('Confirmar y Pagar 🌶️'), findsOneWidget);
    expect(find.text('1. Dirección de Entrega 📍'), findsOneWidget);
    expect(find.text('2. Método de Pago 💳'), findsOneWidget);
  });
}
