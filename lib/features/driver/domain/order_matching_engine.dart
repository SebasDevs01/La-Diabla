// lib/features/driver/domain/order_matching_engine.dart
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/services/maps_service.dart';
import '../../../domain/entities/order_entity.dart';
import 'driver_preferences.dart';

/// Motivos de rechazo o no compatibilidad de un pedido con el perfil del repartidor.
enum MatchRejectionReason {
  driverDisconnected(code: 'DISCONNECTED', label: 'Repartidor desconectado'),
  lowBattery(code: 'LOW_BATTERY', label: 'Batería menor al 10%'),
  offline(code: 'OFFLINE', label: 'Sin conexión a internet'),
  driverBusy(code: 'DRIVER_BUSY', label: 'Entrega en curso'),
  locationUnavailable(code: 'NO_LOCATION', label: 'Ubicación GPS no disponible'),
  storeDistanceExceeded(code: 'STORE_TOO_FAR', label: 'Comercio demasiado lejos'),
  totalDistanceExceeded(code: 'DISTANCE_EXCEEDED', label: 'Distancia total excedida'),
  insufficientAutonomy(code: 'INSUFFICIENT_AUTONOMY', label: 'Autonomía insuficiente'),
  lowProfitPerKm(code: 'LOW_PROFIT', label: 'Ganancia por km insuficiente'),
  tripTimeExceeded(code: 'TIME_EXCEEDED', label: 'Tiempo de viaje excedido'),
  vehicleIncompatible(code: 'VEHICLE_INCOMPATIBLE', label: 'Vehículo incompatible');

  const MatchRejectionReason({
    required this.code,
    required this.label,
  });

  final String code;
  final String label;
}

/// Resultado de la evaluación de compatibilidad de un pedido.
class MatchResult {
  final bool isMatch;
  final MatchRejectionReason? rejectionReason;
  final String? explanation;
  final double storeDistanceKm;
  final double deliveryDistanceKm;
  final double totalDistanceKm;
  final double profitPerKm;
  final int estimatedMinutes;
  final double deliveryFee;

  const MatchResult({
    required this.isMatch,
    this.rejectionReason,
    this.explanation,
    required this.storeDistanceKm,
    required this.deliveryDistanceKm,
    required this.totalDistanceKm,
    required this.profitPerKm,
    required this.estimatedMinutes,
    required this.deliveryFee,
  });

  factory MatchResult.match({
    required double storeDistanceKm,
    required double deliveryDistanceKm,
    required double totalDistanceKm,
    required double profitPerKm,
    required int estimatedMinutes,
    required double deliveryFee,
  }) {
    return MatchResult(
      isMatch: true,
      storeDistanceKm: storeDistanceKm,
      deliveryDistanceKm: deliveryDistanceKm,
      totalDistanceKm: totalDistanceKm,
      profitPerKm: profitPerKm,
      estimatedMinutes: estimatedMinutes,
      deliveryFee: deliveryFee,
    );
  }

  factory MatchResult.noMatch({
    required MatchRejectionReason reason,
    required String explanation,
    double storeDistanceKm = 0.0,
    double deliveryDistanceKm = 0.0,
    double totalDistanceKm = 0.0,
    double profitPerKm = 0.0,
    int estimatedMinutes = 0,
    double deliveryFee = 7500.0,
  }) {
    return MatchResult(
      isMatch: false,
      rejectionReason: reason,
      explanation: explanation,
      storeDistanceKm: storeDistanceKm,
      deliveryDistanceKm: deliveryDistanceKm,
      totalDistanceKm: totalDistanceKm,
      profitPerKm: profitPerKm,
      estimatedMinutes: estimatedMinutes,
      deliveryFee: deliveryFee,
    );
  }
}

