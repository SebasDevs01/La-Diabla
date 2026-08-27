// lib/features/orders/presentation/screens/orders_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/price_formatter.dart';
import '../../../../core/widgets/diabla_offline_view.dart';
import '../../../../domain/entities/order_entity.dart';
import '../../../../domain/entities/order_status.dart';
import '../../providers/orders_provider.dart';
import '../widgets/order_rating_tip_sheet.dart';
import '../widgets/order_stepper_widget.dart';
import '../widgets/order_support_banner.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  String _selectedFilter = 'all'; // 'all', 'active', 'completed', 'cancelled'

  String _formatDate(DateTime? dt) {
    if (dt == null) return 'Hoy';
    const months = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    final month = months[dt.month - 1];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.day} $month ${dt.year} • $hour:$minute $ampm';
  }

  String _fmtTime(DateTime? dt, {int addMinutes = 0}) {
    if (dt == null) return '--';
    final t = dt.add(Duration(minutes: addMinutes));
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final suffix = t.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $suffix';
  }

  String _estimatedArrival(DateTime? createdAt) {
    if (createdAt == null) return 'Calculando...';
    final from = createdAt.add(const Duration(minutes: 20));
    final to = createdAt.add(const Duration(minutes: 30));
    return '${_fmtTime(from)} - ${_fmtTime(to)}';
  }

  String _formatShortDate(DateTime? dt) {
    if (dt == null) return '--';
    const months = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    final month = months[dt.month - 1];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.day} $month • $hour:$minute $ampm';
  }


  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ordersAsync = ref.watch(userOrdersStreamProvider);

    return Scaffold(
      backgroundColor: isDark ? AppColors.surfaceDark : const Color(0xFFFAF7F2),
      body: SafeArea(
        child: ordersAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          error: (err, _) => DiablaOfflineView(
            title: 'Ups, algo salió mal.',
            subtitle: 'No pudimos cargar tus pedidos. Comprueba tu conexión a internet.',
            onRetry: () => ref.invalidate(userOrdersStreamProvider),
          ),
          data: (realOrders) {
            return _buildOrdersView(realOrders, isDark);
          },
        ),
      ),
    );
  }

  Widget _buildOrdersView(List<OrderEntity> allOrders, bool isDark) {
    // Clasificación de órdenes
    final activeOrders = allOrders.where((o) => o.status.isActive).toList();
    final completedOrders = allOrders.where((o) => o.status == OrderStatus.delivered).toList();
    final cancelledOrders = allOrders.where((o) => o.status == OrderStatus.cancelled).toList();

    // Órdenes filtradas según chip seleccionado
    final filteredOrders = switch (_selectedFilter) {
      'active' => activeOrders,
      'completed' => completedOrders,
      'cancelled' => cancelledOrders,
      _ => allOrders,
    };

    final featuredActiveOrder = activeOrders.isNotEmpty ? activeOrders.first : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      children: [
        // ─── 1. HEADER SUPERIOR CON ILUSTRACIÓN ─────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MIS PEDIDOS',
                    style: TextStyle(
                      fontFamily: AppTypography.displayFamily,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                      letterSpacing: 1.5,
                      color: isDark ? const Color(0xFFFF5252) : const Color(0xFFC62828),
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Aquí puedes ver el estado\nde todos tus pedidos.',
                    style: TextStyle(
                      fontFamily: AppTypography.bodyFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.textMutedDark : const Color(0xFF4A342B),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            // Ilustración del Diablito con teléfono y fuego
            Image.asset(
              'assets/images/deliverylogo.png',
              height: 100,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(Icons.delivery_dining, size: 70, color: Color(0xFFDC2626)),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // ─── 2. FILTROS POR ESTADO CON CONTADORES ───────────────────────────
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFilterChip(
                id: 'all',
                label: 'Todos',
                count: allOrders.length,
                icon: Icons.shopping_bag_outlined,
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _buildFilterChip(
                id: 'active',
                label: 'En camino',
                count: activeOrders.length,
                icon: Icons.two_wheeler_rounded,
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _buildFilterChip(
                id: 'completed',
                label: 'Completados',
                count: completedOrders.length,
                icon: Icons.check_circle_outline_rounded,
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _buildFilterChip(
                id: 'cancelled',
                label: 'Cancelados',
                count: cancelledOrders.length,
                icon: Icons.cancel_outlined,
                isDark: isDark,
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ─── 3. TARJETA DESTACADA "EN CAMINO" ───────────────────────────────
        if (featuredActiveOrder != null && (_selectedFilter == 'all' || _selectedFilter == 'active')) ...[
          _buildActiveOrderCard(featuredActiveOrder, isDark),
          const SizedBox(height: 24),
        ],

        // ─── 4. SECCIÓN COMPLETADOS / LISTA FILTRADA ─────────────────────────
        Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 22),
            const SizedBox(width: 8),
            Text(
              _selectedFilter == 'completed'
                  ? 'COMPLETADOS'
                  : _selectedFilter == 'cancelled'
                      ? 'CANCELADOS'
                      : _selectedFilter == 'active'
                          ? 'EN PROCESO'
                          : 'COMPLETADOS',
              style: TextStyle(
                fontFamily: AppTypography.displayFamily,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: isDark ? AppColors.textLight : const Color(0xFF1E1E1E),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Lista de tarjetas
        if (filteredOrders.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? AppColors.cardDark : Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: Text(
                'No hay pedidos en esta sección',
                style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
              ),
            ),
          )
        else
          ...filteredOrders
              .where((o) => _selectedFilter != 'all' || !o.status.isActive)
              .map((order) => _buildOrderListItem(order, isDark)),

        const SizedBox(height: 20),

        // ─── 5. BANNER INFERIOR DE SOPORTE CON LLAMA DE FUEGO ───────────────
        const OrderSupportBanner(),
      ],
    );
  }

  // ─── CHIP DE FILTRO ─────────────────────────────────────────────────────────
  Widget _buildFilterChip({
    required String id,
    required String label,
    required int count,
    required IconData icon,
    required bool isDark,
  }) {
    final isSelected = _selectedFilter == id;

    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFDC2626)
              : (isDark ? AppColors.cardDark : Colors.white),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFDC2626)
                : (isDark ? AppColors.dividerDark : Colors.grey.shade200),
            width: 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFFDC2626).withAlpha(80),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? Colors.white
                  : (isDark ? AppColors.textLight : const Color(0xFF3E2723)),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTypography.bodyFamily,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: isSelected
                    ? Colors.white
                    : (isDark ? AppColors.textLight : const Color(0xFF3E2723)),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white
                    : (isDark ? AppColors.surfaceDark : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontFamily: AppTypography.bodyFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? const Color(0xFFDC2626) : Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── TARJETA DE PEDIDO ACTIVO CON MOTO Y STEPPER ────────────────────────────
  Widget _buildActiveOrderCard(OrderEntity order, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : const Color(0xFFFFE0B2),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fila superior: Datos + Ilustración de la Moto
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Badge En Camino
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFB74D), Color(0xFFFF9800)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.two_wheeler_rounded, size: 14, color: Color(0xFF3E2723)),
                          SizedBox(width: 4),
                          Text(
                            'EN CAMINO',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: Color(0xFF3E2723),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Número de Pedido
                    Text(
                      'Pedido #${order.id.length > 6 ? order.id.substring(order.id.length - 6).toUpperCase() : order.id}',
                      style: TextStyle(
                        fontFamily: AppTypography.bodyFamily,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: isDark ? AppColors.textLight : const Color(0xFF1E1E1E),
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Fecha y Hora real
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined, size: 13, color: Color(0xFFDC2626)),
                        const SizedBox(width: 5),
                        Text(
                          _formatDate(order.createdAt),
                          style: TextStyle(
                            fontFamily: AppTypography.bodyFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isDark ? AppColors.textMutedDark : const Color(0xFF6B4B3E),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Dirección
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFFDC2626)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            order.address?.formattedAddress ?? 'Calle 45 #23-67, Medellín, Antioquia',
                            style: TextStyle(
                              fontFamily: AppTypography.bodyFamily,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppColors.textLight : const Color(0xFF1E1E1E),
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

              // Ilustración de la Moto con el Diablito
              Image.asset(
                'assets/images/delivery.png',
                width: 120,
                height: 100,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Icon(Icons.delivery_dining, size: 70, color: Color(0xFFDC2626)),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Cuadro de Llegada Estimada + Botón "Ver en Mapa"
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C1E14) : const Color(0xFFFFF8E7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFFFCC80),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Llegada estimada',
                      style: TextStyle(
                        fontFamily: AppTypography.bodyFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.textMutedDark : const Color(0xFF6D4C41),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _estimatedArrival(order.createdAt),
                      style: const TextStyle(
                        fontFamily: AppTypography.bodyFamily,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                  ],
                ),

                // Botón "VER EN MAPA"
                ElevatedButton.icon(
                  onPressed: () {
                    context.push('/tracking/${order.id}');
                  },
                  icon: const Icon(Icons.location_pin, size: 15, color: Color(0xFFDC2626)),
                  label: const Text(
                    'VER EN MAPA',
                    style: TextStyle(
                      fontFamily: AppTypography.bodyFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFDC2626),
                      letterSpacing: 0.5,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFDC2626),
                    elevation: 0,
                    side: const BorderSide(color: Color(0xFFEF5350), width: 1.2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Stepper de 5 Estados con Íconos Personalizados
          OrderStepperWidget(
            status: order.status,
            recibidoTime: _fmtTime(order.createdAt),
            confirmadoTime: order.status.index >= OrderStatus.confirmed.index
                ? _fmtTime(order.createdAt, addMinutes: 2)
                : '-',
            preparandoTime: order.status.index >= OrderStatus.preparing.index
                ? _fmtTime(order.createdAt, addMinutes: 4)
                : '-',
            enCaminoTime: order.status.index >= OrderStatus.onTheWay.index
                ? _fmtTime(order.createdAt, addMinutes: 12)
                : '-',
            entregadoTime: order.status == OrderStatus.delivered
                ? _fmtTime(order.createdAt, addMinutes: 25)
                : '-',
          ),
        ],
      ),
    );
  }

  // ─── ITEM DE PEDIDO COMPLETADO ──────────────────────────────────────────────
  Widget _buildOrderListItem(OrderEntity order, bool isDark) {
    final firstItemImage = order.items.isNotEmpty
        ? order.items.first.product.imageUrl
        : 'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=600';

    final isDelivered = order.status == OrderStatus.delivered;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 20 : 6),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Imagen del platillo
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(
              firstItemImage,
              width: 80,
              height: 80,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 80,
                height: 80,
                color: isDark ? AppColors.surfaceDark : Colors.grey.shade200,
                child: const Icon(Icons.fastfood_rounded, color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Datos del Pedido
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pedido #${order.id.length > 6 ? order.id.substring(order.id.length - 6).toUpperCase() : order.id}',
                  style: TextStyle(
                    fontFamily: AppTypography.bodyFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: isDark ? AppColors.textLight : const Color(0xFF1E1E1E),
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 12, color: Colors.grey),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _formatShortDate(order.createdAt),
                        style: TextStyle(
                          fontFamily: AppTypography.bodyFamily,
                          fontSize: 11.5,
                          color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.shopping_bag_outlined, size: 13, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      '${order.itemCount} Productos',
                      style: TextStyle(
                        fontFamily: AppTypography.bodyFamily,
                        fontSize: 11.5,
                        color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  PriceFormatter.formatSmart(order.total),
                  style: const TextStyle(
                    fontFamily: AppTypography.bodyFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ],
            ),
          ),

          // Badge Entregado + Flecha
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDelivered ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDelivered ? const Color(0xFF81C784) : const Color(0xFFE57373),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isDelivered ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      size: 13,
                      color: isDelivered ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isDelivered ? 'ENTREGADO' : 'CANCELADO',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: isDelivered ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                      ),
                    ),
                  ],
                ),
              ),
              if (isDelivered) ...[
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => OrderRatingTipSheet.show(context, order),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFFB74D)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded, size: 14, color: Color(0xFFE65100)),
                        SizedBox(width: 2),
                        Text(
                          'Calificar',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFE65100),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 24),
              ],
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.chevron_right_rounded, color: Color(0xFFDC2626)),
                onPressed: () {
                  context.push('/tracking/${order.id}');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

}
