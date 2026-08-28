// test/unit/driver/order_matching_engine_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:la_diabla/domain/entities/order_entity.dart';
import 'package:la_diabla/domain/entities/order_status.dart';
import 'package:la_diabla/features/driver/domain/driver_preferences.dart';
import 'package:la_diabla/features/driver/domain/order_matching_engine.dart';
import 'package:la_diabla/features/driver/domain/work_mode.dart';

void main() {
  group('OrderMatchingEngine & WorkModes Tests (Soy Rappi / La Diabla)', () {
    const kitchenLoc = LatLng(7.092758, -73.142590); // Cocina Central Mutis
    const driverNearby = LatLng(7.093000, -73.142000); // 0.1 km de cocina
    const clientNearby = LatLng(7.100000, -73.140000); // ~1.0 km de cocina
    const clientFarAway = LatLng(7.160000, -73.120000); // ~8.0 km de cocina

    final baseOrder = OrderEntity(
      id: 'order_test_001',
      userId: 'user_123',
      items: [],
      subtotal: 27500.0,
      total: 35000.0,
      deliveryFee: 7500.0,
      status: OrderStatus.ready,
      paymentMethod: PaymentMethod.cash,
      paymentStatus: PaymentStatus.pending,
      orderType: OrderType.delivery,
      latitude: clientNearby.latitude,
      longitude: clientNearby.longitude,
      createdAt: DateTime.now(),
    );

    test('1. Repartidor Desconectado: No debe hacer match', () {
      const prefs = DriverPreferences(isConnected: false);
      final result = OrderMatchingEngine.evaluate(
        order: baseOrder,
        driverLocation: driverNearby,
        preferences: prefs,
        batteryLevel: 80,
        isBatteryLow: false,
        isOnline: true,
        hasActiveDelivery: false,
        storeLocation: kitchenLoc,
      );

      expect(result.isMatch, isFalse);
      expect(result.rejectionReason, equals(MatchRejectionReason.driverDisconnected));
    });

    test('2. Batería Baja (<10%): Bloquea autoaceptación y match', () {
      const prefs = DriverPreferences(isConnected: true);
      final result = OrderMatchingEngine.evaluate(
        order: baseOrder,
        driverLocation: driverNearby,
        preferences: prefs,
        batteryLevel: 8,
        isBatteryLow: true,
        isOnline: true,
        hasActiveDelivery: false,
        storeLocation: kitchenLoc,
      );

      expect(result.isMatch, isFalse);
      expect(result.rejectionReason, equals(MatchRejectionReason.lowBattery));
    });

    test('3. Distancia Total Excedida: Modo Cercano (máx 3 km) rechaza pedido a 8 km', () {
      final farOrder = baseOrder.copyWith(
        latitude: clientFarAway.latitude,
        longitude: clientFarAway.longitude,
      );

      final nearbyModePrefs = WorkMode.nearby.preferences; // maxTotalDistanceKm = 3.0
      final result = OrderMatchingEngine.evaluate(
        order: farOrder,
        driverLocation: driverNearby,
        preferences: nearbyModePrefs,
        batteryLevel: 90,
        isBatteryLow: false,
        isOnline: true,
        hasActiveDelivery: false,
        storeLocation: kitchenLoc,
      );

      expect(result.isMatch, isFalse);
      expect(result.rejectionReason, equals(MatchRejectionReason.totalDistanceExceeded));
      expect(result.totalDistanceKm, greaterThan(3.0));
    });

    test('4. Modo Cercano (máx 3 km) acepta pedido compatible a 1.1 km', () {
      final nearbyModePrefs = WorkMode.nearby.preferences;
      final result = OrderMatchingEngine.evaluate(
        order: baseOrder,
        driverLocation: driverNearby,
        preferences: nearbyModePrefs,
        batteryLevel: 90,
        isBatteryLow: false,
        isOnline: true,
        hasActiveDelivery: false,
        storeLocation: kitchenLoc,
      );

      expect(result.isMatch, isTrue);
      expect(result.rejectionReason, isNull);
      expect(result.totalDistanceKm, lessThanOrEqualTo(3.0));
    });

    test('5. Ganancia Mínima por Km: Modo Maximizar Ganancias evalúa ratio \$/km', () {
      // Pedido con tarifa de $7.500 pero distancia de 8.0 km -> ~$937/km
      final farOrder = baseOrder.copyWith(
        deliveryFee: 7500.0,
        latitude: clientFarAway.latitude,
        longitude: clientFarAway.longitude,
      );

      const strictProfitPrefs = DriverPreferences(
        isConnected: true,
        maxTotalDistanceKm: 15.0,
        maxStoreDistanceKm: 10.0,
        minProfitPerKm: 1500.0, // Requiere al menos $1.500/km
      );

      final result = OrderMatchingEngine.evaluate(
        order: farOrder,
        driverLocation: driverNearby,
        preferences: strictProfitPrefs,
        batteryLevel: 90,
        isBatteryLow: false,
        isOnline: true,
        hasActiveDelivery: false,
        storeLocation: kitchenLoc,
      );

      expect(result.isMatch, isFalse);
      expect(result.rejectionReason, equals(MatchRejectionReason.lowProfitPerKm));
    });

    test('6. Entrega Activa: No ofrece nuevos pedidos mientras está ocupado', () {
      const prefs = DriverPreferences(isConnected: true);
      final result = OrderMatchingEngine.evaluate(
        order: baseOrder,
        driverLocation: driverNearby,
        preferences: prefs,
        batteryLevel: 90,
        isBatteryLow: false,
        isOnline: true,
        hasActiveDelivery: true,
        storeLocation: kitchenLoc,
      );

      expect(result.isMatch, isFalse);
      expect(result.rejectionReason, equals(MatchRejectionReason.driverBusy));
    });

    test('7. Modos de Trabajo: Verificación de Presets', () {
      expect(WorkMode.nearby.preferences.vehicleType, equals(VehicleType.bicycle));
      expect(WorkMode.nearby.preferences.maxTotalDistanceKm, equals(3.0));

      expect(WorkMode.electric.preferences.vehicleType, equals(VehicleType.electricMotorcycle));
      expect(WorkMode.electric.preferences.estimatedAutonomyKm, equals(40.0));

      expect(WorkMode.normal.preferences.vehicleType, equals(VehicleType.motorcycle));
      expect(WorkMode.normal.preferences.maxTotalDistanceKm, equals(7.0));

      expect(WorkMode.maxProfit.preferences.minProfitPerKm, equals(1500.0));
    });
  });
}
