// lib/data/datasources/remote/product_remote_datasource.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import '../../../../core/constants/firestore_constants.dart';
import '../../../../core/errors/app_exception.dart';
import '../../models/category_model.dart';
import '../../models/product_model.dart';

class ProductRemoteDataSource {
  ProductRemoteDataSource({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final Logger _logger = Logger();

  CollectionReference<Map<String, dynamic>> get _productsRef =>
      _firestore.collection(FirestoreConstants.productsCollection);

  CollectionReference<Map<String, dynamic>> get _categoriesRef =>
      _firestore.collection(FirestoreConstants.categoriesCollection);

  /// Obtiene la lista de productos disponibles en Firestore.
  Future<List<ProductModel>> getProducts() async {
    try {
      final snapshot = await _productsRef.where('available', isEqualTo: true).get();
      return snapshot.docs
          .map((doc) => ProductModel.fromMap(doc.data(), id: doc.id))
          .toList();
    } on FirebaseException catch (e) {
      _logger.e('Error obteniendo productos de Firestore', error: e);
      throw DataException('Error al consultar catálogo de productos', code: e.code);
    } catch (e) {
      _logger.w('Firestore no disponible o vacío: $e');
      return [];
    }
  }

  /// Obtiene la lista de categorías disponibles ordenadas.
  Future<List<CategoryModel>> getCategories() async {
    try {
      final snapshot = await _categoriesRef
          .where('available', isEqualTo: true)
          .orderBy('order')
          .get();
      return snapshot.docs
          .map((doc) => CategoryModel.fromMap(doc.data(), id: doc.id))
          .toList();
    } on FirebaseException catch (e) {
      _logger.e('Error obteniendo categorías de Firestore', error: e);
      throw DataException('Error al consultar categorías', code: e.code);
    } catch (e) {
      _logger.w('Firestore no disponible para categorías: $e');
      return [];
    }
  }

  /// Stream en tiempo real de productos por categoría.
  Stream<List<ProductModel>> watchProductsByCategory(String categoryId) {
    return _productsRef
        .where('categoryId', isEqualTo: categoryId)
        .where('available', isEqualTo: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ProductModel.fromMap(doc.data(), id: doc.id))
            .toList());
  }
}
