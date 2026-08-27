// lib/core/errors/app_exception.dart

/// Excepción base de la aplicación.
/// Todas las excepciones de negocio deben extender de esta clase.
sealed class AppException implements Exception {
  const AppException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'AppException(code: $code, message: $message)';
}

/// Error de autenticación (login, registro, sesión expirada).
final class AuthException extends AppException {
  const AuthException(super.message, {super.code});
}

/// Error de red o comunicación con el servidor.
final class NetworkException extends AppException {
  const NetworkException(super.message, {super.code});
}

/// Error al acceder a datos locales o remotos.
final class DataException extends AppException {
  const DataException(super.message, {super.code});
}

/// Error de validación de datos del usuario.
final class ValidationException extends AppException {
  const ValidationException(super.message, {super.code});
}

/// Error de permisos (ubicación, notificaciones, etc.).
final class PermissionException extends AppException {
  const PermissionException(super.message, {super.code});
}

/// Error al procesar el pago.
final class PaymentException extends AppException {
  const PaymentException(super.message, {super.code});
}

/// Error de ubicación o Google Maps.
final class LocationException extends AppException {
  const LocationException(super.message, {super.code});
}

/// El recurso solicitado no fue encontrado.
final class NotFoundException extends AppException {
  const NotFoundException(super.message, {super.code});
}

/// Error de servidor (500, 503, etc.)
final class ServerException extends AppException {
  const ServerException(super.message, {super.code});
}
