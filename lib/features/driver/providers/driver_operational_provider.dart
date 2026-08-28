// lib/features/driver/providers/driver_operational_provider.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/services/battery_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../auth/providers/auth_notifier.dart';
import '../domain/driver_operational_state.dart';

class DriverOperationalNotifier extends StateNotifier<DriverOperationalState> {
  final Ref _ref;
  StreamSubscription<int>? _batterySubscription;
  StreamSubscription<bool>? _connectivitySubscription;
  Timer? _firestoreSyncDebounce;

  DriverOperationalNotifier(this._ref)
      : super(DriverOperationalState(lastUpdated: DateTime.now())) {
    _initListeners();
  }

  Future<void> _initListeners() async {
    // 1. Inicializar Batería
    await BatteryService.instance.init();
    final initialBattery = await BatteryService.instance.getBatteryLevel();
    _updateBattery(initialBattery);

    _batterySubscription = BatteryService.instance.batteryStream.listen((level) {
      _updateBattery(level);
    });

    // 2. Conectividad inicial
    final isOnline = await ConnectivityService.hasInternetConnection();
    state = state.copyWith(isOnline: isOnline);

    // 3. Revisar GPS inicial
    await checkLocationStatus();
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
    _connectivitySubscription?.cancel();
    _firestoreSyncDebounce?.cancel();
    super.dispose();
  }
}

final driverOperationalProvider =
    StateNotifierProvider<DriverOperationalNotifier, DriverOperationalState>(
        (ref) {
  return DriverOperationalNotifier(ref);
});
