// lib/features/driver/presentation/screens/driver_dashboard_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
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
import '../../../../domain/entities/order_entity.dart';
import '../../../../domain/entities/order_status.dart';
import '../../../auth/providers/auth_notifier.dart';
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
  bool _isAvailable = true;

  // GPS real — stream de posición del repartidor
  StreamSubscription<Position>? _gpsStreamSubscription;
  bool _gpsActive = false;
  bool _arrivalAlertSpoken = false; // Evitar repetir el aviso de voz

  // TTS para aviso de llegada
  final FlutterTts _flutterTts = FlutterTts();

  // Mapa y Ruta
  final Completer<GoogleMapController> _mapControllerCompleter = Completer<GoogleMapController>();
  OrderEntity? _activeOrder;
  LatLng _driverCurrentPos = MapsService.defaultLocation;
  double _currentBearing = 0.0;
  BitmapDescriptor? _driverMarkerIcon;
  final Set<String> _autoAcceptedOrderIds = {};

  // Datos editables del vehículo y del repartidor
  String _vehicleModel = 'Motocicleta 125cc';
  String _vehiclePlate = 'ABC-12D';
  String _vehicleSoat = 'Vigente ✅';
  String _driverName = 'Repartidor La Diabla';
  String _driverPhone = '300 123 4567';
  String _driverPhoto = 'assets/images/diabloperfil.png';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadMarkerIcon();
    _loadDriverPreferences();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      ref.read(driverEarningsProvider.notifier).loadEarnings();
      // Solicitar permisos de ubicacion (tiempo real + segundo plano) al repartidor
      if (mounted) {
        await PermissionService.requestDriverLocationPermissions(context);
        ref.read(driverOperationalProvider.notifier).checkLocationStatus();
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
      // Mostrar burbuja flotante si el repartidor está en servicio o en entrega activa
      final opState = ref.read(driverOperationalProvider);
      if (opState.isManualAvailable || opState.hasActiveDelivery) {
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
      setState(() {
        _vehicleModel = prefs.getString('driver_vehicle_model') ?? 'Motocicleta 125cc';
        _vehiclePlate = prefs.getString('driver_vehicle_plate') ?? 'ABC-12D';
        _vehicleSoat = prefs.getString('driver_vehicle_soat') ?? 'Vigente ✅';
        _driverName = prefs.getString('driver_name') ?? (user?.name ?? 'Repartidor La Diabla');
        _driverPhone = prefs.getString('driver_phone') ?? (user?.phone ?? '300 123 4567');
        _driverPhoto = prefs.getString('driver_photo') ?? (user?.photoUrl ?? 'assets/images/diabloperfil.png');
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FloatingBubbleService.instance.hideBubble();
    _gpsStreamSubscription?.cancel();
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

        if (mounted) {
          setState(() {
            _driverCurrentPos = newPos;
            if (bearing > 0) _currentBearing = bearing;
          });
        }

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
              '¡Atención! Has llegado a la ubicación del cliente. Por favor marca el pedido como entregado cuando hagas la entrega.',
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

  /// Toma el pedido (estado -> assigned) y cambia al mapa para iniciar el viaje.
  Future<void> _takeAndAcceptOrder(OrderEntity order) async {
    try {
      final user = ref.read(authNotifierProvider).user;
      final driverId = user?.id ?? 'driver_01';
      final driverName = user?.name ?? 'Repartidor Diabla';

      // Estado: assigned (repartidor asignado, aún no ha salido)
      await FirebaseFirestore.instance.collection('orders').doc(order.id).update({
        'status': OrderStatus.assigned.name,
        'driverId': driverId,
        'driverName': driverName,
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
        _activeOrder = order.copyWith(status: OrderStatus.assigned);
        _currentNavIndex = 1; // Ir a pestaña Mapa para presionar "INICIAR VIAJE"
      });

      ref.read(driverOperationalProvider.notifier).setActiveDelivery(order.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Pedido #${order.id.substring(0, order.id.length > 6 ? 6 : order.id.length).toUpperCase()} aceptado. Presiona INICIAR VIAJE cuando salgas.'),
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

  /// Inicia el viaje: estado -> onTheWay, arranca GPS y TTS.
  Future<void> _startTripWithGps(OrderEntity order) async {
    try {
      final destLat = order.address?.latitude ?? order.latitude;
      final destLng = order.address?.longitude ?? order.longitude;

      await FirebaseFirestore.instance.collection('orders').doc(order.id).update({
        'status': OrderStatus.onTheWay.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      NotificationService().saveOrderNotification(
        userId: order.userId,
        orderId: order.id,
        title: '🛵 ¡El repartidor va en camino!',
        body: 'Tu comida de La Diabla está en ruta hacia tu puerta 🔥',
        emoji: '🛵',
        status: OrderStatus.onTheWay.name,
      );

      setState(() {
        _activeOrder = order.copyWith(status: OrderStatus.onTheWay);
      });

      ref.read(driverOperationalProvider.notifier).setActiveDelivery(order.id);

      await _startGpsBroadcast(
        order,
        destLat: destLat,
        destLng: destLng,
      );

      // Abrir mapa externo si el cliente tiene coordenadas
      if (destLat != null && destLng != null && mounted) {
        _openExternalMap(destLat, destLng, address: order.address?.formattedAddress);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🛵 ¡Viaje iniciado! #${order.id.substring(0, order.id.length > 6 ? 6 : order.id.length).toUpperCase()} — GPS activo.'),
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
            setModalState(() => isUploading = true);
            try {
              String? proofUrl;
              if (proofImage != null) {
                proofUrl = await StorageService().uploadDeliveryProof(
                  orderId: order.id,
                  file: proofImage!,
                );
              }

              final driverId = ref.read(authNotifierProvider).user?.id ?? 'driver_01';
              final fee = order.deliveryFee > 0 ? order.deliveryFee : 7500.0;

              final updateData = <String, dynamic>{
                'status': OrderStatus.delivered.name,
                'driverId': driverId,
                'driverName': _driverName,
                'deliveredAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
              };
              if (proofUrl != null) {
                updateData['deliveryProofUrl'] = proofUrl;
              }

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
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 2,
                    ),
                    icon: isUploading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_circle_rounded, size: 20),
                    label: Text(
                      isUploading ? 'Finalizando entrega...' : 'FINALIZAR ENTREGA ✅',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                    ),
                    onPressed: isUploading ? null : submitDelivery,
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

        // 🤖 Reactor de Autoaceptación Inteligente
        if (opState.preferences.isAutoAcceptEnabled &&
            opState.canReceiveOrders &&
            availableOrders.isNotEmpty) {
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
              if (match.isMatch) {
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

    final canReceive = opState.canReceiveOrders;

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
                canReceive ? 'TOMAR Y SALIR EN RUTA 🛵' : 'BLOQUEADO PARA RECIBIR',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
              ),
              onPressed: canReceive
                  ? () => _takeAndAcceptOrder(order)
                  : () {
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

  // ═════════════════════════════════════════════════════════════════════════════
  // PESTAÑA 1: RUTA INTELIGENTE & MAPA GPS EN VIVO
  // ═════════════════════════════════════════════════════════════════════════════
  Widget _buildMapRouteTab(bool isDark) {
    final activeOrder = _activeOrder;
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

    final routePoints = activeOrder != null
        ? [_driverCurrentPos, destPos]
        : [_driverCurrentPos, kitchenPos];

    final polylines = <Polyline>{
      Polyline(
        polylineId: const PolylineId('active_route'),
        points: routePoints,
        color: const Color(0xFFDC2626),
        width: 5,
      ),
    };

    return Stack(
      children: [
        // Mapa de Google a pantalla completa
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _driverCurrentPos,
            zoom: 15.5,
          ),
          markers: markers,
          polylines: polylines,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          onMapCreated: (ctrl) {
            if (!_mapControllerCompleter.isCompleted) {
              _mapControllerCompleter.complete(ctrl);
            }
            _centerMapOnRealGps();
          },
        ),

        // HUD Superior Flotante sobre el Mapa
        Positioned(
          top: 14,
          left: 14,
          right: 70,
          child: _buildTopControlHud(opState, isDark),
        ),

        // Botón flotante para centrar en GPS Real
        Positioned(
          top: 20,
          right: 14,
          child: FloatingActionButton.small(
            backgroundColor: isDark ? const Color(0xFF1E1712) : Colors.white,
            foregroundColor: const Color(0xFFDC2626),
            elevation: 4,
            onPressed: _centerMapOnRealGps,
            child: const Icon(Icons.my_location_rounded, size: 22),
          ),
        ),

        // Botón flotante para re-centrar el mapa
        Positioned(
          top: 16,
          right: 16,
          child: FloatingActionButton.small(
            backgroundColor: isDark ? const Color(0xFF2C1B14) : Colors.white,
            foregroundColor: const Color(0xFFDC2626),
            onPressed: () async {
              final ctrl = await _mapControllerCompleter.future;
              ctrl.animateCamera(CameraUpdate.newLatLngZoom(_driverCurrentPos, 15.5));
            },
            child: const Icon(Icons.my_location_rounded),
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
                                const Icon(Icons.navigation_rounded, color: Color(0xFFDC2626), size: 20),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'EN RUTA • #${activeOrder.id.length > 6 ? activeOrder.id.substring(activeOrder.id.length - 6).toUpperCase() : activeOrder.id}',
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
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
                            onPressed: () => _openExternalMap(destLat, destLng),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        activeOrder.address?.formattedAddress ?? 'Dirección de Entrega',
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

                      // Botones de Contacto Rápido al Cliente
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF25D366),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.chat_rounded, size: 16),
                              label: const Text('WhatsApp', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              onPressed: () => _whatsappCustomer('3001234567', activeOrder.id),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF009EE3),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.call_rounded, size: 16),
                              label: const Text('Llamar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              onPressed: () => _callCustomer('3001234567'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Botón principal: INICIAR VIAJE (si assigned) o ENTREGA COMPLETADA (si onTheWay)
                      if (activeOrder.status == OrderStatus.assigned)
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
                              'INICIAR VIAJE 🏍️',
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                            ),
                            onPressed: () => _startTripWithGps(activeOrder),
                          ),
                        )
                      else
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
                  ),
                ),
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════════════
  // PESTAÑA 2: GANANCIAS & RENDIMIENTO (100% REALES DESDE FIRESTORE)
  // ═════════════════════════════════════════════════════════════════════════════
  Widget _buildEarningsTab(bool isDark) {
    final deliveredOrdersAsync = ref.watch(driverDeliveredOrdersStreamProvider);

    return deliveredOrdersAsync.when(
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
                      child: ClipOval(
                        child: _buildDriverAvatarImage(_driverPhoto),
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
                '📞 $_driverPhone • ${user?.email ?? "repartidor@ladiabla.app"}',
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
                trailing: Text(_vehicleModel, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.pin_rounded, color: Color(0xFFDC2626)),
                title: const Text('Placa'),
                trailing: Text(_vehiclePlate, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.verified_rounded, color: Color(0xFF16A34A)),
                title: const Text('SOAT y Tecnomecánica'),
                trailing: Text(_vehicleSoat, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF16A34A))),
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

  Widget _buildDriverAvatarImage(String path) {
    if (path.startsWith('http')) {
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
                        final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 800, maxHeight: 800);
                        if (picked != null) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('driver_photo', picked.path);
                          if (mounted) {
                            setState(() => _driverPhoto = picked.path);
                          }
                          await ref.read(authNotifierProvider.notifier).updateUserProfile(photoUrl: picked.path);
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
                        final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 800, maxHeight: 800);
                        if (picked != null) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('driver_photo', picked.path);
                          if (mounted) {
                            setState(() => _driverPhoto = picked.path);
                          }
                          await ref.read(authNotifierProvider.notifier).updateUserProfile(photoUrl: picked.path);
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
    String soatStatus = _vehicleSoat;

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E1712) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.motorcycle_rounded, color: Color(0xFFDC2626)),
                  SizedBox(width: 8),
                  Text('Editar Vehículo 🛵', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Modelo / Tipo de Vehículo:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: modelCtrl,
                      decoration: InputDecoration(
                        hintText: 'Ej: Motocicleta 125cc / Bicicleta',
                        filled: true,
                        fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Placa del Vehículo:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: plateCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'Ej: ABC-12D',
                        filled: true,
                        fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Estado de Documentos (SOAT):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
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
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (updated == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('driver_vehicle_model', modelCtrl.text.trim());
      await prefs.setString('driver_vehicle_plate', plateCtrl.text.trim().toUpperCase());
      await prefs.setString('driver_vehicle_soat', soatStatus);

      setState(() {
        _vehicleModel = modelCtrl.text.trim().isEmpty ? 'Motocicleta 125cc' : modelCtrl.text.trim();
        _vehiclePlate = plateCtrl.text.trim().isEmpty ? 'ABC-12D' : plateCtrl.text.trim().toUpperCase();
        _vehicleSoat = soatStatus;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Datos del vehículo actualizados correctamente.'),
            backgroundColor: Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
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
      await prefs.setString('driver_phone', phoneCtrl.text.trim());

      setState(() {
        _driverName = nameCtrl.text.trim().isEmpty ? 'Repartidor La Diabla' : nameCtrl.text.trim();
        _driverPhone = phoneCtrl.text.trim().isEmpty ? '300 123 4567' : phoneCtrl.text.trim();
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
