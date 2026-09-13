import 'dart:convert';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:logger/logger.dart';
import '../errors/app_exception.dart';

/// Servicio de Firebase Storage para subir/bajar archivos con fallback a Base64.
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

  /// Sube la foto de prueba de entrega de un pedido.
  Future<String> uploadDeliveryProof({
    required String orderId,
    required File file,
  }) async {
    return _uploadFile(
      path: 'orders/$orderId/delivery_proof.jpg',
      file: file,
    );
  }

  /// Elimina un archivo del storage dado su URL de descarga.
  Future<void> deleteFileByUrl(String downloadUrl) async {
    try {
      if (downloadUrl.startsWith('data:')) return;
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
      final uploadTask = await ref.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final downloadUrl = await uploadTask.ref.getDownloadURL();
      _logger.d('Archivo subido a Firebase Storage: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      _logger.w('Firebase Storage no disponible ($e). Usando fallback local Base64.');
      try {
        final bytes = await file.readAsBytes();
        final base64Str = base64Encode(bytes);
        return 'data:image/jpeg;base64,$base64Str';
      } catch (readErr) {
        _logger.e('Error leyendo archivo para Base64', error: readErr);
        throw DataException('Error al procesar archivo: $readErr');
      }
    }
  }
}
