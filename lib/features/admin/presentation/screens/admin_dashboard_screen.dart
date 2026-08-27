// lib/features/admin/presentation/screens/admin_dashboard_screen.dart
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

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _filterStatus = 'all';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
            Tab(icon: Icon(Icons.bar_chart_rounded), text: 'Stats'),
            Tab(icon: Icon(Icons.local_offer_rounded), text: 'Cupones'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOrdersTab(isDark),
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
        .limit(50);
    if (_filterStatus != 'all') {
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
    final minOrderCtrl = TextEditingController(text: '25000');
    String type = 'fixed';

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
                const Text('Crear cupon', style: TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 20)),
                const SizedBox(height: 16),
                TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'Codigo (ej: DIABLO20)', border: OutlineInputBorder()), textCapitalization: TextCapitalization.characters),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: TextField(controller: discountCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: type == 'percent' ? 'Porcentaje (%)' : 'Valor fijo (COP)', border: const OutlineInputBorder()))),
                    const SizedBox(width: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'fixed', label: Text('\$')),
                        ButtonSegment(value: 'percent', label: Text('%')),
                      ],
                      selected: {type},
                      onSelectionChanged: (s) => setSheetState(() => type = s.first),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(controller: minOrderCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Pedido minimo (COP)', border: OutlineInputBorder())),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626), padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: () async {
                      final code = codeCtrl.text.trim().toUpperCase();
                      if (code.isEmpty) return;
                      await FirebaseFirestore.instance.collection('coupons').doc(code).set({
                        'active': true,
                        'type': type,
                        'discount': double.tryParse(discountCtrl.text) ?? 0,
                        'minOrder': double.tryParse(minOrderCtrl.text) ?? 0,
                        'createdAt': FieldValue.serverTimestamp(),
                      });
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Crear cupon', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
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
                Row(children: [
                  const Icon(Icons.location_on_rounded, size: 15, color: Color(0xFFDC2626)),
                  const SizedBox(width: 4),
                  Expanded(child: Text(address, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 6),
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
