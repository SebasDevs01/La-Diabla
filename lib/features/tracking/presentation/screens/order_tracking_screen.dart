// lib/features/tracking/presentation/screens/order_tracking_screen.dart
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
  // ignore: unused_field
  GoogleMapController? _mapController;
  bool _notifiedArrival = false;
  bool _promptedRating = false;

  BitmapDescriptor? _driverIcon;
  List<LatLng> _routePoints = [];
  bool _isLoadingRoute = false;
  LatLng? _lastDriverPos;
  double _driverBearing = 0.0;
  String _etaText = '';
  String? _cachedRouteKey;

  @override
  void initState() {
    super.initState();
    _loadDriverIcon();
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

  void _checkDeliveredRating(OrderEntity order) {
    if (order.status == OrderStatus.delivered && !_promptedRating) {
      _promptedRating = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        OrderRatingTipSheet.show(context, order);
      });
    }
  }

  /// Calcula la ruta óptima por calles reales (OSRM) para el cliente
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

    final destLat = order.latitude ?? order.address?.latitude ?? 7.092758;
    final destLng = order.longitude ?? order.address?.longitude ?? -73.142590;
    final destPos = LatLng(destLat, destLng);

    // Posición del repartidor (si viene de Firestore o calculada en ruta)
    final driverLat = order.driverLatitude ?? (destLat + 0.0035);
    final driverLng = order.driverLongitude ?? (destLng + 0.0028);
    final driverPos = LatLng(driverLat, driverLng);

    final distanceToDestKm = MapsService.calculateDistanceKm(driverPos, destPos);
    if (currentStatus == OrderStatus.onTheWay) {
      _checkProximityAlert(distanceToDestKm);
    }
    _checkDeliveredRating(order);

    // Cargar ruta por calles reales si aún no se ha obtenido
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureSmartRoute(driverPos, destPos);
    });

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('restaurant'),
        position: MapsService.defaultLocation,
        infoWindow: const InfoWindow(title: 'La Diabla 🌶️', snippet: 'Cocina Central'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      ),
      Marker(
        markerId: const MarkerId('driver'),
        position: driverPos,
        rotation: _driverBearing,
        flat: true,
        anchor: const Offset(0.5, 0.5),
        infoWindow: InfoWindow(
          title: 'Repartidor La Diabla 🛵',
          snippet: _etaText.isNotEmpty
              ? 'Llegada: $_etaText (${(distanceToDestKm * 1000).toInt()}m)'
              : 'A ${(distanceToDestKm * 1000).toInt()}m de tu destino',
        ),
        icon: _driverIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
      ),
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

    final routePoints = _routePoints.isNotEmpty ? _routePoints : [driverPos, destPos];

    final polylines = <Polyline>{
      // Sombra oscura para alto contraste estilo Waze
      Polyline(
        polylineId: const PolylineId('driver_route_shadow'),
        points: routePoints,
        color: const Color(0xFF7F1D1D),
        width: 7,
      ),
      // Línea principal rojo fuego sobre las calles
      Polyline(
        polylineId: const PolylineId('driver_route'),
        points: routePoints,
        color: const Color(0xFFDC2626),
        width: 4,
      ),
    };

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
                        'Total: ${PriceFormatter.formatSmart(order.total)} • A ${(distanceToDestKm * 1000).toInt()}m de tu casa',
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

          // Mapa interactivo Google Maps con Ruta en Vivo por Calles Reales (Estilo Uber)
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                Container(
                  height: 280,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isDark ? AppColors.dividerDark : Colors.grey.shade300,
                      width: 1.2,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: driverPos,
                      zoom: 15.2,
                    ),
                    onMapCreated: (ctrl) => _mapController = ctrl,
                    markers: markers,
                    polylines: polylines,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                  ),
                ),

                // Badge Flotante con ETA en tiempo real estilo Uber
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1712).withAlpha(230) : Colors.white.withAlpha(235),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
                      ],
                      border: Border.all(
                        color: const Color(0xFFDC2626).withAlpha(120),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF16A34A),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _etaText.isNotEmpty ? 'Llegada: $_etaText' : 'Calculando ruta...',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                            ),
                          ],
                        ),
                        Text(
                          '${distanceToDestKm.toStringAsFixed(1)} km',
                          style: const TextStyle(
                            color: Color(0xFFDC2626),
                            fontWeight: FontWeight.w900,
                            fontSize: 12.5,
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

          // Tarjeta de Repartidor con Reseñas y Calificaciones (Estilo Rappi)
          if (order.status.index >= OrderStatus.assigned.index) ...[
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

  /// Tarjeta del Repartidor asignado con Foto, Calificación, Contacto y Reseñas
  Widget _buildDriverProfileCard(OrderEntity order, bool isDark) {
    final driverId = order.driverId ?? 'driver_01';
    final fallbackName = order.driverName ?? 'Repartidor La Diabla';

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

        final vehicleParts = <String>[];
        if (vehicleModel.isNotEmpty) vehicleParts.add(vehicleModel);
        if (vehiclePlate.isNotEmpty) vehicleParts.add('Placa: $vehiclePlate');
        if (vehicleColor.isNotEmpty) vehicleParts.add('Color: $vehicleColor');
        final vehicleDisplay = vehicleParts.isNotEmpty ? vehicleParts.join(' • ') : 'Repartidor Autorizado';

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
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFDC2626), width: 2),
                      color: const Color(0xFF1E1712),
                    ),
                    child: const Center(
                      child: Text('🛵', style: TextStyle(fontSize: 26)),
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

              // Botones de Contacto y Botón de Reseñas
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
                  label: const Text(
                    'Chat con el Repartidor 💬',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                  onPressed: () {
                    final currentUserId = ref.read(authNotifierProvider).user?.id ?? 'customer';
                    final currentUserName = ref.read(authNotifierProvider).user?.name ?? 'Cliente';
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
