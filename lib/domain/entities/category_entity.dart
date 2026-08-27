// lib/domain/entities/category_entity.dart
import 'package:equatable/equatable.dart';

/// Entidad de categoría del menú.
class CategoryEntity extends Equatable {
  const CategoryEntity({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.order,
    this.available = true,
    this.emoji,
    this.localImage,
  });

  final String id;
  final String name;
  final String imageUrl;
  final int order;
  final bool available;
  final String? emoji;
  /// Ruta local del asset (assets/images/...) para mostrar sin red
  final String? localImage;

  String get iconEmoji => emoji ?? '🌮';

  CategoryEntity copyWith({
    String? id,
    String? name,
    String? imageUrl,
    int? order,
    bool? available,
    String? emoji,
    String? localImage,
  }) {
    return CategoryEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
      order: order ?? this.order,
      available: available ?? this.available,
      emoji: emoji ?? this.emoji,
      localImage: localImage ?? this.localImage,
    );
  }

  @override
  List<Object?> get props => [id, name, imageUrl, order, available, emoji, localImage];
}
