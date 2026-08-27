// lib/core/services/location_service.dart
import 'package:geolocator/geolocator.dart';
import 'package:logger/logger.dart';
import '../errors/app_exception.dart';

/// Servicio de ubicación — wrapper de Geolocator.
/// Gestiona permisos y obtención de coordenadas.
class LocationService {
  final Logger _logger = Logger();

  /// Solicita permisos y retorna la posición actual del dispositivo.
  Future<Position> getCurrentPosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw const LocationException(
          'El servicio de ubicación está desactivado. Actívalo para continuar.',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw const PermissionException(
            'Permiso de ubicación denegado.',
          );
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw const PermissionException(
          'Permiso de ubicación denegado permanentemente. '
          'Habilítalo en la configuración del dispositivo.',
        );
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } on LocationException {
      rethrow;
    } on PermissionException {
      rethrow;
    } catch (e) {
      _logger.e('Error getting location', error: e);
      throw LocationException('Error al obtener ubicación: $e');
    }
  }

  /// Calcula la distancia en kilómetros entre dos puntos.
  double calculateDistanceKm({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) {
    return Geolocator.distanceBetween(startLat, startLng, endLat, endLng) /
        1000;
  }

  /// Stream de actualizaciones de posición.
  Stream<Position> get positionStream => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, // Solo actualiza si se mueve más de 10 metros
        ),
      );
}
