// lib/core/utils/price_formatter.dart
import 'package:intl/intl.dart';

/// Formateador de precios para La Diabla (COP - Pesos Colombianos).
abstract final class PriceFormatter {
  static final _formatter = NumberFormat.currency(
    locale: 'es_CO',
    symbol: '\$',
    decimalDigits: 0,
  );

  /// Formatea un double a precio en COP.
  /// Ejemplo: 15000.0 → "$15.000"
  static String format(double amount) => _formatter.format(amount);

  /// Formatea con símbolo de moneda.
  /// Ejemplo: 15000.0 → "$15.000 COP"
  static String formatWithCode(double amount) =>
      '${_formatter.format(amount)} COP';

  /// Formatea inteligentemente sin decimales para pesos colombianos.
  static String formatSmart(double amount) {
    return _formatter.format(amount);
  }
}
