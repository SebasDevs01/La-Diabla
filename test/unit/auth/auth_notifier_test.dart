// test/unit/auth/auth_notifier_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:la_diabla/domain/entities/user_entity.dart';

void main() {
  group('AuthState', () {
    test('crea un estado inicial no autenticado', () {
      const state = UserEntity(
        id: 'u1',
        name: 'Juan Perez',
        email: 'juan@example.com',
        role: UserRole.customer,
      );

      expect(state.id, 'u1');
      expect(state.isCustomer, isTrue);
      expect(state.isAdmin, isFalse);
    });
  });
}
