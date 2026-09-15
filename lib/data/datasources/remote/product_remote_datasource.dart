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

  /// Stream en tiempo real de todos los productos (opcionalmente filtrado por disponibilidad).
  Stream<List<ProductModel>> watchAllProducts({bool availableOnly = true}) {
    Query<Map<String, dynamic>> query = _productsRef;
    if (availableOnly) {
      query = query.where('available', isEqualTo: true);
    }
    return query.snapshots().map((snapshot) => snapshot.docs
        .map((doc) => ProductModel.fromMap(doc.data(), id: doc.id))
        .toList());
  }

  /// Crea un nuevo producto en Firestore.
  Future<void> createProduct(ProductModel product) async {
    try {
      final docRef = product.id.isNotEmpty ? _productsRef.doc(product.id) : _productsRef.doc();
      final data = product.toMap();
      data['id'] = docRef.id;
      data['createdAt'] = FieldValue.serverTimestamp();
      data['updatedAt'] = FieldValue.serverTimestamp();
      await docRef.set(data, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      _logger.e('Error creando producto en Firestore', error: e);
      throw DataException('Error al crear producto: ${e.message}', code: e.code);
    }
  }

  /// Actualiza un producto existente en Firestore.
  Future<void> updateProduct(ProductModel product) async {
    try {
      final data = product.toMap();
      data['updatedAt'] = FieldValue.serverTimestamp();
      await _productsRef.doc(product.id).set(data, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      _logger.e('Error actualizando producto en Firestore', error: e);
      throw DataException('Error al actualizar producto: ${e.message}', code: e.code);
    }
  }

  /// Elimina un producto de Firestore.
  Future<void> deleteProduct(String productId) async {
    try {
      await _productsRef.doc(productId).delete();
    } on FirebaseException catch (e) {
      _logger.e('Error eliminando producto de Firestore', error: e);
      throw DataException('Error al eliminar producto: ${e.message}', code: e.code);
    }
  }

  /// Cambia el estado de disponibilidad de un producto.
  Future<void> toggleProductAvailability(String productId, bool available) async {
    try {
      await _productsRef.doc(productId).update({
        'available': available,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      _logger.e('Error cambiando disponibilidad de producto', error: e);
      throw DataException('Error al cambiar disponibilidad: ${e.message}', code: e.code);
    }
  }

  /// Siembra el catálogo inicial en Firestore en lote.
  Future<int> seedInitialCatalog(List<ProductModel> initialProducts) async {
    try {
      final batch = _firestore.batch();
      int count = 0;
      for (final prod in initialProducts) {
        final docRef = _productsRef.doc(prod.id);
        final data = prod.toMap();
        data['createdAt'] = FieldValue.serverTimestamp();
        data['updatedAt'] = FieldValue.serverTimestamp();
        batch.set(docRef, data, SetOptions(merge: true));
        count++;
      }
      await batch.commit();
      return count;
    } on FirebaseException catch (e) {
      _logger.e('Error sembrando catálogo en Firestore', error: e);
      throw DataException('Error al sembrar catálogo: ${e.message}', code: e.code);
    }
  }
}
