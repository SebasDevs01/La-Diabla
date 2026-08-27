// lib/core/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:logger/logger.dart';
import '../errors/app_exception.dart';

/// Servicio de autenticación — wrapper de Firebase Auth.
class AuthService {
  AuthService({
    FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn();

  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;
  final Logger _logger = Logger();

  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();
  User? get currentUser => _firebaseAuth.currentUser;

  Future<UserCredential> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw const AuthException('Login con Google cancelado por el usuario.');
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      return await _firebaseAuth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      _logger.e('Google sign-in error', error: e);
      throw AuthException(e.message ?? 'Error de autenticación', code: e.code);
    } catch (e) {
      if (e is AuthException) rethrow;
      _logger.e('Unexpected Google sign-in error', error: e);
      throw const AuthException('Error inesperado al iniciar sesión con Google.');
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
      throw AuthException(e.message ?? 'Error de autenticación por correo', code: e.code);
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
      throw AuthException(e.message ?? 'Error al registrar cuenta', code: e.code);
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
