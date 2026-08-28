// lib/features/driver/domain/driver_preferences.dart

/// Tipos de vehículo disponibles para el repartidor.
enum VehicleType {
  bicycle(displayName: 'Bicicleta 🚲', defaultSpeedKmh: 15.0, icon: '🚲'),
  electricMotorcycle(displayName: 'Moto Eléctrica ⚡', defaultSpeedKmh: 35.0, icon: '⚡'),
  motorcycle(displayName: 'Motocicleta 🛵', defaultSpeedKmh: 40.0, icon: '🛵'),
  car(displayName: 'Automóvil 🚗', defaultSpeedKmh: 30.0, icon: '🚗');

  const VehicleType({
    required this.displayName,
    required this.defaultSpeedKmh,
    required this.icon,
  });

  final String displayName;
  final double defaultSpeedKmh;
  final String icon;
}

/// Preferencias y filtros configurables del repartidor.
class DriverPreferences {
  final bool isConnected;
  final bool isAutoAcceptEnabled;
  final double maxTotalDistanceKm;
  final double maxStoreDistanceKm;
  final double minProfitPerKm;
  final int maxTripMinutes;
  final VehicleType vehicleType;
  final double estimatedAutonomyKm;
  final double minAutonomyReserveKm;
  final bool avoidSteepHills;
  final String activeWorkModeId;

  const DriverPreferences({
    this.isConnected = true,
    this.isAutoAcceptEnabled = false,
    this.maxTotalDistanceKm = 7.0,
    this.maxStoreDistanceKm = 3.5,
    this.minProfitPerKm = 0.0,
    this.maxTripMinutes = 45,
    this.vehicleType = VehicleType.motorcycle,
    this.estimatedAutonomyKm = 50.0,
    this.minAutonomyReserveKm = 10.0,
    this.avoidSteepHills = false,
    this.activeWorkModeId = 'normal',
  });

  DriverPreferences copyWith({
    bool? isConnected,
    bool? isAutoAcceptEnabled,
    double? maxTotalDistanceKm,
    double? maxStoreDistanceKm,
    double? minProfitPerKm,
    int? maxTripMinutes,
    VehicleType? vehicleType,
    double? estimatedAutonomyKm,
    double? minAutonomyReserveKm,
    bool? avoidSteepHills,
    String? activeWorkModeId,
  }) {
    return DriverPreferences(
      isConnected: isConnected ?? this.isConnected,
      isAutoAcceptEnabled: isAutoAcceptEnabled ?? this.isAutoAcceptEnabled,
      maxTotalDistanceKm: maxTotalDistanceKm ?? this.maxTotalDistanceKm,
      maxStoreDistanceKm: maxStoreDistanceKm ?? this.maxStoreDistanceKm,
      minProfitPerKm: minProfitPerKm ?? this.minProfitPerKm,
      maxTripMinutes: maxTripMinutes ?? this.maxTripMinutes,
      vehicleType: vehicleType ?? this.vehicleType,
      estimatedAutonomyKm: estimatedAutonomyKm ?? this.estimatedAutonomyKm,
      minAutonomyReserveKm: minAutonomyReserveKm ?? this.minAutonomyReserveKm,
      avoidSteepHills: avoidSteepHills ?? this.avoidSteepHills,
      activeWorkModeId: activeWorkModeId ?? this.activeWorkModeId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'isConnected': isConnected,
      'isAutoAcceptEnabled': isAutoAcceptEnabled,
      'maxTotalDistanceKm': maxTotalDistanceKm,
      'maxStoreDistanceKm': maxStoreDistanceKm,
      'minProfitPerKm': minProfitPerKm,
      'maxTripMinutes': maxTripMinutes,
      'vehicleType': vehicleType.name,
      'estimatedAutonomyKm': estimatedAutonomyKm,
      'minAutonomyReserveKm': minAutonomyReserveKm,
      'avoidSteepHills': avoidSteepHills,
      'activeWorkModeId': activeWorkModeId,
    };
  }

  factory DriverPreferences.fromMap(Map<String, dynamic> map) {
    return DriverPreferences(
      isConnected: map['isConnected'] as bool? ?? true,
      isAutoAcceptEnabled: map['isAutoAcceptEnabled'] as bool? ?? false,
      maxTotalDistanceKm: (map['maxTotalDistanceKm'] as num?)?.toDouble() ?? 7.0,
      maxStoreDistanceKm: (map['maxStoreDistanceKm'] as num?)?.toDouble() ?? 3.5,
      minProfitPerKm: (map['minProfitPerKm'] as num?)?.toDouble() ?? 0.0,
      maxTripMinutes: (map['maxTripMinutes'] as num?)?.toInt() ?? 45,
      vehicleType: VehicleType.values.firstWhere(
        (v) => v.name == map['vehicleType'],
        orElse: () => VehicleType.motorcycle,
      ),
      estimatedAutonomyKm: (map['estimatedAutonomyKm'] as num?)?.toDouble() ?? 50.0,
      minAutonomyReserveKm: (map['minAutonomyReserveKm'] as num?)?.toDouble() ?? 10.0,
      avoidSteepHills: map['avoidSteepHills'] as bool? ?? false,
      activeWorkModeId: map['activeWorkModeId'] as String? ?? 'normal',
    );
  }
}
