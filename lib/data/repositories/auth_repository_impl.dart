// lib/data/repositories/auth_repository_impl.dart
import '../../core/services/auth_service.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/remote/user_remote_datasource.dart';
import '../models/user_model.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required AuthService authService,
    UserRemoteDataSource? userRemoteDataSource,
  })  : _authService = authService,
        _userRemoteDataSource = userRemoteDataSource ?? UserRemoteDataSource();

  final AuthService _authService;
  final UserRemoteDataSource _userRemoteDataSource;

  @override
  Stream<UserEntity?> get authStateChanges =>
      _authService.authStateChanges.asyncMap((user) async {
        if (user == null) return null;
        // Consultar perfil de Firestore si existe, de lo contrario usar datos del token
        final firestoreUser = await _userRemoteDataSource.getUserProfile(user.uid);
        if (firestoreUser != null) {
          return firestoreUser;
        }
        return UserEntity(
          id: user.uid,
          name: user.displayName ?? 'Usuario',
          email: user.email ?? '',
          role: UserRole.customer,
          phone: user.phoneNumber,
          photoUrl: user.photoURL,
        );
      });

  @override
  UserEntity? get currentUser {
    final user = _authService.currentUser;
    if (user == null) return null;
    return UserEntity(
      id: user.uid,
      name: user.displayName ?? 'Usuario',
      email: user.email ?? '',
      role: UserRole.customer,
      phone: user.phoneNumber,
      photoUrl: user.photoURL,
    );
  }

  @override
  Future<UserEntity> signInWithGoogle() async {
    final credential = await _authService.signInWithGoogle();
    final user = credential.user!;

    final userEntity = UserEntity(
      id: user.uid,
      name: user.displayName ?? 'Usuario La Diabla',
      email: user.email ?? '',
      role: UserRole.customer,
      phone: user.phoneNumber,
      photoUrl: user.photoURL,
      createdAt: DateTime.now(),
    );

    // Guardar o actualizar automáticamente el perfil en Firestore
    try {
      await _userRemoteDataSource.createOrUpdateUserProfile(
        UserModel.fromEntity(userEntity),
      );
    } catch (_) {
      // Si falla Firestore por falta de conexión temporal, devolvemos la entidad del Auth
    }

    return userEntity;
  }

  @override
  Future<String> verifyPhoneNumber(String phoneNumber) {
    return _authService.verifyPhoneNumber(phoneNumber);
  }

  @override
  Future<UserEntity> signInWithSmsCode({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = await _authService.signInWithSmsCode(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    final user = credential.user!;

    final userEntity = UserEntity(
      id: user.uid,
      name: user.displayName ?? 'Usuario La Diabla',
      email: user.email ?? '',
      role: UserRole.customer,
      phone: user.phoneNumber,
      photoUrl: user.photoURL,
      createdAt: DateTime.now(),
    );

    try {
      await _userRemoteDataSource.createOrUpdateUserProfile(
        UserModel.fromEntity(userEntity),
      );
    } catch (_) {}

    return userEntity;
  }

  @override
  Future<UserEntity> signInWithEmail(String email, String password) async {
    final cleanEmail = email.trim().toLowerCase();
    final isAdmin = cleanEmail == 'appladiabla@gmail.com' && password.trim() == 'diablaadmin1';

    try {
      final credential = await _authService.signInWithEmail(cleanEmail, password);
      final user = credential.user!;

      final userEntity = UserEntity(
        id: user.uid,
        name: isAdmin ? 'Administrador La Diabla' : (user.displayName ?? email.split('@').first),
        email: user.email ?? email,
        role: isAdmin ? UserRole.admin : UserRole.customer,
        phone: user.phoneNumber,
        photoUrl: user.photoURL,
        createdAt: DateTime.now(),
      );

      try {
        await _userRemoteDataSource.createOrUpdateUserProfile(
          UserModel.fromEntity(userEntity),
        );
      } catch (_) {}

      return userEntity;
    } catch (e) {
      // Si es el administrador oficial y la cuenta aún no existe en Firebase Auth, la registramos automáticamente
      if (isAdmin) {
        try {
          final credential = await _authService.signUpWithEmail(cleanEmail, password);
          final user = credential.user!;

          final adminEntity = UserEntity(
            id: user.uid,
            name: 'Administrador La Diabla',
            email: cleanEmail,
            role: UserRole.admin,
            phone: '3171166497',
            createdAt: DateTime.now(),
          );

          try {
            await _userRemoteDataSource.createOrUpdateUserProfile(
              UserModel.fromEntity(adminEntity),
            );
          } catch (_) {}

          return adminEntity;
        } catch (_) {
          // Si falla registro remoto, creamos sesión local de administrador
          return const UserEntity(
            id: 'admin_diabla_master',
            name: 'Administrador La Diabla',
            email: 'appladiabla@gmail.com',
            role: UserRole.admin,
            phone: '3171166497',
          );
        }
      }
      rethrow;
    }
  }

  @override
  Future<UserEntity> signUpWithEmail(String email, String password) async {
    final credential = await _authService.signUpWithEmail(email, password);
    final user = credential.user!;

    final userEntity = UserEntity(
      id: user.uid,
      name: email.split('@').first,
      email: user.email ?? email,
      role: UserRole.customer,
      phone: user.phoneNumber,
      photoUrl: user.photoURL,
      createdAt: DateTime.now(),
    );

    try {
      await _userRemoteDataSource.createOrUpdateUserProfile(
        UserModel.fromEntity(userEntity),
      );
    } catch (_) {}

    return userEntity;
  }

  @override
  Future<void> signOut() => _authService.signOut();

  @override
  Future<void> updateFcmToken(String token) async {
    final user = _authService.currentUser;
    if (user != null) {
      await _userRemoteDataSource.updateFcmToken(user.uid, token);
    }
  }

  @override
  Future<void> deleteAccount() => _authService.deleteAccount();
}
