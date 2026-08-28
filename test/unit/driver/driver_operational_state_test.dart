// test/unit/driver/driver_operational_state_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:la_diabla/core/services/battery_service.dart';
import 'package:la_diabla/features/driver/domain/driver_operational_state.dart';

void main() {
  group('Pruebas de Estado Operativo del Repartidor (Soy Rappi / La Diabla)', () {
    test('1. Batería: Verificación de umbral estricto del 10%', () {
      final batteryService = BatteryService.instance;

      // >= 10% -> NO es batería baja
      expect(batteryService.isLowBattery(100), isFalse);
      expect(batteryService.isLowBattery(50), isFalse);
      expect(batteryService.isLowBattery(11), isFalse);
      expect(batteryService.isLowBattery(10), isFalse);

      // < 10% -> ES batería baja
      expect(batteryService.isLowBattery(9), isTrue);
      expect(batteryService.isLowBattery(5), isTrue);
      expect(batteryService.isLowBattery(1), isTrue);
      expect(batteryService.isLowBattery(0), isTrue);
    });

    test('2. Matriz de Validación: Batería >= 10% permite recibir pedidos', () {
      final state10 = DriverOperationalState(
        batteryLevel: 10,
        isBatteryLow: false,
        isLocationEnabled: true,
        isOnline: true,
        isManualAvailable: true,
        hasActiveDelivery: false,
        lastUpdated: DateTime.now(),
      );

      expect(state10.canReceiveOrders, isTrue);
      expect(state10.blockingReason, isNull);
    });

    test('3. Matriz de Validación: Batería < 10% bloquea nuevos pedidos', () {
      final state9 = DriverOperationalState(
        batteryLevel: 9,
        isBatteryLow: true,
        isLocationEnabled: true,
        isOnline: true,
        isManualAvailable: true,
        hasActiveDelivery: false,
        lastUpdated: DateTime.now(),
      );

      expect(state9.canReceiveOrders, isFalse);
      expect(state9.blockingReason, contains('Batería menor al 10%'));
    });

    test('4. Pedido Activo en Curso: No se cancela por batería baja', () {
      // Repartidor en entrega activa que baja al 8% de batería
      final activeState = DriverOperationalState(
        status: DriverOperationalStatus.activeDelivery,
        batteryLevel: 8,
        isBatteryLow: true,
        isLocationEnabled: true,
        isOnline: true,
        isManualAvailable: true,
        hasActiveDelivery: true,
        activeOrderId: 'order_abc123',
        lastUpdated: DateTime.now(),
      );

      // No puede recibir pedidos NUEVOS mientras tiene entrega activa y batería baja
      expect(activeState.canReceiveOrders, isFalse);
      // Pero mantiene la orden activa asignada para finalizar la entrega
      expect(activeState.activeOrderId, equals('order_abc123'));
      expect(activeState.hasActiveDelivery, isTrue);
    });

    test('5. Ubicación Desactivada: Bloquea recepción de pedidos', () {
      final noGpsState = DriverOperationalState(
        batteryLevel: 80,
        isBatteryLow: false,
        isLocationEnabled: false,
        isOnline: true,
        isManualAvailable: true,
        hasActiveDelivery: false,
        lastUpdated: DateTime.now(),
      );

      expect(noGpsState.canReceiveOrders, isFalse);
      expect(noGpsState.blockingReason, contains('Ubicación GPS'));
    });

    test('6. Sin Conexión (Offline): Bloquea recepción de pedidos', () {
      final offlineState = DriverOperationalState(
        batteryLevel: 80,
        isBatteryLow: false,
        isLocationEnabled: true,
        isOnline: false,
        isManualAvailable: true,
        hasActiveDelivery: false,
        lastUpdated: DateTime.now(),
      );

      expect(offlineState.canReceiveOrders, isFalse);
      expect(offlineState.blockingReason, contains('conexión a internet'));
    });

    test('7. Serialización Firestore: Campos de telemetría correctos', () {
      final state = DriverOperationalState(
        status: DriverOperationalStatus.available,
        batteryLevel: 85,
        isBatteryLow: false,
        isLocationEnabled: true,
        isBackgroundLocationEnabled: true,
        isOnline: true,
        isManualAvailable: true,
        hasActiveDelivery: false,
        lastUpdated: DateTime.now(),
      );

      final map = state.toFirestoreMap();
      expect(map['batteryLevel'], equals(85));
      expect(map['batteryStatus'], equals('NORMAL'));
      expect(map['isAvailable'], equals(true));
      expect(map['operationalStatus'], equals('AVAILABLE'));
      expect(map['locationEnabled'], equals(true));
      expect(map['backgroundLocationEnabled'], equals(true));
      expect(map['isOnline'], equals(true));
      expect(map['hasActiveDelivery'], equals(false));
    });
  });
}
