// lib/domain/repositories/auth_repository.dart
import '../entities/user_entity.dart';

/// Interfaz del repositorio de autenticación.
/// Define el contrato que cualquier implementación debe cumplir.
/// La UI y los use cases solo dependen de esta interfaz, no de Firebase.
abstract interface class AuthRepository {
  /// Stream del estado de autenticación actual.
  Stream<UserEntity?> get authStateChanges;

  /// Retorna el usuario actualmente autenticado, o null si no hay sesión.
  UserEntity? get currentUser;

  /// Inicia sesión con Google.
  Future<UserEntity> signInWithGoogle();

  /// Verifica el número de teléfono y envía el código SMS.
  Future<String> verifyPhoneNumber(String phoneNumber);

  /// Completa el login con el código SMS recibido.
  Future<UserEntity> signInWithSmsCode({
    required String verificationId,
    required String smsCode,
  });

  /// Inicia sesión con correo y contraseña.
  Future<UserEntity> signInWithEmail(String email, String password);

  /// Registra una nueva cuenta con correo y contraseña.
  Future<UserEntity> signUpWithEmail(String email, String password);

  /// Cierra la sesión del usuario actual.
  Future<void> signOut();

  /// Actualiza el FCM token del usuario en Firestore.
  Future<void> updateFcmToken(String token);

  /// Elimina la cuenta del usuario actual.
  Future<void> deleteAccount();
}
