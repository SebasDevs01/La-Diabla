// lib/core/errors/failure.dart
import 'package:equatable/equatable.dart';

/// Representa un fallo tipado para el dominio.
/// Permite que los use cases devuelvan errores sin exponer excepciones.
sealed class Failure extends Equatable {
  const Failure(this.message, {this.code});

  final String message;
  final String? code;

  @override
  List<Object?> get props => [message, code];

  @override
  String toString() => '$runtimeType(code: $code, message: $message)';
}

final class AuthFailure extends Failure {
  const AuthFailure(super.message, {super.code});
}

final class NetworkFailure extends Failure {
  const NetworkFailure(super.message, {super.code});
}

final class DataFailure extends Failure {
  const DataFailure(super.message, {super.code});
}

final class ValidationFailure extends Failure {
  const ValidationFailure(super.message, {super.code});
}

final class PermissionFailure extends Failure {
  const PermissionFailure(super.message, {super.code});
}

final class PaymentFailure extends Failure {
  const PaymentFailure(super.message, {super.code});
}

final class LocationFailure extends Failure {
  const LocationFailure(super.message, {super.code});
}

final class NotFoundFailure extends Failure {
  const NotFoundFailure(super.message, {super.code});
}

final class ServerFailure extends Failure {
  const ServerFailure(super.message, {super.code});
}

final class UnexpectedFailure extends Failure {
  const UnexpectedFailure(super.message, {super.code});
}
