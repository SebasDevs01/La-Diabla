// lib/features/orders/presentation/widgets/order_rating_tip_sheet.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/price_formatter.dart';
import '../../../../domain/entities/order_entity.dart';
import '../../../auth/providers/auth_notifier.dart';

class OrderRatingTipSheet extends ConsumerStatefulWidget {
  const OrderRatingTipSheet({
    super.key,
    required this.order,
  });

  final OrderEntity order;

  static Future<void> show(BuildContext context, OrderEntity order) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => OrderRatingTipSheet(order: order),
    );
  }

  @override
  ConsumerState<OrderRatingTipSheet> createState() => _OrderRatingTipSheetState();
}

class _OrderRatingTipSheetState extends ConsumerState<OrderRatingTipSheet> {
  int _foodRating = 5;
  int _driverRating = 5;
  double _selectedTip = 5000;
  final _commentController = TextEditingController();
  bool _isSubmitting = false;

  final List<double> _tipOptions = [0, 2000, 5000, 10000];

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  String _getFoodRatingLabel(int stars) {
    return switch (stars) {
      5 => '¡Increíble, para chuparse los dedos! 🔥🌶️',
      4 => '¡Muy rico y picante! 🌮',
      3 => 'Estuvo bien 🙂',
      2 => 'Podría mejorar 😕',
      _ => 'No me gustó 😞',
    };
  }

  String _getDriverRatingLabel(int stars) {
    return switch (stars) {
      5 => '¡Súper rápido y muy amable! 🛵💨',
      4 => 'Buen servicio y a tiempo 👍',
      3 => 'Normal 🙂',
      2 => 'Demorado ⏱️',
      _ => 'Mala experiencia 👎',
    };
  }

  Future<void> _submitReview() async {
    setState(() => _isSubmitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final user = ref.read(authNotifierProvider).user;
      final reviewData = {
        'foodRating': _foodRating,
        'driverRating': _driverRating,
        'tipAmount': _selectedTip,
        'comment': _commentController.text.trim(),
        'userId': user?.id ?? widget.order.userId,
        'userName': user?.name ?? 'Cliente Diabla',
        'ratedAt': FieldValue.serverTimestamp(),
      };

      // Guardar en la orden
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.order.id)
          .update({
        'rating': _foodRating,
        'driverRating': _driverRating,
        'tip': _selectedTip,
        'reviewComment': _commentController.text.trim(),
        'isRated': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Guardar en la subcolección de reviews
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.order.id)
          .collection('reviews')
          .add(reviewData);

      if (mounted) {
        navigator.pop();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('¡Muchas gracias por tu calificación y propina! 🌶️🌮'),
            backgroundColor: Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Error al enviar calificación: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shortId = widget.order.id.length > 6
        ? widget.order.id.substring(widget.order.id.length - 6).toUpperCase()
        : widget.order.id;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1712) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Indicador de arrastre
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.dividerDark : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 18),

            // Encabezado
            const Text(
              '¿QUÉ TAL TU EXPERIENCIA? 🌶️',
              style: TextStyle(
                fontFamily: AppTypography.displayFamily,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: Color(0xFFDC2626),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Pedido #$shortId completado',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),

            // ─── 1. CALIFICACIÓN DE LA COMIDA ─────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C1B14) : const Color(0xFFFFF9F5),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark ? AppColors.dividerDark : const Color(0xFFFFE0B2),
                ),
              ),
              child: Column(
                children: [
                  const Text(
                    'Califica la Comida 🌮',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final starNum = index + 1;
                      return IconButton(
                        icon: Icon(
                          starNum <= _foodRating ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: starNum <= _foodRating ? Colors.amber.shade600 : Colors.grey,
                          size: 36,
                        ),
                        onPressed: () => setState(() => _foodRating = starNum),
                      );
                    }),
                  ),
                  Text(
                    _getFoodRatingLabel(_foodRating),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : const Color(0xFF8D2B0B),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ─── 2. CALIFICACIÓN DEL REPARTIDOR ───────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C1B14) : const Color(0xFFFFF9F5),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark ? AppColors.dividerDark : const Color(0xFFFFE0B2),
                ),
              ),
              child: Column(
                children: [
                  const Text(
                    'Califica al Repartidor 🛵',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final starNum = index + 1;
                      return IconButton(
                        icon: Icon(
                          starNum <= _driverRating ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: starNum <= _driverRating ? Colors.amber.shade600 : Colors.grey,
                          size: 36,
                        ),
                        onPressed: () => setState(() => _driverRating = starNum),
                      );
                    }),
                  ),
                  Text(
                    _getDriverRatingLabel(_driverRating),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : const Color(0xFF8D2B0B),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ─── 3. PROPINA PARA EL REPARTIDOR ────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C1B14) : const Color(0xFFFFF9F5),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark ? AppColors.dividerDark : const Color(0xFFFFE0B2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Propina para el Repartidor 💵',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                      ),
                      Text('100% para él', style: TextStyle(fontSize: 11.5, color: Color(0xFF16A34A), fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: _tipOptions.map((tip) {
                      final isSelected = _selectedTip == tip;
                      final label = tip == 0 ? 'Sin propina' : PriceFormatter.formatSmart(tip);
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedTip = tip),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF16A34A)
                                  : (isDark ? Colors.black26 : Colors.white),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF16A34A)
                                    : (isDark ? AppColors.dividerDark : Colors.grey.shade300),
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? Colors.white
                                    : (isDark ? Colors.white70 : Colors.black87),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ─── 4. COMENTARIO OPCIONAL ──────────────────────────────────
            TextField(
              controller: _commentController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Comentario opcional sobre tu pedido...',
                hintStyle: TextStyle(fontSize: 13, color: isDark ? AppColors.textMutedDark : Colors.grey),
                filled: true,
                fillColor: isDark ? const Color(0xFF2C1B14) : Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: isDark ? AppColors.dividerDark : Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: isDark ? AppColors.dividerDark : Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Botón de Enviar
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                ),
                onPressed: _isSubmitting ? null : _submitReview,
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'ENVIAR CALIFICACIÓN 🔥',
                        style: TextStyle(
                          fontFamily: AppTypography.displayFamily,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
