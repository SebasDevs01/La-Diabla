// lib/features/driver/domain/work_mode.dart
import 'driver_preferences.dart';

/// Modo o perfil preconfigurado de trabajo para el repartidor.
class WorkMode {
  final String id;
  final String name;
  final String emoji;
  final String description;
  final DriverPreferences preferences;

  const WorkMode({
    required this.id,
    required this.name,
    required this.emoji,
    required this.description,
    required this.preferences,
  });

  /// Modos de trabajo predefinidos
  static const WorkMode nearby = WorkMode(
    id: 'nearby',
    name: 'Modo Cercano',
    emoji: '🚲',
    description: 'Distancias cortas y menor esfuerzo. Ideal para bicicleta.',
    preferences: DriverPreferences(
      maxTotalDistanceKm: 3.0,
      maxStoreDistanceKm: 1.5,
      vehicleType: VehicleType.bicycle,
      avoidSteepHills: true,
      activeWorkModeId: 'nearby',
    ),
  );

  static const WorkMode electric = WorkMode(
    id: 'electric',
    name: 'Modo Eléctrico',
    emoji: '⚡',
    description: 'Control de autonomía para motos y bicis eléctricas.',
    preferences: DriverPreferences(
      maxTotalDistanceKm: 5.0,
      maxStoreDistanceKm: 2.5,
      vehicleType: VehicleType.electricMotorcycle,
      estimatedAutonomyKm: 40.0,
      minAutonomyReserveKm: 10.0,
      activeWorkModeId: 'electric',
    ),
  );

  static const WorkMode normal = WorkMode(
    id: 'normal',
    name: 'Modo Normal',
    emoji: '🛵',
    description: 'Configuración equilibrada y mayor radio para motocicleta.',
    preferences: DriverPreferences(
      maxTotalDistanceKm: 7.0,
      maxStoreDistanceKm: 3.5,
      vehicleType: VehicleType.motorcycle,
      activeWorkModeId: 'normal',
    ),
  );

  static const WorkMode maxProfit = WorkMode(
    id: 'max_profit',
    name: 'Maximizar Ganancias',
    emoji: '💰',
    description: 'Filtra pedidos con la mejor relación de ganancia por kilómetro.',
    preferences: DriverPreferences(
      maxTotalDistanceKm: 8.0,
      maxStoreDistanceKm: 4.0,
      minProfitPerKm: 1500.0,
      vehicleType: VehicleType.motorcycle,
      activeWorkModeId: 'max_profit',
    ),
  );

  static List<WorkMode> get defaultModes => [
        nearby,
        electric,
        normal,
        maxProfit,
      ];

  static WorkMode getById(String id) {
    return defaultModes.firstWhere(
      (m) => m.id == id,
      orElse: () => normal,
    );
  }
}
