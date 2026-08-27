// lib/data/models/product_model.dart
import '../../domain/entities/product_entity.dart';
import 'extra_model.dart';

/// Modelo de producto para serialización con Firestore.
class ProductModel extends ProductEntity {
  const ProductModel({
    required super.id,
    required super.name,
    required super.description,
    required super.price,
    required super.imageUrl,
    required super.categoryId,
    required super.spicyLevel,
    super.available,
    super.ingredients,
    super.extras,
    super.createdAt,
    super.updatedAt,
  });

  factory ProductModel.fromMap(Map<String, dynamic> map, {required String id}) {
    final extrasRaw = map['extras'] as List<dynamic>? ?? [];
    final ingredientsRaw = map['ingredients'] as List<dynamic>? ?? [];

    return ProductModel(
      id: id,
      name: map['name'] as String? ?? '',
      description: map['description'] as String? ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      imageUrl: map['imageUrl'] as String? ?? '',
      categoryId: map['categoryId'] as String? ?? '',
      spicyLevel: map['spicyLevel'] as int? ?? 0,
      available: map['available'] as bool? ?? true,
      ingredients: ingredientsRaw.map((e) => e.toString()).toList(),
      extras: extrasRaw
          .map((e) => ExtraModel.fromMap(e as Map<String, dynamic>))
          .toList(),
      createdAt: map['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int)
          : null,
      updatedAt: map['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'price': price,
      'imageUrl': imageUrl,
      'categoryId': categoryId,
      'spicyLevel': spicyLevel,
      'available': available,
      'ingredients': ingredients,
      'extras': extras.map((e) => ExtraModel.fromEntity(e).toMap()).toList(),
      'createdAt': createdAt?.millisecondsSinceEpoch,
      'updatedAt':
          updatedAt?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch,
    };
  }

  factory ProductModel.fromEntity(ProductEntity entity) {
    return ProductModel(
      id: entity.id,
      name: entity.name,
      description: entity.description,
      price: entity.price,
      imageUrl: entity.imageUrl,
      categoryId: entity.categoryId,
      spicyLevel: entity.spicyLevel,
      available: entity.available,
      ingredients: entity.ingredients,
      extras: entity.extras,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
    );
  }
}
