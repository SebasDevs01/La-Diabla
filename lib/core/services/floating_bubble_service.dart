// lib/core/services/floating_bubble_service.dart
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

/// Servicio para controlar el acceso rápido flotante (Overlay Bubble) del repartidor.
class FloatingBubbleService {
  FloatingBubbleService._();
  static final FloatingBubbleService instance = FloatingBubbleService._();

  static const MethodChannel _channel = MethodChannel('com.ladiabla.app/floating_bubble');
  static final Logger _logger = Logger();

  /// Comprueba si la app tiene permiso para mostrar sobre otras aplicaciones (SYSTEM_ALERT_WINDOW).
  Future<bool> hasOverlayPermission() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('hasOverlayPermission');
      return result ?? false;
    } catch (e) {
      _logger.w('Error verificando permiso overlay: $e');
      return false;
    }
  }

  /// Solicita el permiso para mostrar sobre otras aplicaciones abriendo los Ajustes de Android.
  Future<bool> requestOverlayPermission() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('requestOverlayPermission');
      return result ?? false;
    } catch (e) {
      _logger.w('Error solicitando permiso overlay: $e');
      return false;
    }
  }

  /// Muestra la burbuja flotante fuera de la app (cuando pasa a segundo plano).
  Future<bool> showBubble() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('showFloatingBubble');
      return result ?? false;
    } catch (e) {
      _logger.w('Error mostrando burbuja flotante: $e');
      return false;
    }
  }

  /// Oculta y destruye la burbuja flotante (cuando la app vuelve a primer plano).
  Future<bool> hideBubble() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('hideFloatingBubble');
      return result ?? false;
    } catch (e) {
      _logger.w('Error ocultando burbuja flotante: $e');
      return false;
    }
  }
}
