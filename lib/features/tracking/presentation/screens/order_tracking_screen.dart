// lib/features/tracking/presentation/screens/order_tracking_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/services/maps_service.dart';
import '../../../../core/utils/price_formatter.dart';
import '../../../../core/widgets/diabla_card.dart';
import '../../../../core/widgets/diabla_offline_view.dart';
import '../../../../domain/entities/order_entity.dart';
import '../../../../domain/entities/order_status.dart';
import '../../../driver/presentation/widgets/animated_driver_marker.dart';
import '../../../auth/providers/auth_notifier.dart';
import '../../../orders/presentation/screens/order_chat_screen.dart';
import '../../../orders/presentation/widgets/order_rating_tip_sheet.dart';
import '../../../orders/presentation/widgets/order_stepper_widget.dart';
import '../../../orders/presentation/widgets/order_support_banner.dart';
import '../../../orders/presentation/widgets/order_support_sheet.dart';
import '../../../orders/providers/orders_provider.dart';

class OrderTrackingScreen extends ConsumerStatefulWidget {
  const OrderTrackingScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen> {
  final Completer<GoogleMapController> _mapCompleter = Completer<GoogleMapController>();
  bool _notifiedArrival = false;

  BitmapDescriptor? _driverIcon;
  List<LatLng> _routePoints = [];
  bool _isLoadingRoute = false;
  LatLng? _lastDriverPos;
  double _driverBearing = 0.0;
  String _etaText = '';
  String? _cachedRouteKey;

  // Live animated driver marker interpolation
  LatLng? _animatedDriverPos;
  Timer? _lerpTimer;
  bool _isCameraFollowing = true;

  // Phase-aware route tracking (kitchen route vs client route)
  List<LatLng> _kitchenRoutePoints = [];
  bool _isLoadingKitchenRoute = false;
  String? _cachedKitchenRouteKey;
  String _kitchenEtaText = '';

  @override
  void initState() {
    super.initState();
    _loadDriverIcon();
  }

  @override
  void dispose() {
    _lerpTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDriverIcon() async {
    try {
      final icon = await AnimatedDriverMarker.getDriverIcon();
      if (mounted) setState(() => _driverIcon = icon);
    } catch (_) {}
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $suffix';
  }

  void _showSupportSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => OrderSupportSheet(orderId: widget.orderId),
    );
  }

