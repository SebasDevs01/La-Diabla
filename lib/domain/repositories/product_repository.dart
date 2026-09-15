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

  /// Stream de todos los productos en tiempo real.
  Stream<List<ProductEntity>> watchAllProducts({bool availableOnly = true});

  /// Crea un nuevo producto en Firestore.
  Future<void> createProduct(ProductEntity product);

  /// Actualiza un producto existente en Firestore.
  Future<void> updateProduct(ProductEntity product);

  /// Elimina un producto de Firestore.
  Future<void> deleteProduct(String productId);

  /// Cambia el estado de disponibilidad de un producto.
  Future<void> toggleProductAvailability(String productId, bool available);

  /// Busca productos por nombre o descripción.
  Future<List<ProductEntity>> searchProducts(String query);

  /// Migra o siembra el catálogo inicial en Firestore.
  Future<int> seedInitialCatalog(List<ProductEntity> initialProducts);
}
