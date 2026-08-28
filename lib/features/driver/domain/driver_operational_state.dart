// lib/features/driver/domain/driver_operational_state.dart

/// Estados operativos del repartidor según condiciones del dispositivo.
enum DriverOperationalStatus {
  available,
  lowBattery,
  locationUnavailable,
  offline,
  activeDelivery,
  paused;

  String get displayName {
    return switch (this) {
      DriverOperationalStatus.available => 'Disponible para recibir pedidos',
      DriverOperationalStatus.lowBattery => 'No disponible — batería baja',
      DriverOperationalStatus.locationUnavailable => 'No disponible — sin ubicación GPS',
      DriverOperationalStatus.offline => 'Sin conexión a internet',
      DriverOperationalStatus.activeDelivery => 'En entrega activa',
      DriverOperationalStatus.paused => 'En pausa',
    };
  }

  String get firestoreValue {
    return switch (this) {
      DriverOperationalStatus.available => 'AVAILABLE',
      DriverOperationalStatus.lowBattery => 'LOW_BATTERY',
      DriverOperationalStatus.locationUnavailable => 'LOCATION_UNAVAILABLE',
      DriverOperationalStatus.offline => 'OFFLINE',
      DriverOperationalStatus.activeDelivery => 'ACTIVE_DELIVERY',
      DriverOperationalStatus.paused => 'PAUSED',
    };
  }
}

/// Estado global de operación del repartidor.
class DriverOperationalState {
  final DriverOperationalStatus status;
  final int batteryLevel;
  final bool isBatteryLow;
  final bool isLocationEnabled;
  final bool isBackgroundLocationEnabled;
  final bool isOnline;
  final bool isManualAvailable;
  final bool hasActiveDelivery;
  final String? activeOrderId;
  final DateTime lastUpdated;

  const DriverOperationalState({
    this.status = DriverOperationalStatus.available,
    this.batteryLevel = 100,
    this.isBatteryLow = false,
    this.isLocationEnabled = true,
    this.isBackgroundLocationEnabled = true,
    this.isOnline = true,
    this.isManualAvailable = true,
    this.hasActiveDelivery = false,
    this.activeOrderId,
    required this.lastUpdated,
  });

  /// Regla de negocio estricta: Solo puede recibir pedidos si está online,
  /// disponible manualmente, con batería >= 10%, con ubicación activa y sin entrega activa en curso.
  bool get canReceiveOrders =>
      isOnline &&
      isManualAvailable &&
      !isBatteryLow &&
      isLocationEnabled &&
      !hasActiveDelivery;

  /// Motivo de bloqueo en caso de no poder recibir pedidos.
  String? get blockingReason {
    if (isBatteryLow) {
      return 'Batería menor al 10%. Conecta el cargador para volver a recibir pedidos.';
    }
    if (!isLocationEnabled) {
      return 'Ubicación GPS desactivada o sin permisos. Actívala para continuar.';
    }
    if (!isOnline) {
      return 'Sin conexión a internet. Revisa tu red móvil o Wi-Fi.';
    }
    if (!isManualAvailable) {
      return 'Te encuentras en modo pausa.';
    }
    if (hasActiveDelivery) {
      return 'Tienes un pedido activo en curso.';
    }
    return null;
  }

  DriverOperationalState copyWith({
    DriverOperationalStatus? status,
    int? batteryLevel,
    bool? isBatteryLow,
    bool? isLocationEnabled,
    bool? isBackgroundLocationEnabled,
    bool? isOnline,
    bool? isManualAvailable,
    bool? hasActiveDelivery,
    String? activeOrderId,
    DateTime? lastUpdated,
  }) {
    return DriverOperationalState(
      status: status ?? this.status,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isBatteryLow: isBatteryLow ?? this.isBatteryLow,
      isLocationEnabled: isLocationEnabled ?? this.isLocationEnabled,
      isBackgroundLocationEnabled:
          isBackgroundLocationEnabled ?? this.isBackgroundLocationEnabled,
      isOnline: isOnline ?? this.isOnline,
      isManualAvailable: isManualAvailable ?? this.isManualAvailable,
      hasActiveDelivery: hasActiveDelivery ?? this.hasActiveDelivery,
      activeOrderId: activeOrderId ?? this.activeOrderId,
      lastUpdated: lastUpdated ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'batteryLevel': batteryLevel,
      'batteryStatus': isBatteryLow ? 'LOW' : 'NORMAL',
      'isAvailable': canReceiveOrders,
      'operationalStatus': status.firestoreValue,
      'locationEnabled': isLocationEnabled,
      'backgroundLocationEnabled': isBackgroundLocationEnabled,
      'isOnline': isOnline,
      'hasActiveDelivery': hasActiveDelivery,
      'activeOrderId': activeOrderId,
      'lastHeartbeat': DateTime.now().toIso8601String(),
    };
  }
}
