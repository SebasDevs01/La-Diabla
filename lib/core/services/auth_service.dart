// lib/core/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:logger/logger.dart';
import '../errors/app_exception.dart';

/// Servicio de autenticación — wrapper de Firebase Auth.
class AuthService {
  AuthService({
    FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ??
            GoogleSignIn(
              serverClientId:
                  '724540997267-n9v2et9nms53b549jdcnk41tmpecqlen.apps.googleusercontent.com',
            );

  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;
  final Logger _logger = Logger();

  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();
  User? get currentUser => _firebaseAuth.currentUser;

  static String _translateAuthError(String code, [String? defaultMsg]) {
    switch (code) {
      case 'user-not-found':
        return 'No existe ninguna cuenta con este correo. Regístrate para comenzar.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Correo o contraseña incorrectos. Verifica tus datos o usa "¿Olvidaste tu contraseña?".';
      case 'email-already-in-use':
        return 'Ya existe una cuenta con este correo electrónico. Inicia sesión directamente.';
      case 'invalid-email':
        return 'El formato del correo electrónico no es válido.';
      case 'weak-password':
        return 'La contraseña es muy débil. Debe tener al menos 6 caracteres.';
      case 'user-disabled':
        return 'Esta cuenta ha sido inhabilitada por el administrador.';
      case 'too-many-requests':
        return 'Demasiados intentos fallidos. Por favor, espera unos minutos antes de reintentar.';
      case 'network-request-failed':
        return 'Error de conexión. Verifica tu conexión a internet.';
      case 'popup-closed-by-user':
      case 'canceled':
      case 'cancelled':
        return 'Inicio de sesión cancelado.';
      default:
        return defaultMsg ?? 'Error de autenticación ($code)';
    }
  }

  Future<UserCredential> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw const AuthException('Login con Google cancelado por el usuario.');
      }

      final googleAuth = await googleUser.authentication;
      if (googleAuth.idToken == null && googleAuth.accessToken == null) {
        throw const AuthException(
            'Google no devolvió token de acceso. Verifica la huella SHA-1 en Firebase.',
            code: 'google-sha1-missing');
      }

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      return await _firebaseAuth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      _logger.e('Google sign-in Firebase error', error: e);
      throw AuthException(_translateAuthError(e.code, e.message), code: e.code);
    } on PlatformException catch (e) {
      _logger.e('Google sign-in platform error: ${e.code} - ${e.message}', error: e);
      if (e.code == 'sign_in_failed' ||
          e.message?.contains('10') == true ||
          e.message?.contains('12500') == true ||
          e.message?.contains('ApiException: 10') == true) {
        throw const AuthException(
          'Falta registrar la huella digital SHA-1 de esta firma en Firebase Console para permitir Google Sign-In en esta versión.',
          code: 'google-sha1-missing',
        );
      }
      if (e.code == 'network_error' || e.message?.contains('7') == true) {
        throw const AuthException(
          'Error de red al conectar con Google. Verifica tu conexión a internet.',
          code: 'network-error',
        );
      }
      throw AuthException(
        e.message ?? 'Error al iniciar sesión con Google (${e.code})',
        code: e.code,
      );
    } catch (e) {
      if (e is AuthException) rethrow;
      _logger.e('Unexpected Google sign-in error', error: e);
      throw AuthException('Error al iniciar sesión con Google: ${e.toString()}');
    }
  }

  Future<UserCredential> signInWithEmail(String email, String password) async {
    try {
      return await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      _logger.e('Email sign-in error', error: e);
      throw AuthException(_translateAuthError(e.code, e.message), code: e.code);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw const AuthException('Error inesperado al iniciar sesión con correo.');
    }
  }

  Future<UserCredential> signUpWithEmail(String email, String password) async {
    try {
      return await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      _logger.e('Email sign-up error', error: e);
      throw AuthException(_translateAuthError(e.code, e.message), code: e.code);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw const AuthException('Error inesperado al registrar cuenta.');
    }
  }

  Future<String> verifyPhoneNumber(String phoneNumber) async {
    final completer = _PhoneVerificationCompleter();

    await _firebaseAuth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (credential) {
        completer.completeAuto(credential);
      },
      verificationFailed: (e) {
        _logger.e('Phone verification failed', error: e);
        completer.completeError(
          AuthException(e.message ?? 'Error al verificar teléfono', code: e.code),
        );
      },
      codeSent: (verificationId, resendToken) {
        completer.completeCode(verificationId);
      },
      codeAutoRetrievalTimeout: (verificationId) {
        if (!completer.isComplete) {
          completer.completeCode(verificationId);
        }
      },
    );

    return completer.future;
  }

  Future<UserCredential> signInWithSmsCode({
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      return await _firebaseAuth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      _logger.e('SMS code sign-in error', error: e);
      throw AuthException(
        e.message ?? 'Código SMS incorrecto',
        code: e.code,
      );
    }
  }

  Future<void> signOut() async {
    await Future.wait([
      _firebaseAuth.signOut(),
      _googleSignIn.signOut(),
    ]);
  }

  Future<void> deleteAccount() async {
    try {
      await _firebaseAuth.currentUser?.delete();
    } on FirebaseAuthException catch (e) {
      throw AuthException(
        e.message ?? 'Error al eliminar cuenta',
        code: e.code,
      );
    }
  }
}

class _PhoneVerificationCompleter {
  final _completer = _FutureCompleter<String>();
  bool _completed = false;

  bool get isComplete => _completed;

  Future<String> get future => _completer.future;

  void completeCode(String verificationId) {
    if (!_completed) {
      _completed = true;
      _completer.complete(verificationId);
    }
  }

  void completeAuto(PhoneAuthCredential credential) {}

  void completeError(Object error) {
    if (!_completed) {
      _completed = true;
      _completer.completeError(error);
    }
  }
}

class _FutureCompleter<T> {
  T? _value;
  Object? _error;
  bool _completed = false;

  late final Future<T> future = Future(() async {
    while (!_completed) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    if (_error != null) throw _error!;
    return _value as T;
  });

  void complete(T value) {
    _value = value;
    _completed = true;
  }

  void completeError(Object error) {
    _error = error;
    _completed = true;
  }
}
