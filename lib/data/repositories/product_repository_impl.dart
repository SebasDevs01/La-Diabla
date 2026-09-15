// lib/data/repositories/product_repository_impl.dart
import '../../domain/entities/product_entity.dart';
import '../../domain/repositories/product_repository.dart';
import '../../mock/mock_products.dart';
import '../datasources/remote/product_remote_datasource.dart';

import '../models/product_model.dart';

class ProductRepositoryImpl implements ProductRepository {
  ProductRepositoryImpl({ProductRemoteDataSource? remoteDataSource})
      : _remoteDataSource = remoteDataSource ?? ProductRemoteDataSource();

  final ProductRemoteDataSource _remoteDataSource;
  final List<ProductEntity> _mockProducts = List.from(mockProducts);

  @override
  Future<List<ProductEntity>> getProducts() async {
    try {
      final remoteProducts = await _remoteDataSource.getProducts();
      if (remoteProducts.isNotEmpty) {
        // Garantizar que el producto de prueba de $50 COP esté siempre disponible para pruebas de pago con tarjeta
        final hasTest = remoteProducts.any((p) => p.id == 'test_tarjeta_50');
        if (!hasTest) {
          final testProduct = _mockProducts.firstWhere(
            (p) => p.id == 'test_tarjeta_50',
            orElse: () => mockProducts.first,
          );
          return [testProduct, ...remoteProducts];
        }
        return remoteProducts;
      }
    } catch (_) {}
    return _mockProducts.where((p) => p.available).toList();
  }

  @override
  Stream<List<ProductEntity>> watchAllProducts({bool availableOnly = true}) {
    return _remoteDataSource
        .watchAllProducts(availableOnly: availableOnly)
        .map((products) {
      if (products.isEmpty) {
        // Fallback al mock si la colección en Firestore está vacía aún
        return availableOnly
            ? _mockProducts.where((p) => p.available).toList()
            : _mockProducts;
      }
      return products;
    });
  }

  @override
  Future<void> createProduct(ProductEntity product) async {
    final model = ProductModel(
      id: product.id,
      name: product.name,
      description: product.description,
      price: product.price,
      imageUrl: product.imageUrl,
      categoryId: product.categoryId,
      spicyLevel: product.spicyLevel,
      available: product.available,
      ingredients: product.ingredients,
      extras: product.extras,
      createdAt: product.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _remoteDataSource.createProduct(model);
  }

  @override
  Future<void> updateProduct(ProductEntity product) async {
    final model = ProductModel(
      id: product.id,
      name: product.name,
      description: product.description,
      price: product.price,
      imageUrl: product.imageUrl,
      categoryId: product.categoryId,
      spicyLevel: product.spicyLevel,
      available: product.available,
      ingredients: product.ingredients,
      extras: product.extras,
      createdAt: product.createdAt,
      updatedAt: DateTime.now(),
    );
    await _remoteDataSource.updateProduct(model);
  }

  @override
  Future<void> deleteProduct(String productId) async {
    await _remoteDataSource.deleteProduct(productId);
  }

  @override
  Future<void> toggleProductAvailability(String productId, bool available) async {
    await _remoteDataSource.toggleProductAvailability(productId, available);
  }

  @override
  Future<int> seedInitialCatalog(List<ProductEntity> initialProducts) async {
    final models = initialProducts.map((p) => ProductModel(
      id: p.id,
      name: p.name,
      description: p.description,
      price: p.price,
      imageUrl: p.imageUrl,
      categoryId: p.categoryId,
      spicyLevel: p.spicyLevel,
      available: p.available,
      ingredients: p.ingredients,
      extras: p.extras,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    )).toList();
    return await _remoteDataSource.seedInitialCatalog(models);
  }

  @override
  Future<List<ProductEntity>> getProductsByCategory(String categoryId) async {
    final allProducts = await getProducts();
    return allProducts.where((p) => p.categoryId == categoryId && p.available).toList();
  }

  @override
  Future<ProductEntity?> getProductById(String productId) async {
    final allProducts = await getProducts();
    try {
      return allProducts.firstWhere((p) => p.id == productId);
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<ProductEntity?> watchProduct(String productId) async* {
    yield await getProductById(productId);
  }

  @override
  Future<List<ProductEntity>> searchProducts(String query) async {
    final cleanQuery = query.trim().toLowerCase();
    final allProducts = await getProducts();
    if (cleanQuery.isEmpty) return allProducts;

    return allProducts.where((p) {
      return p.name.toLowerCase().contains(cleanQuery) ||
          p.description.toLowerCase().contains(cleanQuery);
    }).toList();
  }
}
