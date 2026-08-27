// lib/data/repositories/product_repository_impl.dart
import '../../domain/entities/product_entity.dart';
import '../../domain/repositories/product_repository.dart';
import '../../mock/mock_products.dart';
import '../datasources/remote/product_remote_datasource.dart';

class ProductRepositoryImpl implements ProductRepository {
  ProductRepositoryImpl({ProductRemoteDataSource? remoteDataSource})
      : _remoteDataSource = remoteDataSource ?? ProductRemoteDataSource();

  final ProductRemoteDataSource _remoteDataSource;
  final List<ProductEntity> _mockProducts = List.from(mockProducts);

  @override
  Future<List<ProductEntity>> getProducts() async {
    try {
      final remoteProducts = await _remoteDataSource.getProducts();
      if (remoteProducts.isNotEmpty) return remoteProducts;
    } catch (_) {}
    return _mockProducts.where((p) => p.available).toList();
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
