// lib/domain/usecases/auth/sign_out_usecase.dart
import '../../repositories/auth_repository.dart';

/// Use case para cerrar sesión.
class SignOutUseCase {
  const SignOutUseCase(this._authRepository);

  final AuthRepository _authRepository;

  Future<void> call() => _authRepository.signOut();
}
