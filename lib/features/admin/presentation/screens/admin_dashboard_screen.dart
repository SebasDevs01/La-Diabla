// lib/features/admin/presentation/screens/admin_dashboard_screen.dart
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/utils/price_formatter.dart';
import '../../../../domain/entities/user_entity.dart';
import '../../../auth/providers/auth_notifier.dart';
import '../../../checkout/providers/coupon_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../domain/entities/product_entity.dart';
import '../../../../mock/mock_products.dart';
import '../../../home/providers/home_provider.dart';
import '../widgets/product_form_modal.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _filterStatus = 'all';
  String _productCategoryFilter = 'all';
  String _productSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ─── Status colors and labels ─────────────────────────────────────────────
  Color _statusColor(String status) {
    switch (status) {
      case 'pending':    return const Color(0xFFF59E0B);
      case 'confirmed':  return const Color(0xFF3B82F6);
      case 'preparing':  return const Color(0xFF8B5CF6);
      case 'ready':      return const Color(0xFF06B6D4);
      case 'onTheWay':   return const Color(0xFF10B981);
      case 'delivered':  return const Color(0xFF16A34A);
      case 'cancelled':  return const Color(0xFFEF4444);
      default:           return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':    return '⏳ Pendiente';
      case 'confirmed':  return '✅ Confirmado';
      case 'preparing':  return '🍳 Preparando';
      case 'ready':      return '📦 Listo';
      case 'onTheWay':   return '🛵 En camino';
      case 'delivered':  return '✅ Entregado';
      case 'cancelled':  return '❌ Cancelado';
      default:           return status;
    }
  }

  // ─── Order status progression ────────────────────────────────────────────
  String? _nextStatus(String current) {
    const progression = {
      'pending':   'confirmed',
      'confirmed': 'preparing',
      'preparing': 'ready',
      'ready':     'onTheWay',
      'onTheWay':  'delivered',
    };
    return progression[current];
  }

  Future<void> _advanceStatus(String orderId, String currentStatus, {String? userId}) async {
    final next = _nextStatus(currentStatus);
    if (next == null) return;
    await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
      'status': next,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (userId != null && userId.isNotEmpty) {
      String title = '🔥 Estado de tu pedido actualizado';
      String body = 'Tu pedido en La Diabla pasó a ${_statusLabel(next)}';
      String emoji = '🌮';

      if (next == 'confirmed') {
        title = '✅ ¡Pedido confirmado por el restaurante!';
        body = 'La Diabla ha recibido tu orden y pasará a cocina pronto 🔥';
        emoji = '✅';
      } else if (next == 'preparing') {
        title = '🍳 ¡Tus platillos están en la plancha!';
        body = 'Nuestros taqueros están preparando tu comida con el mejor sazón 🌶️';
        emoji = '🍳';
      } else if (next == 'ready') {
        title = '📦 ¡Pedido empacado y listo para despacho!';
        body = 'Asignando el repartidor más cercano para llevarlo a tu puerta 🛵';
        emoji = '📦';
      }

      NotificationService().saveOrderNotification(
        userId: userId,
        orderId: orderId,
        title: title,
        body: body,
        emoji: emoji,
        status: next,
      );
    }
  }

  Future<void> _cancelOrder(String orderId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar pedido'),
        content: const Text('Esta acción no se puede deshacer. El pedido será marcado como cancelado.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancelar pedido'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
        'status': 'cancelled',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = ref.watch(authNotifierProvider).user;

    final isAuthorized = user?.role == UserRole.admin ||
        user?.email == 'appladiabla@gmail.com' ||
        user?.isGuest == false;

    // Guard: solo usuarios autorizados o admin
    if (!isAuthorized && user == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline_rounded, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('Acceso restringido', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Solo administradores (appladiabla@gmail.com) pueden acceder a este panel.'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.go('/home'),
                child: const Text('Volver al inicio'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0A08) : const Color(0xFFF8F5F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFDC2626),
        foregroundColor: Colors.white,
        title: Row(
          children: [
            Image.asset('assets/images/logo.png', height: 32),
            const SizedBox(width: 10),
            const Text(
              'PANEL ADMIN',
              style: TextStyle(
                fontFamily: AppTypography.displayFamily,
                fontSize: 22,
                letterSpacing: 2,
                color: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Cerrar sesion',
            onPressed: () async {
              final router = GoRouter.of(context);
              await ref.read(authNotifierProvider.notifier).signOut();
              if (mounted) router.go('/auth');
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.receipt_long_rounded), text: 'Pedidos'),
            Tab(icon: Icon(Icons.restaurant_menu_rounded), text: 'Menú'),
            Tab(icon: Icon(Icons.bar_chart_rounded), text: 'Stats'),
            Tab(icon: Icon(Icons.local_offer_rounded), text: 'Cupones'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOrdersTab(isDark),
          _buildProductsTab(isDark),
          _buildStatsTab(isDark),
          _buildCouponsTab(isDark),
        ],
      ),
    );
  }

  // ─── Tab 1: Pedidos en tiempo real ────────────────────────────────────────

  Widget _buildOrdersTab(bool isDark) {
    return Column(
      children: [
        // Filtros
        SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              _FilterChip(label: 'Todos', value: 'all', selected: _filterStatus == 'all', onTap: () => setState(() => _filterStatus = 'all')),
              _FilterChip(label: '⏳ Pendientes', value: 'pending', selected: _filterStatus == 'pending', onTap: () => setState(() => _filterStatus = 'pending')),
              _FilterChip(label: '🍳 Preparando', value: 'preparing', selected: _filterStatus == 'preparing', onTap: () => setState(() => _filterStatus = 'preparing')),
              _FilterChip(label: '🛵 En camino', value: 'onTheWay', selected: _filterStatus == 'onTheWay', onTap: () => setState(() => _filterStatus = 'onTheWay')),
              _FilterChip(label: '✅ Entregados', value: 'delivered', selected: _filterStatus == 'delivered', onTap: () => setState(() => _filterStatus = 'delivered')),
              _FilterChip(label: '📸 Evidencias', value: 'evidence', selected: _filterStatus == 'evidence', onTap: () => setState(() => _filterStatus = 'evidence')),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _orderStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Color(0xFFDC2626)));
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text('No hay pedidos activos', style: TextStyle(color: Colors.grey)));
              }
              final docs = snapshot.data!.docs;
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                itemBuilder: (ctx, i) {
                  final data = docs[i].data() as Map<String, dynamic>;
                  final orderId = docs[i].id;
                  return _OrderCard(
                    orderId: orderId,
                    data: data,
                    isDark: isDark,
                    statusColor: _statusColor(data['status'] as String? ?? ''),
                    statusLabel: _statusLabel(data['status'] as String? ?? ''),
                    nextStatus: _nextStatus(data['status'] as String? ?? ''),
                    onAdvance: () => _advanceStatus(orderId, data['status'] as String? ?? '', userId: data['userId'] as String?),
                    onCancel: () => _cancelOrder(orderId),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Stream<QuerySnapshot> _orderStream() {
    Query query = FirebaseFirestore.instance
        .collection('orders')
        .orderBy('createdAt', descending: true)
        .limit(60);
    if (_filterStatus == 'evidence') {
      query = query.where('status', isEqualTo: 'delivered');
    } else if (_filterStatus != 'all') {
      query = query.where('status', isEqualTo: _filterStatus);
    }
    return query.snapshots();
  }

  // ─── Tab 2: Estadisticas ──────────────────────────────────────────────────

  Widget _buildStatsTab(bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('createdAt',
              isGreaterThan: Timestamp.fromDate(
                  DateTime.now().subtract(const Duration(days: 30))))
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        int total = docs.length;
        int delivered = docs.where((d) => (d.data() as Map)['status'] == 'delivered').length;
        int pending = docs.where((d) {
          final s = (d.data() as Map)['status'] as String? ?? '';
          return s != 'delivered' && s != 'cancelled';
        }).length;
        double revenue = docs
            .where((d) => (d.data() as Map)['status'] == 'delivered')
            .fold(0.0, (acc, d) => acc + ((d.data() as Map)['total'] as num? ?? 0).toDouble());

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ULTIMOS 30 DIAS',
                  style: TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 20, letterSpacing: 2, color: Colors.grey.shade500)),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.4,
                children: [
                  _StatCard(label: 'Total Pedidos', value: '$total', icon: Icons.receipt_long_rounded, color: const Color(0xFF3B82F6), isDark: isDark),
                  _StatCard(label: 'Entregados', value: '$delivered', icon: Icons.check_circle_rounded, color: const Color(0xFF16A34A), isDark: isDark),
                  _StatCard(label: 'En Proceso', value: '$pending', icon: Icons.pending_rounded, color: const Color(0xFFF59E0B), isDark: isDark),
                  _StatCard(label: 'Ingresos', value: PriceFormatter.formatSmart(revenue), icon: Icons.attach_money_rounded, color: const Color(0xFFDC2626), isDark: isDark),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Tab 3: Gestion de Cupones ────────────────────────────────────────────

  Widget _buildCouponsTab(bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('coupons').snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  Text('Cupones activos (${docs.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const Spacer(),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                    onPressed: () => _showAddCouponSheet(isDark),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Nuevo'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: docs.length,
                itemBuilder: (ctx, i) {
                  final data = docs[i].data() as Map<String, dynamic>;
                  final code = docs[i].id;
                  final active = data['active'] as bool? ?? false;
                  final type = data['type'] as String? ?? 'fixed';
                  final discount = (data['discount'] as num? ?? 0).toDouble();
                  final minOrder = (data['minOrder'] as num? ?? 0).toDouble();

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: active ? const Color(0xFF16A34A).withAlpha(30) : Colors.grey.withAlpha(30),
                        child: Icon(Icons.local_offer_rounded,
                            color: active ? const Color(0xFF16A34A) : Colors.grey),
                      ),
                      title: Text(code, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Courier')),
                      subtitle: Text(
                        type == 'percent'
                            ? '$discount% dcto — Min \$${minOrder.toStringAsFixed(0)}'
                            : '-\$${discount.toStringAsFixed(0)} — Min \$${minOrder.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Switch.adaptive(
                        value: active,
                        activeTrackColor: const Color(0xFFDC2626),
                        onChanged: (val) => FirebaseFirestore.instance
                            .collection('coupons')
                            .doc(code)
                            .update({'active': val}),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _showAddCouponSheet(bool isDark) {
    final codeCtrl = TextEditingController();
    final discountCtrl = TextEditingController();
    final minOrderCtrl = TextEditingController(text: '25.000');
    String type = 'fixed';
    bool singleUse = true;

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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Crear Cupón 🌶️', style: TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 20)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626).withAlpha(20),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('Validez: 30 Días ⏳', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Código (ej: ENVIOGRATIS, DIABLO20)',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (type != 'freeDelivery') ...[
                      Expanded(
                        child: TextField(
                          controller: discountCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: type == 'percent' ? 'Porcentaje (%) ej: 10' : 'Valor fijo (COP) ej: 5.000',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'fixed', label: Text('\$')),
                          ButtonSegment(value: 'percent', label: Text('%')),
                          ButtonSegment(value: 'freeDelivery', label: Text('🛵')),
                        ],
                        selected: {type},
                        onSelectionChanged: (s) => setSheetState(() => type = s.first),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: minOrderCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Pedido mínimo (COP) ej: 25.000',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: singleUse,
                  title: const Text('Cupón de un solo uso por cliente 🎟️', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Cada cliente podrá canjearlo una única vez', style: TextStyle(fontSize: 11.5)),
                  activeTrackColor: const Color(0xFFDC2626),
                  onChanged: (val) => setSheetState(() => singleUse = val),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626), padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: () async {
                      final code = codeCtrl.text.trim().toUpperCase();
                      if (code.isEmpty) return;

                      final messenger = ScaffoldMessenger.of(context);
                      final parsedDiscount = type == 'freeDelivery'
                          ? 4500.0
                          : CouponNotifier.parseMoneyOrPercent(discountCtrl.text, isPercent: type == 'percent');
                      final parsedMinOrder = CouponNotifier.parseMoneyOrPercent(minOrderCtrl.text);

                      final expiresAt = DateTime.now().add(const Duration(days: 30));

                      await FirebaseFirestore.instance.collection('coupons').doc(code).set({
                        'active': true,
                        'type': type,
                        'discount': parsedDiscount,
                        'minOrder': parsedMinOrder,
                        'singleUse': singleUse,
                        'description': type == 'freeDelivery'
                            ? 'Envío 100% Gratis 🛵'
                            : (type == 'percent'
                                ? '${parsedDiscount.toInt()}% de descuento 🔥'
                                : '\$${PriceFormatter.formatSmart(parsedDiscount)} COP de descuento 🌶️'),
                        'createdAt': FieldValue.serverTimestamp(),
                        'expiresAt': Timestamp.fromDate(expiresAt),
                      }, SetOptions(merge: true));

                      if (ctx.mounted) Navigator.pop(ctx);
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('✅ Cupón $code creado exitosamente (Válido 30 días)'),
                          backgroundColor: const Color(0xFF16A34A),
                        ),
                      );
                    },
                    child: const Text('Crear cupón', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Tab 4: Gestión Dinámica de Productos / Menú ───────────────────────────
  Widget _buildProductsTab(bool isDark) {
    final productsAsync = ref.watch(adminProductsStreamProvider);

    return Column(
      children: [
        // Barra superior: Botón crear + Botón sembrar catálogo
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: isDark ? const Color(0xFF1E1712) : Colors.white,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => ProductFormModal.show(context),
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                      label: const Text('Nuevo Producto', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF16A34A),
                      side: const BorderSide(color: Color(0xFF16A34A), width: 1.2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                    ),
                    onPressed: _showSeedCatalogDialog,
                    icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                    label: const Text('Sembrar Menú', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Campo de búsqueda
              TextField(
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre o ingrediente...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  filled: true,
                  fillColor: isDark ? Colors.black26 : const Color(0xFFFAF7F2),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                onChanged: (val) => setState(() => _productSearchQuery = val.trim().toLowerCase()),
              ),
              const SizedBox(height: 8),
              // Categorías
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _FilterChip(
                      label: 'Todos',
                      value: 'all',
                      selected: _productCategoryFilter == 'all',
                      onTap: () => setState(() => _productCategoryFilter = 'all'),
                    ),
                    _FilterChip(
                      label: '🌮 Tacos',
                      value: 'tacos',
                      selected: _productCategoryFilter == 'tacos',
                      onTap: () => setState(() => _productCategoryFilter = 'tacos'),
                    ),
                    _FilterChip(
                      label: '🌯 Burritos',
                      value: 'burritos',
                      selected: _productCategoryFilter == 'burritos',
                      onTap: () => setState(() => _productCategoryFilter = 'burritos'),
                    ),
                    _FilterChip(
                      label: '🧀 Quesadillas',
                      value: 'quesadillas',
                      selected: _productCategoryFilter == 'quesadillas',
                      onTap: () => setState(() => _productCategoryFilter = 'quesadillas'),
                    ),
                    _FilterChip(
                      label: '🥤 Bebidas',
                      value: 'bebidas',
                      selected: _productCategoryFilter == 'bebidas',
                      onTap: () => setState(() => _productCategoryFilter = 'bebidas'),
                    ),
                    _FilterChip(
                      label: '⭐ Especiales',
                      value: 'especiales',
                      selected: _productCategoryFilter == 'especiales',
                      onTap: () => setState(() => _productCategoryFilter = 'especiales'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Lista de productos en tiempo real
        Expanded(
          child: productsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Error cargando productos: $err')),
            data: (products) {
              final filtered = products.where((p) {
                final matchCat = _productCategoryFilter == 'all' || p.categoryId == _productCategoryFilter;
                final matchSearch = _productSearchQuery.isEmpty ||
                    p.name.toLowerCase().contains(_productSearchQuery) ||
                    p.ingredients.any((ing) => ing.toLowerCase().contains(_productSearchQuery));
                return matchCat && matchSearch;
              }).toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.fastfood_outlined, size: 64, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text('No se encontraron platillos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 6),
                      Text(
                        'Crea un nuevo producto o pulsa "Sembrar Menú" para cargar el catálogo base.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final p = filtered[index];
                  return _buildProductAdminCard(p, isDark);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProductAdminCard(ProductEntity product, bool isDark) {
    final isSpicy = product.spicyLevel > 0;
    String spicyEmoji = '';
    if (product.spicyLevel == 1) spicyEmoji = '🌶️';
    if (product.spicyLevel == 2) spicyEmoji = '🌶️🌶️';
    if (product.spicyLevel == 3) spicyEmoji = '🔥🌶️';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1712) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: product.available
              ? (isDark ? Colors.white10 : Colors.grey.shade200)
              : Colors.red.withAlpha(60),
          width: product.available ? 1 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Imagen
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: CachedNetworkImage(
                    imageUrl: product.imageUrl,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.fastfood_rounded, color: Colors.grey),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            product.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isSpicy) ...[
                          const SizedBox(width: 4),
                          Text(spicyEmoji, style: const TextStyle(fontSize: 12)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      PriceFormatter.formatSmart(product.price),
                      style: const TextStyle(
                        color: Color(0xFF16A34A),
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626).withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        product.categoryId.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFFDC2626),
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Acciones: Editar y Borrar
              Column(
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_rounded, size: 20, color: Color(0xFF3B82F6)),
                    tooltip: 'Editar',
                    onPressed: () => ProductFormModal.show(context, productToEdit: product),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.red),
                    tooltip: 'Eliminar',
                    onPressed: () => _confirmDeleteProduct(product),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Ingredientes
          if (product.ingredients.isNotEmpty) ...[
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: product.ingredients.map((ing) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(ing, style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
          ],

          // Barra de disponibilidad
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? Colors.black12 : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      product.available ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      size: 14,
                      color: product.available ? const Color(0xFF16A34A) : Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      product.available ? 'En venta (Disponible)' : 'Agotado (Oculto)',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: product.available ? const Color(0xFF16A34A) : Colors.red,
                      ),
                    ),
                  ],
                ),
                Switch(
                  value: product.available,
                  activeTrackColor: const Color(0xFF16A34A),
                  activeThumbColor: Colors.white,
                  onChanged: (val) {
                    ref.read(productRepositoryProvider).toggleProductAvailability(product.id, val);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteProduct(ProductEntity product) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar platillo?'),
        content: Text('¿Estás seguro de eliminar "${product.name}" del catálogo? Esta acción lo removerá de la app.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(productRepositoryProvider).deleteProduct(product.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('🗑️ "${product.name}" eliminado del catálogo'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  void _showSeedCatalogDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Text('⚡ ', style: TextStyle(fontSize: 22)),
            Text('Sembrar Menú Base'),
          ],
        ),
        content: const Text(
          'Esto cargará todos los productos del menú predeterminado (tacos, burritos, bebidas y especiales) directamente en Firestore para que puedas gestionarlos y editarlos sin depender de código.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A), foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              final count = await ref.read(productRepositoryProvider).seedInitialCatalog(mockProducts);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('🎉 ¡Se subieron $count platillos a Firestore exitosamente!'),
                    backgroundColor: const Color(0xFF16A34A),
                  ),
                );
              }
            },
            child: const Text('Subir Catálogo a Firestore'),
          ),
        ],
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.value, required this.selected, required this.onTap});
  final String label, value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFDC2626) : Colors.grey.withAlpha(30),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.grey.shade700,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              fontSize: 12.5,
            )),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.orderId,
    required this.data,
    required this.isDark,
    required this.statusColor,
    required this.statusLabel,
    required this.nextStatus,
    required this.onAdvance,
    required this.onCancel,
  });

  final String orderId;
  final Map<String, dynamic> data;
  final bool isDark;
  final Color statusColor;
  final String statusLabel;
  final String? nextStatus;
  final VoidCallback onAdvance;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final shortId = orderId.length > 6 ? orderId.substring(0, 6).toUpperCase() : orderId.toUpperCase();
    final total = (data['total'] as num? ?? 0).toDouble();
    final address = data['formattedAddress'] as String? ?? 'Sin direccion';
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
    final timeStr = createdAt != null ? DateFormat('hh:mm a').format(createdAt) : '';
    final items = (data['items'] as List?)?.length ?? 0;
    final payMethod = data['paymentMethod'] as String? ?? '';
    final customerName = data['userName'] as String? ?? data['customerName'] as String? ?? '';
    final driverName = data['driverName'] as String? ?? '';
    final driverPlate = data['driverVehiclePlate'] as String? ?? data['vehiclePlate'] as String? ?? '';
    final deliveryProofUrl = data['deliveryProofUrl'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: statusColor.withAlpha(30),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Text('#$shortId', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Courier')),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(20)),
                  child: Text(statusLabel, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                Text(timeStr, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (customerName.isNotEmpty) ...[
                  Row(children: [
                    const Icon(Icons.person_rounded, size: 15, color: Color(0xFFDC2626)),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'Cliente: $customerName',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 5),
                ],
                Row(children: [
                  const Icon(Icons.location_on_rounded, size: 15, color: Color(0xFFDC2626)),
                  const SizedBox(width: 5),
                  Expanded(child: Text(address, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 6),
                if (driverName.isNotEmpty) ...[
                  Row(children: [
                    const Icon(Icons.two_wheeler_rounded, size: 15, color: Color(0xFF10B981)),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'Repartidor: $driverName ${driverPlate.isNotEmpty ? "• Placa: $driverPlate" : ""}',
                        style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                ],
                Row(children: [
                  Icon(Icons.shopping_bag_rounded, size: 15, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text('$items producto${items != 1 ? "s" : ""}', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  const Spacer(),
                  Text(PriceFormatter.formatSmart(total),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFFDC2626))),
                ]),
                if (payMethod.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.payment_rounded, size: 15, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text(payMethod, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  ]),
                ],
                if (deliveryProofUrl.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildProofButton(context, deliveryProofUrl, shortId, customerName),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (data['status'] != 'delivered' && data['status'] != 'cancelled') ...[
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF16A34A),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          onPressed: nextStatus != null ? onAdvance : null,
                          icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                          label: Text(_nextLabel(data['status'] as String? ?? ''), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          foregroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        ),
                        onPressed: onCancel,
                        child: const Icon(Icons.cancel_rounded, size: 18),
                      ),
                    ] else
                      Center(
                        child: Text(
                          data['status'] == 'delivered' ? '✅ Entregado' : '❌ Cancelado',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProofButton(BuildContext context, String url, String orderShortId, String client) {
    return InkWell(
      onTap: () => _showProofZoomDialog(context, url, orderShortId, client),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withAlpha(25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF10B981).withAlpha(90)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 44,
                height: 44,
                child: _buildProofImage(url),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('📸 Evidencia de Entrega', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF10B981))),
                  Text(client.isNotEmpty ? 'Entregado a: $client' : 'Comprobante registrado', style: TextStyle(fontSize: 11, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Icon(Icons.zoom_in_rounded, color: Color(0xFF10B981), size: 22),
          ],
        ),
      ),
    );
  }

  static Widget _buildProofImage(String url) {
    if (url.startsWith('data:image/')) {
      try {
        final bytes = base64Decode(url.split(',').last);
        return Image.memory(bytes, fit: BoxFit.cover);
      } catch (_) {
        return const Icon(Icons.broken_image_rounded, color: Colors.grey);
      }
    } else if (url.startsWith('http')) {
      return Image.network(url, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image_rounded, color: Colors.grey));
    }
    return const Icon(Icons.image_rounded, color: Color(0xFF10B981));
  }

  void _showProofZoomDialog(BuildContext context, String url, String orderShortId, String client) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF1E1712),
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.photo_camera_rounded, color: Color(0xFF10B981), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Orden #$orderShortId ${client.isNotEmpty ? "• $client" : ""}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.7,
                maxWidth: double.infinity,
              ),
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: _buildProofImage(url),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              alignment: Alignment.center,
              child: const Text(
                'Pellizca para hacer zoom en la evidencia',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _nextLabel(String status) {
    switch (status) {
      case 'pending':   return 'Confirmar pedido';
      case 'confirmed': return 'Iniciar preparacion';
      case 'preparing': return 'Marcar como listo';
      case 'ready':     return 'Asignar repartidor';
      case 'onTheWay':  return 'Marcar entregado';
      default:          return 'Avanzar';
    }
  }
}


class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon, required this.color, required this.isDark});
  final String label, value;
  final IconData icon;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1712) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(40)),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const Spacer(),
          Text(value, style: TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 22, color: color, letterSpacing: 1)),
          Text(label, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
