// lib/core/services/permission_service.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:logger/logger.dart';

/// Servicio centralizado de permisos — solicita notificaciones y ubicacion
/// de forma progresiva (estilo Rappi) al abrir la app.
class PermissionService {
  static final Logger _log = Logger();

  // Notificaciones
  static Future<bool> requestNotificationPermission() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      _log.i('Permiso notificaciones: ${settings.authorizationStatus}');
      return granted;
    } catch (e) {
      _log.w('Error permisos notificacion: $e');
      return false;
    }
  }

  // Ubicacion cliente
  static Future<bool> requestLocationPermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) return false;

      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (e) {
      _log.w('Error permiso ubicacion: $e');
      return false;
    }
  }

  // Ubicacion background (repartidor)
  static Future<bool> requestBackgroundLocationPermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.whileInUse) {
        permission = await Geolocator.requestPermission();
      }
      return permission == LocationPermission.always;
    } catch (e) {
      _log.w('Error permiso ubicacion background: $e');
      return false;
    }
  }

  /// Solicita permisos completos para el repartidor de forma estrictamente secuencial:
  /// 1. Ubicación en primer plano (whileInUse) -> Espera confirmación del sistema
  /// 2. Pausa fluida -> Ubicación en segundo plano (Always) -> Espera confirmación
  /// 3. Pausa fluida -> Notificaciones (si faltan)
  static Future<bool> requestDriverLocationPermissions(BuildContext context) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _log.w('Servicio de ubicación desactivado');
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      // Si ya tiene Always no hacemos nada más
      if (permission == LocationPermission.always) return true;

      // Paso 1: Ubicación en primer plano (whileInUse)
      if (permission == LocationPermission.denied) {
        if (!context.mounted) return false;
        final shouldRequest = await showLocationRationaleDialog(context);
        if (!shouldRequest) return false;

        // Breve pausa para permitir que el diálogo se cierre limpiamente antes del prompt nativo
        await Future.delayed(const Duration(milliseconds: 300));
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        _log.w('Ubicación denegada permanentemente');
        return false;
      }

      // Paso 2: Escalar a Always (segundo plano) de forma secuencial y sin amontonar
      if (permission == LocationPermission.whileInUse) {
        // Pausa estética para que el sistema cierre la ventana anterior
        await Future.delayed(const Duration(milliseconds: 450));
        if (!context.mounted) return true;

        final shouldEscalate = await showBackgroundLocationRationaleDialog(context);
        if (shouldEscalate) {
          await Future.delayed(const Duration(milliseconds: 300));
          permission = await Geolocator.requestPermission();
        }
      }

      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (e) {
      _log.w('Error permisos repartidor: $e');
      return false;
    }
  }

  /// Flujo guiado maestro paso a paso para configurar todos los permisos de una sola vez
  static Future<void> requestAllPermissionsStepByStep(BuildContext context) async {
    // 1. Ubicación
    await requestDriverLocationPermissions(context);

    // 2. Notificaciones
    await Future.delayed(const Duration(milliseconds: 450));
    try {
      final notifSettings = await FirebaseMessaging.instance.getNotificationSettings();
      if (notifSettings.authorizationStatus != AuthorizationStatus.authorized &&
          notifSettings.authorizationStatus != AuthorizationStatus.provisional) {
        if (context.mounted) {
          final shouldRequestNotif = await showNotificationRationaleDialog(context);
          if (shouldRequestNotif) {
            await Future.delayed(const Duration(milliseconds: 300));
            await requestNotificationPermission();
          }
        }
      }
    } catch (e) {
      _log.w('Error en paso de notificaciones: $e');
    }
  }

  // Posicion actual
  static Future<Position?> getCurrentPosition() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      _log.w('Error obteniendo posicion: $e');
      return null;
    }
  }

  // Stream GPS para repartidor
  static Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    );
  }

  // Dialogo pre-permiso ubicacion (estilo Rappi)
  static Future<bool> showLocationRationaleDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.location_on_rounded, color: Color(0xFFDC2626), size: 36),
            ),
            const SizedBox(height: 16),
            const Text(
              'Necesitamos tu ubicacion',
              style: TextStyle(fontFamily: 'Bangers', fontSize: 22, letterSpacing: 1),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Para mostrarte restaurantes cercanos, calcular el costo de envio y rastrear tu pedido en tiempo real necesitamos acceder a tu ubicacion.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600, height: 1.5),
            ),
            const SizedBox(height: 8),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Ahora no', style: TextStyle(color: Colors.grey.shade500)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Activar ubicacion'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // Dialogo pre-permiso notificaciones (estilo Rappi)
  static Future<bool> showNotificationRationaleDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.notifications_active_rounded, color: Color(0xFFDC2626), size: 36),
            ),
            const SizedBox(height: 16),
            const Text(
              'Activa las notificaciones',
              style: TextStyle(fontFamily: 'Bangers', fontSize: 22, letterSpacing: 1),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Recibe actualizaciones en tiempo real sobre tu pedido: cuando este en preparacion, cuando salga para entrega y cuando llegue a tu puerta.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600, height: 1.5),
            ),
            const SizedBox(height: 8),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Ahora no', style: TextStyle(color: Colors.grey.shade500)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Activar notificaciones'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // Dialogo permiso ubicacion en segundo plano (repartidor)
  static Future<bool> showBackgroundLocationRationaleDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.location_on_rounded, color: Color(0xFFDC2626), size: 36),
            ),
            const SizedBox(height: 16),
            const Text(
              'Ubicacion en segundo plano',
              style: TextStyle(fontFamily: 'Bangers', fontSize: 22, letterSpacing: 1),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Para recibir nuevos pedidos y transmitir tu posicion incluso con la app en segundo plano (como Rappi), selecciona "Permitir siempre" en la siguiente pantalla.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600, height: 1.5),
            ),
            const SizedBox(height: 8),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Ahora no', style: TextStyle(color: Colors.grey.shade500)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Permitir siempre'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
