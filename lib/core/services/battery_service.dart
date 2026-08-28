// lib/core/services/battery_service.dart
import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';

/// Servicio centralizado para monitorear el estado y nivel de batería del repartidor.
class BatteryService {
  BatteryService._();
  static final BatteryService instance = BatteryService._();

  final Battery _battery = Battery();
  StreamSubscription<BatteryState>? _stateSubscription;
  final ValueNotifier<int> batteryLevelNotifier = ValueNotifier<int>(100);
  final ValueNotifier<BatteryState> batteryStateNotifier = ValueNotifier<BatteryState>(BatteryState.full);

  bool _initialized = false;
  static const int lowBatteryThreshold = 10;

  /// Inicializa la escucha de cambios de batería del sistema operativo.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final initialLevel = await _battery.batteryLevel;
      batteryLevelNotifier.value = initialLevel;

      _stateSubscription = _battery.onBatteryStateChanged.listen((state) async {
        batteryStateNotifier.value = state;
        try {
          final level = await _battery.batteryLevel;
          batteryLevelNotifier.value = level;
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('Error inicializando BatteryService: $e');
    }
  }

  /// Obtiene el nivel de batería actual (0 - 100).
  Future<int> getBatteryLevel() async {
    try {
      final level = await _battery.batteryLevel;
      batteryLevelNotifier.value = level;
      return level;
    } catch (e) {
      return batteryLevelNotifier.value;
    }
  }

  /// Indica si la batería está en estado crítico (< 10%).
  bool isLowBattery(int level) => level < lowBatteryThreshold;

  /// Stream reactivo de cambios de nivel de batería.
  Stream<int> get batteryStream => _battery.onBatteryStateChanged.asyncMap((_) async {
        return await getBatteryLevel();
      });

  void dispose() {
    _stateSubscription?.cancel();
    batteryLevelNotifier.dispose();
    batteryStateNotifier.dispose();
  }
}
