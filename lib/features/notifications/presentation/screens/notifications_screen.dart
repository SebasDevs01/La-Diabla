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

  Future<void> _confirmClearAll(String userId) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1712) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_sweep_rounded, color: Color(0xFFDC2626)),
            SizedBox(width: 8),
            Text('¿Limpiar notificaciones?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: const Text(
          'Se eliminarán todas las notificaciones de tu historial.',
          style: TextStyle(fontSize: 13.5),
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
            child: const Text('Limpiar Todo'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final col = FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('notifications');
        final snapshots = await col.get();
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in snapshots.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();

        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('✅ Notificaciones eliminadas.'),
              backgroundColor: Color(0xFF16A34A),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('Error al limpiar notificaciones: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteNotification(String userId, String notifId) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .doc(notifId)
          .delete();
    } catch (_) {}
  }

  Future<void> _markAsRead(String userId, String notifId) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .doc(notifId)
          .update({'isRead': true});
    } catch (_) {}
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
        actions: [
          if (userId.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded),
              tooltip: 'Limpiar todas',
              onPressed: () => _confirmClearAll(userId),
            ),
        ],
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

          // Lista de notificaciones reales de Firestore
          Expanded(
            child: userId.isEmpty
                ? _buildEmptyState(
                    title: 'Inicia sesión para ver notificaciones',
                    subtitle: 'Tus alertas de pedidos y promociones aparecerán aquí.',
                    isDark: isDark,
                  )
                : StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(userId)
                        .collection('notifications')
                        .orderBy('createdAt', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(color: Color(0xFFDC2626)),
                        );
                      }

                      final firestoreDocs = snapshot.data?.docs ?? [];

                      if (firestoreDocs.isEmpty) {
                        return _buildEmptyState(
                          title: 'Sin notificaciones pendientes',
                          subtitle: 'Aquí recibirás en tiempo real las actualizaciones cuando tu comida esté en camino 🔥',
                          isDark: isDark,
                        );
                      }

                      final filteredDocs = firestoreDocs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final type = data['type'] as String? ?? (data['orderId'] != null ? 'orders' : 'promos');
                        if (_selectedFilter == 'orders') return type == 'orders';
                        if (_selectedFilter == 'promos') return type == 'promos';
                        return true;
                      }).toList();

                      if (filteredDocs.isEmpty) {
                        return _buildEmptyState(
                          title: 'No hay notificaciones en este filtro',
                          subtitle: 'Prueba seleccionando "Todas" para ver el historial.',
                          isDark: isDark,
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: filteredDocs.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final doc = filteredDocs[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final docId = doc.id;
                          final isRead = data['isRead'] as bool? ?? false;
                          final orderId = data['orderId'] as String?;
                          final emoji = data['emoji'] as String? ?? '🛵';
                          final title = data['title'] as String? ?? 'Notificación de La Diabla';
                          final body = data['body'] as String? ?? '';
                          final timeText = _formatTimestamp(data['createdAt']);

                          return Dismissible(
                            key: Key(docId),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDC2626),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.delete_rounded, color: Colors.white),
                                  SizedBox(width: 6),
                                  Text(
                                    'Eliminar',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            onDismissed: (_) => _deleteNotification(userId, docId),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                _markAsRead(userId, docId);
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
                                    color: isRead
                                        ? (isDark ? AppColors.dividerDark : Colors.grey.shade200)
                                        : const Color(0xFFDC2626).withAlpha(150),
                                    width: isRead ? 1.0 : 1.5,
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
                                        color: const Color(0xFFDC2626).withAlpha(isDark ? 50 : 25),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Text(emoji, style: const TextStyle(fontSize: 22)),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  title,
                                                  style: TextStyle(
                                                    fontWeight: isRead ? FontWeight.bold : FontWeight.w900,
                                                    fontSize: 14,
                                                    color: isDark ? Colors.white : const Color(0xFF1C1C1C),
                                                  ),
                                                ),
                                              ),
                                              if (!isRead)
                                                Container(
                                                  width: 8,
                                                  height: 8,
                                                  decoration: const BoxDecoration(
                                                    color: Color(0xFFDC2626),
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            body,
                                            style: TextStyle(
                                              color: isDark ? AppColors.textMutedDark : Colors.grey.shade700,
                                              fontSize: 12.5,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            timeText,
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

  Widget _buildEmptyState({
    required String title,
    required String subtitle,
    required bool isDark,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_none_rounded,
                size: 48,
                color: Color(0xFFDC2626),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
