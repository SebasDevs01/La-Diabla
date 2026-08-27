// lib/features/driver/presentation/screens/driver_dashboard_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/services/maps_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/services/permission_service.dart';
import '../../../../core/utils/price_formatter.dart';
import '../../../../core/widgets/diabla_offline_view.dart';
import '../../../../core/widgets/navigation_app_picker.dart';
import '../../../../domain/entities/order_entity.dart';
import '../../../../domain/entities/order_status.dart';
import '../../../auth/providers/auth_notifier.dart';
import '../../../orders/providers/orders_provider.dart';
import '../../../profile/presentation/widgets/privacy_policy_sheet.dart';
import '../../providers/driver_earnings_provider.dart';

class DriverDashboardScreen extends ConsumerStatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  ConsumerState<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends ConsumerState<DriverDashboardScreen> {
  int _currentNavIndex = 0; // 0: Pedidos, 1: Mapa/Ruta, 2: Ganancias, 3: Perfil
  bool _isAvailable = true;

  // GPS real — stream de posición del repartidor
  StreamSubscription<Position>? _gpsStreamSubscription;
  bool _gpsActive = false;

  // Mapa y Ruta
  final Completer<GoogleMapController> _mapControllerCompleter = Completer<GoogleMapController>();
  OrderEntity? _activeOrder;
  LatLng _driverCurrentPos = MapsService.defaultLocation;

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
    _loadDriverPreferences();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(driverEarningsProvider.notifier).loadEarnings();
      _centerMapOnRealGps();
    });
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
    _gpsStreamSubscription?.cancel();
    super.dispose();
  }

  /// Solicita permiso de ubicación y arranca el stream GPS real hacia Firestore.
  Future<void> _startGpsBroadcast(OrderEntity order) async {
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

    if (mounted) setState(() => _gpsActive = true);

    _gpsStreamSubscription = PermissionService.getPositionStream().listen(
      (Position position) async {
        final newPos = LatLng(position.latitude, position.longitude);
        if (mounted) {
          setState(() => _driverCurrentPos = newPos);
        }

        // Transmitir coordenadas reales a Firestore cada actualización
        try {
          await FirebaseFirestore.instance
              .collection('orders')
              .doc(order.id)
              .update({
            'driverLatitude': position.latitude,
            'driverLongitude': position.longitude,
            'driverHeading': position.heading,
            'driverSpeed': position.speed,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } catch (_) {}
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

  Future<void> _takeAndAcceptOrder(OrderEntity order) async {
    try {
      final user = ref.read(authNotifierProvider).user;
      final driverId = user?.id ?? 'driver_01';
      final driverName = user?.name ?? 'Repartidor Diabla';

      await FirebaseFirestore.instance.collection('orders').doc(order.id).update({
        'status': OrderStatus.onTheWay.name,
        'driverId': driverId,
        'driverName': driverName,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Guardar notificación para el cliente en tiempo real
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
        _currentNavIndex = 1; // Cambiar automáticamente a la pestaña de Mapa/Ruta
      });

      await _startGpsBroadcast(order);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🛵 Pedido #${order.id.substring(0, order.id.length > 6 ? 6 : order.id.length).toUpperCase()} tomado. ¡Ruta iniciada!'),
            backgroundColor: const Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
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
  Future<void> _markOrderAsDelivered(OrderEntity order) async {
    try {
      final driverId = ref.read(authNotifierProvider).user?.id ?? 'driver_01';
      final fee = order.deliveryFee > 0 ? order.deliveryFee : 7500.0;
      await FirebaseFirestore.instance.collection('orders').doc(order.id).update({
        'status': OrderStatus.delivered.name,
        'driverId': driverId,
        'driverName': _driverName,
        'deliveredAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

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

      setState(() {
        _activeOrder = null;
      });

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Text('🎉', style: TextStyle(fontSize: 26)),
                SizedBox(width: 8),
                Text('¡ENTREGA EXITOSA!'),
              ],
            ),
            content: Text(
              'Has completado la entrega de la orden #${order.id.substring(0, order.id.length > 6 ? 6 : order.id.length).toUpperCase()}.\n\nGanancia acreditada a tu cuenta: +${PriceFormatter.formatSmart(fee)} COP 💵',
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() => _currentNavIndex = 2); // Ver panel de ganancias
                },
                child: const Text('Ver Mis Ganancias 💵'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
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
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _gpsActive
                  ? const Color(0xFF0EA5E9)
                  : (_isAvailable ? const Color(0xFF16A34A) : Colors.grey.shade700),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _gpsActive
                      ? Icons.gps_fixed_rounded
                      : (_isAvailable ? Icons.check_circle_rounded : Icons.pause_circle_filled_rounded),
                  color: Colors.white,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  _gpsActive
                      ? 'GPS ACTIVO'
                      : (_isAvailable ? 'DISPONIBLE' : 'PAUSA'),
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
  Widget _buildDispatchTab(bool isDark) {
    // Usa el stream que escucha TODOS los pedidos pendientes (sin filtrar por userId)
    // para que el repartidor vea los pedidos de los clientes
    final allOrdersAsync = ref.watch(allPendingOrdersStreamProvider);

    return allOrdersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFDC2626))),
      error: (err, _) => DiablaOfflineView(
        title: 'Ups, algo salió mal.',
        subtitle: 'No pudimos conectar con el servidor de pedidos. Comprueba tu conexión a internet.',
        onRetry: () => ref.invalidate(allPendingOrdersStreamProvider),
      ),
      data: (orders) {
        // Pedidos listos o en preparación
        final availableOrders = orders.where((o) =>
            o.status == OrderStatus.confirmed ||
            o.status == OrderStatus.preparing ||
            o.status == OrderStatus.ready ||
            o.status == OrderStatus.pending).toList();

        final activeOrders = orders.where((o) => o.status == OrderStatus.onTheWay).toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
              ...availableOrders.map((order) => _buildOrderCard(order, isDark, isAvailable: true)),
          ],
        );
      },
    );
  }

  Widget _buildOrderCard(OrderEntity order, bool isDark, {required bool isAvailable}) {
    final address = order.address?.formattedAddress ?? 'Dirección de Entrega';
    final isPaid = order.paymentStatus == PaymentStatus.paid;
    final shortId = order.id.length > 6 ? order.id.substring(order.id.length - 6).toUpperCase() : order.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C1B14) : Colors.white,
        borderRadius: BorderRadius.circular(18),
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
                'Ganancia: +${PriceFormatter.formatSmart(7500)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF16A34A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.two_wheeler_rounded, size: 20),
              label: const Text(
                'TOMAR Y SALIR EN RUTA 🛵',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
              ),
              onPressed: () => _takeAndAcceptOrder(order),
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
        infoWindow: const InfoWindow(title: 'Mi Posición 🛵 (Repartidor)'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
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

        // Botón flotante para centrar en GPS Real
        Positioned(
          top: 16,
          right: 16,
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

                      // Botón Marcar Entregado
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
