// lib/features/notifications/presentation/screens/notifications_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../auth/providers/auth_notifier.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  String _selectedFilter = 'all';

  String _formatTimestamp(dynamic ts) {
    if (ts is Timestamp) {
      final dt = ts.toDate();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
      if (diff.inHours < 24) return 'Hace ${diff.inHours} horas';
      return '${dt.day}/${dt.month}/${dt.year}';
    }
    return 'Reciente';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = ref.watch(authNotifierProvider).user;
    final userId = user?.id ?? '';

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1E1712) : const Color(0xFFFAF7F2),
      appBar: AppBar(
        title: const Text(
          'NOTIFICACIONES 🔔',
          style: TextStyle(
            fontFamily: AppTypography.displayFamily,
            fontSize: 20,
            letterSpacing: 1.0,
          ),
        ),
      ),
      body: Column(
        children: [
          // Chips de filtro
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                _buildFilterChip('all', 'Todas', isDark),
                const SizedBox(width: 8),
                _buildFilterChip('orders', '🛵 Pedidos', isDark),
                const SizedBox(width: 8),
                _buildFilterChip('promos', '🔥 Promos', isDark),
              ],
            ),
          ),

          // Lista de notificaciones
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: userId.isNotEmpty
                  ? FirebaseFirestore.instance
                      .collection('users')
                      .doc(userId)
                      .collection('notifications')
                      .orderBy('createdAt', descending: true)
                      .snapshots()
                  : null,
              builder: (context, snapshot) {
                final firestoreDocs = snapshot.data?.docs ?? [];

                final notificationsList = <Map<String, dynamic>>[];

                // Notificaciones en vivo de Firestore
                for (final doc in firestoreDocs) {
                  final data = doc.data() as Map<String, dynamic>;
                  notificationsList.add({
                    'title': data['title'] ?? 'Actualización de Pedido',
                    'body': data['body'] ?? '',
                    'time': _formatTimestamp(data['createdAt']),
                    'orderId': data['orderId'],
                    'type': 'orders',
                    'icon': Icons.receipt_long_rounded,
                    'color': const Color(0xFFDC2626),
                  });
                }

                // Notificaciones del sistema / promocionales fijas
                final systemNotifications = [
                  {
                    'title': '🚴 ¡Tu pedido está en camino!',
                    'body': 'El repartidor va rumbo a tu ubicación con la comida caliente.',
                    'time': 'Hoy',
                    'type': 'orders',
                    'icon': Icons.two_wheeler_rounded,
                    'color': const Color(0xFFDC2626),
                  },
                  {
                    'title': '🔥 PROMO DIABLA ACTIVA',
                    'body': 'Obtén 25% OFF en tu combo favorito ingresando el código DIABLA25.',
                    'time': 'Hoy',
                    'type': 'promos',
                    'icon': Icons.local_fire_department_rounded,
                    'color': const Color(0xFFE65100),
                  },
                  {
                    'title': '🌮 ¡Bienvenido a La Diabla!',
                    'body': 'Disfruta de la mejor comida mexicana con entrega rápida en Bucaramanga.',
                    'time': 'Ayer',
                    'type': 'promos',
                    'icon': Icons.celebration_rounded,
                    'color': const Color(0xFF16A34A),
                  },
                ];

                final combined = [...notificationsList, ...systemNotifications];
                final filtered = switch (_selectedFilter) {
                  'orders' => combined.where((n) => n['type'] == 'orders').toList(),
                  'promos' => combined.where((n) => n['type'] == 'promos').toList(),
                  _ => combined,
                };

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final notif = filtered[index];
                    final color = notif['color'] as Color? ?? const Color(0xFFDC2626);
                    final icon = notif['icon'] as IconData? ?? Icons.notifications_rounded;
                    final orderId = notif['orderId'] as String?;

                    return GestureDetector(
                      onTap: () {
                        if (orderId != null && orderId.isNotEmpty) {
                          context.push('/tracking/$orderId');
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2C1B14) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(isDark ? 25 : 8),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: color.withAlpha(isDark ? 50 : 25),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(icon, color: color, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    notif['title'] as String,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    notif['body'] as String,
                                    style: TextStyle(
                                      color: isDark ? AppColors.textMutedDark : Colors.grey.shade700,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    notif['time'] as String,
                                    style: TextStyle(
                                      color: isDark ? Colors.white38 : Colors.grey.shade500,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label, bool isDark) {
    final isSelected = _selectedFilter == key;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFDC2626)
              : (isDark ? const Color(0xFF2C1B14) : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFDC2626)
                : (isDark ? AppColors.dividerDark : Colors.grey.shade300),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.white70 : Colors.black87),
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

