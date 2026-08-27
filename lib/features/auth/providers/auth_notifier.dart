// lib/features/auth/providers/auth_notifier.dart
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../domain/entities/user_entity.dart';
import 'auth_provider.dart';

/// Estado de la autenticacion.
class AuthState {
  const AuthState({
    this.user,
    this.isLoading = false,
    this.errorMessage,
    this.verificationId,
  });

  final UserEntity? user;
  final bool isLoading;
  final String? errorMessage;
  final String? verificationId;

  bool get isAuthenticated => user != null;

  AuthState copyWith({
    UserEntity? user,
    bool? isLoading,
    String? errorMessage,
    String? verificationId,
    bool clearError = false,
    bool clearUser = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      verificationId: verificationId ?? this.verificationId,
    );
  }
}

/// Controller de estado de autenticacion con persistencia total permanente (Riverpod StateNotifier).
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._ref) : super(const AuthState()) {
    _init();
  }

  final Ref _ref;
  StreamSubscription<UserEntity?>? _authSubscription;

  Future<void> _saveUserSession(UserEntity user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', true);
      await prefs.setString('saved_user_id', user.id);
      await prefs.setString('saved_user_name', user.name);
      await prefs.setString('saved_user_email', user.email);
      if (user.phone != null) {
        await prefs.setString('saved_user_phone', user.phone!);
      }
      await prefs.setString('saved_user_role', user.role.name);
      if (user.photoUrl != null) {
        await prefs.setString('saved_user_photo', user.photoUrl!);
      }
      if (user.guestAddress != null) {
        await prefs.setString('guest_address', user.guestAddress!);
      }
    } catch (_) {}
  }

  Future<void> _clearUserSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', false);
      await prefs.setBool('is_guest_user', false);
      await prefs.setBool('is_delivery_mode', false);
      await prefs.remove('saved_user_id');
      await prefs.remove('saved_user_name');
      await prefs.remove('saved_user_email');
      await prefs.remove('saved_user_phone');
      await prefs.remove('saved_user_role');
      await prefs.remove('saved_user_photo');
      await prefs.remove('guest_name');
      await prefs.remove('guest_phone');
      await prefs.remove('guest_address');
    } catch (_) {}
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final isGuest = prefs.getBool('is_guest_user') ?? false;
    final isLoggedIn = prefs.getBool('is_logged_in') ?? false;

    if (isGuest) {
      final guestName = prefs.getString('guest_name') ?? 'Invitado Diabla';
      final guestPhone = prefs.getString('guest_phone') ?? '3000000000';
      final guestAddress = prefs.getString('guest_address') ?? 'Direccion de entrega';

      final guestUser = UserEntity(
        id: 'guest_${guestPhone.replaceAll(' ', '')}',
        name: guestName,
        email: 'invitado@ladiabla.app',
        role: UserRole.customer,
        phone: guestPhone,
        isGuest: true,
        guestAddress: guestAddress,
        referralCode: 'DIABLA-INV${guestPhone.length >= 4 ? guestPhone.substring(guestPhone.length - 4) : "7824"}',
      );
      state = state.copyWith(user: guestUser, isLoading: false);
      return;
    }

    if (isLoggedIn) {
      final savedId = prefs.getString('saved_user_id') ?? 'user_cached';
      final savedName = prefs.getString('saved_user_name') ?? 'Usuario La Diabla';
      final savedEmail = prefs.getString('saved_user_email') ?? '';
      final savedPhone = prefs.getString('saved_user_phone');
      final savedPhoto = prefs.getString('saved_user_photo');
      final savedRole = prefs.getString('saved_user_role') == 'driver' ? UserRole.driver : UserRole.customer;

      final cachedUser = UserEntity(
        id: savedId,
        name: savedName,
        email: savedEmail,
        role: savedRole,
        phone: savedPhone,
        photoUrl: savedPhoto,
      );
      state = state.copyWith(user: cachedUser, isLoading: false);
    }

    final repo = _ref.read(authRepositoryProvider);
    final initialUser = repo.currentUser;
    if (initialUser != null) {
      state = state.copyWith(user: initialUser, isLoading: false);
      await _saveUserSession(initialUser);
    }

    _authSubscription = repo.authStateChanges.listen((user) {
      if (user != null) {
        state = state.copyWith(user: user, isLoading: false);
        _saveUserSession(user);
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  /// Inicia sesion como Invitado con Nombre, Telefono y Direccion.
  Future<bool> signInAsGuest({
    required String name,
    required String phone,
    required String address,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_guest_user', true);
      await prefs.setBool('is_logged_in', true);
      await prefs.setString('guest_name', name);
      await prefs.setString('guest_phone', phone);
      await prefs.setString('guest_address', address);
      await prefs.setString('user_registered_name', name);

      final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
      final referral = 'DIABLA-${cleanPhone.length >= 4 ? cleanPhone.substring(cleanPhone.length - 4) : "INV1"}';

      try {
        if (FirebaseAuth.instance.currentUser == null) {
          await FirebaseAuth.instance.signInAnonymously();
        }
      } catch (_) {}

      final guestUid = FirebaseAuth.instance.currentUser?.uid ?? 'guest_$cleanPhone';

      final guestUser = UserEntity(
        id: guestUid,
        name: name,
        email: '$cleanPhone@invitado.ladiabla.app',
        role: UserRole.customer,
        phone: phone,
        isGuest: true,
        guestAddress: address,
        referralCode: referral,
        createdAt: DateTime.now(),
      );

      state = state.copyWith(user: guestUser, isLoading: false);
      await _saveUserSession(guestUser);
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Error al iniciar como invitado: $e',
      );
      return false;
    }
  }

  /// Inicia sesion con Apple Sign In.
  Future<bool> signInWithApple() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final appleProvider = OAuthProvider('apple.com');
      appleProvider.addScope('email');
      appleProvider.addScope('name');

      final userCredential = await FirebaseAuth.instance.signInWithProvider(appleProvider);
      final fbUser = userCredential.user;

      if (fbUser != null) {
        final user = UserEntity(
          id: fbUser.uid,
          name: fbUser.displayName ?? 'Usuario Apple',
          email: fbUser.email ?? 'apple_user@icloud.com',
          role: UserRole.customer,
          photoUrl: fbUser.photoURL,
          phone: fbUser.phoneNumber,
          referralCode: 'DIABLA-${fbUser.uid.substring(0, 5).toUpperCase()}',
        );
        state = state.copyWith(user: user, isLoading: false);
        await _saveUserSession(user);
        return true;
      }
      state = state.copyWith(isLoading: false, errorMessage: 'No se completo el acceso con Apple');
      return false;
    } catch (e) {
      final err = e.toString().replaceAll('Exception: ', '').replaceAll('FirebaseAuthException: ', '');
      state = state.copyWith(
        isLoading: false,
        errorMessage: err.contains('plugin') || err.contains('cancelled')
            ? 'Inicio con Apple cancelado o no configurado en este dispositivo.'
            : 'Error con Apple: $err',
      );
      return false;
    }
  }

  /// Inicia sesion con Google.
  Future<bool> signInWithGoogle() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final repo = _ref.read(authRepositoryProvider);
      final user = await repo.signInWithGoogle();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_guest_user', false);
      await prefs.setBool('is_logged_in', true);
      state = state.copyWith(user: user, isLoading: false);
      await _saveUserSession(user);
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceAll('Exception: ', '').replaceAll('AuthException: ', ''),
      );
      return false;
    }
  }

  /// Verifica el numero de telefono y envia codigo SMS.
  Future<bool> verifyPhoneNumber(String phoneNumber) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final repo = _ref.read(authRepositoryProvider);
      final verId = await repo.verifyPhoneNumber(phoneNumber);
      state = state.copyWith(
        isLoading: false,
        verificationId: verId,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
      return false;
    }
  }

  /// Completa el inicio de sesion con el codigo SMS.
  Future<bool> signInWithSmsCode(String smsCode) async {
    final verId = state.verificationId;
    if (verId == null) {
      state = state.copyWith(errorMessage: 'No se encontro el ID de verificacion SMS');
      return false;
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final repo = _ref.read(authRepositoryProvider);
      final user = await repo.signInWithSmsCode(
        verificationId: verId,
        smsCode: smsCode,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_guest_user', false);
      await prefs.setBool('is_logged_in', true);
      state = state.copyWith(user: user, isLoading: false);
      await _saveUserSession(user);
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
      return false;
    }
  }

  /// Inicia sesion con correo y contrasena.
  Future<bool> signInWithEmail(String email, String password) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final repo = _ref.read(authRepositoryProvider);
      final user = await repo.signInWithEmail(email, password);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_guest_user', false);
      await prefs.setBool('is_logged_in', true);
      state = state.copyWith(user: user, isLoading: false);
      await _saveUserSession(user);
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceAll('Exception: ', '').replaceAll('AuthException: ', ''),
      );
      return false;
    }
  }

  /// Registra una nueva cuenta con correo y contrasena.
  Future<bool> signUpWithEmail(String email, String password) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final repo = _ref.read(authRepositoryProvider);
      final user = await repo.signUpWithEmail(email, password);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_guest_user', false);
      await prefs.setBool('is_logged_in', true);
      state = state.copyWith(user: user, isLoading: false);
      await _saveUserSession(user);
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceAll('Exception: ', '').replaceAll('AuthException: ', ''),
      );
      return false;
    }
  }

  /// Cierra sesion manualmente.
  Future<void> signOut() async {
    state = state.copyWith(isLoading: true);
    try {
      await _clearUserSession();
      final repo = _ref.read(authRepositoryProvider);
      await repo.signOut();
      state = const AuthState();
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Elimina permanentemente la cuenta del usuario (Requisito estricto de Google Play Store).
  Future<bool> deleteAccount() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final fbUser = FirebaseAuth.instance.currentUser;
      if (fbUser != null) {
        try {
          await fbUser.delete();
        } catch (_) {}
      }
      await _clearUserSession();
      final repo = _ref.read(authRepositoryProvider);
      try {
        await repo.signOut();
      } catch (_) {}
      state = const AuthState();
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Error al eliminar cuenta: $e',
      );
      return false;
    }
  }
  /// Actualiza los datos del perfil del usuario y los persiste.
  Future<bool> updateUserProfile({
    String? name,
    String? email,
    String? phone,
    String? photoUrl,
  }) async {
    if (state.user == null) return false;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final updatedUser = state.user!.copyWith(
        name: name ?? state.user!.name,
        email: email ?? state.user!.email,
        phone: phone ?? state.user!.phone,
        photoUrl: photoUrl ?? state.user!.photoUrl,
        updatedAt: DateTime.now(),
      );

      state = state.copyWith(user: updatedUser, isLoading: false);
      await _saveUserSession(updatedUser);

      // Si es un usuario de Firebase, actualizar en FirebaseAuth
      try {
        final fbUser = FirebaseAuth.instance.currentUser;
        if (fbUser != null) {
          if (name != null && name.isNotEmpty) await fbUser.updateDisplayName(name);
          if (photoUrl != null && photoUrl.isNotEmpty) await fbUser.updatePhotoURL(photoUrl);
        }
      } catch (_) {}
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Error al actualizar perfil: $e',
      );
      return false;
    }
  }

  void updateUser(UserEntity updatedUser) {
    state = state.copyWith(user: updatedUser);
    _saveUserSession(updatedUser);
  }
}

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref);
});