  void _checkProximityAlert(double distanceKm) {
    if (distanceKm <= 0.4 && !_notifiedArrival) {
      _notifiedArrival = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Text('🛵', style: TextStyle(fontSize: 20)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '¡El repartidor está a menos de 400m de tu puerta! 🔥',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
          ),
        );
      });
    }
  }

  /// Anima suavemente el icono del repartidor interpolando entre posición anterior y nueva (LERP)
  void _smoothMoveMarker(LatLng from, LatLng to) {
    _lerpTimer?.cancel();
    const steps = 30;
    int step = 0;
    _lerpTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted) { timer.cancel(); return; }
      step++;
      final t = step / steps;
      final lat = from.latitude + (to.latitude - from.latitude) * t;
      final lng = from.longitude + (to.longitude - from.longitude) * t;
      setState(() => _animatedDriverPos = LatLng(lat, lng));
      if (step >= steps) {
        timer.cancel();
        // Camera follow: suavemente centrar en la posición del repartidor
        if (_isCameraFollowing && _mapCompleter.isCompleted) {
          _mapCompleter.future.then((ctrl) {
            ctrl.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: LatLng(lat, lng),
                  zoom: 16.0,
                  bearing: _driverBearing > 0 ? _driverBearing : 0.0,
                ),
              ),
            );
          }).catchError((_) {});
        }
      }
    });
  }

  /// Calcula la ruta óptima por calles reales (OSRM) para la fase actual
  Future<void> _ensureSmartRoute(LatLng driverPos, LatLng destPos) async {
    final routeKey =
        '${driverPos.latitude.toStringAsFixed(4)},${driverPos.longitude.toStringAsFixed(4)}->${destPos.latitude.toStringAsFixed(4)},${destPos.longitude.toStringAsFixed(4)}';
    if (_cachedRouteKey == routeKey || _isLoadingRoute) return;
    _cachedRouteKey = routeKey;
    _isLoadingRoute = true;

    if (_lastDriverPos != null) {
      final bearing = MapsService.calculateBearing(_lastDriverPos!, driverPos);
      if (bearing > 0) _driverBearing = bearing;
    }

    // Animate the marker smoothly from old → new position
    if (_lastDriverPos != null && _animatedDriverPos != null) {
      _smoothMoveMarker(_animatedDriverPos!, driverPos);
    } else {
      _animatedDriverPos = driverPos;
    }
    _lastDriverPos = driverPos;

    try {
      final details = await MapsService().getRouteDetails(driverPos, destPos);
      if (mounted) {
        setState(() {
          _routePoints = details.points;
          _etaText = '${details.durationMinutes} - ${details.durationMinutes + 6} min';
          _isLoadingRoute = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _routePoints = [driverPos, destPos];
          _isLoadingRoute = false;
        });
      }
    }
  }

  /// Calcula la ruta del repartidor a la cocina central (Fase 1)
  Future<void> _ensureKitchenRoute(LatLng driverPos, LatLng kitchenPos) async {
    final routeKey =
        '${driverPos.latitude.toStringAsFixed(4)},${driverPos.longitude.toStringAsFixed(4)}->kitchen';
    if (_cachedKitchenRouteKey == routeKey || _isLoadingKitchenRoute) return;
    _cachedKitchenRouteKey = routeKey;
    _isLoadingKitchenRoute = true;

    try {
      final details = await MapsService().getRouteDetails(driverPos, kitchenPos);
      if (mounted) {
        setState(() {
          _kitchenRoutePoints = details.points;
          _kitchenEtaText = '${details.durationMinutes} - ${details.durationMinutes + 5} min';
          _isLoadingKitchenRoute = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _kitchenRoutePoints = [driverPos, kitchenPos];
          _isLoadingKitchenRoute = false;
        });
      }
    }
  }

  Future<void> _centerOnDriver(LatLng driverPos) async {
    if (!_mapCompleter.isCompleted) return;
    final ctrl = await _mapCompleter.future;
    ctrl.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: driverPos, zoom: 16.5,
            bearing: _driverBearing > 0 ? _driverBearing : 0.0),
      ),
    );
    setState(() => _isCameraFollowing = true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final orderAsync = ref.watch(singleOrderStreamProvider(widget.orderId));
    final shortId = widget.orderId.length > 6
        ? widget.orderId.substring(widget.orderId.length - 6).toUpperCase()
        : widget.orderId.toUpperCase();

    return Scaffold(
      backgroundColor: isDark ? AppColors.surfaceDark : const Color(0xFFFAF7F2),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
        title: Text(
          'RASTREO #$shortId 🚴',
          style: const TextStyle(
            fontFamily: AppTypography.displayFamily,
            fontSize: 20,
            letterSpacing: 1.0,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: Color(0xFFDC2626)),
            tooltip: 'Soporte de Pedido',
            onPressed: () => _showSupportSheet(context),
          ),
        ],
      ),
      body: orderAsync.when(
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (err, _) => DiablaOfflineView(
          title: 'Ups, algo salió mal.',
          subtitle: 'No pudimos cargar la información de este pedido. Comprueba tu conexión a internet.',
          onRetry: () => ref.invalidate(singleOrderStreamProvider(widget.orderId)),
        ),
        data: (order) {
          if (order == null) {
            return DiablaOfflineView(
              title: 'Pedido no encontrado',
              subtitle: 'Este pedido no existe o aún no ha sido sincronizado con el servidor.',
              onRetry: () => ref.invalidate(singleOrderStreamProvider(widget.orderId)),
            );
          }
          return _buildTrackingContent(order, isDark);
        },
      ),
    );
  }

  Widget _buildTrackingContent(OrderEntity order, bool isDark) {
    final currentStatus = order.status;
    final kitchenPos = MapsService.defaultLocation;

    final destLat = order.latitude ?? order.address?.latitude ?? 7.092758;
    final destLng = order.longitude ?? order.address?.longitude ?? -73.142590;
    final destPos = LatLng(destLat, destLng);

    // Posición del repartidor en tiempo real (viene de Firestore via watchOrder stream)
    final driverLat = order.driverLatitude ?? (destLat + 0.0035);
    final driverLng = order.driverLongitude ?? (destLng + 0.0028);
    final driverPos = LatLng(driverLat, driverLng);

    // Fase del repartidor: heading_to_kitchen = yendo a cocina, heading_to_client = yendo al cliente
    final isHeadingToKitchen = order.driverPhase == 'heading_to_kitchen';

    // Si hay heading real del driver, usarlo
    if (order.driverHeading != null && order.driverHeading! > 0) {
      _driverBearing = order.driverHeading!;
    }

    // Trigger smooth animation when driver position changes
    final liveDriverPos = _animatedDriverPos ?? driverPos;
    if (_lastDriverPos == null ||
        (_lastDriverPos!.latitude - driverPos.latitude).abs() > 0.00003 ||
        (_lastDriverPos!.longitude - driverPos.longitude).abs() > 0.00003) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (_lastDriverPos != null) {
            _smoothMoveMarker(_animatedDriverPos ?? _lastDriverPos!, driverPos);
          } else {
            setState(() => _animatedDriverPos = driverPos);
          }
          _lastDriverPos = driverPos;
        }
      });
    }

    final distanceToDestKm = MapsService.calculateDistanceKm(driverPos, destPos);
    final distanceToKitchenKm = MapsService.calculateDistanceKm(driverPos, kitchenPos);
    if (currentStatus == OrderStatus.onTheWay) {
      _checkProximityAlert(distanceToDestKm);
    }

    final bool isDelivered = currentStatus == OrderStatus.delivered;

    // Cargar ruta por calles reales según la fase actual
    if (!isDelivered && currentStatus != OrderStatus.cancelled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (isHeadingToKitchen) {
          _ensureKitchenRoute(driverPos, kitchenPos);
          _ensureSmartRoute(kitchenPos, destPos); // Pre-cargar la ruta a cliente también
        } else {
          _ensureSmartRoute(driverPos, destPos);
        }
      });
    }

    final markers = isDelivered
        ? <Marker>{
            Marker(
              markerId: const MarkerId('destination'),
              position: destPos,
              infoWindow: InfoWindow(
                title: '¡Entregado aquí! 🏠🎉',
                snippet: order.address?.formattedAddress ?? 'Dirección de Entrega',
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            ),
          }
        : <Marker>{
            // Marcador Cocina Central (siempre visible)
            Marker(
              markerId: const MarkerId('restaurant'),
              position: kitchenPos,
              infoWindow: const InfoWindow(title: 'La Diabla 🌶️', snippet: 'Cocina Central • Cl. 59 # 39W-24'),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
            ),
            // Marcador del repartidor con animación suave de posición
            Marker(
              markerId: const MarkerId('driver'),
              position: liveDriverPos,
              rotation: _driverBearing,
              flat: true,
              anchor: const Offset(0.5, 0.5),
              infoWindow: InfoWindow(
                title: 'Tu Repartidor 🛵',
                snippet: isHeadingToKitchen
                    ? (_kitchenEtaText.isNotEmpty ? 'En cocina: $_kitchenEtaText (${(distanceToKitchenKm * 1000).toInt()}m)' : 'Recogiendo tu pedido...')
                    : (_etaText.isNotEmpty ? 'Llegada: $_etaText (${(distanceToDestKm * 1000).toInt()}m)' : 'En camino a tu dirección'),
              ),
              icon: _driverIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
            ),
            // Marcador destino del cliente
            Marker(
              markerId: const MarkerId('destination'),
              position: destPos,
              infoWindow: InfoWindow(
                title: 'Tu Dirección 🏠',
                snippet: order.address?.formattedAddress ?? 'Dirección de Entrega',
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            ),
          };

    // Rutas dinámicas según la fase:
    // Fase 1 (heading_to_kitchen): Repartidor → Cocina (naranja) + Cocina → Cliente (rojo punteado)
    // Fase 2 (heading_to_client): Solo Repartidor → Cliente (rojo sólido)
    final Set<Polyline> polylines;
    if (isDelivered) {
      polylines = {};
    } else if (isHeadingToKitchen) {
      final kitchenPts = _kitchenRoutePoints.isNotEmpty ? _kitchenRoutePoints : [liveDriverPos, kitchenPos];
      final clientPts = _routePoints.isNotEmpty ? _routePoints : [kitchenPos, destPos];
      polylines = {
        // Ruta repartidor → cocina (naranja fuego)
        Polyline(
          polylineId: const PolylineId('kitchen_route_shadow'),
          points: kitchenPts,
          color: const Color(0xFF78350F),
          width: 8,
        ),
        Polyline(
          polylineId: const PolylineId('kitchen_route'),
          points: kitchenPts,
          color: const Color(0xFFF59E0B),
          width: 5,
        ),
        // Ruta cocina → cliente (rojo suave, punteado para indicar "futura")
        Polyline(
          polylineId: const PolylineId('client_route_preview_shadow'),
          points: clientPts,
          color: const Color(0xFF7F1D1D).withAlpha(120),
          width: 6,
          patterns: [PatternItem.dash(20), PatternItem.gap(10)],
        ),
        Polyline(
          polylineId: const PolylineId('client_route_preview'),
          points: clientPts,
          color: const Color(0xFFDC2626).withAlpha(160),
          width: 4,
          patterns: [PatternItem.dash(20), PatternItem.gap(10)],
        ),
      };
    } else {
      final routePoints = _routePoints.isNotEmpty ? _routePoints : [liveDriverPos, destPos];
      polylines = {
        Polyline(
          polylineId: const PolylineId('driver_route_shadow'),
          points: routePoints,
          color: const Color(0xFF7F1D1D),
          width: 7,
        ),
        Polyline(
          polylineId: const PolylineId('driver_route'),
          points: routePoints,
          color: const Color(0xFFDC2626),
          width: 4,
        ),
      };
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner Animado de Proximidad (<400m)
          if (distanceToDestKm <= 0.4 && currentStatus == OrderStatus.onTheWay)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFDC2626), Color(0xFFB91C1C)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
                ],
              ),
              child: const Row(
                children: [
                  Text('🛵', style: TextStyle(fontSize: 24)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '¡REPARTIDOR A MENOS DE 400 METROS! 🔥',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 12.5,
                          ),
                        ),
                        Text(
                          'Ten listo el timbre, tu comida está llegando.',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Banner en tiempo real de fase del repartidor (recogiendo en cocina / en camino)
          if (currentStatus == OrderStatus.assigned || currentStatus == OrderStatus.onTheWay)
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('orders').doc(widget.orderId).snapshots(),
              builder: (context, snap) {
                final phase = (snap.data?.data() as Map<String, dynamic>?)?['driverPhase'] as String? ?? 'heading_to_client';
                final isHeadingToKitchen = phase == 'heading_to_kitchen';
                if (!isHeadingToKitchen) return const SizedBox.shrink();
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFD97706), Color(0xFFB45309)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
                    ],
                  ),
                  child: const Row(
                    children: [
                      Text('📦', style: TextStyle(fontSize: 24)),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'REPARTIDOR RECOGIENDO TU PEDIDO 🏍️',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 12.5,
                              ),
                            ),
                            Text(
                              'Tu repartidor está en camino a la cocina central para reclamar tu orden.',
                              style: TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

          // Botón destacado de Calificación si ya fue entregado
          if (currentStatus == OrderStatus.delivered)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.star_rate_rounded, size: 22),
                label: const Text(
                  'CALIFICAR COMIDA Y REPARTIDOR ⭐',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onPressed: () => OrderRatingTipSheet.show(context, order),
              ),
            ),

          // Header de estado con fondo rojo Diabla
          DiablaCard(
            backgroundColor: const Color(0xFFDC2626),
            child: Row(
              children: [
                Image.asset(
                  'assets/images/delivery.png',
                  width: 65,
                  height: 55,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Text('🔥', style: TextStyle(fontSize: 36)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentStatus.displayName.toUpperCase(),
                        style: const TextStyle(
                          fontFamily: AppTypography.displayFamily,
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isDelivered
                            ? 'Total: ${PriceFormatter.formatSmart(order.total)} • ¡Entregado con éxito! 🎉'
                            : 'Total: ${PriceFormatter.formatSmart(order.total)} • A ${(distanceToDestKm * 1000).toInt()}m de tu casa',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Stepper de los 5 estados con íconos personalizados
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.cardDark : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
                width: 1.2,
              ),
            ),
            child: OrderStepperWidget(
              status: currentStatus,
              recibidoTime: order.createdAt != null ? _fmtTime(order.createdAt!) : '--',
              confirmadoTime: order.status.index >= OrderStatus.confirmed.index && order.createdAt != null
                  ? _fmtTime(order.createdAt!.add(const Duration(minutes: 2)))
                  : '-',
              preparandoTime: order.status.index >= OrderStatus.preparing.index && order.createdAt != null
                  ? _fmtTime(order.createdAt!.add(const Duration(minutes: 4)))
                  : '-',
              enCaminoTime: order.status.index >= OrderStatus.onTheWay.index && order.createdAt != null
                  ? _fmtTime(order.createdAt!.add(const Duration(minutes: 12)))
                  : '-',
              entregadoTime: currentStatus == OrderStatus.delivered && order.createdAt != null
                  ? _fmtTime(order.createdAt!.add(const Duration(minutes: 25)))
                  : '-',
            ),
          ),
          const SizedBox(height: 20),

          // Mapa interactivo Google Maps en Vivo (Estilo Uber/InDriver)
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                Container(
                  height: 340,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isDark ? AppColors.dividerDark : Colors.grey.shade300,
                      width: 1.2,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: isDelivered ? destPos : liveDriverPos,
                      zoom: 15.0,
                    ),
                    onMapCreated: (ctrl) {
                      if (!_mapCompleter.isCompleted) _mapCompleter.complete(ctrl);
                    },
                    onCameraMoveStarted: () {
                      if (_isCameraFollowing) {
                        setState(() => _isCameraFollowing = false);
                      }
                    },
                    markers: markers,
                    polylines: polylines,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                  ),
                ),

                // Badge Flotante con ETA — compacto, parte inferior del mapa
                Positioned(
                  bottom: 50,
                  left: 12,
                  right: 56,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1712).withAlpha(230) : Colors.white.withAlpha(235),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
                      ],
                      border: Border.all(
                        color: isDelivered
                            ? const Color(0xFF16A34A).withAlpha(150)
                            : (isHeadingToKitchen
                                ? const Color(0xFFF59E0B).withAlpha(180)
                                : const Color(0xFFDC2626).withAlpha(120)),
                        width: 1.2,
                      ),
                    ),
                    child: isDelivered
                        ? const Row(
                            children: [
                              Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 19),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '¡Pedido Entregado con éxito! 🎉',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isHeadingToKitchen
                                          ? const Color(0xFFF59E0B)
                                          : const Color(0xFF16A34A),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    isHeadingToKitchen
                                        ? (_kitchenEtaText.isNotEmpty ? '📦 Cocina: $_kitchenEtaText' : '📦 Recogiendo pedido...')
                                        : (_etaText.isNotEmpty ? '🛵 Llegada: $_etaText' : '🛵 Calculando ruta...'),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ],
                              ),
                              Text(
                                isHeadingToKitchen
                                    ? '${distanceToKitchenKm.toStringAsFixed(1)} km'
                                    : '${distanceToDestKm.toStringAsFixed(1)} km',
                                style: TextStyle(
                                  color: isHeadingToKitchen
                                      ? const Color(0xFFF59E0B)
                                      : const Color(0xFFDC2626),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),

                // Botón de centrar mapa en el repartidor
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: GestureDetector(
                    onTap: () => _centerOnDriver(liveDriverPos),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _isCameraFollowing
                            ? const Color(0xFFDC2626)
                            : (isDark ? const Color(0xFF2C1B14) : Colors.white),
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2)),
                        ],
                      ),
                      child: Icon(
                        _isCameraFollowing ? Icons.navigation_rounded : Icons.my_location_rounded,
                        color: _isCameraFollowing
                            ? Colors.white
                            : const Color(0xFFDC2626),
                        size: 22,
                      ),
                    ),
                  ),
                ),

                // Badge de fase (Recogiendo/En Camino) — esquina superior izquierda
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isHeadingToKitchen
                          ? const Color(0xFFF59E0B).withAlpha(220)
                          : const Color(0xFFDC2626).withAlpha(220),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isHeadingToKitchen ? Icons.storefront_rounded : Icons.navigation_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isHeadingToKitchen ? 'Recogiendo pedido' : 'En camino a ti',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Comprobante de Entrega fotográfico registrado por el repartidor
          if (order.deliveryProofUrl != null && order.deliveryProofUrl!.isNotEmpty) ...[
            _buildDeliveryProofCard(order.deliveryProofUrl!, isDark),
            const SizedBox(height: 20),
          ],

          // Tarjeta de Repartidor visible en todo momento si está asignado o el pedido lo referencia
          if (order.driverId != null ||
              order.driverName != null ||
              order.status.index >= OrderStatus.assigned.index) ...[
            _buildDriverProfileCard(order, isDark),
            const SizedBox(height: 20),
          ],

          // Banner unificado de ayuda / soporte 24/7 en vivo
          OrderSupportBanner(
            orderId: widget.orderId,
            title: '¿Tienes alguna duda con tu entrega?',
            subtitle:
                'Escríbele a nuestro asistente de IA o solicita la atención de un asesor humano por WhatsApp de inmediato.',
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// Tarjeta de Comprobante de Entrega fotográfico registrado por el repartidor
  Widget _buildDeliveryProofCard(String proofUrl, bool isDark) {
    return Container(
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
          Row(
            children: [
              const Icon(Icons.photo_camera_rounded, color: Color(0xFF16A34A), size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'COMPROBANTE DE ENTREGA 📸',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: Color(0xFF16A34A),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A).withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Verificada',
                  style: TextStyle(
                    color: Color(0xFF16A34A),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Foto capturada por el repartidor al momento de entregarte el pedido:',
            style: TextStyle(fontSize: 11.5, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => _showProfilePhotoDialog(context, proofUrl, 'Comprobante de Entrega'),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  proofUrl.startsWith('data:image/')
                      ? Image.memory(
                          base64Decode(proofUrl.split(',').last),
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            height: 180,
                            color: Colors.grey.shade300,
                            child: const Center(child: Icon(Icons.broken_image, size: 40)),
                          ),
                        )
                      : Image.network(
                          proofUrl,
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            height: 180,
                            color: Colors.grey.shade300,
                            child: const Center(child: Icon(Icons.broken_image, size: 40)),
                          ),
                        ),
                  Container(
                    margin: const EdgeInsets.all(8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(180),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.zoom_in_rounded, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'Toca para ampliar',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tarjeta del Repartidor asignado con Foto, Calificación, Contacto y Reseñas
  Widget _buildDriverProfileCard(OrderEntity order, bool isDark) {
    final driverId = order.driverId ?? 'driver_01';
    final fallbackName = order.driverName ?? 'Repartidor La Diabla';
    final bool isDelivered = order.status == OrderStatus.delivered;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(driverId).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final driverName = data?['name'] as String? ?? fallbackName;
        final phone = data?['phone'] as String? ?? '';
        final vehicleModel = data?['vehicleModel'] as String? ?? '';
        final vehiclePlate = data?['vehiclePlate'] as String? ?? '';
        final vehicleColor = data?['vehicleColor'] as String? ?? '';
        final ratingAvg = (data?['driverAverageRating'] as num?)?.toDouble() ?? 5.0;
        final ratingCount = (data?['driverRatingCount'] as num?)?.toInt() ?? 0;
        // Priority: live Firestore profile → photo saved in the order → default asset
        final rawPhoto = (data?['photoUrl'] as String?)?.isNotEmpty == true
            ? (data!['photoUrl'] as String)
            : (order.driverPhotoUrl ?? '');
        final driverPhotoUrl = rawPhoto.isNotEmpty ? rawPhoto : 'assets/images/diabloperfil.png';

        final vehicleParts = <String>[];
        if (vehicleModel.isNotEmpty) vehicleParts.add(vehicleModel);
        if (vehiclePlate.isNotEmpty) vehicleParts.add('Placa: $vehiclePlate');
        if (vehicleColor.isNotEmpty) vehicleParts.add('Color: $vehicleColor');
        final vehicleDisplay = vehicleParts.isNotEmpty ? vehicleParts.join(' • ') : 'Repartidor Autorizado';

        Widget buildDriverAvatarWidget(String url) {
          if (url.startsWith('data:image/')) {
            try {
              final bytes = base64Decode(url.split(',').last);
              return Image.memory(
                bytes,
                fit: BoxFit.cover,
                width: 58,
                height: 58,
                errorBuilder: (context, error, stackTrace) => Image.asset('assets/images/diabloperfil.png', fit: BoxFit.cover, width: 58, height: 58),
              );
            } catch (_) {
              return Image.asset('assets/images/diabloperfil.png', fit: BoxFit.cover, width: 58, height: 58);
            }
          } else if (url.startsWith('http')) {
            return Image.network(
              url,
              fit: BoxFit.cover,
              width: 58,
              height: 58,
              errorBuilder: (context, error, stackTrace) => Image.asset('assets/images/diabloperfil.png', fit: BoxFit.cover, width: 58, height: 58),
            );
          } else if (url.startsWith('assets/')) {
            return Image.asset(
              url,
              fit: BoxFit.cover,
              width: 58,
              height: 58,
              errorBuilder: (context, error, stackTrace) => Image.asset('assets/images/diabloperfil.png', fit: BoxFit.cover, width: 58, height: 58),
            );
          }
          return Image.asset('assets/images/diabloperfil.png', fit: BoxFit.cover, width: 58, height: 58);
        }

        return Container(
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
              if (isDelivered)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16A34A).withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF16A34A), width: 1),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 14),
                      SizedBox(width: 5),
                      Text(
                        'Tu repartidor en esta entrega 🛵✅',
                        style: TextStyle(
                          color: Color(0xFF16A34A),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  // Foto de perfil del repartidor — toca para ver ampliada
                  GestureDetector(
                    onTap: () => _showProfilePhotoDialog(context, driverPhotoUrl, driverName),
                    child: Stack(
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFDC2626), width: 2.5),
                            color: const Color(0xFF1E1712),
                          ),
                          child: ClipOval(
                            child: buildDriverAvatarWidget(driverPhotoUrl),
                          ),
                        ),
                        if (driverPhotoUrl.isNotEmpty)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFDC2626),
                              ),
                              child: const Icon(Icons.zoom_in_rounded, color: Colors.white, size: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                driverName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.verified_rounded, color: Color(0xFF16A34A), size: 16),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          vehicleDisplay,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B).withAlpha(30),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star_rate_rounded, color: Color(0xFFF59E0B), size: 14),
                                  const SizedBox(width: 3),
                                  Text(
                                    ratingAvg.toStringAsFixed(1),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Color(0xFFD97706),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '($ratingCount entregas)',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 22),

              // Botones de Contacto (siempre disponibles)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF16A34A),
                        side: const BorderSide(color: Color(0xFF16A34A), width: 1.3),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                      ),
                      icon: const Icon(Icons.chat_bubble_rounded, size: 16),
                      label: const Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () async {
                        final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
                        final shortId = widget.orderId.length > 6
                            ? widget.orderId.substring(widget.orderId.length - 6).toUpperCase()
                            : widget.orderId;
                        final url = Uri.parse(
                          'https://wa.me/57$cleanPhone?text=Hola,%20te%20escribo%20sobre%20mi%20pedido%20de%20La%20Diabla%20%23$shortId%20🔥',
                        );
                        try {
                          await launchUrl(url, mode: LaunchMode.externalApplication);
                        } catch (_) {}
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0284C7),
                        side: const BorderSide(color: Color(0xFF0284C7), width: 1.3),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                      ),
                      icon: const Icon(Icons.phone_rounded, size: 16),
                      label: const Text('Llamar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () async {
                        final url = Uri.parse('tel:$phone');
                        try {
                          await launchUrl(url);
                        } catch (_) {}
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Botón "Chat con el Repartidor"
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
                  label: Text(
                    isDelivered ? 'Ver Chat del Pedido 💬' : 'Chat con el Repartidor 💬',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                  onPressed: () {
                    final currentUser = ref.read(authNotifierProvider).user;
                    final currentUserId = currentUser?.id ?? 'customer';
                    final currentUserName = currentUser?.name ?? 'Cliente';
                    final currentUserPhoto = currentUser?.photoUrl;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OrderChatScreen(
                          orderId: widget.orderId,
                          currentUserId: currentUserId,
                          currentUserName: currentUserName,
                          currentUserRole: 'customer',
                          peerName: driverName,
                          peerPhone: phone,
                          peerRole: 'Repartidor',
                          peerPhotoUrl: driverPhotoUrl,
                          currentUserPhotoUrl: currentUserPhoto,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 4),

              // Botón "Ver Reseñas del Repartidor"
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.rate_review_outlined, size: 16),
                  label: const Text(
                    'Ver opiniones y reseñas de este repartidor ⭐',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  onPressed: () => _showDriverReviewsSheet(
                    context,
                    driverId: driverId,
                    driverName: driverName,
                    ratingAvg: ratingAvg,
                    ratingCount: ratingCount,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Muestra la foto de perfil o comprobante en pantalla completa con soporte de zoom.
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

  /// Despliega el bottom sheet de reseñas del repartidor
  void _showDriverReviewsSheet(
    BuildContext context, {
    required String driverId,
    required String driverName,
    required double ratingAvg,
    required int ratingCount,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;

        return Container(
          height: MediaQuery.of(ctx).size.height * 0.70,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1712) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reseñas de $driverName',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 18),
                          const SizedBox(width: 4),
                          Text(
                            '${ratingAvg.toStringAsFixed(1)} ★ ($ratingCount opiniones)',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const Divider(height: 24),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(driverId)
                      .collection('driver_reviews')
                      .orderBy('createdAt', descending: true)
                      .limit(20)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                    }

                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('⭐', style: TextStyle(fontSize: 40)),
                            const SizedBox(height: 8),
                            const Text(
                              '¡Repartidor destacado!',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Calificación promedio de ${ratingAvg.toStringAsFixed(1)} basada en entregas puntuales.',
                              style: TextStyle(color: isDark ? AppColors.textMutedDark : Colors.grey.shade600, fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: docs.length,
                      separatorBuilder: (context, index) => const Divider(height: 16),
                      itemBuilder: (context, i) {
                        final r = docs[i].data() as Map<String, dynamic>;
                        final stars = (r['rating'] as num?)?.toInt() ?? 5;
                        final comment = r['comment'] as String? ?? '¡Excelente servicio y muy rápido!';
                        final customerName = r['customerName'] as String? ?? 'Cliente Diabla';

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(customerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                Row(
                                  children: List.generate(
                                    5,
                                    (idx) => Icon(
                                      Icons.star_rounded,
                                      size: 14,
                                      color: idx < stars ? const Color(0xFFF59E0B) : Colors.grey.shade400,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (comment.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                comment,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
