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
    super.images,
    super.createdAt,
    super.updatedAt,
  });

  factory ProductModel.fromMap(Map<String, dynamic> map, {required String id}) {
    final extrasRaw = map['extras'] as List<dynamic>? ?? [];
    final ingredientsRaw = map['ingredients'] as List<dynamic>? ?? [];
    final imagesRaw = map['images'] as List<dynamic>? ?? [];

    final parsedImages = imagesRaw
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final directImageUrl = (map['imageUrl'] as String? ?? '').trim();
    final effectiveImageUrl = directImageUrl.isNotEmpty
        ? directImageUrl
        : (parsedImages.isNotEmpty ? parsedImages.first : '');

    // Si images no vino pero sí imageUrl, poblar images con esa única foto
    final finalImages = parsedImages.isNotEmpty
        ? parsedImages
        : (effectiveImageUrl.isNotEmpty ? [effectiveImageUrl] : <String>[]);

    return ProductModel(
      id: id,
      name: map['name'] as String? ?? '',
      description: map['description'] as String? ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      imageUrl: effectiveImageUrl,
      categoryId: map['categoryId'] as String? ?? '',
      spicyLevel: map['spicyLevel'] as int? ?? 0,
      available: map['available'] as bool? ?? true,
      ingredients: ingredientsRaw.map((e) => e.toString()).toList(),
      extras: extrasRaw
          .whereType<Map>()
          .map((e) => ExtraModel.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      images: finalImages,
      createdAt: map['createdAt'] != null
          ? (map['createdAt'] is int
              ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int)
              : DateTime.tryParse(map['createdAt'].toString()))
          : null,
      updatedAt: map['updatedAt'] != null
          ? (map['updatedAt'] is int
              ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int)
              : DateTime.tryParse(map['updatedAt'].toString()))
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    final effectiveImages = images.isNotEmpty
        ? images
        : (imageUrl.isNotEmpty ? [imageUrl] : <String>[]);
    final mainImage = imageUrl.isNotEmpty
        ? imageUrl
        : (effectiveImages.isNotEmpty ? effectiveImages.first : '');

    return {
      'id': id,
      'name': name,
      'description': description,
      'price': price,
      'imageUrl': mainImage,
      'images': effectiveImages,
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
      images: entity.images,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
    );
  }
}