/// Motor inteligente de evaluación de compatibilidad de pedidos para La Diabla.
class OrderMatchingEngine {
  /// Evalúa si un pedido cumple con todas las condiciones y preferencias del repartidor.
  static MatchResult evaluate({
    required OrderEntity order,
    required LatLng driverLocation,
    required DriverPreferences preferences,
    required int batteryLevel,
    required bool isBatteryLow,
    required bool isOnline,
    required bool hasActiveDelivery,
    LatLng storeLocation = MapsService.defaultLocation,
  }) {
    final fee = order.deliveryFee > 0 ? order.deliveryFee : 7500.0;

    // 1. Conexión del repartidor
    if (!preferences.isConnected) {
      return MatchResult.noMatch(
        reason: MatchRejectionReason.driverDisconnected,
        explanation: 'Estás en modo desconectado. Conéctate para recibir pedidos.',
      );
    }

    // 2. Conexión a internet
    if (!isOnline) {
      return MatchResult.noMatch(
        reason: MatchRejectionReason.offline,
        explanation: 'Sin conexión a internet activa.',
      );
    }

    // 3. Batería del teléfono
    if (isBatteryLow || batteryLevel < 10) {
      return MatchResult.noMatch(
        reason: MatchRejectionReason.lowBattery,
        explanation: 'Batería en $batteryLevel% (<10%). Carga tu celular para recibir pedidos.',
      );
    }

    // 4. Entrega activa en curso
    if (hasActiveDelivery) {
      return MatchResult.noMatch(
        reason: MatchRejectionReason.driverBusy,
        explanation: 'Tienes una entrega activa en curso.',
      );
    }

    // 5. Coordenadas del cliente
    final custLat = order.address?.latitude ?? order.latitude ?? storeLocation.latitude;
    final custLng = order.address?.longitude ?? order.longitude ?? storeLocation.longitude;
    final customerLocation = LatLng(custLat, custLng);

    // 6. Cálculo de distancias compuestas (Repartidor -> Cocina + Cocina -> Cliente)
    final distanceData = MapsService.calculateCompositeDistance(
      driverLocation: driverLocation,
      storeLocation: storeLocation,
      customerLocation: customerLocation,
    );

    final storeDist = distanceData.storeDistanceKm;
    final deliveryDist = distanceData.deliveryDistanceKm;
    final totalDist = distanceData.totalDistanceKm;

    final profitPerKm = totalDist > 0 ? (fee / totalDist) : fee;
    final estimatedMinutes = (totalDist / preferences.vehicleType.defaultSpeedKmh * 60).round() + 10;

    // 7. Filtro: Distancia al Comercio (Cocina Central)
    if (preferences.maxStoreDistanceKm > 0 && storeDist > preferences.maxStoreDistanceKm) {
      return MatchResult.noMatch(
        reason: MatchRejectionReason.storeDistanceExceeded,
        explanation: 'Cocina a $storeDist km (tu límite es ${preferences.maxStoreDistanceKm} km).',
        storeDistanceKm: storeDist,
        deliveryDistanceKm: deliveryDist,
        totalDistanceKm: totalDist,
        profitPerKm: profitPerKm,
        estimatedMinutes: estimatedMinutes,
        deliveryFee: fee,
      );
    }

    // 8. Filtro: Distancia Total de Ruta
    if (preferences.maxTotalDistanceKm > 0 && totalDist > preferences.maxTotalDistanceKm) {
      return MatchResult.noMatch(
        reason: MatchRejectionReason.totalDistanceExceeded,
        explanation: 'Ruta total de $totalDist km (tu límite es ${preferences.maxTotalDistanceKm} km).',
        storeDistanceKm: storeDist,
        deliveryDistanceKm: deliveryDist,
        totalDistanceKm: totalDist,
        profitPerKm: profitPerKm,
        estimatedMinutes: estimatedMinutes,
        deliveryFee: fee,
      );
    }

    // 9. Filtro: Autonomía del Vehículo (eléctricos y bicicletas)
    if (preferences.vehicleType == VehicleType.electricMotorcycle) {
      final availableAutonomy = preferences.estimatedAutonomyKm - preferences.minAutonomyReserveKm;
      if (totalDist > availableAutonomy) {
        return MatchResult.noMatch(
          reason: MatchRejectionReason.insufficientAutonomy,
          explanation: 'Ruta de $totalDist km compromete tu reserva de batería de ${preferences.minAutonomyReserveKm} km.',
          storeDistanceKm: storeDist,
          deliveryDistanceKm: deliveryDist,
          totalDistanceKm: totalDist,
          profitPerKm: profitPerKm,
          estimatedMinutes: estimatedMinutes,
          deliveryFee: fee,
        );
      }
    }

    // 10. Filtro: Ganancia Mínima por Kilómetro
    if (preferences.minProfitPerKm > 0 && profitPerKm < preferences.minProfitPerKm) {
      return MatchResult.noMatch(
        reason: MatchRejectionReason.lowProfitPerKm,
        explanation: 'Ganancia \$${profitPerKm.round()}/km inferior a tu mínimo de \$${preferences.minProfitPerKm.round()}/km.',
        storeDistanceKm: storeDist,
        deliveryDistanceKm: deliveryDist,
        totalDistanceKm: totalDist,
        profitPerKm: profitPerKm,
        estimatedMinutes: estimatedMinutes,
        deliveryFee: fee,
      );
    }

    // 11. Filtro: Tiempo Máximo de Recorrido
    if (preferences.maxTripMinutes > 0 && estimatedMinutes > preferences.maxTripMinutes) {
      return MatchResult.noMatch(
        reason: MatchRejectionReason.tripTimeExceeded,
        explanation: 'Tiempo estimado de $estimatedMinutes min excede tu máximo de ${preferences.maxTripMinutes} min.',
        storeDistanceKm: storeDist,
        deliveryDistanceKm: deliveryDist,
        totalDistanceKm: totalDist,
        profitPerKm: profitPerKm,
        estimatedMinutes: estimatedMinutes,
        deliveryFee: fee,
      );
    }

    // ✅ MATCH EXITOSO
    return MatchResult.match(
      storeDistanceKm: storeDist,
      deliveryDistanceKm: deliveryDist,
      totalDistanceKm: totalDist,
      profitPerKm: profitPerKm,
      estimatedMinutes: estimatedMinutes,
      deliveryFee: fee,
    );
  }
}
