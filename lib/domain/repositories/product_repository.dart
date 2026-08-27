// lib/domain/repositories/product_repository.dart
import '../entities/product_entity.dart';

/// Interfaz del repositorio de productos.
abstract interface class ProductRepository {
  /// Obtiene todos los productos disponibles.
  Future<List<ProductEntity>> getProducts();

  /// Obtiene productos de una categoría específica.
  Future<List<ProductEntity>> getProductsByCategory(String categoryId);

  /// Obtiene un producto por su ID.
  Future<ProductEntity?> getProductById(String productId);

  /// Stream de un producto (para actualizaciones en tiempo real).
  Stream<ProductEntity?> watchProduct(String productId);

  /// Busca productos por nombre.
  Future<List<ProductEntity>> searchProducts(String query);
}
