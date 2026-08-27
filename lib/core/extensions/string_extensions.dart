// lib/core/extensions/string_extensions.dart

/// Extensiones de String para operaciones comunes en la app.
extension StringExtensions on String {
  /// Capitaliza la primera letra.
  String get capitalize =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1).toLowerCase()}';

  /// Capitaliza cada palabra.
  String get titleCase => split(' ').map((w) => w.capitalize).join(' ');

  /// Retorna null si el string está vacío, de lo contrario retorna el string.
  String? get nullIfEmpty => isEmpty ? null : this;

  /// Verifica si es un email válido básico.
  bool get isValidEmail => RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  ).hasMatch(this);

  /// Verifica si es un número de teléfono válido (básico).
  bool get isValidPhone => RegExp(r'^\+?[0-9]{8,15}$').hasMatch(this);

  /// Formatea como moneda colombiana (sin import de intl).
  String get asCopCurrency => '\$$this COP';
}

/// Extensiones para String? (nullable).
extension NullableStringExtensions on String? {
  /// Retorna el valor o un string vacío si es null.
  String get orEmpty => this ?? '';

  /// Retorna true si es null o vacío.
  bool get isNullOrEmpty => this == null || this!.isEmpty;
}
