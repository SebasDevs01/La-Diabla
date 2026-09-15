// lib/features/home/providers/home_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/repositories/category_repository_impl.dart';
import '../../../data/repositories/product_repository_impl.dart';
import '../../../domain/entities/category_entity.dart';
import '../../../domain/entities/product_entity.dart';
import '../../../domain/repositories/category_repository.dart';
import '../../../domain/repositories/product_repository.dart';

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return CategoryRepositoryImpl();
});

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepositoryImpl();
});

final categoriesProvider = FutureProvider<List<CategoryEntity>>((ref) async {
  final repository = ref.watch(categoryRepositoryProvider);
  return repository.getCategories();
});

final productsProvider = StreamProvider<List<ProductEntity>>((ref) {
  final repository = ref.watch(productRepositoryProvider);
  return repository.watchAllProducts(availableOnly: true);
});

final adminProductsStreamProvider = StreamProvider<List<ProductEntity>>((ref) {
  final repository = ref.watch(productRepositoryProvider);
  return repository.watchAllProducts(availableOnly: false);
});

final productsByCategoryProvider = StreamProvider.family<List<ProductEntity>, String>((ref, categoryId) {
  final repository = ref.watch(productRepositoryProvider);
  if (categoryId == 'all' || categoryId.isEmpty) {
    return repository.watchAllProducts(availableOnly: true);
  }
  return repository.watchAllProducts(availableOnly: true).map(
        (list) => list.where((p) => p.categoryId == categoryId).toList(),
      );
});
