// lib/features/auth/providers/auth_notifier.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/notification_service.dart';
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
      if (user.isGuest) {
        // Invitados NUNCA deben quedar guardados como usuarios con sesión activa
        await prefs.setBool('is_logged_in', false);
        await prefs.setBool('is_guest_user', true);
        return;
      }
      await prefs.setBool('is_logged_in', true);
      await prefs.setBool('is_guest_user', false);
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
      // Sincronizar Token FCM en Firestore en segundo plano (con timeout para jamás bloquear)
      NotificationService()
          .syncUserFcmToken(user.id, role: user.role.name)
          .timeout(const Duration(seconds: 4), onTimeout: () {})
          .ignore();
    } catch (_) {}
  }

  Future<void> _clearUserSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString('saved_user_id');
      if (savedId != null && savedId.isNotEmpty) {
        NotificationService().clearFcmToken(savedId).ignore();
      }
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
      await prefs.remove('saved_addresses');
    } catch (_) {}
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final isGuest = prefs.getBool('is_guest_user') ?? false;
    final savedId = prefs.getString('saved_user_id');
    final savedEmail = prefs.getString('saved_user_email') ?? '';
    final isGuestId = savedId != null && (savedId.startsWith('guest_') || savedId == 'guest');
    final isGuestEmail = savedEmail.contains('@invitado.ladiabla.app') || savedEmail.contains('guest');

    // NUNCA restaurar sesiones de invitados al iniciar la app.
    // Si hay residuos de invitado en SharedPreferences, se limpian por completo.
    if (isGuest || isGuestId || isGuestEmail) {
      await _clearUserSession();
      try {
        final fbUser = FirebaseAuth.instance.currentUser;
        if (fbUser != null && fbUser.isAnonymous) {
          await FirebaseAuth.instance.signOut();
        }
      } catch (_) {}
      state = state.copyWith(user: null, isLoading: false);
      return;
    }

    final isLoggedIn = prefs.getBool('is_logged_in') ?? false;
    final savedRole = prefs.getString('saved_user_role');
    final savedName = prefs.getString('saved_user_name');
    final savedPhone = prefs.getString('saved_user_phone');
    final savedPhoto = prefs.getString('saved_user_photo');

    // ── 1. RESTAURAR SESIÓN DESDE SHAREDPREFERENCES INMEDIATAMENTE (Solo usuarios reales)
    if (isLoggedIn && savedId != null && savedId.isNotEmpty) {
      final effectiveRole = savedRole == 'driver' || savedEmail == 'repartidor@ladiabla.app'
          ? UserRole.driver
          : (savedEmail == 'admin@ladiabla.app' || savedEmail == 'appladiabla@gmail.com' || savedRole == 'admin'
              ? UserRole.admin
              : UserRole.customer);

      final userEntity = UserEntity(
        id: savedId,
        name: (savedName != null && savedName.isNotEmpty) ? savedName : 'Usuario La Diabla',
        email: savedEmail,
        role: effectiveRole,
        phone: savedPhone,
        photoUrl: savedPhoto,
        createdAt: DateTime.now(),
      );
      state = state.copyWith(user: userEntity, isLoading: false);
      NotificationService().syncUserFcmToken(savedId, role: effectiveRole.name).ignore();
    } else {
      state = state.copyWith(user: null, isLoading: false);
    }

    // ── 2. ESCUCHAR FIREBASE AUTH PARA ACTUALIZACIONES EN TIEMPO REAL
    final repo = _ref.read(authRepositoryProvider);
    _authSubscription = repo.authStateChanges.listen((user) {
      if (user != null && !user.isGuest) {
        // Solo restaurar estado para usuarios reales (no invitados/anónimos)
        final fbUser = FirebaseAuth.instance.currentUser;
        if (fbUser != null && !fbUser.isAnonymous) {
          state = state.copyWith(user: user, isLoading: false);
          _saveUserSession(user).ignore();
        }
      } else {
        final fbUser = FirebaseAuth.instance.currentUser;
        if (fbUser == null) {
          SharedPreferences.getInstance().then((p) {
            final logged = p.getBool('is_logged_in') ?? false;
            final isGuest = p.getBool('is_guest_user') ?? false;
            if (!logged && !isGuest) {
              state = state.copyWith(user: null, isLoading: false, clearUser: true);
              _clearUserSession().ignore();
            }
          });
        }
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
      await prefs.setBool('is_logged_in', false);
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
      _saveUserSession(guestUser).ignore();
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Error al iniciar como invitado: $e',
      );
      return false;
    }
  }


  /// Inicia sesion con Google.
  Future<bool> signInWithGoogle({bool isDeliveryMode = false}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final repo = _ref.read(authRepositoryProvider);
      var user = await repo.signInWithGoogle();
      if (isDeliveryMode && user.role != UserRole.driver) {
        user = user.copyWith(role: UserRole.driver);
        FirebaseFirestore.instance
            .collection('users')
            .doc(user.id)
            .set({'role': 'driver'}, SetOptions(merge: true))
            .ignore();
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_guest_user', false);
      await prefs.setBool('is_logged_in', true);
      await prefs.setBool('is_delivery_mode', isDeliveryMode);
      state = state.copyWith(user: user, isLoading: false);
      _saveUserSession(user).ignore();
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
      _saveUserSession(user).ignore();
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
  Future<bool> signInWithEmail(String email, String password, {bool isDeliveryMode = false}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final repo = _ref.read(authRepositoryProvider);
      var user = await repo.signInWithEmail(email, password);
      if (isDeliveryMode && user.role != UserRole.driver) {
        user = user.copyWith(role: UserRole.driver);
        FirebaseFirestore.instance
            .collection('users')
            .doc(user.id)
            .set({'role': 'driver'}, SetOptions(merge: true))
            .ignore();
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_guest_user', false);
      await prefs.setBool('is_logged_in', true);
      await prefs.setBool('is_delivery_mode', isDeliveryMode);
      state = state.copyWith(user: user, isLoading: false);
      _saveUserSession(user).ignore();
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
  Future<bool> signUpWithEmail(String email, String password, {bool isDeliveryMode = false}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final repo = _ref.read(authRepositoryProvider);
      var user = await repo.signUpWithEmail(email, password);
      if (isDeliveryMode && user.role != UserRole.driver) {
        user = user.copyWith(role: UserRole.driver);
        FirebaseFirestore.instance
            .collection('users')
            .doc(user.id)
            .set({'role': 'driver'}, SetOptions(merge: true))
            .ignore();
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_guest_user', false);
      await prefs.setBool('is_logged_in', true);
      await prefs.setBool('is_delivery_mode', isDeliveryMode);
      state = state.copyWith(user: user, isLoading: false);
      _saveUserSession(user).ignore();
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
      // Cerrar también sesión anónima de Firebase para que no quede residuo
      final fbUser = FirebaseAuth.instance.currentUser;
      if (fbUser != null && fbUser.isAnonymous) {
        await FirebaseAuth.instance.signOut();
      }
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
        final uid = fbUser.uid;
        // 1. Limpiar datos personales y direcciones en Firestore
        try {
          final addrSnap = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('addresses')
              .get()
              .timeout(const Duration(seconds: 4));
          for (final doc in addrSnap.docs) {
            await doc.reference.delete();
          }
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .delete()
              .timeout(const Duration(seconds: 4));
        } catch (_) {}

        // 2. Eliminar de Firebase Auth
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
