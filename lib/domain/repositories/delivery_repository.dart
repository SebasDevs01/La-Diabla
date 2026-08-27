// lib/domain/repositories/delivery_repository.dart

/// Ubicación del repartidor en tiempo real.
class DriverLocation {
  const DriverLocation({
    required this.driverId,
    required this.latitude,
    required this.longitude,
    required this.updatedAt,
  });

  final String driverId;
  final double latitude;
  final double longitude;
  final DateTime updatedAt;
}

/// Interfaz del repositorio de entregas.
/// Preparado para tracking GPS en tiempo real del repartidor.
abstract interface class DeliveryRepository {
  /// Obtiene la ubicación actual del repartidor.
  Future<DriverLocation?> getDriverLocation(String driverId);

  /// Stream de la ubicación del repartidor en tiempo real.
  /// Se usa cuando el pedido está en estado 'on_the_way'.
  Stream<DriverLocation?> watchDriverLocation(String driverId);

  /// Calcula el tiempo estimado de entrega dado un origen y destino.
  Future<Duration?> estimateDeliveryTime({
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
  });

  /// Calcula la tarifa de entrega según distancia y configuración.
  Future<double> calculateDeliveryFee({
    required double distanceKm,
    String? promotionCode,
  });
}
