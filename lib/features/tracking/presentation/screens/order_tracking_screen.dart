// lib/features/tracking/presentation/screens/order_tracking_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/services/maps_service.dart';
import '../../../../core/utils/price_formatter.dart';
import '../../../../core/widgets/diabla_card.dart';
import '../../../../core/widgets/diabla_offline_view.dart';
import '../../../../domain/entities/order_entity.dart';
import '../../../../domain/entities/order_status.dart';
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
  // ignore: unused_field  // reservado para futuras animaciones de cámara
  GoogleMapController? _mapController;
  bool _notifiedArrival = false;
  bool _promptedRating = false;

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
        infoWindow: InfoWindow(
          title: 'Repartidor La Diabla 🛵',
          snippet: 'A ${(distanceToDestKm * 1000).toInt()}m de tu destino',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
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

    final polylines = <Polyline>{
      Polyline(
        polylineId: const PolylineId('driver_route'),
        points: [
          MapsService.defaultLocation,
          driverPos,
          destPos,
        ],
        color: const Color(0xFFDC2626),
        width: 5,
        patterns: [PatternItem.dash(20), PatternItem.gap(10)],
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
                  'CALIFICAR COMIDA Y DAR PROPINA ⭐',
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
              recibidoTime: order.createdAt != null
                  ? _fmtTime(order.createdAt!)
                  : '--',
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

          // Mapa interactivo Google Maps con Ruta en Vivo
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              height: 270,
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
                  zoom: 14.8,
                ),
                onMapCreated: (ctrl) => _mapController = ctrl,
                markers: markers,
                polylines: polylines,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Banner unificado de ayuda / soporte 24/7 en vivo
          OrderSupportBanner(
            orderId: widget.orderId,
            title: '¿Tienes alguna duda con tu entrega?',
            subtitle: 'Escríbele a nuestro asistente de IA o solicita la atención de un asesor humano por WhatsApp de inmediato.',
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

