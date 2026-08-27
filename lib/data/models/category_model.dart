// lib/data/models/category_model.dart
import '../../domain/entities/category_entity.dart';

/// Modelo de categoría para serialización con Firestore.
class CategoryModel extends CategoryEntity {
  const CategoryModel({
    required super.id,
    required super.name,
    required super.imageUrl,
    required super.order,
    super.available,
    super.emoji,
  });

  factory CategoryModel.fromMap(Map<String, dynamic> map, {required String id}) {
    return CategoryModel(
      id: id,
      name: map['name'] as String? ?? '',
      imageUrl: map['imageUrl'] as String? ?? '',
      order: map['order'] as int? ?? 0,
      available: map['available'] as bool? ?? true,
      emoji: map['emoji'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'imageUrl': imageUrl,
      'order': order,
      'available': available,
      if (emoji != null) 'emoji': emoji,
    };
  }

  factory CategoryModel.fromEntity(CategoryEntity entity) {
    return CategoryModel(
      id: entity.id,
      name: entity.name,
      imageUrl: entity.imageUrl,
      order: entity.order,
      available: entity.available,
      emoji: entity.emoji,
    );
  }
}
