// lib/domain/entities/extra_entity.dart
import 'package:equatable/equatable.dart';

/// Extra o complemento para un producto (ejemplo: guacamole, queso extra).
class ExtraEntity extends Equatable {
  const ExtraEntity({
    required this.id,
    required this.name,
    required this.price,
    this.available = true,
  });

  final String id;
  final String name;
  final double price;
  final bool available;

  bool get isFree => price == 0.0;

  ExtraEntity copyWith({
    String? id,
    String? name,
    double? price,
    bool? available,
  }) {
    return ExtraEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      available: available ?? this.available,
    );
  }

  @override
  List<Object?> get props => [id, name, price, available];
}
