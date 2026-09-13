// lib/features/driver/presentation/screens/driver_dashboard_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/services/floating_bubble_service.dart';
import '../../../../core/services/maps_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/services/permission_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/utils/price_formatter.dart';
import '../../../../core/widgets/diabla_offline_view.dart';
import '../../../../core/widgets/navigation_app_picker.dart';
import '../../../../data/models/order_model.dart';
import '../../../../domain/entities/order_entity.dart';
import '../../../../domain/entities/order_status.dart';
import '../../../auth/providers/auth_notifier.dart';
import '../../../orders/presentation/screens/order_chat_screen.dart';
import '../../../orders/providers/orders_provider.dart';
import '../../../profile/presentation/widgets/privacy_policy_sheet.dart';
import '../../domain/driver_operational_state.dart';
import '../../domain/order_matching_engine.dart';
import '../../domain/work_mode.dart';
import '../../providers/driver_earnings_provider.dart';
import '../../providers/driver_operational_provider.dart';
import '../widgets/animated_driver_marker.dart';
import '../widgets/low_battery_modal.dart';
import '../widgets/work_mode_selector_sheet.dart';
import 'driver_permissions_screen.dart';
import 'driver_support_screen.dart';

class DriverDashboardScreen extends ConsumerStatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  ConsumerState<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends ConsumerState<DriverDashboardScreen>
    with WidgetsBindingObserver {
  int _currentNavIndex = 0; // 0: Pedidos, 1: Mapa/Ruta, 2: Ganancias, 3: Perfil
  int _ordersSubTabIndex = 0; // 0: Disponibles, 1: Mis Entregas (Historial)
  bool _isAvailable = true;

  // GPS real — stream de posición del repartidor
  StreamSubscription<Position>? _gpsStreamSubscription;
  bool _gpsActive = false;
  bool _arrivalAlertSpoken = false; // Evitar repetir el aviso de voz

  // Suscripción Firestore para mantener _activeOrder sincronizado con el admin
  StreamSubscription<DocumentSnapshot>? _activeOrderSub;

  // TTS para aviso de llegada
  final FlutterTts _flutterTts = FlutterTts();

  // Mapa y Ruta Inteligente
  final Completer<GoogleMapController> _mapControllerCompleter = Completer<GoogleMapController>();
  OrderEntity? _activeOrder;
  LatLng _driverCurrentPos = MapsService.defaultLocation;
  double _currentBearing = 0.0;
  BitmapDescriptor? _driverMarkerIcon;
  final Set<String> _autoAcceptedOrderIds = {};
  List<LatLng> _smartRoutePoints = [];
  bool _isLoadingRoute = false;
  double _remainingDistanceKm = 0.0;
  String _remainingTimeText = '';
  bool _isCameraFollowEnabled = true;
  String? _lastCalculatedOrderId;
  bool _headingToKitchen = false; // true = Ruta hacia la cocina a reclamar el pedido; false = Ruta al cliente

  // Datos editables del vehículo y del repartidor (vacíos al inicio, obligatorios)
  String _vehicleModel = '';
  String _vehiclePlate = '';
  String _vehicleColor = '';
  String _vehiclePlatePhoto = '';
  String _vehicleSoat = '';
  String _driverName = 'Repartidor La Diabla';
  String _driverPhone = '';
  String _driverPhoto = 'assets/images/diabloperfil.png';

  /// Determina si el repartidor tiene su perfil y vehículo en regla
  bool get _isVehicleRegistered =>
      _vehicleModel.trim().isNotEmpty && _vehiclePlate.trim().isNotEmpty && _vehicleColor.trim().isNotEmpty;

  /// Teléfono válido: necesario para que el cliente pueda contactarlo
  bool get _isDriverPhoneValid =>
      _driverPhone.trim().isNotEmpty &&
      _driverPhone.trim() != '3000000000' &&
      _driverPhone.trim().length >= 7;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadMarkerIcon();
    _loadDriverPreferences();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      ref.read(driverEarningsProvider.notifier).loadEarnings();
      // Solicitar permisos de ubicación (tiempo real + segundo plano) al repartidor con transición suave
      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          await PermissionService.requestDriverLocationPermissions(context);
          ref.read(driverOperationalProvider.notifier).checkLocationStatus();

          // Verificar y solicitar permiso de burbuja flotante ("Mostrar sobre otras apps")
          final hasOverlay = await FloatingBubbleService.instance.hasOverlayPermission();
          if (!hasOverlay) {
            await FloatingBubbleService.instance.requestOverlayPermission();
          }
        }
      }
      _centerMapOnRealGps();
    });
  }



  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Ocultar burbuja flotante al volver a primer plano
      FloatingBubbleService.instance.hideBubble();
      ref.read(driverOperationalProvider.notifier).checkLocationStatus();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Mostrar la burbuja flotante del repartidor al minimizar SOLO si está en turno activo
      final opState = ref.read(driverOperationalProvider);
      if (opState.isOnline) {
        FloatingBubbleService.instance.showBubble();
      }
    }
  }

  Future<void> _centerMapOnRealGps() async {
    final pos = await PermissionService.getCurrentPosition();
    if (pos != null && mounted) {
      final newPos = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _driverCurrentPos = newPos;
      });
      if (_mapControllerCompleter.isCompleted) {
        final ctrl = await _mapControllerCompleter.future;
        ctrl.animateCamera(CameraUpdate.newCameraPosition(
          CameraPosition(target: newPos, zoom: 16.0),
        ));
      }
    }
  }

  Future<void> _loadMarkerIcon() async {
    try {
      AnimatedDriverMarker.clearCache(); // forzar regeneración con nueva configuración
      final icon = await AnimatedDriverMarker.getDriverIcon();
      if (mounted) {
        setState(() {
          _driverMarkerIcon = icon;
        });
      }
    } catch (_) {}
  }

  Future<void> _autoAcceptOrder(OrderEntity order, MatchResult match) async {
    final shortId = order.id.length > 6 ? order.id.substring(order.id.length - 6).toUpperCase() : order.id;
    try {
      await _flutterTts.speak('¡Nuevo pedido autoaceptado de La Diabla!');
    } catch (_) {}

    await _takeAndAcceptOrder(order);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Text('🤖', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '¡Pedido #$shortId AUTOACEPTADO!\nRuta total: ${match.totalDistanceKm} km · Ganancia: +${PriceFormatter.formatSmart(match.deliveryFee)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _loadDriverPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final user = ref.read(authNotifierProvider).user;
    if (mounted) {
      // El nombre SIEMPRE viene de la cuenta Google/Auth.
      // Solo se usa el valor guardado en prefs si el usuario lo editó manualmente
      // (es decir, si existe en prefs Y es distinto al nombre de la cuenta).
      final authName = user?.name ?? '';
      final savedName = prefs.getString('driver_name');
      final defaultPlaceholders = ['Repartidor La Diabla', 'Usuario La Diabla', ''];

      // Si hay un nombre guardado que no coincide con el de Auth y no es un placeholder
      // genérico, se conserva (el usuario lo cambió a propósito).
      // En cualquier otro caso se usa el nombre de Auth y se limpia el guardado stale.
      String effectiveName;
      if (savedName != null &&
          savedName.isNotEmpty &&
          !defaultPlaceholders.contains(savedName) &&
          authName.isNotEmpty &&
          savedName == authName) {
        // Mismo nombre que Auth → OK
        effectiveName = savedName;
      } else if (savedName != null &&
          savedName.isNotEmpty &&
          !defaultPlaceholders.contains(savedName) &&
          authName.isEmpty) {
        // No hay nombre en Auth, usar el guardado
        effectiveName = savedName;
      } else {
        // En todos los demás casos: usar Auth y limpiar el prefs stale
        effectiveName = authName.isNotEmpty ? authName : 'Repartidor La Diabla';
        if (savedName != null && savedName != effectiveName) {
          await prefs.remove('driver_name');
        }
      }

      // El teléfono solo se muestra si fue ingresado manualmente en prefs
      // o si Firebase Auth lo provee (ej: login con número). Nunca mostramos placeholders.
      const phonePlaceholders = ['300 123 4567', '3000000000', ''];
      final savedPhone = prefs.getString('driver_phone') ?? '';
      final authPhone = user?.phone ?? '';
      final effectivePhone = (!phonePlaceholders.contains(savedPhone) && savedPhone.isNotEmpty)
          ? savedPhone
          : (!phonePlaceholders.contains(authPhone) && authPhone.isNotEmpty
              ? authPhone
              : '');
      // Si el teléfono guardado era un placeholder, limpiarlo
      if (phonePlaceholders.contains(savedPhone) && savedPhone.isNotEmpty) {
        await prefs.remove('driver_phone');
      }

      final savedVehicleModel = prefs.getString('driver_vehicle_model') ?? '';
      final savedVehiclePlate = prefs.getString('driver_vehicle_plate') ?? '';
      final savedVehicleColor = prefs.getString('driver_vehicle_color') ?? '';
      final savedVehiclePlatePhoto = prefs.getString('driver_vehicle_plate_photo') ?? '';
      final savedVehicleSoat = prefs.getString('driver_vehicle_soat') ?? '';

      // Limpiar datos dummy/quemados si quedaron en caché previa
      final dummyModels = ['Motocicleta 125cc', 'Moto Deportiva'];
      final dummyPlates = ['ABC-12D', 'DIABLA-01'];
      final effectiveVehicleModel = dummyModels.contains(savedVehicleModel) ? '' : savedVehicleModel;
      final effectiveVehiclePlate = dummyPlates.contains(savedVehiclePlate) ? '' : savedVehiclePlate;

      final savedDriverPhoto = prefs.getString('driver_photo');
      final fbPhoto = FirebaseAuth.instance.currentUser?.photoURL;
      final userPhoto = user?.photoUrl;
      final googlePhoto = (fbPhoto != null && fbPhoto.startsWith('http'))
          ? fbPhoto
          : ((userPhoto != null && userPhoto.startsWith('http')) ? userPhoto : '');
      
      String effectiveDriverPhoto;
      if (googlePhoto.isNotEmpty) {
        if (savedDriverPhoto == null || savedDriverPhoto.isEmpty || savedDriverPhoto.contains('diabloperfil') || savedDriverPhoto.startsWith('assets/')) {
          effectiveDriverPhoto = googlePhoto;
          prefs.setString('driver_photo', googlePhoto);
        } else {
          effectiveDriverPhoto = savedDriverPhoto;
        }
      } else if (savedDriverPhoto != null && savedDriverPhoto.isNotEmpty && !savedDriverPhoto.startsWith('assets/')) {
        effectiveDriverPhoto = savedDriverPhoto;
      } else if (userPhoto != null && userPhoto.isNotEmpty && !userPhoto.startsWith('assets/')) {
        effectiveDriverPhoto = userPhoto;
      } else {
        effectiveDriverPhoto = 'assets/images/diabloperfil.png';
      }

      setState(() {
        _vehicleModel = effectiveVehicleModel;
        _vehiclePlate = effectiveVehiclePlate;
        _vehicleColor = savedVehicleColor;
        _vehiclePlatePhoto = savedVehiclePlatePhoto;
        _vehicleSoat = savedVehicleSoat;
        _driverName = effectiveName;
        _driverPhone = effectivePhone;
        _driverPhoto = effectiveDriverPhoto;
      });

      // Si hay usuario autenticado, sincronizar datos con Firestore
      if (user != null && user.id.isNotEmpty) {
        // Asegurar que si inició sesión con Google, su foto de Google quede registrada en users/{id}
        if (googlePhoto.isNotEmpty) {
          FirebaseFirestore.instance.collection('users').doc(user.id).set({
            'photoUrl': googlePhoto,
            'name': effectiveName,
          }, SetOptions(merge: true)).ignore();
        }

        FirebaseFirestore.instance.collection('users').doc(user.id).get().then((doc) {
          if (doc.exists && mounted) {
            final d = doc.data();
            if (d != null) {
              final remoteModel = d['vehicleModel'] as String? ?? '';
              final remotePlate = d['vehiclePlate'] as String? ?? '';
              final remoteColor = d['vehicleColor'] as String? ?? '';
              final remotePhoto = d['vehiclePlatePhotoUrl'] as String? ?? '';
              final remotePhone = d['phone'] as String? ?? '';
              final remoteDriverPhoto = d['photoUrl'] as String? ?? '';

              setState(() {
                if (_vehicleModel.isEmpty && remoteModel.isNotEmpty) _vehicleModel = remoteModel;
                if (_vehiclePlate.isEmpty && remotePlate.isNotEmpty) _vehiclePlate = remotePlate;
                if (_vehicleColor.isEmpty && remoteColor.isNotEmpty) _vehicleColor = remoteColor;
                if (_vehiclePlatePhoto.isEmpty && remotePhoto.isNotEmpty) _vehiclePlatePhoto = remotePhoto;
                if (_driverPhone.isEmpty && remotePhone.isNotEmpty) _driverPhone = remotePhone;
                if (remoteDriverPhoto.isNotEmpty && !remoteDriverPhoto.startsWith('assets/')) {
                  _driverPhoto = remoteDriverPhoto;
                  prefs.setString('driver_photo', remoteDriverPhoto);
                } else if (_driverPhoto.isNotEmpty && !_driverPhoto.startsWith('assets/')) {
                  // Si Firestore no la tenía, sincronizar nuestra foto real
                  FirebaseFirestore.instance.collection('users').doc(user.id).set({
                    'photoUrl': _driverPhoto,
                    'name': effectiveName,
                  }, SetOptions(merge: true)).ignore();
                }
              });
            }
          }
        }).catchError((_) {});
      }
    }
  }

  /// Suscribe el listener de Firestore para mantener _activeOrder en tiempo real.
  /// Esta es la ÚNICA definición canónica — siempre actualiza desde Firestore,
  /// incluyendo cambios de estado hechos por el admin.
  void _subscribeToActiveOrder(String orderId) {
    _activeOrderSub?.cancel();
    _activeOrderSub = FirebaseFirestore.instance
        .collection('orders')
        .doc(orderId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) return;
      try {
        final updated = OrderModel.fromFirestore(snapshot);
        final data = snapshot.data();
        final phase = data?['driverPhase'] as String?;
        if (mounted) {
          setState(() {
            _activeOrder = updated;
            if (phase == 'heading_to_kitchen') {
              _headingToKitchen = true;
            } else if (phase == 'heading_to_client' || updated.status == OrderStatus.onTheWay) {
              _headingToKitchen = false;
            }
          });
        }
      } catch (_) {}
    });
  }

  void _unsubscribeFromActiveOrder() {
    _activeOrderSub?.cancel();
    _activeOrderSub = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FloatingBubbleService.instance.hideBubble();
    _gpsStreamSubscription?.cancel();
    _activeOrderSub?.cancel();
    _flutterTts.stop();
    super.dispose();
  }

  /// Solicita permiso de ubicación y arranca el stream GPS real hacia Firestore.
  /// [destLat]/[destLng]: coordenadas del cliente para calcular proximidad.
  Future<void> _startGpsBroadcast(OrderEntity order, {double? destLat, double? destLng}) async {
    // Solicitar permiso al repartidor si no lo tiene
    final hasPermission = await PermissionService.requestLocationPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Necesitas activar la ubicación para iniciar la ruta.'),
            backgroundColor: Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // Cancelar stream previo si existía
    await _gpsStreamSubscription?.cancel();
    _arrivalAlertSpoken = false;

    if (mounted) setState(() => _gpsActive = true);

    // Configurar TTS en español
    await _flutterTts.setLanguage('es-CO');
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);

    _gpsStreamSubscription = PermissionService.getPositionStream().listen(
      (Position position) async {
        final newPos = LatLng(position.latitude, position.longitude);
        double bearing = position.heading;
        if (bearing <= 0) {
          bearing = MapsService.calculateBearing(_driverCurrentPos, newPos);
        }

        _driverCurrentPos = newPos;
        if (bearing > 0) _currentBearing = bearing;

        // Transmitir coordenadas reales a Firestore cada actualización
        try {
          await FirebaseFirestore.instance
              .collection('orders')
              .doc(order.id)
              .update({
            'driverLatitude': position.latitude,
            'driverLongitude': position.longitude,
            'driverHeading': _currentBearing,
            'driverSpeed': position.speed,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } catch (_) {}

        // Actualizar distancia y tiempo restante en vivo para el HUD de navegación
        if (destLat != null && destLng != null) {
          final distKm = MapsService.calculateDistanceKm(newPos, LatLng(destLat, destLng));
          final timeText = MapsService.estimateDeliveryTime(distKm);
          _remainingDistanceKm = distKm;
          _remainingTimeText = timeText;
        }

        // Solo activar setState si el repartidor está en la pestaña de Mapa GPS (_currentNavIndex == 1)
        // Esto previene que las pestañas de Pedidos, Ganancias y Perfil parpadeen continuamente.
        if (mounted && _currentNavIndex == 1) {
          setState(() {});
        }

        // Seguimiento de cámara en vivo estilo navegación GPS si está habilitado
        if (_isCameraFollowEnabled && _mapControllerCompleter.isCompleted && _currentNavIndex == 1) {
          try {
            final ctrl = await _mapControllerCompleter.future;
            ctrl.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: newPos,
                  zoom: 17.5,
                  tilt: 45.0,
                  bearing: _currentBearing > 0 ? _currentBearing : 0.0,
                ),
              ),
            );
          } catch (_) {}
        }

        // Calcular distancia al cliente y emitir aviso de voz al llegar a < 100m
        if (destLat != null && destLng != null && !_arrivalAlertSpoken) {
          final distanceMeters = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            destLat,
            destLng,
          );
          if (distanceMeters < 100) {
            _arrivalAlertSpoken = true;
            await _flutterTts.speak(
              '¡Atención! Has llegado a la ubicación del cliente. Por favor marca el pedido como entregado y toma la foto de comprobante.',
            );
          }
        }
      },
      onError: (e) {
        debugPrint('GPS stream error: $e');
        if (mounted) setState(() => _gpsActive = false);
      },
      cancelOnError: false,
    );
  }

  /// Detiene la transmisión de GPS.
  Future<void> _stopGpsBroadcast() async {
    await _gpsStreamSubscription?.cancel();
    _gpsStreamSubscription = null;
    if (mounted) setState(() => _gpsActive = false);
  }

  /// Calcula la ruta óptima por calles reales usando Directions API
  Future<void> _calculateSmartRoute(OrderEntity order) async {
    if (_isLoadingRoute) return;
    _lastCalculatedOrderId = order.id;

    final kitchenPos = MapsService.defaultLocation;
    final custLat = order.address?.latitude ?? order.latitude ?? 7.092758;
    final custLng = order.address?.longitude ?? order.longitude ?? -73.142590;
    final custPos = LatLng(custLat, custLng);

    // Si está en fase de ir a la cocina a reclamar el pedido: destino = cocina
    // Si ya reclamó el pedido o está en camino: destino = cliente
    final targetPos = _headingToKitchen ? kitchenPos : custPos;

    setState(() => _isLoadingRoute = true);

    try {
      final routeDetails = await MapsService().getRouteDetails(_driverCurrentPos, targetPos);
      final dist = routeDetails.distanceKm;
      final timeEst = '${routeDetails.durationMinutes} - ${routeDetails.durationMinutes + 6} min';

      if (mounted) {
        setState(() {
          _smartRoutePoints = routeDetails.points;
          _remainingDistanceKm = dist;
          _remainingTimeText = timeEst;
          _isLoadingRoute = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _smartRoutePoints = [_driverCurrentPos, targetPos];
          _isLoadingRoute = false;
        });
      }
    }
  }

  /// Toma el pedido (estado -> assigned) y cambia al mapa para iniciar el viaje.
  Future<void> _takeAndAcceptOrder(OrderEntity order) async {
    try {
      final user = ref.read(authNotifierProvider).user;
      final driverId = user?.id ?? 'driver_01';
      final effectiveDriverName = _driverName.isNotEmpty ? _driverName : (user?.name ?? 'Repartidor Diabla');

      final fbPhoto = FirebaseAuth.instance.currentUser?.photoURL;
      final uPhoto = user?.photoUrl;
      final effectiveDriverPhoto = (_driverPhoto.isNotEmpty && !_driverPhoto.startsWith('assets/'))
          ? _driverPhoto
          : ((uPhoto != null && uPhoto.isNotEmpty && !uPhoto.startsWith('assets/'))
              ? uPhoto
              : (fbPhoto ?? _driverPhoto));

      // Estado: assigned (repartidor asignado, siempre se dirige primero a la cocina central a reclamar el pedido)
      await FirebaseFirestore.instance.collection('orders').doc(order.id).update({
        'status': OrderStatus.assigned.name,
        'driverId': driverId,
        'driverName': effectiveDriverName,
        'driverPhone': _driverPhone,
        'driverPhotoUrl': effectiveDriverPhoto,
        'driverVehicleModel': _vehicleModel,
        'driverVehiclePlate': _vehiclePlate,
        'driverVehicleColor': _vehicleColor,
        if (_vehiclePlatePhoto.isNotEmpty) 'driverVehiclePlatePhotoUrl': _vehiclePlatePhoto,
        'driverPhase': 'heading_to_kitchen',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Notificar al cliente que ya hay repartidor asignado
      NotificationService().saveOrderNotification(
        userId: order.userId,
        orderId: order.id,
        title: '🛵 ¡Repartidor asignado!',
        body: 'Tu repartidor ya recibió tu pedido y pronto saldrá de La Diabla 🔥',
        emoji: '🛵',
        status: OrderStatus.assigned.name,
      );

      setState(() {
        _headingToKitchen = true;
        _currentNavIndex = 1; // Ir a pestaña Mapa
      });

      // Suscribir a cambios en tiempo real del pedido (sincroniza con el admin)
      _subscribeToActiveOrder(order.id);

      ref.read(driverOperationalProvider.notifier).setActiveDelivery(order.id);
      _calculateSmartRoute(order);

      if (mounted) {
        final shortCode = order.id.length > 6 ? order.id.substring(order.id.length - 6).toUpperCase() : order.id;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🛵 Pedido #$shortCode aceptado. Dirígete a la Cocina Central La Diabla para reclamar los platillos.',
            ),
            backgroundColor: const Color(0xFF0369A1),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al tomar el pedido: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Permite al repartidor navegar hacia la Cocina Central en In-App, Waze o Google Maps
  Future<void> _startTripToKitchen(OrderEntity order) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kitchenPos = MapsService.defaultLocation;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1712) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 80 : 30),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD97706).withAlpha(25),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.restaurant_rounded, color: Color(0xFFD97706), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ruta a Cocina Central 🍳',
                        style: TextStyle(
                          fontFamily: AppTypography.displayFamily,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1C1C1C),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Cl. 59 # 39W-24, Bucaramanga',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // In-App
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: isDark ? AppColors.dividerDark : Colors.grey.shade300)),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFDC2626).withAlpha(20), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.two_wheeler_rounded, color: Color(0xFFDC2626)),
              ),
              title: const Text('Navegar en App La Diabla', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
              subtitle: const Text('Ruta inteligente en pantalla con velocímetro', style: TextStyle(fontSize: 11.5)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _headingToKitchen = true);
                _calculateSmartRoute(order);
              },
            ),
            const SizedBox(height: 8),

            // Waze
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: isDark ? AppColors.dividerDark : Colors.grey.shade300)),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFF00A3DA).withAlpha(20), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.directions_car_rounded, color: Color(0xFF00A3DA)),
              ),
              title: const Text('Waze GPS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
              subtitle: const Text('Abrir ruta hacia la cocina en Waze', style: TextStyle(fontSize: 11.5)),
              trailing: const Icon(Icons.open_in_new_rounded, size: 16),
              onTap: () {
                Navigator.pop(ctx);
                MapsService.openInWaze(kitchenPos.latitude, kitchenPos.longitude);
              },
            ),
            const SizedBox(height: 8),

            // Google Maps
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: isDark ? AppColors.dividerDark : Colors.grey.shade300)),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFF10B981).withAlpha(20), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.map_rounded, color: Color(0xFF10B981)),
              ),
              title: const Text('Google Maps', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
              subtitle: const Text('Abrir ruta hacia la cocina en Google Maps', style: TextStyle(fontSize: 11.5)),
              trailing: const Icon(Icons.open_in_new_rounded, size: 16),
              onTap: () {
                Navigator.pop(ctx);
                MapsService.openInGoogleMaps(kitchenPos.latitude, kitchenPos.longitude, label: 'Cocina Central La Diabla');
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Muestra selector para elegir cómo navegar la ruta: In-App, Waze o Google Maps
  Future<void> _startTripWithGps(OrderEntity order) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shortId = order.id.length > 6 ? order.id.substring(order.id.length - 6).toUpperCase() : order.id;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1712) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 80 : 30),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626).withAlpha(25),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.navigation_rounded, color: Color(0xFFDC2626), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Comenzar Ruta #$shortId 🛵',
                        style: TextStyle(
                          fontFamily: AppTypography.displayFamily,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1C1C1C),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Elige cómo prefieres seguir el recorrido:',
                        style: TextStyle(
                          fontFamily: AppTypography.bodyFamily,
                          fontSize: 12.5,
                          color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Opción 1: Navegar en la App La Diabla (Ruta Inteligente In-App)
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                Navigator.of(ctx).pop();
                _executeStartTrip(order, mode: 'in_app');
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C1610) : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFDC2626), width: 1.5),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFDC2626), Color(0xFFB91C1C)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Icon(Icons.two_wheeler_rounded, color: Colors.white, size: 26),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Navegar en App La Diabla',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14.5,
                                  color: isDark ? Colors.white : const Color(0xFF1C1C1C),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDC2626),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'RECOMENDADO',
                                  style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Ruta calle por calle, velocímetro, voz TTS y panel en vivo sin salir de la app',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Color(0xFFDC2626)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Opción 2: Waze (Prioridad de Repartidores)
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                Navigator.of(ctx).pop();
                _executeStartTrip(order, mode: 'waze');
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF141F2B) : const Color(0xFFF0F9FF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF00A3DA).withAlpha(120)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFF33CCFF).withAlpha(35),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Image.network(
                          'https://upload.wikimedia.org/wikipedia/commons/thumb/7/7b/Waze_icon.svg/120px-Waze_icon.svg.png',
                          width: 28,
                          height: 28,
                          errorBuilder: (_, _, _) => const Icon(Icons.directions_car_rounded, color: Color(0xFF00A3DA), size: 26),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Waze GPS',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                              color: isDark ? Colors.white : const Color(0xFF1C1C1C),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Alertas de tráfico en vivo, cámaras y policía en tiempo real',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.open_in_new_rounded, size: 18, color: Color(0xFF00A3DA)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Opción 3: Google Maps App Nativa
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                Navigator.of(ctx).pop();
                _executeStartTrip(order, mode: 'maps');
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF161F1A) : const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF10B981).withAlpha(120)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withAlpha(30),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Icon(Icons.map_rounded, color: Color(0xFF10B981), size: 26),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Google Maps (App)',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                              color: isDark ? Colors.white : const Color(0xFF1C1C1C),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Abre directo en la app de Maps (no en el navegador)',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.open_in_new_rounded, size: 18, color: Color(0xFF10B981)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Ejecuta el arranque del viaje según el modo seleccionado
  Future<void> _executeStartTrip(OrderEntity order, {required String mode}) async {
    try {
      final destLat = order.address?.latitude ?? order.latitude;
      final destLng = order.address?.longitude ?? order.longitude;

      await FirebaseFirestore.instance.collection('orders').doc(order.id).update({
        'status': OrderStatus.onTheWay.firestoreValue, // 'on_the_way'
        'driverPhase': 'heading_to_client',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      NotificationService().saveOrderNotification(
        userId: order.userId,
        orderId: order.id,
        title: '🛵 ¡El repartidor va en camino!',
        body: 'Tu comida de La Diabla está en ruta hacia tu puerta 🔥',
        emoji: '🛵',
        status: OrderStatus.onTheWay.firestoreValue,
      );

      setState(() {
        // No sobreescribir _activeOrder — el stream de Firestore actualizará
        // el estado en tiempo real (incluyendo driverId/driverName del admin).
        _currentNavIndex = 1; // Pestaña del Mapa
        _isCameraFollowEnabled = true;
      });

      ref.read(driverOperationalProvider.notifier).setActiveDelivery(order.id);

      await _startGpsBroadcast(
        order,
        destLat: destLat,
        destLng: destLng,
      );

      // Calcular la ruta inteligente de calles para la vista in-app
      await _calculateSmartRoute(order);

      // Centrar e inclinar la cámara en perspectiva de conducción 3D
      if (_mapControllerCompleter.isCompleted) {
        final ctrl = await _mapControllerCompleter.future;
        ctrl.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: _driverCurrentPos,
              zoom: 17.5,
              tilt: 45.0,
              bearing: _currentBearing > 0 ? _currentBearing : 0.0,
            ),
          ),
        );
      }

      if (mode == 'in_app') {
        try {
          await _flutterTts.speak('Ruta iniciada. Conduce con precaución hacia el destino del cliente.');
        } catch (_) {}
      } else if (mode == 'waze' && destLat != null && destLng != null) {
        await MapsService.openInWaze(destLat, destLng);
      } else if (mode == 'maps' && destLat != null && destLng != null) {
        await MapsService.openInGoogleMaps(destLat, destLng, label: 'Entrega La Diabla');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mode == 'in_app'
                  ? '🛵 ¡Navegación iniciada en app! Sigue la ruta en pantalla.'
                  : '🛵 ¡Viaje iniciado! Abriendo navegador GPS externo...',
            ),
            backgroundColor: const Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al iniciar viaje: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _markOrderAsDelivered(OrderEntity order) async {
    File? proofImage;
    bool isUploading = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final shortId = order.id.length > 6 ? order.id.substring(order.id.length - 6).toUpperCase() : order.id;
          final bool canFinish = proofImage != null && !isUploading;

          Future<void> pickProofImage(ImageSource source) async {
            try {
              final picker = ImagePicker();
              final picked = await picker.pickImage(
                source: source,
                maxWidth: 1200,
                maxHeight: 1200,
                imageQuality: 80,
              );
              if (picked != null) {
                setModalState(() {
                  proofImage = File(picked.path);
                });
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error al capturar imagen: $e')),
                );
              }
            }
          }

          Future<void> submitDelivery() async {
            if (proofImage == null) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('⚠️ Debes adjuntar la foto del comprobante de entrega obligatoriamente.'),
                    backgroundColor: Color(0xFFDC2626),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
              return;
            }

            setModalState(() => isUploading = true);
            try {
              String proofUrl = '';
              try {
                proofUrl = await StorageService().uploadDeliveryProof(
                  orderId: order.id,
                  file: proofImage!,
                ).timeout(const Duration(seconds: 25));
              } catch (e) {
                debugPrint('⚠️ Upload de comprobante a Storage falló, usando Base64: $e');
                final bytes = await proofImage!.readAsBytes();
                proofUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
              }

              final driverId = ref.read(authNotifierProvider).user?.id ?? 'driver_01';
              final fee = order.deliveryFee > 0 ? order.deliveryFee : 7500.0;

              final user = ref.read(authNotifierProvider).user;
              final fbPhoto = FirebaseAuth.instance.currentUser?.photoURL;
              final uPhoto = user?.photoUrl;
              final effectiveDriverPhoto = (_driverPhoto.isNotEmpty && !_driverPhoto.startsWith('assets/'))
                  ? _driverPhoto
                  : ((uPhoto != null && uPhoto.isNotEmpty && !uPhoto.startsWith('assets/'))
                      ? uPhoto
                      : (fbPhoto ?? _driverPhoto));

              final updateData = <String, dynamic>{
                'status': OrderStatus.delivered.name,
                'driverId': driverId,
                'driverName': _driverName,
                'driverPhone': _driverPhone,
                'driverPhotoUrl': effectiveDriverPhoto,
                'driverVehicleModel': _vehicleModel,
                'driverVehiclePlate': _vehiclePlate,
                'driverVehicleColor': _vehicleColor,
                if (_vehiclePlatePhoto.isNotEmpty) 'driverVehiclePlatePhotoUrl': _vehiclePlatePhoto,
                'deliveryProofUrl': proofUrl,
                'deliveredAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
              };

              await FirebaseFirestore.instance.collection('orders').doc(order.id).update(updateData);

              // Registrar ganancia en Firestore para el repartidor
              try {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(driverId)
                    .collection('earnings')
                    .doc(order.id)
                    .set({
                  'orderId': order.id,
                  'amount': fee,
                  'date': FieldValue.serverTimestamp(),
                  'customerAddress': order.address?.formattedAddress ?? '',
                  'orderTotal': order.total,
                }, SetOptions(merge: true));

                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(driverId)
                    .collection('earnings')
                    .doc('__summary__')
                    .set({
                  'totalEarned': FieldValue.increment(fee),
                  'totalDeliveries': FieldValue.increment(1),
                  'lastUpdated': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));

                ref.read(driverEarningsProvider.notifier).loadEarnings();
              } catch (_) {}

              // Guardar notificación para el cliente en tiempo real
              NotificationService().saveOrderNotification(
                userId: order.userId,
                orderId: order.id,
                title: '✅ ¡Pedido entregado! ¡Buen provecho!',
                body: '¿Qué tal estuvo tu experiencia? Califica al repartidor y la comida 🌮⭐',
                emoji: '✅',
                status: OrderStatus.delivered.name,
              );

              await _stopGpsBroadcast();

              if (ctx.mounted) {
                Navigator.pop(ctx);
              }

              if (mounted) {
                setState(() {
                  _activeOrder = null;
                });
                _unsubscribeFromActiveOrder();
                ref.read(driverOperationalProvider.notifier).setActiveDelivery(null);

                showDialog(
                  context: context,
                  builder: (dialogCtx) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: const Row(
                      children: [
                        Text('🎉', style: TextStyle(fontSize: 26)),
                        SizedBox(width: 8),
                        Text('¡ENTREGA EXITOSA!'),
                      ],
                    ),
                    content: Text(
                      'Has completado la entrega de la orden #$shortId.\n\nGanancia acreditada a tu cuenta: +${PriceFormatter.formatSmart(fee)} COP 💵',
                    ),
                    actions: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          Navigator.pop(dialogCtx);
                          setState(() => _currentNavIndex = 2); // Ver panel de ganancias
                        },
                        child: const Text('Ver Mis Ganancias 💵'),
                      ),
                    ],
                  ),
                );
              }
            } catch (e) {
              setModalState(() => isUploading = false);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error al marcar entrega: $e'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            }
          }

          return Container(
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1712) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.camera_alt_rounded, color: Color(0xFFDC2626), size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'Confirmar Entrega #$shortId',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Toma o adjunta una foto como comprobante de entrega del pedido:',
                    style: TextStyle(fontSize: 13, color: isDark ? AppColors.textMutedDark : Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  if (proofImage != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        alignment: Alignment.topRight,
                        children: [
                          Image.file(
                            proofImage!,
                            height: 180,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                          IconButton(
                            icon: const CircleAvatar(
                              backgroundColor: Colors.black54,
                              child: Icon(Icons.close, color: Colors.white, size: 18),
                            ),
                            onPressed: () => setModalState(() => proofImage = null),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.camera_alt_rounded, color: Color(0xFFDC2626)),
                            label: const Text('Tomar Foto 📸', style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.bold)),
                            onPressed: isUploading ? null : () => pickProofImage(ImageSource.camera),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.photo_library_rounded, color: Color(0xFF0EA5E9)),
                            label: const Text('Galería 🖼️', style: TextStyle(color: Color(0xFF0EA5E9), fontWeight: FontWeight.bold)),
                            onPressed: isUploading ? null : () => pickProofImage(ImageSource.gallery),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canFinish ? const Color(0xFF16A34A) : (isDark ? Colors.white12 : Colors.grey.shade400),
                      foregroundColor: canFinish ? Colors.white : (isDark ? Colors.white38 : Colors.black45),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: canFinish ? 2 : 0,
                    ),
                    icon: isUploading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(canFinish ? Icons.check_circle_rounded : Icons.photo_camera_rounded, size: 20),
                    label: Text(
                      isUploading
                          ? 'Finalizando entrega...'
                          : (proofImage == null
                              ? '📸 ADJUNTA FOTO DE ENTREGA PRIMERO'
                              : 'FINALIZAR ENTREGA ✅'),
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                    ),
                    onPressed: canFinish ? submitDelivery : null,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openExternalMap(double lat, double lng, {String? address}) async {
    NavigationAppPicker.show(
      context,
      latitude: lat,
      longitude: lng,
      destinationName: 'Entrega de Pedido La Diabla',
      addressText: address,
    );
  }

  /// Muestra la foto de perfil en pantalla completa con fondo oscuro y opción de cerrar.
  void _showProfilePhotoDialog(BuildContext context, String photoUrl, String name) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Center(
                child: Hero(
                  tag: 'profile_photo_$photoUrl',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: InteractiveViewer(
                      child: photoUrl.startsWith('data:image/')
                          ? Image.memory(
                              base64Decode(photoUrl.split(',').last),
                              fit: BoxFit.contain,
                              width: MediaQuery.of(ctx).size.width * 0.88,
                              errorBuilder: (_, e, s) => const Icon(
                                Icons.person_rounded,
                                color: Colors.white54,
                                size: 80,
                              ),
                            )
                          : Image.network(
                              photoUrl,
                              fit: BoxFit.contain,
                              width: MediaQuery.of(ctx).size.width * 0.88,
                              errorBuilder: (_, e, s) => const Icon(
                                Icons.person_rounded,
                                color: Colors.white54,
                                size: 80,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.of(ctx).padding.top + 12,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.of(ctx).padding.top + 8,
                right: 16,
                child: IconButton(
                  icon: const CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: Icon(Icons.close_rounded, color: Colors.white, size: 20),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _callCustomer(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _whatsappCustomer(String phone, String orderId) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    final shortId = orderId.length > 6 ? orderId.substring(orderId.length - 6).toUpperCase() : orderId;
    final msg = Uri.encodeComponent('¡Hola! Soy tu repartidor de La Diabla 🛵. Voy en camino con tu pedido #$shortId caliente y listo.');
    final waUri = Uri.parse('whatsapp://send?phone=57$cleanPhone&text=$msg');
    final webUri = Uri.parse('https://wa.me/57$cleanPhone?text=$msg');

    if (await canLaunchUrl(waUri)) {
      await launchUrl(waUri, mode: LaunchMode.externalApplication);
    } else if (await canLaunchUrl(webUri)) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = ref.watch(authNotifierProvider).user;
    final opState = ref.watch(driverOperationalProvider);

    // Escuchar cambios de batería para mostrar modal reactivo (anti-spam)
    ref.listen<DriverOperationalState>(driverOperationalProvider, (prev, next) {
      if (next.isBatteryLow && (prev == null || !prev.isBatteryLow)) {
        LowBatteryModal.showIfNeeded(context, next.batteryLevel);
      }
    });

    // Escuchar cambios de autenticación para sincronizar inmediatamente la foto de Google si llega al loguearse
    ref.listen<AuthState>(authNotifierProvider, (prev, next) {
      final nextUser = next.user;
      final fbPhoto = FirebaseAuth.instance.currentUser?.photoURL;
      final newPhoto = (fbPhoto != null && fbPhoto.startsWith('http'))
          ? fbPhoto
          : ((nextUser?.photoUrl != null && nextUser!.photoUrl!.startsWith('http')) ? nextUser.photoUrl! : '');
      if (newPhoto.isNotEmpty && (_driverPhoto.startsWith('assets/') || _driverPhoto.isEmpty)) {
        setState(() {
          _driverPhoto = newPhoto;
        });
        SharedPreferences.getInstance().then((p) => p.setString('driver_photo', newPhoto));
      }
    });

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1E1712) : const Color(0xFFFAF7F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFDC2626),
        foregroundColor: Colors.white,
        title: Row(
          children: [
            Image.asset(
              'assets/images/logo.png',
              width: 34,
              height: 34,
              errorBuilder: (_, _, _) => const Icon(Icons.two_wheeler_rounded, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PANEL REPARTIDOR',
                  style: TextStyle(
                    fontFamily: AppTypography.displayFamily,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  user?.name ?? 'Repartidor Activo',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Badge Nivel de Batería
          Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: opState.isBatteryLow
                  ? const Color(0xFF991B1B)
                  : Colors.black.withAlpha(50),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: opState.isBatteryLow
                    ? const Color(0xFFFCA5A5)
                    : Colors.white24,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  opState.isBatteryLow
                      ? Icons.battery_alert_rounded
                      : Icons.battery_charging_full_rounded,
                  color: opState.isBatteryLow
                      ? const Color(0xFFFCA5A5)
                      : Colors.white,
                  size: 13,
                ),
                const SizedBox(width: 3),
                Text(
                  '${opState.batteryLevel}%',
                  style: TextStyle(
                    color: opState.isBatteryLow
                        ? const Color(0xFFFCA5A5)
                        : Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Badge Estado Operativo
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: opState.isBatteryLow
                  ? const Color(0xFFDC2626)
                  : (_gpsActive
                      ? const Color(0xFF0EA5E9)
                      : (opState.canReceiveOrders
                          ? const Color(0xFF16A34A)
                          : Colors.grey.shade700)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  opState.isBatteryLow
                      ? Icons.battery_alert_rounded
                      : (_gpsActive
                          ? Icons.gps_fixed_rounded
                          : (opState.canReceiveOrders
                              ? Icons.check_circle_rounded
                              : Icons.pause_circle_filled_rounded)),
                  color: Colors.white,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  opState.isBatteryLow
                      ? 'BATERÍA BAJA'
                      : (_gpsActive
                          ? 'GPS ACTIVO'
                          : (opState.canReceiveOrders
                              ? 'DISPONIBLE'
                              : 'NO DISPONIBLE')),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentNavIndex,
        children: [
          // Pestaña 0: Despacho / Pedidos Disponibles
          _buildDispatchTab(isDark),

          // Pestaña 1: Ruta Inteligente & Mapa GPS
          _buildMapRouteTab(isDark),

          // Pestaña 2: Ganancias & Rendimiento
          _buildEarningsTab(isDark),

          // Pestaña 3: Perfil Repartidor
          _buildDriverProfileTab(isDark),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C1B14) : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 50 : 15),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentNavIndex,
          onTap: (idx) => setState(() => _currentNavIndex = idx),
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.transparent,
          selectedItemColor: const Color(0xFFDC2626),
          unselectedItemColor: isDark ? Colors.white60 : Colors.grey.shade600,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
          unselectedLabelStyle: const TextStyle(fontSize: 10.5),
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_rounded),
              activeIcon: Icon(Icons.receipt_long_rounded, color: Color(0xFFDC2626)),
              label: 'Pedidos',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.map_rounded),
              activeIcon: Icon(Icons.map_rounded, color: Color(0xFFDC2626)),
              label: 'Ruta GPS',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.monetization_on_rounded),
              activeIcon: Icon(Icons.monetization_on_rounded, color: Color(0xFFDC2626)),
              label: 'Ganancias',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_pin_rounded),
              activeIcon: Icon(Icons.person_pin_rounded, color: Color(0xFFDC2626)),
              label: 'Mi Perfil',
            ),
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════════
  // PESTAÑA 0: DESPACHO / PEDIDOS DISPONIBLES EN COCINA
  // ═════════════════════════════════════════════════════════════════════════════
  Widget _buildTopControlHud(DriverOperationalState opState, bool isDark) {
    final prefs = opState.preferences;
    final workMode = WorkMode.getById(prefs.activeWorkModeId);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C1B14) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 10),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 🟢 Conectado / 🔴 Desconectado
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: prefs.isConnected ? const Color(0xFF16A34A) : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    prefs.isConnected ? 'CONECTADO' : 'DESCONECTADO',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      color: prefs.isConnected ? const Color(0xFF16A34A) : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Transform.scale(
                    scale: 0.75,
                    child: Switch(
                      value: prefs.isConnected,
                      activeThumbColor: const Color(0xFF16A34A),
                      onChanged: (val) {
                        ref.read(driverOperationalProvider.notifier).toggleConnection(val);
                      },
                    ),
                  ),
                ],
              ),

              // 🤖 Autoaceptación Switch
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      'AUTOACEPTAR 🤖',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        color: prefs.isAutoAcceptEnabled ? const Color(0xFF0284C7) : Colors.grey,
                      ),
                    ),
                  ),
                  Transform.scale(
                    scale: 0.75,
                    child: Switch(
                      value: prefs.isAutoAcceptEnabled,
                      activeThumbColor: const Color(0xFF0284C7),
                      onChanged: (val) {
                        ref.read(driverOperationalProvider.notifier).toggleAutoAccept(val);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Chip Modo de Trabajo
              GestureDetector(
                onTap: () => WorkModeSelectorSheet.show(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626).withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFDC2626), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(workMode.emoji, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      Text(
                        workMode.name,
                        style: const TextStyle(
                          color: Color(0xFFDC2626),
                          fontWeight: FontWeight.w900,
                          fontSize: 11.5,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFFDC2626), size: 18),
                    ],
                  ),
                ),
              ),

              // Métricas de Filtros
              Flexible(
                child: Text(
                  'Máx: ${prefs.maxTotalDistanceKm.toStringAsFixed(0)} km · ${prefs.vehicleType.displayName}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.textMutedDark : Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDispatchTab(bool isDark) {
    final allOrdersAsync = ref.watch(allPendingOrdersStreamProvider);
    final opState = ref.watch(driverOperationalProvider);

    return allOrdersAsync.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFDC2626))),
      error: (err, _) => DiablaOfflineView(
        title: 'Ups, algo salió mal.',
        subtitle: 'No pudimos conectar con el servidor de pedidos. Comprueba tu conexión a internet.',
        onRetry: () => ref.invalidate(allPendingOrdersStreamProvider),
      ),
      data: (orders) {
        // Pedidos listos para despacho (único estado visible para repartidores)
        final availableOrders = orders.where((o) => o.status == OrderStatus.ready).toList();

        final activeOrders = orders.where((o) =>
            o.status == OrderStatus.onTheWay || o.status == OrderStatus.assigned).toList();

        // 🤖 Reactor de Autoaceptación Inteligente por Proximidad
        if (opState.preferences.isAutoAcceptEnabled &&
            opState.canReceiveOrders &&
            _isVehicleRegistered &&
            availableOrders.isNotEmpty) {
          final kitchenPos = MapsService.defaultLocation;
          final distToKitchen = MapsService.calculateDistanceKm(_driverCurrentPos, kitchenPos);

          for (final order in availableOrders) {
            if (!_autoAcceptedOrderIds.contains(order.id)) {
              final match = OrderMatchingEngine.evaluate(
                order: order,
                driverLocation: _driverCurrentPos,
                preferences: opState.preferences,
                batteryLevel: opState.batteryLevel,
                isBatteryLow: opState.isBatteryLow,
                isOnline: opState.isOnline,
                hasActiveDelivery: opState.hasActiveDelivery,
              );

              // Validar compatibilidad y proximidad a la cocina (máximo 4.0 km o límite configurado)
              final maxAllowedStoreDist = opState.preferences.maxStoreDistanceKm > 0
                  ? opState.preferences.maxStoreDistanceKm
                  : 4.0;

              if (match.isMatch && distToKitchen <= maxAllowedStoreDist) {
                _autoAcceptedOrderIds.add(order.id);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _autoAcceptOrder(order, match);
                });
                break;
              }
            }
          }
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // HUD Superior de Control
            _buildTopControlHud(opState, isDark),

            // Banner de Batería Baja (< 10%)
            if (opState.isBatteryLow) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withAlpha(20),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFDC2626), width: 1.5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.battery_alert_rounded, color: Color(0xFFDC2626), size: 34),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '⚠️ ¡CUIDADO, CARGA TU CELULAR! (${opState.batteryLevel}%)',
                            style: const TextStyle(
                              color: Color(0xFFDC2626),
                              fontWeight: FontWeight.w900,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            'Tienes menos del 10% de batería. No recibirás más pedidos hasta que cargues tu celular.',
                            style: TextStyle(fontSize: 12, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (!opState.isLocationEnabled) ...[
              // Banner de Ubicación Desactivada
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withAlpha(20),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF0284C7), width: 1.5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_off_rounded, color: Color(0xFF0284C7), size: 30),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '📍 UBICACIÓN REQUERIDA',
                            style: TextStyle(
                              color: Color(0xFF0284C7),
                              fontWeight: FontWeight.w900,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            'Activa el GPS para poder recibir y tomar pedidos.',
                            style: TextStyle(fontSize: 12, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const DriverPermissionsScreen()),
                        );
                      },
                      child: const Text('Activar', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ],
            // Banner de Advertencia si el Vehículo no está registrado
            if (!_isVehicleRegistered) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withAlpha(15),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFDC2626), width: 1.5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.two_wheeler_rounded, color: Color(0xFFDC2626), size: 30),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '🛵 VEHÍCULO PENDIENTE POR REGISTRAR',
                            style: TextStyle(
                              color: Color(0xFFDC2626),
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            'Ingresa el modelo, la placa y sube la foto de tu placa para habilitar la toma de pedidos.',
                            style: TextStyle(fontSize: 11.5, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _showEditVehicleDialog,
                      child: const Text('Registrar', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ],

            // Banner de Alerta si tiene pedido en curso
            if (activeOrders.isNotEmpty || _activeOrder != null) ...[
              GestureDetector(
                onTap: () => setState(() => _currentNavIndex = 1),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFDC2626).withAlpha(80),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.two_wheeler_rounded, color: Colors.white, size: 28),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TIENES 1 ENTREGA EN CURSO 🛵',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              'Toca aquí para ver el mapa y la ruta en vivo',
                              style: TextStyle(color: Colors.white70, fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Selector de Subpestañas: [🛵 Disponibles (X)] | [✅ Mis Entregas (Historial)]
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1712) : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _ordersSubTabIndex = 0),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          color: _ordersSubTabIndex == 0
                              ? const Color(0xFFDC2626)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: _ordersSubTabIndex == 0
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFFDC2626).withAlpha(80),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  )
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.two_wheeler_rounded,
                              size: 16,
                              color: _ordersSubTabIndex == 0
                                  ? Colors.white
                                  : (isDark ? Colors.white60 : Colors.grey.shade700),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Disponibles (${availableOrders.length})',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: _ordersSubTabIndex == 0
                                    ? Colors.white
                                    : (isDark ? Colors.white70 : Colors.grey.shade800),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _ordersSubTabIndex = 1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          color: _ordersSubTabIndex == 1
                              ? const Color(0xFF16A34A)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: _ordersSubTabIndex == 1
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF16A34A).withAlpha(80),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  )
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.task_alt_rounded,
                              size: 16,
                              color: _ordersSubTabIndex == 1
                                  ? Colors.white
                                  : (isDark ? Colors.white60 : Colors.grey.shade700),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Mis Entregas',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: _ordersSubTabIndex == 1
                                    ? Colors.white
                                    : (isDark ? Colors.white70 : Colors.grey.shade800),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_ordersSubTabIndex == 1) ...[
              _buildDeliveredOrdersHistory(isDark),
            ] else ...[
              // Título de Sección
              Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'PEDIDOS DISPONIBLES (${availableOrders.length})',
                  style: TextStyle(
                    fontFamily: AppTypography.displayFamily,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF2C1B14),
                  ),
                ),
                Text(
                  'Bucaramanga 📍',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (availableOrders.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C1B14) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_outline_rounded, size: 54, color: Color(0xFF16A34A)),
                    const SizedBox(height: 12),
                    const Text(
                      'No hay pedidos pendientes en cocina',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Te notificaremos en cuanto entre un nuevo pedido a La Diabla 🔥',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              ...availableOrders.map((order) => _buildOrderCard(
                    order,
                    isDark,
                    isAvailable: true,
                    opState: opState,
                  )),
            ],
          ],
        );
      },
    );
  }

  Widget _buildOrderCard(
    OrderEntity order,
    bool isDark, {
    required bool isAvailable,
    required DriverOperationalState opState,
  }) {
    final address = order.address?.formattedAddress ?? 'Dirección de Entrega';
    final isPaid = order.paymentStatus == PaymentStatus.paid;
    final shortId = order.id.length > 6 ? order.id.substring(order.id.length - 6).toUpperCase() : order.id;

    // Evaluación con OrderMatchingEngine
    final match = OrderMatchingEngine.evaluate(
      order: order,
      driverLocation: _driverCurrentPos,
      preferences: opState.preferences,
      batteryLevel: opState.batteryLevel,
      isBatteryLow: opState.isBatteryLow,
      isOnline: opState.isOnline,
      hasActiveDelivery: opState.hasActiveDelivery,
    );

    final canReceive = opState.canReceiveOrders && _isVehicleRegistered && _isDriverPhoneValid;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C1B14) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: match.isMatch
              ? (isDark ? const Color(0xFF16A34A).withAlpha(120) : const Color(0xFF81C784))
              : (isDark ? AppColors.dividerDark : Colors.grey.shade200),
          width: match.isMatch ? 1.5 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 10),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Orden #$shortId',
                style: const TextStyle(
                  fontFamily: AppTypography.displayFamily,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isPaid
                      ? const Color(0xFFE8F5E9)
                      : (order.paymentMethod == PaymentMethod.pos
                          ? const Color(0xFFE0F2FE)
                          : const Color(0xFFFFF3E0)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isPaid
                        ? const Color(0xFF81C784)
                        : (order.paymentMethod == PaymentMethod.pos
                            ? const Color(0xFF38BDF8)
                            : const Color(0xFFFFB74D)),
                  ),
                ),
                child: Text(
                  isPaid
                      ? 'PAGADO DIGITAL ✅'
                      : (order.paymentMethod == PaymentMethod.pos
                          ? 'COBRAR CON DATÁFONO 📟'
                          : 'COBRAR EN EFECTIVO 💵'),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: isPaid
                        ? const Color(0xFF2E7D32)
                        : (order.paymentMethod == PaymentMethod.pos
                            ? const Color(0xFF0369A1)
                            : const Color(0xFFE65100)),
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 16),

          // Desglose de Ruta y Distancias
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: isDark ? Colors.black26 : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.route_rounded, size: 20, color: Color(0xFFDC2626)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '🛵 A cocina: ${match.storeDistanceKm} km  →  📍 Entrega: ${match.deliveryDistanceKm} km\nTotal: ${match.totalDistanceKm} km (~${match.estimatedMinutes} min)',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.3),
                  ),
                ),
              ],
            ),
          ),

          Row(
            children: [
              const Icon(Icons.location_on_rounded, color: Color(0xFFDC2626), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  address,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
          if (order.notes != null && order.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C2219) : const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? const Color(0xFFB45309).withAlpha(120) : const Color(0xFFFCD34D),
                  width: 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.edit_note_rounded, size: 18, color: Color(0xFFD97706)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Indicaciones del cliente: ${order.notes}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFFFCD34D) : const Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            '🌮 Platillos: ${order.items.map((i) => '${i.quantity}x ${i.product.name}').join(', ')}',
            style: TextStyle(fontSize: 12, color: isDark ? AppColors.textMutedDark : Colors.grey.shade700),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total: ${PriceFormatter.formatSmart(order.total)}',
                style: const TextStyle(
                  fontFamily: AppTypography.displayFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFDC2626),
                ),
              ),
              Text(
                'Ganancia: +${PriceFormatter.formatSmart(match.deliveryFee)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF16A34A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Badge de Compatibilidad y Explicación Transparente
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: match.isMatch
                  ? const Color(0xFF16A34A).withAlpha(15)
                  : Colors.orange.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: match.isMatch ? const Color(0xFF16A34A) : Colors.orange.shade400,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  match.isMatch ? Icons.verified_rounded : Icons.info_outline_rounded,
                  color: match.isMatch ? const Color(0xFF16A34A) : Colors.orange.shade800,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    match.isMatch
                        ? 'COMPATIBLE CON TU MODO (${opState.preferences.activeWorkModeId.toUpperCase()})'
                        : 'NO COMPATIBLE: ${match.explanation}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: match.isMatch
                          ? (isDark ? Colors.green.shade300 : const Color(0xFF16A34A))
                          : (isDark ? Colors.orange.shade200 : Colors.orange.shade900),
                    ),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: canReceive ? const Color(0xFFDC2626) : Colors.grey.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.two_wheeler_rounded, size: 20),
              label: Text(
                canReceive
                    ? 'TOMAR PEDIDO E IR A COCINA 🍳'
                    : (!_isVehicleRegistered
                        ? 'REGISTRA TU VEHÍCULO PRIMERO ⚠️'
                        : (!_isDriverPhoneValid
                            ? 'AGREGA TU TELÉFONO PRIMERO 📱'
                            : 'BLOQUEADO PARA RECIBIR')),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
              ),
              onPressed: canReceive
                  ? () => _takeAndAcceptOrder(order)
                  : () {
                      if (!_isVehicleRegistered) {
                        _showEditVehicleDialog();
                        return;
                      }
                      if (!_isDriverPhoneValid) {
                        _showRequireDriverPhoneDialog();
                        return;
                      }
                      final op = ref.read(driverOperationalProvider);
                      if (op.isBatteryLow) {
                        LowBatteryModal.showIfNeeded(context, op.batteryLevel);
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const DriverPermissionsScreen()),
                        );
                      }
                    },
              ),
            ),
          ],
        ),
      );
  }

  /// Pestaña de Historial de Entregas del Repartidor con acceso a Chats y Detalles
  Widget _buildDeliveredOrdersHistory(bool isDark) {
    final driverId = ref.read(authNotifierProvider).user?.id ?? 'driver_01';

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('driverId', isEqualTo: driverId)
          .where('status', isEqualTo: OrderStatus.delivered.name)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C1B14) : Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Text(
                'Error al cargar entregas: ${snapshot.error}',
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator(color: Color(0xFF16A34A))),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C1B14) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.inventory_2_outlined, size: 54, color: Color(0xFF16A34A)),
                const SizedBox(height: 12),
                const Text(
                  'Aún no tienes pedidos entregados',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Cuando completes y finalices una entrega, aparecerá aquí con acceso directo a su chat y datos del cliente.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        // Ordenar en memoria por fecha más reciente
        final sortedDocs = List<QueryDocumentSnapshot>.from(docs);
        sortedDocs.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>?;
          final bData = b.data() as Map<String, dynamic>?;
          final aTime = aData?['deliveredAt'] ?? aData?['updatedAt'] ?? aData?['createdAt'];
          final bTime = bData?['deliveredAt'] ?? bData?['updatedAt'] ?? bData?['createdAt'];
          DateTime aDate = DateTime(2020);
          DateTime bDate = DateTime(2020);
          if (aTime is Timestamp) aDate = aTime.toDate();
          if (bTime is Timestamp) bDate = bTime.toDate();
          return bDate.compareTo(aDate);
        });

        return Column(
          children: sortedDocs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final orderId = doc.id;
            final shortId = orderId.length > 6
                ? orderId.substring(orderId.length - 6).toUpperCase()
                : orderId.toUpperCase();
            final customerName = data['customerName'] as String? ??
                data['userName'] as String? ??
                'Cliente La Diabla';
            final customerPhone = data['customerPhone'] as String? ??
                data['userPhone'] as String? ??
                data['phone'] as String? ??
                '';
            final address = data['formattedAddress'] as String? ?? 'Dirección de entrega';
            final fee = (data['deliveryFee'] as num?)?.toDouble() ?? 7500.0;
            final proofUrl = data['deliveryProofUrl'] as String?;
            final clientId = data['userId'] as String? ?? '';

            // Fecha/hora de entrega formateada
            String deliveredTimeStr = '';
            final deliveredAtRaw = data['deliveredAt'] ?? data['updatedAt'];
            if (deliveredAtRaw is Timestamp) {
              deliveredTimeStr = DateFormat('dd MMM • hh:mm a').format(deliveredAtRaw.toDate());
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C1B14) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(isDark ? 30 : 10),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Encabezado del pedido entregado
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF16A34A).withAlpha(25),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF16A34A), width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  '#$shortId',
                                  style: const TextStyle(
                                    color: Color(0xFF16A34A),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (deliveredTimeStr.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              deliveredTimeStr,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16A34A).withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '+${PriceFormatter.formatSmart(fee)}',
                          style: const TextStyle(
                            color: Color(0xFF16A34A),
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),

                  // Cliente y foto
                  Row(
                    children: [
                      // Avatar o Foto de cliente
                      StreamBuilder<DocumentSnapshot>(
                        stream: clientId.isNotEmpty
                            ? FirebaseFirestore.instance.collection('users').doc(clientId).snapshots()
                            : null,
                        builder: (context, userSnap) {
                          final userData = userSnap.data?.data() as Map<String, dynamic>?;
                          final clientPhoto = userData?['photoUrl'] as String? ?? '';
                          return GestureDetector(
                            onTap: clientPhoto.isNotEmpty
                                ? () => _showProfilePhotoDialog(context, clientPhoto, customerName)
                                : null,
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFF16A34A), width: 2),
                                color: const Color(0xFF1E1712),
                              ),
                              child: ClipOval(
                                child: clientPhoto.isNotEmpty
                                    ? _buildSafeImage(
                                        clientPhoto,
                                        width: 44,
                                        height: 44,
                                        fit: BoxFit.cover,
                                        errorWidget: const Center(child: Icon(Icons.person, color: Colors.white70)),
                                      )
                                    : const Center(child: Icon(Icons.person, color: Colors.white70)),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customerName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.location_on_rounded, size: 13, color: Color(0xFFDC2626)),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    address,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Si hay comprobante fotográfico, mostrar miniatura
                  if (proofUrl != null && proofUrl.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => _showProfilePhotoDialog(context, proofUrl, 'Comprobante Entrega #$shortId'),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E1712) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.withAlpha(50)),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: _buildSafeImage(
                                proofUrl,
                                width: 42,
                                height: 42,
                                fit: BoxFit.cover,
                                errorWidget: const Icon(Icons.image, color: Colors.grey),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '📸 Comprobante de Entrega',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                  Text(
                                    'Toca para ver foto ampliada',
                                    style: TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.zoom_in_rounded, size: 20, color: Color(0xFF16A34A)),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 14),

                  // Botones de Acción: "Ver Chat con Cliente 💬" y WhatsApp
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            elevation: 1,
                          ),
                          icon: const Icon(Icons.forum_rounded, size: 16),
                          label: const Text(
                            'Ver Chat con Cliente 💬',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          onPressed: () {
                            final myDriverId = ref.read(authNotifierProvider).user?.id ?? 'driver_01';
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OrderChatScreen(
                                  orderId: orderId,
                                  currentUserId: myDriverId,
                                  currentUserName: _driverName,
                                  currentUserRole: 'driver',
                                  peerName: customerName,
                                  peerPhone: customerPhone,
                                  peerRole: 'Cliente',
                                  currentUserPhotoUrl: _driverPhoto,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      if (customerPhone.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFF16A34A).withAlpha(20),
                            foregroundColor: const Color(0xFF16A34A),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: Color(0xFF16A34A), width: 1.2),
                            ),
                          ),
                          icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                          tooltip: 'WhatsApp',
                          onPressed: () async {
                            final cleanPhone = customerPhone.replaceAll(RegExp(r'[^0-9]'), '');
                            final url = Uri.parse(
                              'https://wa.me/57$cleanPhone?text=Hola,%20te%20escribe%20tu%20repartidor%20sobre%20el%20pedido%20%23$shortId%20entregado%20🔥',
                            );
                            try {
                              await launchUrl(url, mode: LaunchMode.externalApplication);
                            } catch (_) {}
                          },
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  // ═════════════════════════════════════════════════════════════════════════════
  // PESTAÑA 1: RUTA INTELIGENTE & MAPA GPS EN VIVO
  // ═════════════════════════════════════════════════════════════════════════════
  Widget _buildMapRouteTab(bool isDark) {
    final allOrdersAsync = ref.watch(allPendingOrdersStreamProvider);
    final activeOrdersFromStream = allOrdersAsync.maybeWhen(
      data: (orders) => orders.where((o) =>
          o.status == OrderStatus.onTheWay || o.status == OrderStatus.assigned).toList(),
      orElse: () => <OrderEntity>[],
    );

    final activeOrder = _activeOrder ?? (activeOrdersFromStream.isNotEmpty ? activeOrdersFromStream.first : null);
    final opState = ref.watch(driverOperationalProvider);

    final destLat = activeOrder?.address?.latitude ?? activeOrder?.latitude ?? 7.092758;
    final destLng = activeOrder?.address?.longitude ?? activeOrder?.longitude ?? -73.142590;
    final destPos = LatLng(destLat, destLng);
    final kitchenPos = MapsService.defaultLocation;

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('kitchen'),
        position: kitchenPos,
        infoWindow: const InfoWindow(title: 'Restaurante La Diabla 🌶️', snippet: 'Cl. 59 # 39W-24, Estoraques 1'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      ),
      Marker(
        markerId: const MarkerId('driver'),
        position: _driverCurrentPos,
        rotation: _currentBearing,
        flat: true,
        anchor: const Offset(0.5, 0.5),
        infoWindow: const InfoWindow(title: 'Mi Posición 🛵 (La Diabla)'),
        icon: _driverMarkerIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose),
      ),
      if (activeOrder != null)
        Marker(
          markerId: const MarkerId('destination'),
          position: destPos,
          infoWindow: InfoWindow(
            title: 'Cliente: ${activeOrder.address?.formattedAddress ?? "Destino"}',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
    };

    // Si hay orden activa y no se ha calculado la ruta inteligente, calcularla
    if (activeOrder != null && _smartRoutePoints.isEmpty && !_isLoadingRoute && activeOrder.id != _lastCalculatedOrderId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _calculateSmartRoute(activeOrder);
      });
    }

    // Si está en fase de recogida hacia la cocina: destino = cocina
    // Si ya reclamó el pedido: destino = cliente
    final targetDestPos = _headingToKitchen ? kitchenPos : destPos;

    // Puntos de la ruta: usar la ruta inteligente por calles si está disponible
    final routePoints = activeOrder != null
        ? (_smartRoutePoints.isNotEmpty ? _smartRoutePoints : [_driverCurrentPos, targetDestPos])
        : [_driverCurrentPos, kitchenPos];

    final polylines = <Polyline>{
      // Sombra/borde de alto contraste estilo navegación Waze
      Polyline(
        polylineId: const PolylineId('active_route_shadow'),
        points: routePoints,
        color: const Color(0xFF7F1D1D),
        width: 8,
      ),
      // Línea principal rojo fuego La Diabla
      Polyline(
        polylineId: const PolylineId('active_route'),
        points: routePoints,
        color: const Color(0xFFDC2626),
        width: 5,
      ),
    };

    final currentDistanceKm = _remainingDistanceKm > 0
        ? _remainingDistanceKm
        : MapsService.calculateDistanceKm(_driverCurrentPos, targetDestPos);
    final currentEtaText = _remainingTimeText.isNotEmpty
        ? _remainingTimeText
        : MapsService.estimateDeliveryTime(currentDistanceKm);

    return Stack(
      children: [
        // Mapa de Google a pantalla completa
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _driverCurrentPos,
            zoom: 16.5,
            tilt: activeOrder?.status == OrderStatus.onTheWay ? 45.0 : 0.0,
            bearing: _currentBearing > 0 ? _currentBearing : 0.0,
          ),
          markers: markers,
          polylines: polylines,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          onCameraMoveStarted: () {
            if (_isCameraFollowEnabled) {
              setState(() => _isCameraFollowEnabled = false);
            }
          },
          onMapCreated: (ctrl) {
            if (!_mapControllerCompleter.isCompleted) {
              _mapControllerCompleter.complete(ctrl);
            }
            _centerMapOnRealGps();
          },
        ),

        // HUD Superior Flotante sobre el Mapa:
        // Si hay viaje en camino -> Banner de Navegación In-App inteligente
        // Si no -> HUD clásico de control operativo
        Positioned(
          top: 14,
          left: 14,
          right: 14,
          child: activeOrder != null && (activeOrder.status == OrderStatus.onTheWay || _headingToKitchen)
              ? _buildInAppNavigationHud(
                  activeOrder: activeOrder,
                  distanceKm: currentDistanceKm,
                  etaText: currentEtaText,
                  destLat: targetDestPos.latitude,
                  destLng: targetDestPos.longitude,
                  isDark: isDark,
                )
              : _buildTopControlHud(opState, isDark),
        ),

        // Botón flotante para centrar en GPS Real con modo conducción
        Positioned(
          right: 16,
          bottom: activeOrder == null ? 175 : 325,
          child: FloatingActionButton.small(
            backgroundColor: _isCameraFollowEnabled
                ? const Color(0xFFDC2626)
                : (isDark ? const Color(0xFF2C1B14) : Colors.white),
            foregroundColor: _isCameraFollowEnabled
                ? Colors.white
                : const Color(0xFFDC2626),
            elevation: 6,
            tooltip: _isCameraFollowEnabled ? 'Siguiendo tu moto' : 'Centrar y seguir ruta',
            onPressed: () async {
              setState(() => _isCameraFollowEnabled = true);
              await _centerMapOnRealGps();
              if (_mapControllerCompleter.isCompleted) {
                final ctrl = await _mapControllerCompleter.future;
                ctrl.animateCamera(
                  CameraUpdate.newCameraPosition(
                    CameraPosition(
                      target: _driverCurrentPos,
                      zoom: 17.5,
                      tilt: 45.0,
                      bearing: _currentBearing > 0 ? _currentBearing : 0.0,
                    ),
                  ),
                );
              }
            },
            child: Icon(
              _isCameraFollowEnabled ? Icons.navigation_rounded : Icons.my_location_rounded,
              size: 22,
            ),
          ),
        ),

        // Panel inferior flotante con la orden activa o estado de espera
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: activeOrder == null
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C1B14) : Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 14,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDC2626).withAlpha(20),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.two_wheeler_rounded,
                              color: Color(0xFFDC2626),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Sin Ruta en Curso',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Acepta una orden en "Pedidos" para iniciar tu navegación GPS.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.receipt_long_rounded, size: 18),
                          label: const Text(
                            'VER PEDIDOS DISPONIBLES 🛵',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                          onPressed: () => setState(() => _currentNavIndex = 0),
                        ),
                      ),
                    ],
                  ),
                )
              : Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C1B14) : Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 14, offset: Offset(0, 4))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Icon(
                                  _headingToKitchen ? Icons.storefront_rounded : Icons.navigation_rounded,
                                  color: const Color(0xFFDC2626),
                                  size: 20,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _headingToKitchen
                                        ? 'PASO 1: RECLAMAR EN COCINA • #${activeOrder.id.length > 6 ? activeOrder.id.substring(activeOrder.id.length - 6).toUpperCase() : activeOrder.id}'
                                        : 'PASO 2: EN RUTA AL CLIENTE • #${activeOrder.id.length > 6 ? activeOrder.id.substring(activeOrder.id.length - 6).toUpperCase() : activeOrder.id}',
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.directions_rounded, color: Color(0xFF009EE3)),
                            tooltip: 'Abrir GPS Externo',
                            onPressed: () => _openExternalMap(
                              _headingToKitchen ? kitchenPos.latitude : destLat,
                              _headingToKitchen ? kitchenPos.longitude : destLng,
                              address: _headingToKitchen ? 'Cocina Central La Diabla' : activeOrder.address?.formattedAddress,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _headingToKitchen
                            ? 'Cocina Central La Diabla (Cl. 59 # 39W-24, Estoraques 1)'
                            : (activeOrder.address?.formattedAddress ?? 'Dirección de Entrega'),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),

                      // Badge del Método de Pago para el Repartidor
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: activeOrder.paymentStatus == PaymentStatus.paid
                              ? const Color(0xFFE8F5E9)
                              : (activeOrder.paymentMethod == PaymentMethod.pos
                                  ? const Color(0xFFE0F2FE)
                                  : const Color(0xFFFFF3E0)),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: activeOrder.paymentStatus == PaymentStatus.paid
                                ? const Color(0xFF81C784)
                                : (activeOrder.paymentMethod == PaymentMethod.pos
                                    ? const Color(0xFF38BDF8)
                                    : const Color(0xFFFFB74D)),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              activeOrder.paymentStatus == PaymentStatus.paid
                                  ? '✅ PAGADO ONLINE'
                                  : (activeOrder.paymentMethod == PaymentMethod.pos
                                      ? '📟 COBRAR CON DATÁFONO: ${PriceFormatter.formatSmart(activeOrder.total)}'
                                      : '💵 COBRAR EN EFECTIVO: ${PriceFormatter.formatSmart(activeOrder.total)}'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: activeOrder.paymentStatus == PaymentStatus.paid
                                    ? const Color(0xFF2E7D32)
                                    : (activeOrder.paymentMethod == PaymentMethod.pos
                                        ? const Color(0xFF0369A1)
                                        : const Color(0xFFE65100)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Indicaciones / Notas de Entrega del Cliente
                      if (activeOrder.notes != null && activeOrder.notes!.trim().isNotEmpty) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF332010) : const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark ? const Color(0xFFF59E0B) : const Color(0xFFD97706),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.edit_note_rounded, color: Color(0xFFD97706), size: 24),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'NOTAS / INDICACIONES DEL CLIENTE:',
                                      style: TextStyle(
                                        color: Color(0xFFD97706),
                                        fontWeight: FontWeight.w900,
                                        fontSize: 11,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      activeOrder.notes!,
                                      style: TextStyle(
                                        color: isDark ? Colors.white : const Color(0xFF78350F),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      // Información y Contacto con el Cliente
                      Builder(
                        builder: (context) {
                          final clientName = (activeOrder.customerName?.isNotEmpty == true)
                              ? activeOrder.customerName!
                              : 'Cliente La Diabla';
                          final clientPhone = (activeOrder.customerPhone?.isNotEmpty == true)
                              ? activeOrder.customerPhone!
                              : '';

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.black26 : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                                ),
                                child: Row(
                                  children: [
                                    // Foto del cliente desde Firestore (toca para ver ampliada)
                                    StreamBuilder<DocumentSnapshot>(
                                      stream: FirebaseFirestore.instance
                                          .collection('users')
                                          .doc(activeOrder.userId)
                                          .snapshots(),
                                      builder: (context, userSnap) {
                                        final userData = userSnap.data?.data() as Map<String, dynamic>?;
                                        final customerPhotoUrl = userData?['photoUrl'] as String? ?? '';
                                        return GestureDetector(
                                          onTap: customerPhotoUrl.isNotEmpty
                                              ? () => _showProfilePhotoDialog(context, customerPhotoUrl, clientName)
                                              : null,
                                          child: Stack(
                                            children: [
                                              CircleAvatar(
                                                radius: 20,
                                                backgroundColor: const Color(0xFFDC2626).withAlpha(25),
                                                child: ClipOval(
                                                  child: customerPhotoUrl.isNotEmpty
                                                      ? (customerPhotoUrl.startsWith('data:image/')
                                                          ? Image.memory(
                                                              base64Decode(customerPhotoUrl.split(',').last),
                                                              width: 40,
                                                              height: 40,
                                                              fit: BoxFit.cover,
                                                              errorBuilder: (context, error, stackTrace) => const Icon(Icons.person_rounded, color: Color(0xFFDC2626), size: 22),
                                                            )
                                                          : Image.network(
                                                              customerPhotoUrl,
                                                              width: 40,
                                                              height: 40,
                                                              fit: BoxFit.cover,
                                                              errorBuilder: (context, error, stackTrace) => const Icon(Icons.person_rounded, color: Color(0xFFDC2626), size: 22),
                                                            ))
                                                      : const Icon(Icons.person_rounded, color: Color(0xFFDC2626), size: 22),
                                                ),
                                              ),
                                              if (customerPhotoUrl.isNotEmpty)
                                                Positioned(
                                                  right: 0,
                                                  bottom: 0,
                                                  child: Container(
                                                    width: 14,
                                                    height: 14,
                                                    decoration: const BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: Color(0xFFDC2626),
                                                    ),
                                                    child: const Icon(Icons.zoom_in_rounded, color: Colors.white, size: 9),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            clientName,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            clientPhone.isNotEmpty ? '📞 $clientPhone' : '📞 Teléfono registrado en orden',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),

                              // Botones de Contacto Rápido al Cliente
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF25D366),
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        padding: const EdgeInsets.symmetric(vertical: 9),
                                      ),
                                      icon: const Icon(Icons.chat_rounded, size: 15),
                                      label: const Text('WhatsApp', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                      onPressed: () => _whatsappCustomer(clientPhone, activeOrder.id),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF009EE3),
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        padding: const EdgeInsets.symmetric(vertical: 9),
                                      ),
                                      icon: const Icon(Icons.call_rounded, size: 15),
                                      label: const Text('Llamar', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                      onPressed: () => _callCustomer(clientPhone),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFDC2626),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    elevation: 1,
                                  ),
                                  icon: const Icon(Icons.forum_rounded, size: 17),
                                  label: const Text('Chat con el Cliente 💬', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                  onPressed: () {
                                    final driverId = ref.read(authNotifierProvider).user?.id ?? 'driver_01';
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => OrderChatScreen(
                                          orderId: activeOrder.id,
                                          currentUserId: driverId,
                                          currentUserName: _driverName,
                                          currentUserRole: 'driver',
                                          peerName: clientName,
                                          peerPhone: clientPhone,
                                          peerRole: 'Cliente',
                                          currentUserPhotoUrl: _driverPhoto,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 10),

                      // Botón dinámico según fase de entrega (Estilo Rappi / DiDi Food):
                      // Fase 1: Va hacia la cocina a reclamar el pedido
                      // Fase 2: Reclama el pedido y sale hacia el cliente
                      // Fase 3: Llega al cliente y finaliza con foto de comprobante
                      if (_headingToKitchen) ...[
                        Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0284C7),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  elevation: 2,
                                ),
                                icon: const Icon(Icons.navigation_rounded, size: 18),
                                label: const Text(
                                  'GPS COCINA 🧭',
                                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5),
                                ),
                                onPressed: () => _startTripToKitchen(activeOrder),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 6,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFD97706),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  elevation: 4,
                                ),
                                icon: const Icon(Icons.inventory_2_rounded, size: 19),
                                label: const Text(
                                  'PEDIDO RECIBIDO 📦',
                                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                                ),
                                onPressed: () async {
                                  setState(() {
                                    _headingToKitchen = false;
                                    _smartRoutePoints = [];
                                  });
                                  try {
                                    await FirebaseFirestore.instance
                                        .collection('orders')
                                        .doc(activeOrder.id)
                                        .update({
                                      'driverPhase': 'heading_to_client',
                                      'updatedAt': FieldValue.serverTimestamp(),
                                    });
                                  } catch (_) {}
                                  try {
                                    await _flutterTts.speak('¡Pedido recibido en cocina! Ahora inicia la ruta hacia el cliente.');
                                  } catch (_) {}
                                  await _calculateSmartRoute(activeOrder);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('📦 Pedido recibido en cocina. Presiona "INICIAR RUTA AL CLIENTE" para salir.'),
                                        backgroundColor: Color(0xFF16A34A),
                                        behavior: SnackBarBehavior.floating,
                                        duration: Duration(seconds: 4),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ] else if (activeOrder.status == OrderStatus.assigned) ...[
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0EA5E9),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 4,
                            ),
                            icon: const Icon(Icons.two_wheeler_rounded, size: 22),
                            label: const Text(
                              'INICIAR RUTA AL CLIENTE 🏍️',
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5),
                            ),
                            onPressed: () => _startTripWithGps(activeOrder),
                          ),
                        ),
                      ] else ...[
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF16A34A),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            icon: const Icon(Icons.check_circle_rounded, size: 20),
                            label: const Text(
                              'ENTREGA COMPLETADA ✅',
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                            ),
                            onPressed: () => _markOrderAsDelivered(activeOrder),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  /// HUD Superior de Navegación In-App en Vivo
  Widget _buildInAppNavigationHud({
    required OrderEntity activeOrder,
    required double distanceKm,
    required String etaText,
    required double destLat,
    required double destLng,
    required bool isDark,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1712).withAlpha(240) : Colors.white.withAlpha(245),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFDC2626).withAlpha(120),
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fila superior: Estado de navegación y botones rápidos a navegadores externos
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF16A34A),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _headingToKitchen
                      ? 'RECOGIENDO EN COCINA 📦'
                      : 'EN RUTA AL CLIENTE 🛵',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 11.5,
                    color: _headingToKitchen
                        ? const Color(0xFFD97706)
                        : const Color(0xFFDC2626),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              // Botón rápido Waze
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => MapsService.openInWaze(destLat, destLng),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00A3DA).withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF00A3DA).withAlpha(80)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.directions_car_rounded, size: 13, color: Color(0xFF00A3DA)),
                      SizedBox(width: 4),
                      Text('Waze', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF00A3DA))),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Botón rápido Google Maps
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => MapsService.openInGoogleMaps(destLat, destLng, label: 'Entrega La Diabla'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF10B981).withAlpha(80)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.map_rounded, size: 13, color: Color(0xFF10B981)),
                      SizedBox(width: 4),
                      Text('Maps', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Dirección destino
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_pin, size: 18, color: Color(0xFFDC2626)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _headingToKitchen
                      ? 'Cocina Central La Diabla • Cl. 59 # 39W-24'
                      : (activeOrder.address?.formattedAddress ?? 'Dirección de Entrega'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isDark ? Colors.white : const Color(0xFF1C1C1C),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (!_headingToKitchen && activeOrder.notes != null && activeOrder.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF332010) : const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? const Color(0xFFF59E0B) : const Color(0xFFD97706)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit_note_rounded, size: 16, color: Color(0xFFD97706)),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Nota: ${activeOrder.notes}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.amber.shade200 : const Color(0xFF78350F),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),

          // Métricas en vivo de conducción: Distancia restante, Tiempo estimado y Recalcular
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? Colors.black26 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.route_rounded, size: 16, color: Color(0xFFDC2626)),
                    const SizedBox(width: 4),
                    Text(
                      '${distanceKm.toStringAsFixed(1)} km',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                    ),
                  ],
                ),
                Container(width: 1, height: 16, color: Colors.grey.shade400),
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 16, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 4),
                    Text(
                      etaText,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                    ),
                  ],
                ),
                Container(width: 1, height: 16, color: Colors.grey.shade400),
                InkWell(
                  onTap: () => _calculateSmartRoute(activeOrder),
                  child: Row(
                    children: [
                      Icon(
                        Icons.refresh_rounded,
                        size: 15,
                        color: _isLoadingRoute ? const Color(0xFFDC2626) : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        _isLoadingRoute ? 'Ruta...' : 'Recalcular',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _isLoadingRoute ? const Color(0xFFDC2626) : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════════
  // PESTAÑA 2: GANANCIAS & RENDIMIENTO (100% REALES DESDE FIRESTORE)
  // ═════════════════════════════════════════════════════════════════════════════
  Widget _buildEarningsTab(bool isDark) {
    final deliveredOrdersAsync = ref.watch(driverDeliveredOrdersStreamProvider);

    return deliveredOrdersAsync.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFDC2626))),
      error: (err, _) => Center(child: Text('Error cargando ganancias: $err')),
      data: (deliveredOrders) {
        final totalDeliveredCount = deliveredOrders.length;
        final totalEarnings = deliveredOrders.fold<double>(
          0.0,
          (acc, o) => acc + (o.deliveryFee > 0 ? o.deliveryFee : 7500.0),
        );
        final totalTips = deliveredOrders.fold<double>(
          0.0,
          (acc, o) => acc + 0.0,
        );

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Tarjeta Principal de Ganancias Reales
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFDC2626), Color(0xFF991B1B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFDC2626).withAlpha(80),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'GANANCIAS ACUMULADAS 💵',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 1.0,
                        ),
                      ),
                      Icon(Icons.account_balance_wallet_rounded, color: Colors.white),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    PriceFormatter.formatSmart(totalEarnings),
                    style: const TextStyle(
                      fontFamily: AppTypography.displayFamily,
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$totalDeliveredCount entregas realizadas con éxito',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Grid de Métricas
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    title: 'Propinas',
                    value: PriceFormatter.formatSmart(totalTips),
                    icon: Icons.volunteer_activism_rounded,
                    color: const Color(0xFF16A34A),
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricCard(
                    title: 'Calificación',
                    value: totalDeliveredCount > 0 ? '⭐ 5.0 / 5.0' : '⭐ 5.0 (Nuevo)',
                    icon: Icons.star_rounded,
                    color: Colors.amber.shade700,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ─── Tarjeta Bancaria del Repartidor (para recibir pagos de domicilios) ───
            _buildDriverBankAccountCard(isDark),
            const SizedBox(height: 20),

            // Historial de Hoy
            Text(
              'HISTORIAL DE ENTREGAS REALIZADAS (${deliveredOrders.length})',
              style: TextStyle(
                fontFamily: AppTypography.displayFamily,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF2C1B14),
              ),
            ),
            const SizedBox(height: 10),

            if (deliveredOrders.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C1B14) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
                  ),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.receipt_long_outlined, size: 48, color: AppColors.textMuted),
                    const SizedBox(height: 12),
                    const Text(
                      'Aún no has completado entregas',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Cuando aceptes y finalices un pedido de un cliente, aparecerá registrado aquí con su ganancia real.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              ...deliveredOrders.map((order) {
                final shortId = order.id.length > 6
                    ? order.id.substring(order.id.length - 6).toUpperCase()
                    : order.id;
                final fee = order.deliveryFee > 0 ? order.deliveryFee : 7500.0;
                final dt = order.updatedAt ?? order.createdAt ?? DateTime.now();
                final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
                final minute = dt.minute.toString().padLeft(2, '0');
                final ampm = dt.hour >= 12 ? 'PM' : 'AM';
                final timeFormatted = '$hour:$minute $ampm';

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C1B14) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Entrega #$shortId • $timeFormatted',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              order.address?.formattedAddress ?? 'Dirección de Entrega',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '+${PriceFormatter.formatSmart(fee)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF16A34A),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C1B14) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverBankAccountCard(bool isDark) {
    final earningsState = ref.watch(driverEarningsProvider);
    final bank = earningsState.bankAccount;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C1B14) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A).withAlpha(20),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.account_balance_rounded, color: Color(0xFF16A34A), size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mi Cuenta para Cobros 🏦',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                      Text(
                        'Donde se abonan tus domicilios',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.edit_rounded, size: 20, color: Color(0xFFDC2626)),
                tooltip: 'Editar cuenta bancaria',
                onPressed: () => _showEditBankAccountSheet(isDark),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (bank.isComplete) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1712) : const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withAlpha(30)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        bank.bank.toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFDC2626)),
                      ),
                      Text(
                        'Cuenta de ${bank.accountType}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'No. ${bank.accountNumber}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Titular: ${bank.holderName} • CC: ${bank.documentNumber}',
                    style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white70 : Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ] else ...[
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
                foregroundColor: const Color(0xFFDC2626),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                minimumSize: const Size(double.infinity, 42),
              ),
              icon: const Icon(Icons.add_card_rounded, size: 18),
              label: const Text(
                'Vincular Cuenta Bancaria / Tarjeta',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
              ),
              onPressed: () => _showEditBankAccountSheet(isDark),
            ),
          ],
        ],
      ),
    );
  }

  void _showEditBankAccountSheet(bool isDark) {
    final currentBank = ref.read(driverEarningsProvider).bankAccount;
    final bankCtrl = TextEditingController(text: currentBank.bank);
    final accountNumCtrl = TextEditingController(text: currentBank.accountNumber);
    final holderCtrl = TextEditingController(text: currentBank.holderName.isNotEmpty ? currentBank.holderName : _driverName);
    final docCtrl = TextEditingController(text: currentBank.documentNumber);
    String type = currentBank.accountType.isNotEmpty ? currentBank.accountType : 'Ahorros';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1712) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const Text(
                  'Datos Bancarios para Transferencias 💳',
                  style: TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Ingresa la cuenta o tarjeta donde te transferiremos las ganancias de tus entregas:',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: bankCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Banco (ej: Bancolombia, Nequi, Davivienda)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: accountNumCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Número de cuenta / Tarjeta',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        initialValue: type,
                        decoration: const InputDecoration(
                          labelText: 'Tipo',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Ahorros', child: Text('Ahorros', style: TextStyle(fontSize: 12))),
                          DropdownMenuItem(value: 'Corriente', child: Text('Corriente', style: TextStyle(fontSize: 12))),
                          DropdownMenuItem(value: 'Dígital', child: Text('Digital', style: TextStyle(fontSize: 12))),
                        ],
                        onChanged: (v) => setSheetState(() => type = v ?? 'Ahorros'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: holderCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre completo del titular',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: docCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Cédula de ciudadanía / NIT del titular',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () async {
                      if (bankCtrl.text.trim().isEmpty || accountNumCtrl.text.trim().isEmpty) return;

                      final account = BankAccount(
                        bank: bankCtrl.text.trim(),
                        accountNumber: accountNumCtrl.text.trim(),
                        accountType: type,
                        holderName: holderCtrl.text.trim(),
                        documentNumber: docCtrl.text.trim(),
                      );

                      final ok = await ref.read(driverEarningsProvider.notifier).saveBankAccount(account);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(ok ? '✅ Datos bancarios guardados con éxito' : '❌ Error al guardar datos bancarios'),
                            backgroundColor: ok ? const Color(0xFF16A34A) : AppColors.error,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    child: const Text('Guardar Cuenta de Cobro 💾', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════════
  // PESTAÑA 3: PERFIL DEL REPARTIDOR (EDITABLE & PERSISTENTE)
  // ═════════════════════════════════════════════════════════════════════════════
  Widget _buildDriverProfileTab(bool isDark) {
    final user = ref.watch(authNotifierProvider).user;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Tarjeta de perfil
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C1B14) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: Color(0xFFDC2626), size: 20),
                    tooltip: 'Editar Datos de Contacto',
                    onPressed: _showEditProfileDialog,
                  ),
                ],
              ),
              GestureDetector(
                onTap: _showDriverAvatarPickerSheet,
                child: Stack(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFDC2626), width: 2.5),
                        color: const Color(0xFF1E1712),
                      ),
                      child: Builder(
                        builder: (context) {
                          final uPhoto = user?.photoUrl;
                          final activePhoto = (_driverPhoto.isNotEmpty && !_driverPhoto.startsWith('assets/'))
                              ? _driverPhoto
                              : ((uPhoto != null && uPhoto.isNotEmpty && !uPhoto.startsWith('assets/'))
                                  ? uPhoto
                                  : (FirebaseAuth.instance.currentUser?.photoURL?.isNotEmpty == true
                                      ? FirebaseAuth.instance.currentUser!.photoURL!
                                      : _driverPhoto));
                          return ClipOval(
                            child: _buildDriverAvatarImage(activePhoto),
                          );
                        },
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: const BoxDecoration(
                          color: Color(0xFFDC2626),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black45, blurRadius: 4),
                          ],
                        ),
                        child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _driverName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  if (_driverPhone.isNotEmpty) '📞 $_driverPhone',
                  user?.email ?? 'repartidor@ladiabla.app',
                ].join(' • '),
                style: TextStyle(fontSize: 12.5, color: isDark ? AppColors.textMutedDark : Colors.grey.shade600),
              ),
              const SizedBox(height: 14),

              // Switch de Disponibilidad
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : const Color(0xFFFAF7F2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Disponible para recibir pedidos', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Switch(
                      value: _isAvailable,
                      activeThumbColor: const Color(0xFFDC2626),
                      onChanged: (val) => setState(() => _isAvailable = val),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Mis Calificaciones y Reseñas (Estilo Rappi)
        _buildDriverRatingsAndReviewsCard(user?.id ?? 'driver_01', isDark),
        const SizedBox(height: 16),

        // Datos del Vehículo (Totalmente Editable)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C1B14) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('DATOS DEL VEHÍCULO 🛵', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: Color(0xFFDC2626), size: 20),
                    tooltip: 'Editar Vehículo',
                    onPressed: _showEditVehicleDialog,
                  ),
                ],
              ),
              const Divider(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.motorcycle_rounded, color: Color(0xFFDC2626)),
                title: const Text('Vehículo'),
                trailing: Text(
                  _vehicleModel.isNotEmpty ? _vehicleModel : 'Sin registrar ⚠️',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _vehicleModel.isNotEmpty ? null : const Color(0xFFDC2626),
                  ),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.pin_rounded, color: Color(0xFFDC2626)),
                title: const Text('Placa'),
                trailing: Text(
                  _vehiclePlate.isNotEmpty ? _vehiclePlate : 'Sin registrar ⚠️',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _vehiclePlate.isNotEmpty ? null : const Color(0xFFDC2626),
                  ),
                ),
              ),
              if (_vehiclePlatePhoto.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.photo_camera_front_rounded, size: 18, color: Color(0xFF10B981)),
                      const SizedBox(width: 8),
                      const Text('Foto de Placa:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => _showProfilePhotoDialog(context, _vehiclePlatePhoto, 'Placa: $_vehiclePlate'),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: _buildPlateImageWidget(_vehiclePlatePhoto, width: 48, height: 48),
                            ),
                            Positioned(
                              right: 2,
                              bottom: 2,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFFDC2626),
                                ),
                                child: const Icon(Icons.zoom_in_rounded, size: 10, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.verified_rounded, color: Color(0xFF16A34A)),
                title: const Text('SOAT y Tecnomecánica'),
                trailing: Text(
                  _vehicleSoat.isNotEmpty ? _vehicleSoat : 'Vigente ✅',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Modos y Preferencias de Trabajo (La Diabla)
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C1B14) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
            ),
          ),
          child: ListTile(
            leading: const Icon(Icons.tune_rounded, color: Color(0xFFDC2626)),
            title: const Text('Modos y Preferencias de Trabajo 🛵', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
            subtitle: const Text('Cercano, Eléctrico, Normal, Maximizar Ganancias', style: TextStyle(fontSize: 11.5)),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            onTap: () => WorkModeSelectorSheet.show(context),
          ),
        ),
        const SizedBox(height: 14),

        // Configuración de Permisos y Dispositivo (Soy Rappi / La Diabla)
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C1B14) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
            ),
          ),
          child: ListTile(
            leading: const Icon(Icons.settings_suggest_rounded, color: Color(0xFF0EA5E9)),
            title: const Text('Configuración de Permisos y Dispositivo ⚙️', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
            subtitle: const Text('Ubicación, Batería, Notificaciones y Acceso Flotante', style: TextStyle(fontSize: 11.5)),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DriverPermissionsScreen()),
              );
            },
          ),
        ),
        const SizedBox(height: 14),

        // Centro de Ayuda y Soporte al Repartidor
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C1B14) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
            ),
          ),
          child: ListTile(
            leading: const Icon(Icons.support_agent_rounded, color: Color(0xFF16A34A)),
            title: const Text('Centro de Ayuda y Soporte 🆘', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
            subtitle: const Text('Asesor humano, problemas con pedidos y liquidación', style: TextStyle(fontSize: 11.5)),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DriverSupportScreen(activeOrder: _activeOrder),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),

        // Privacidad y Términos
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C1B14) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
            ),
          ),
          child: ListTile(
            leading: const Icon(Icons.shield_rounded, color: Color(0xFFDC2626)),
            title: const Text('Política de Privacidad y Términos 🔒', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
            subtitle: const Text('Tratamiento de datos y geolocalización', style: TextStyle(fontSize: 11.5)),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            onTap: () => PrivacyPolicySheet.show(context),
          ),
        ),
        const SizedBox(height: 20),

        // Botón Cerrar Sesión Repartidor
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
              foregroundColor: const Color(0xFFDC2626),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Cerrar Sesión Repartidor', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              final router = GoRouter.of(context);
              await ref.read(authNotifierProvider.notifier).signOut();
              if (mounted) {
                router.go('/auth');
              }
            },
          ),
        ),
        const SizedBox(height: 10),

        // Eliminar cuenta
        Center(
          child: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey,
            ),
            icon: const Icon(Icons.delete_forever_rounded, size: 16, color: Colors.grey),
            label: const Text(
              'Eliminar mi cuenta de repartidor',
              style: TextStyle(fontSize: 12, decoration: TextDecoration.underline),
            ),
            onPressed: _confirmDriverAccountDeletion,
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  /// Sección interactiva de Calificaciones y Reseñas del Repartidor (Estilo Rappi)
  Widget _buildDriverRatingsAndReviewsCard(String driverId, bool isDark) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(driverId).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final ratingAvg = (data?['driverAverageRating'] as num?)?.toDouble() ?? 5.0;
        final ratingCount = (data?['driverRatingCount'] as num?)?.toInt() ?? 0;
        final ordersCompleted = (data?['completedOrders'] as num?)?.toInt() ?? (ratingCount > 0 ? ratingCount : 2);

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C1B14) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 30 : 10),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 22),
                      SizedBox(width: 6),
                      Text(
                        'MIS RESEÑAS Y PUNTAJE ⭐',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A).withAlpha(25),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF16A34A), width: 1),
                    ),
                    child: const Text(
                      'Excelente',
                      style: TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Fila de Estadísticas y Score
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : const Color(0xFFFAF7F2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    // Puntuación destacada
                    Column(
                      children: [
                        Text(
                          ratingAvg.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFD97706),
                          ),
                        ),
                        Row(
                          children: List.generate(
                            5,
                            (idx) => Icon(
                              Icons.star_rounded,
                              size: 15,
                              color: idx < ratingAvg.round() ? const Color(0xFFF59E0B) : Colors.grey.shade400,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$ratingCount opiniones',
                          style: TextStyle(fontSize: 11, color: isDark ? AppColors.textMutedDark : Colors.grey.shade600),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Container(width: 1.2, height: 55, color: isDark ? AppColors.dividerDark : Colors.grey.shade300),
                    const SizedBox(width: 16),

                    // Métricas guiadas por entregas
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 14),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Entregas: $ordersCompleted',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          const Row(
                            children: [
                              Icon(Icons.electric_bolt_rounded, color: Color(0xFFDC2626), size: 14),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Puntualidad: 99%',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11.5),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          const Row(
                            children: [
                              Icon(Icons.thumb_up_rounded, color: Color(0xFF0284C7), size: 14),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Satisfacción: 100%',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11.5),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Lista de Reseñas de Clientes
              const Text(
                'Comentarios de tus clientes:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
              ),
              const SizedBox(height: 8),

              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(driverId)
                    .collection('driver_reviews')
                    .orderBy('createdAt', descending: true)
                    .limit(5)
                    .snapshots(),
                builder: (context, reviewSnap) {
                  final docs = reviewSnap.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.black12 : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? AppColors.dividerDark : Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.verified_user_rounded, color: Color(0xFF16A34A), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '¡Excelente perfil! Completa pedidos a tiempo para sumar más reseñas y mejorar tu prioridad.',
                              style: TextStyle(fontSize: 11.5, color: isDark ? AppColors.textMutedDark : Colors.grey.shade700),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: docs.map((doc) {
                      final rev = doc.data() as Map<String, dynamic>;
                      final stars = (rev['rating'] as num?)?.toInt() ?? 5;
                      final comment = rev['comment'] as String? ?? '¡Excelente servicio!';
                      final client = rev['customerName'] as String? ?? 'Cliente Diabla';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black12 : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? AppColors.dividerDark : Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(client, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                Row(
                                  children: List.generate(
                                    5,
                                    (i) => Icon(
                                      Icons.star_rounded,
                                      size: 13,
                                      color: i < stars ? const Color(0xFFF59E0B) : Colors.grey.shade400,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (comment.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(comment, style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white70 : Colors.black87)),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDriverAvatarImage(String path) {
    if (path.startsWith('data:image/')) {
      try {
        final bytes = base64Decode(path.split(',').last);
        return Image.memory(
          bytes,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Image.asset('assets/images/diabloperfil.png', width: double.infinity, height: double.infinity, fit: BoxFit.cover),
        );
      } catch (_) {
        return Image.asset('assets/images/diabloperfil.png', width: double.infinity, height: double.infinity, fit: BoxFit.cover);
      }
    } else if (path.startsWith('http')) {
      return Image.network(
        path,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Image.asset('assets/images/diabloperfil.png', width: double.infinity, height: double.infinity, fit: BoxFit.cover),
      );
    } else if (path.startsWith('assets/')) {
      return Image.asset(
        path,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Image.asset('assets/images/diabloperfil.png', width: double.infinity, height: double.infinity, fit: BoxFit.cover),
      );
    }
    final file = File(path);
    if (file.existsSync()) {
      return Image.file(
        file,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Image.asset('assets/images/diabloperfil.png', width: double.infinity, height: double.infinity, fit: BoxFit.cover),
      );
    }
    return Image.asset('assets/images/diabloperfil.png', width: double.infinity, height: double.infinity, fit: BoxFit.cover);
  }

  /// Caché en memoria para bytes Base64 decodificados que erradica el parpadeo
  /// de las imágenes ante cada emisión periódica del GPS del repartidor.
  static final Map<String, Uint8List> _base64MemoryCache = {};

  static Uint8List? _getCachedBase64Bytes(String dataUri) {
    if (_base64MemoryCache.containsKey(dataUri)) {
      return _base64MemoryCache[dataUri];
    }
    try {
      final clean = dataUri.contains(',') ? dataUri.split(',').last : dataUri;
      final bytes = base64Decode(clean.trim());
      if (_base64MemoryCache.length > 100) {
        _base64MemoryCache.clear();
      }
      _base64MemoryCache[dataUri] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// Renderizador seguro y anti-parpadeo para imágenes en base64, URLs remotas y archivos locales
  Widget _buildSafeImage(
    String pathOrUrl, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    Widget? placeholder,
    Widget? errorWidget,
  }) {
    final fallbackError = errorWidget ??
        Container(
          width: width,
          height: height,
          color: Colors.grey.shade300,
          child: const Center(child: Icon(Icons.broken_image, size: 22, color: Colors.grey)),
        );

    if (pathOrUrl.startsWith('data:image/')) {
      final bytes = _getCachedBase64Bytes(pathOrUrl);
      if (bytes != null) {
        return Image.memory(
          bytes,
          key: ValueKey('b64_${pathOrUrl.hashCode}'),
          width: width,
          height: height,
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (ctx, err, stack) => fallbackError,
        );
      }
      return fallbackError;
    } else if (pathOrUrl.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: pathOrUrl,
        width: width,
        height: height,
        fit: fit,
        placeholder: (ctx, url) =>
            placeholder ??
            Container(
              width: width,
              height: height,
              color: Colors.grey.shade200,
            ),
        errorWidget: (ctx, url, err) => fallbackError,
      );
    } else if (pathOrUrl.isNotEmpty) {
      final file = File(pathOrUrl);
      if (file.existsSync()) {
        return Image.file(
          file,
          key: ValueKey('file_${pathOrUrl.hashCode}'),
          width: width,
          height: height,
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (ctx, err, stack) => fallbackError,
        );
      }
    }
    return fallbackError;
  }

  Widget _buildPlateImageWidget(String pathOrUrl, {double? width, double? height, BoxFit fit = BoxFit.cover}) {
    return _buildSafeImage(
      pathOrUrl,
      width: width,
      height: height,
      fit: fit,
      errorWidget: Container(
        width: width,
        height: height,
        color: Colors.grey.shade300,
        child: const Center(child: Icon(Icons.photo_camera_rounded, size: 22, color: Colors.grey)),
      ),
    );
  }

  void _showDriverAvatarPickerSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final avatars = [
      {'name': 'Diablo Moto & Fuego', 'path': 'assets/images/diabloperfil.png'},
      {'name': 'Diablo Máscara', 'path': 'assets/images/diablopartedearriba.png'},
      {'name': 'Emblema La Diabla', 'path': 'assets/images/logo.png'},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1712) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const Text('Foto de Perfil del Repartidor 🛵', style: TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Sube una foto de tu galería o selecciona un avatar:', style: TextStyle(fontSize: 12.5, color: Colors.grey)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.photo_library_rounded, size: 20),
                      label: const Text('Mi Galería 🖼️', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: () async {
                        final picker = ImagePicker();
                        final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 75, maxWidth: 600, maxHeight: 600);
                        if (picked != null) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          final bytes = await File(picked.path).readAsBytes();
                          final photoDataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('driver_photo', photoDataUrl);
                          if (mounted) {
                            setState(() => _driverPhoto = photoDataUrl);
                          }
                          final user = ref.read(authNotifierProvider).user;
                          if (user != null && user.id.isNotEmpty) {
                            FirebaseFirestore.instance.collection('users').doc(user.id).set({
                              'photoUrl': photoDataUrl,
                            }, SetOptions(merge: true)).ignore();
                          }
                          if (_activeOrder != null) {
                            FirebaseFirestore.instance.collection('orders').doc(_activeOrder!.id).update({
                              'driverPhotoUrl': photoDataUrl,
                            }).catchError((_) {});
                          }
                          await ref.read(authNotifierProvider.notifier).updateUserProfile(photoUrl: photoDataUrl);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
                        foregroundColor: const Color(0xFFDC2626),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.camera_alt_rounded, size: 20),
                      label: const Text('Cámara 📸', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: () async {
                        final picker = ImagePicker();
                        final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 75, maxWidth: 600, maxHeight: 600);
                        if (picked != null) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          final bytes = await File(picked.path).readAsBytes();
                          final photoDataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('driver_photo', photoDataUrl);
                          if (mounted) {
                            setState(() => _driverPhoto = photoDataUrl);
                          }
                          final user = ref.read(authNotifierProvider).user;
                          if (user != null && user.id.isNotEmpty) {
                            FirebaseFirestore.instance.collection('users').doc(user.id).set({
                              'photoUrl': photoDataUrl,
                            }, SetOptions(merge: true)).ignore();
                          }
                          if (_activeOrder != null) {
                            FirebaseFirestore.instance.collection('orders').doc(_activeOrder!.id).update({
                              'driverPhotoUrl': photoDataUrl,
                            }).catchError((_) {});
                          }
                          await ref.read(authNotifierProvider.notifier).updateUserProfile(photoUrl: photoDataUrl);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: avatars.map((a) {
                  return GestureDetector(
                    onTap: () async {
                      if (ctx.mounted) Navigator.pop(ctx);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('driver_photo', a['path']!);
                      if (mounted) {
                        setState(() => _driverPhoto = a['path']!);
                      }
                      await ref.read(authNotifierProvider.notifier).updateUserProfile(photoUrl: a['path']!);
                    },
                    child: Column(
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFDC2626), width: 2)),
                          child: ClipOval(child: Image.asset(a['path']!, fit: BoxFit.cover)),
                        ),
                        const SizedBox(height: 4),
                        Text(a['name']!.split(' ')[0], style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDriverAccountDeletion() async {
    final router = GoRouter.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626)),
            SizedBox(width: 8),
            Text('¿Eliminar cuenta?'),
          ],
        ),
        content: const Text('Esta acción eliminará de forma permanente tu cuenta de repartidor y todos tus registros.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(authNotifierProvider.notifier).deleteAccount();
      if (mounted) {
        router.go('/auth');
      }
    }
  }

  Future<void> _showEditVehicleDialog() async {
    final modelCtrl = TextEditingController(text: _vehicleModel);
    final plateCtrl = TextEditingController(text: _vehiclePlate);
    final colorCtrl = TextEditingController(text: _vehicleColor);
    String soatStatus = _vehicleSoat.isNotEmpty ? _vehicleSoat : 'Vigente ✅';
    File? tempPlatePhotoFile;
    String currentPlatePhoto = _vehiclePlatePhoto;

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E1712) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              title: const Row(
                children: [
                  Icon(Icons.motorcycle_rounded, color: Color(0xFFDC2626)),
                  SizedBox(width: 8),
                  Text('Datos del Vehículo 🛵', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Campos obligatorios para poder recibir pedidos por seguridad del cliente.',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey),
                    ),
                    const SizedBox(height: 14),
                    const Text('Modelo / Tipo de Vehículo *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: modelCtrl,
                      decoration: InputDecoration(
                        hintText: 'Ej: Boxer CT 100 / Pulsar 200',
                        filled: true,
                        fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Placa del Vehículo *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: plateCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'Ej: XZK-45F',
                        filled: true,
                        fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Color del Vehículo *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: colorCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: 'Ej: Negro brillante / Rojo con negro',
                        filled: true,
                        fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Foto de la Placa del Vehículo 📸', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.black26 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                      ),
                      child: Column(
                        children: [
                          if (tempPlatePhotoFile != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.file(
                                tempPlatePhotoFile!,
                                height: 110,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            )
                          else if (currentPlatePhoto.isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: _buildPlateImageWidget(currentPlatePhoto, height: 110, width: double.infinity),
                            )
                          else
                            Container(
                              height: 70,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withAlpha(8) : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.photo_camera_rounded, color: Colors.grey, size: 26),
                                  SizedBox(height: 4),
                                  Text('Sin foto de placa registrada', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    side: const BorderSide(color: Color(0xFFDC2626)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  icon: const Icon(Icons.camera_alt_rounded, size: 16, color: Color(0xFFDC2626)),
                                  label: const Text('Cámara', style: TextStyle(color: Color(0xFFDC2626), fontSize: 11.5, fontWeight: FontWeight.bold)),
                                  onPressed: () async {
                                    final picker = ImagePicker();
                                    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 900);
                                    if (picked != null) {
                                      setDlgState(() => tempPlatePhotoFile = File(picked.path));
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    side: const BorderSide(color: Color(0xFF0284C7)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  icon: const Icon(Icons.photo_library_rounded, size: 16, color: Color(0xFF0284C7)),
                                  label: const Text('Galería', style: TextStyle(color: Color(0xFF0284C7), fontSize: 11.5, fontWeight: FontWeight.bold)),
                                  onPressed: () async {
                                    final picker = ImagePicker();
                                    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 900);
                                    if (picked != null) {
                                      setDlgState(() => tempPlatePhotoFile = File(picked.path));
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Estado SOAT / Documentos:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: soatStatus.contains('Vigente') ? 'Vigente ✅' : (soatStatus.contains('Exento') ? 'Exento (Bicicleta) 🚲' : 'En Trámite ⚠️'),
                      items: const [
                        DropdownMenuItem(value: 'Vigente ✅', child: Text('Vigente ✅')),
                        DropdownMenuItem(value: 'En Trámite ⚠️', child: Text('En Trámite ⚠️')),
                        DropdownMenuItem(value: 'Exento (Bicicleta) 🚲', child: Text('Exento (Bicicleta) 🚲')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDlgState(() => soatStatus = val);
                        }
                      },
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    if (modelCtrl.text.trim().isEmpty || plateCtrl.text.trim().isEmpty || colorCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('⚠️ Por favor ingresa el modelo, placa y color del vehículo.'),
                          backgroundColor: Color(0xFFDC2626),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (updated == true) {
      final finalModel = modelCtrl.text.trim();
      final finalPlate = plateCtrl.text.trim().toUpperCase();
      final finalColor = colorCtrl.text.trim();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('driver_vehicle_model', finalModel);
      await prefs.setString('driver_vehicle_plate', finalPlate);
      await prefs.setString('driver_vehicle_color', finalColor);
      await prefs.setString('driver_vehicle_soat', soatStatus);

      String platePhotoPath = currentPlatePhoto;
      if (tempPlatePhotoFile != null) {
        try {
          final bytes = await tempPlatePhotoFile!.readAsBytes();
          platePhotoPath = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        } catch (_) {
          platePhotoPath = tempPlatePhotoFile!.path;
        }
        await prefs.setString('driver_vehicle_plate_photo', platePhotoPath);
      }

      setState(() {
        _vehicleModel = finalModel;
        _vehiclePlate = finalPlate;
        _vehicleColor = finalColor;
        _vehicleSoat = soatStatus;
        _vehiclePlatePhoto = platePhotoPath;
      });

      // Sincronizar en Firestore para que el cliente lo vea en el rastreo en vivo
      final user = ref.read(authNotifierProvider).user;
      if (user != null && user.id.isNotEmpty) {
        try {
          await FirebaseFirestore.instance.collection('users').doc(user.id).set({
            'vehicleModel': finalModel,
            'vehiclePlate': finalPlate,
            'vehicleColor': finalColor,
            'vehicleSoat': soatStatus,
            if (platePhotoPath.isNotEmpty) 'vehiclePlatePhotoUrl': platePhotoPath,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (_) {}
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Datos del vehículo y placa actualizados correctamente.'),
            backgroundColor: Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Muestra un diálogo obligatorio para que el repartidor registre su teléfono
  /// antes de poder recibir pedidos (el cliente necesita poder contactarlo).
  Future<void> _showRequireDriverPhoneDialog() async {
    final phoneCtrl = TextEditingController(text: _driverPhone);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final enteredPhone = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1712) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.phone_android_rounded, color: Color(0xFFDC2626)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Teléfono Obligatorio 📱',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withAlpha(15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDC2626).withAlpha(60)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_rounded, color: Color(0xFFDC2626), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'El cliente necesita tu número para contactarte por WhatsApp o llamada al momento de la entrega.',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Tu número de celular o WhatsApp *',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Ej: 3201234567',
                prefixIcon: const Icon(Icons.phone_rounded, size: 20),
                filled: true,
                fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.save_rounded, size: 18),
            label: const Text('Guardar y Continuar'),
            onPressed: () => Navigator.pop(ctx, phoneCtrl.text.trim()),
          ),
        ],
      ),
    );

    if (enteredPhone == null || enteredPhone.length < 7) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Debes registrar un teléfono válido para recibir pedidos.'),
            backgroundColor: Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    setState(() => _driverPhone = enteredPhone);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set({'phone': enteredPhone}, SetOptions(merge: true));
      } catch (_) {}
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Teléfono guardado. ¡Ahora puedes recibir pedidos!'),
          backgroundColor: Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showEditProfileDialog() async {
    final nameCtrl = TextEditingController(text: _driverName);
    final phoneCtrl = TextEditingController(text: _driverPhone);

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1712) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.person_pin_rounded, color: Color(0xFFDC2626)),
              SizedBox(width: 8),
              Text('Editar Perfil Repartidor 👤', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Nombre Completo:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    hintText: 'Tu nombre',
                    filled: true,
                    fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Número de Teléfono / WhatsApp:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                const SizedBox(height: 6),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: 'Ej: 317 116 6497',
                    filled: true,
                    fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    if (updated == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('driver_name', nameCtrl.text.trim());
      if (phoneCtrl.text.trim().isEmpty) {
        await prefs.remove('driver_phone');
      } else {
        await prefs.setString('driver_phone', phoneCtrl.text.trim());
      }

      setState(() {
        _driverName = nameCtrl.text.trim().isEmpty ? 'Repartidor La Diabla' : nameCtrl.text.trim();
        _driverPhone = phoneCtrl.text.trim();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Perfil actualizado correctamente.'),
            backgroundColor: Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
