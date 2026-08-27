// test/unit/models/product_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:la_diabla/data/models/product_model.dart';

void main() {
  group('ProductModel', () {
    test('fromMap parsea correctamente un Map de Firestore', () {
      final map = {
        'name': 'Tacos de Birria',
        'description': '3 tacos con consomé',
        'price': 110.0,
        'imageUrl': 'https://example.com/birria.jpg',
        'categoryId': 'tacos',
        'spicyLevel': 1,
        'available': true,
        'ingredients': ['Birria', 'Queso', 'Consomé'],
        'extras': [
          {'id': 'ex1', 'name': 'Consomé extra', 'price': 20.0, 'available': true}
        ],
      };

      final model = ProductModel.fromMap(map, id: 'birria_123');

      expect(model.id, 'birria_123');
      expect(model.name, 'Tacos de Birria');
      expect(model.price, 110.0);
      expect(model.spicyLevel, 1);
      expect(model.ingredients.length, 3);
      expect(model.extras.length, 1);
      expect(model.extras.first.name, 'Consomé extra');
    });

    test('toMap serializa correctamente el objeto a Map', () {
      const model = ProductModel(
        id: 'p_99',
        name: 'Burrito Diablo',
        description: 'Picante',
        price: 145.0,
        imageUrl: 'img_url',
        categoryId: 'burritos',
        spicyLevel: 3,
      );

      final map = model.toMap();

      expect(map['id'], 'p_99');
      expect(map['name'], 'Burrito Diablo');
      expect(map['price'], 145.0);
      expect(map['spicyLevel'], 3);
    });
  });
}
