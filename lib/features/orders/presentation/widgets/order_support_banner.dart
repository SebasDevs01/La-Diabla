// lib/features/orders/presentation/widgets/order_support_banner.dart
import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import 'order_support_sheet.dart';

class OrderSupportBanner extends StatelessWidget {
  const OrderSupportBanner({
    super.key,
    this.orderId,
    this.title = '¿Tienes alguna duda con tu pedido?',
    this.subtitle =
        'Escríbele a nuestro asistente de IA o solicita la atención de un asesor humano por WhatsApp de inmediato.',
  });

  final String? orderId;
  final String title;
  final String subtitle;

  void _showSupport(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => OrderSupportSheet(orderId: orderId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showSupport(context),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF2C1510), const Color(0xFF1E0E0B)]
                  : [const Color(0xFFFFF5EC), const Color(0xFFFFE8D6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark
                  ? const Color(0xFFDC2626).withAlpha(120)
                  : const Color(0xFFE53935).withAlpha(90),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 40 : 15),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Badge superior
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('🔥', style: TextStyle(fontSize: 12)),
                        SizedBox(width: 4),
                        Text(
                          'SOPORTE 24/7 EN VIVO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.headset_mic_rounded,
                    color: Color(0xFFDC2626),
                    size: 24,
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Título y descripción
              Text(
                title,
                style: TextStyle(
                  fontFamily: AppTypography.displayFamily,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontFamily: AppTypography.bodyFamily,
                  fontSize: 12,
                  height: 1.35,
                  color:
                      isDark ? AppColors.textMutedDark : const Color(0xFF5A4A42),
                ),
              ),

              const SizedBox(height: 14),

              // Botón de acción rectangular
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFDC2626).withAlpha(70),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.support_agent_rounded,
                        size: 20, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'CONTACTAR A SOPORTE',
                      style: TextStyle(
                        fontFamily: AppTypography.displayFamily,
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
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
  }
}
