// lib/domain/repositories/category_repository.dart
import '../entities/category_entity.dart';

/// Interfaz del repositorio de categorías.
abstract interface class CategoryRepository {
  /// Obtiene todas las categorías disponibles, ordenadas.
  Future<List<CategoryEntity>> getCategories();

  /// Stream de categorías para actualizaciones en tiempo real.
  Stream<List<CategoryEntity>> watchCategories();
}
