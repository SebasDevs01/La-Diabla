// lib/domain/entities/product_entity.dart
import 'package:equatable/equatable.dart';
import 'extra_entity.dart';

/// Entidad de producto del menú.
class ProductEntity extends Equatable {
  const ProductEntity({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.imageUrl,
    required this.categoryId,
    required this.spicyLevel,
    this.available = true,
    this.ingredients = const [],
    this.extras = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String description;
  final double price;
  final String imageUrl;
  final String categoryId;

  /// 0 = sin picante, 1 = suave, 2 = medio, 3 = diabla
  final int spicyLevel;
  final bool available;
  final List<String> ingredients;
  final List<ExtraEntity> extras;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isSpicy => spicyLevel > 0;
  bool get isDiablaLevel => spicyLevel == 3;
  bool get hasExtras => extras.isNotEmpty;

  ProductEntity copyWith({
    String? id,
    String? name,
    String? description,
    double? price,
    String? imageUrl,
    String? categoryId,
    int? spicyLevel,
    bool? available,
    List<String>? ingredients,
    List<ExtraEntity>? extras,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ProductEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      imageUrl: imageUrl ?? this.imageUrl,
      categoryId: categoryId ?? this.categoryId,
      spicyLevel: spicyLevel ?? this.spicyLevel,
      available: available ?? this.available,
      ingredients: ingredients ?? this.ingredients,
      extras: extras ?? this.extras,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
    id, name, description, price, imageUrl, categoryId,
    spicyLevel, available, ingredients, extras,
  ];
}
