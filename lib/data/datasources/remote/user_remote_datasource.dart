// lib/data/datasources/remote/user_remote_datasource.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import '../../../../core/constants/firestore_constants.dart';
import '../../../../core/errors/app_exception.dart';
import '../../models/user_model.dart';

class UserRemoteDataSource {
  UserRemoteDataSource({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final Logger _logger = Logger();

  CollectionReference<Map<String, dynamic>> get _usersRef =>
      _firestore.collection(FirestoreConstants.usersCollection);

  /// Obtiene el perfil de un usuario por su ID de Firebase Auth.
  Future<UserModel?> getUserProfile(String userId) async {
    try {
      final doc = await _usersRef.doc(userId).get().timeout(const Duration(seconds: 3));
      if (!doc.exists || doc.data() == null) {
        return null;
      }
      return UserModel.fromMap(doc.data()!, id: doc.id);
    } on FirebaseException catch (e) {
      _logger.e('Error al obtener perfil de usuario: $userId', error: e);
      throw DataException('Error al consultar perfil de usuario', code: e.code);
    } catch (e) {
      return null;
    }
  }

  /// Crea o actualiza el documento de perfil de un usuario en Firestore.
  Future<void> createOrUpdateUserProfile(UserModel user) async {
    try {
      final docRef = _usersRef.doc(user.id);
      final doc = await docRef.get().timeout(const Duration(seconds: 3));

      if (!doc.exists) {
        // Nuevo usuario -> guardar documento completo
        await docRef.set(user.toMap());
        _logger.d('Perfil de usuario creado en Firestore: ${user.id}');
      } else {
        // Usuario existente -> actualizar campos modificados y timestamp.
        // El nombre solo se sobreescribe si es un nombre real (no un placeholder genérico).
        const namePlaceholders = ['Usuario La Diabla', 'Repartidor La Diabla', ''];
        final updateData = <String, dynamic>{
          'email': user.email,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        };
        if (user.name.isNotEmpty && !namePlaceholders.contains(user.name)) {
          updateData['name'] = user.name;
        }
        if (user.phone != null && user.phone!.isNotEmpty) updateData['phone'] = user.phone;
        if (user.photoUrl != null) updateData['photoUrl'] = user.photoUrl;
        if (user.fcmToken != null) updateData['fcmToken'] = user.fcmToken;

        await docRef.update(updateData);
        _logger.d('Perfil de usuario actualizado en Firestore: ${user.id}');
      }
    } on FirebaseException catch (e) {
      _logger.e('Error al guardar perfil de usuario: ${user.id}', error: e);
      throw DataException('Error al guardar datos de usuario', code: e.code);
    }
  }

  /// Actualiza el FCM token del usuario.
  Future<void> updateFcmToken(String userId, String token) async {
    try {
      await _usersRef.doc(userId).update({
        'fcmToken': token,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      _logger.w('No se pudo actualizar FCM token para $userId', error: e);
    }
  }
}
