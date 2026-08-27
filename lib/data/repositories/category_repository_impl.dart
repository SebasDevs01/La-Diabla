// lib/data/repositories/category_repository_impl.dart
import '../../domain/entities/category_entity.dart';
import '../../domain/repositories/category_repository.dart';
import '../../mock/mock_categories.dart';

class CategoryRepositoryImpl implements CategoryRepository {
  final List<CategoryEntity> _categories = List.from(mockCategories);

  @override
  Future<List<CategoryEntity>> getCategories() async {
    await Future.delayed(const Duration(milliseconds: 200));
    final result = _categories.where((c) => c.available).toList();
    result.sort((a, b) => a.order.compareTo(b.order));
    return result;
  }

  @override
  Stream<List<CategoryEntity>> watchCategories() async* {
    yield await getCategories();
  }
}
