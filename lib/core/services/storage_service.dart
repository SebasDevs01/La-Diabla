// lib/core/services/storage_service.dart
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:logger/logger.dart';
import '../errors/app_exception.dart';

/// Servicio de Firebase Storage para subir/bajar archivos.
class StorageService {
  StorageService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;
  final Logger _logger = Logger();

  // ─── Rutas de Storage ─────────────────────────────────────────────────────────
  static const String _usersPath = 'users';
  static const String _productsPath = 'products';

  /// Sube la foto de perfil de un usuario.
  Future<String> uploadUserPhoto({
    required String userId,
    required File file,
  }) async {
    return _uploadFile(
      path: '$_usersPath/$userId/profile.jpg',
      file: file,
    );
  }

  /// Sube la imagen de un producto.
  Future<String> uploadProductImage({
    required String productId,
    required File file,
  }) async {
    return _uploadFile(
      path: '$_productsPath/$productId/main.jpg',
      file: file,
    );
  }

  /// Elimina un archivo del storage dado su URL de descarga.
  Future<void> deleteFileByUrl(String downloadUrl) async {
    try {
      final ref = _storage.refFromURL(downloadUrl);
      await ref.delete();
    } catch (e) {
      _logger.w('No se pudo eliminar el archivo: $downloadUrl', error: e);
    }
  }

  // ─── Privado ──────────────────────────────────────────────────────────────────
  Future<String> _uploadFile({
    required String path,
    required File file,
  }) async {
    try {
      final ref = _storage.ref().child(path);
      final uploadTask = await ref.putFile(file);
      final downloadUrl = await uploadTask.ref.getDownloadURL();
      _logger.d('Archivo subido: $downloadUrl');
      return downloadUrl;
    } on FirebaseException catch (e) {
      _logger.e('Error subiendo archivo', error: e);
      throw DataException(
        'Error al subir archivo: ${e.message}',
        code: e.code,
      );
    }
  }
}
