// lib/features/driver/providers/driver_operational_provider.dart
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/battery_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../auth/providers/auth_notifier.dart';
import '../domain/driver_operational_state.dart';
import '../domain/driver_preferences.dart';
import '../domain/work_mode.dart';

class DriverOperationalNotifier extends StateNotifier<DriverOperationalState> {
  final Ref _ref;
  StreamSubscription<int>? _batterySubscription;
  Timer? _firestoreSyncDebounce;
  static const String _prefsKey = 'driver_preferences_v1';

  DriverOperationalNotifier(this._ref)
      : super(DriverOperationalState(lastUpdated: DateTime.now())) {
    _init();
  }

  Future<void> _init() async {
    // 1. Cargar preferencias guardadas
    await _loadSavedPreferences();

    // 2. Inicializar Batería
    await BatteryService.instance.init();
    final initialBattery = await BatteryService.instance.getBatteryLevel();
    _updateBattery(initialBattery);

    _batterySubscription = BatteryService.instance.batteryStream.listen((level) {
      _updateBattery(level);
    });

    // 3. Conectividad inicial
    final isOnline = await ConnectivityService.hasInternetConnection();
    state = state.copyWith(isOnline: isOnline);

    // 4. Revisar GPS inicial
    await checkLocationStatus();
  }

  Future<void> _loadSavedPreferences() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final jsonStr = sp.getString(_prefsKey);
      if (jsonStr != null) {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        final prefs = DriverPreferences.fromMap(map);
        state = state.copyWith(preferences: prefs);
      }
    } catch (e) {
      debugPrint('Error cargando preferencias de repartidor: $e');
    }
  }

  Future<void> _savePreferences() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(state.preferences.toMap());
      await sp.setString(_prefsKey, jsonStr);
    } catch (e) {
      debugPrint('Error guardando preferencias de repartidor: $e');
    }
  }

  void _updateBattery(int level) {
    final isLow = BatteryService.instance.isLowBattery(level);
    state = state.copyWith(
      batteryLevel: level,
      isBatteryLow: isLow,
    );
    _recalculateOperationalStatus();
  }

  Future<void> checkLocationStatus() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      final permission = await Geolocator.checkPermission();
      final hasLocation = serviceEnabled &&
          (permission == LocationPermission.always ||
              permission == LocationPermission.whileInUse);
      final hasBackground = permission == LocationPermission.always;

      state = state.copyWith(
        isLocationEnabled: hasLocation,
        isBackgroundLocationEnabled: hasBackground,
      );
      _recalculateOperationalStatus();
    } catch (_) {}
  }

  /// Conectar / Desconectar el repartidor
  void toggleConnection([bool? isConnected]) {
    final newConnected = isConnected ?? !state.preferences.isConnected;
    final updatedPrefs = state.preferences.copyWith(isConnected: newConnected);
    state = state.copyWith(preferences: updatedPrefs);
    _savePreferences();
    _recalculateOperationalStatus();
  }

  /// Activar / Desactivar Autoaceptación inteligente
  void toggleAutoAccept([bool? isAutoAccept]) {
    final newAutoAccept = isAutoAccept ?? !state.preferences.isAutoAcceptEnabled;
    final updatedPrefs = state.preferences.copyWith(isAutoAcceptEnabled: newAutoAccept);
    state = state.copyWith(preferences: updatedPrefs);
    _savePreferences();
    _syncToFirestoreDebounced();
  }

  /// Cambiar el Modo de Trabajo activo (Cercano, Eléctrico, Normal, Maximizar Ganancias)
  void setWorkMode(WorkMode mode) {
    final updatedPrefs = mode.preferences.copyWith(
      isConnected: state.preferences.isConnected,
      isAutoAcceptEnabled: state.preferences.isAutoAcceptEnabled,
      activeWorkModeId: mode.id,
    );
    state = state.copyWith(preferences: updatedPrefs);
    _savePreferences();
    _syncToFirestoreDebounced();
  }

  /// Actualizar preferencias detalladas
  void updatePreferences(DriverPreferences newPrefs) {
    state = state.copyWith(preferences: newPrefs);
    _savePreferences();
    _syncToFirestoreDebounced();
  }

  void setManualAvailability(bool isAvailable) {
    state = state.copyWith(isManualAvailable: isAvailable);
    _recalculateOperationalStatus();
  }

  void setActiveDelivery(String? orderId) {
    state = state.copyWith(
      hasActiveDelivery: orderId != null,
      activeOrderId: orderId,
    );
    _recalculateOperationalStatus();
  }

  void _recalculateOperationalStatus() {
    DriverOperationalStatus newStatus;

    if (!state.isOnline) {
      newStatus = DriverOperationalStatus.offline;
    } else if (!state.preferences.isConnected) {
      newStatus = DriverOperationalStatus.disconnected;
    } else if (state.hasActiveDelivery) {
      newStatus = DriverOperationalStatus.activeDelivery;
    } else if (state.isBatteryLow) {
      newStatus = DriverOperationalStatus.lowBattery;
    } else if (!state.isLocationEnabled) {
      newStatus = DriverOperationalStatus.locationUnavailable;
    } else if (!state.isManualAvailable) {
      newStatus = DriverOperationalStatus.paused;
    } else {
      newStatus = DriverOperationalStatus.available;
    }

    state = state.copyWith(
      status: newStatus,
      lastUpdated: DateTime.now(),
    );

    _syncToFirestoreDebounced();
  }

  void _syncToFirestoreDebounced() {
    _firestoreSyncDebounce?.cancel();
    _firestoreSyncDebounce = Timer(const Duration(seconds: 2), () async {
      try {
        final user = _ref.read(authNotifierProvider).user;
        if (user != null && user.id.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.id)
              .set(state.toFirestoreMap(), SetOptions(merge: true));
        }
      } catch (e) {
        debugPrint('Error sincronizando estado de repartidor a Firestore: $e');
      }
    });
  }

  @override
  void dispose() {
    _batterySubscription?.cancel();
    _firestoreSyncDebounce?.cancel();
    super.dispose();
  }
}

final driverOperationalProvider =
    StateNotifierProvider<DriverOperationalNotifier, DriverOperationalState>(
        (ref) {
  return DriverOperationalNotifier(ref);
});
