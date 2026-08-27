// lib/features/orders/presentation/widgets/order_stepper_widget.dart
import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../domain/entities/order_status.dart';

class OrderStepperWidget extends StatelessWidget {
  const OrderStepperWidget({
    super.key,
    required this.status,
    this.recibidoTime = '7:45 PM',
    this.confirmadoTime = '7:46 PM',
    this.preparandoTime = '7:48 PM',
    this.enCaminoTime = '7:55 PM',
    this.entregadoTime = '-',
  });

  final OrderStatus status;
  final String recibidoTime;
  final String confirmadoTime;
  final String preparandoTime;
  final String enCaminoTime;
  final String entregadoTime;

  int get _currentStepIndex {
    return switch (status) {
      OrderStatus.pending => 0,
      OrderStatus.confirmed => 1,
      OrderStatus.preparing => 2,
      OrderStatus.ready || OrderStatus.assigned || OrderStatus.onTheWay => 3,
      OrderStatus.delivered => 4,
      OrderStatus.cancelled => -1,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeIndex = _currentStepIndex;

    final steps = [
      _StepInfo(
        title: 'Recibido',
        time: recibidoTime,
        iconPath: 'assets/icons/recibido.png',
      ),
      _StepInfo(
        title: 'Confirmado',
        time: confirmadoTime,
        iconPath: 'assets/icons/confirmado.png',
      ),
      _StepInfo(
        title: 'Preparando',
        time: preparandoTime,
        iconPath: 'assets/icons/preparando.png',
      ),
      _StepInfo(
        title: 'En camino',
        time: enCaminoTime,
        iconPath: 'assets/icons/encamino.png',
      ),
      _StepInfo(
        title: 'Entregado',
        time: entregadoTime,
        iconPath: 'assets/icons/entregado.png',
      ),
    ];

    return Column(
      children: [
        Row(
          children: [
            for (int i = 0; i < steps.length; i++) ...[
              // Nodo del paso
              _buildStepIcon(
                step: steps[i],
                isCompleted: activeIndex >= i,
                isCurrent: activeIndex == i,
                isDark: isDark,
              ),

              // Línea conectora
              if (i < steps.length - 1)
                Expanded(
                  child: _buildConnectorLine(
                    isCompleted: activeIndex > i,
                    isDark: isDark,
                  ),
                ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        // Fila de textos (título y hora)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < steps.length; i++)
              Expanded(
                child: Column(
                  children: [
                    Text(
                      steps[i].title,
                      style: TextStyle(
                        fontFamily: AppTypography.bodyFamily,
                        fontSize: 10,
                        fontWeight: activeIndex >= i ? FontWeight.w700 : FontWeight.w500,
                        color: activeIndex >= i
                            ? (isDark ? AppColors.textLight : const Color(0xFF2D1500))
                            : Colors.grey.shade400,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      steps[i].time,
                      style: TextStyle(
                        fontFamily: AppTypography.bodyFamily,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                        color: activeIndex >= i
                            ? (isDark ? AppColors.textMutedDark : const Color(0xFF6B4B3E))
                            : Colors.grey.shade400,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildStepIcon({
    required _StepInfo step,
    required bool isCompleted,
    required bool isCurrent,
    required bool isDark,
  }) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: isCompleted
            ? const Color(0xFFFFF3E0)
            : (isDark ? AppColors.cardDark : Colors.grey.shade100),
        shape: BoxShape.circle,
        border: Border.all(
          color: isCompleted ? const Color(0xFFFF9800) : Colors.grey.shade300,
          width: isCurrent ? 2.2 : 1.5,
        ),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: const Color(0xFFFF9800).withAlpha(100),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.all(6),
      child: Image.asset(
        step.iconPath,
        fit: BoxFit.contain,
        color: isCompleted ? null : Colors.grey.shade400,
      ),
    );
  }

  Widget _buildConnectorLine({
    required bool isCompleted,
    required bool isDark,
  }) {
    if (isCompleted) {
      return Container(
        height: 3,
        color: const Color(0xFFFF9800),
      );
    }
    // Línea punteada o atenuada
    return Container(
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: isDark ? Colors.white12 : Colors.grey.shade300,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}

class _StepInfo {
  const _StepInfo({
    required this.title,
    required this.time,
    required this.iconPath,
  });

  final String title;
  final String time;
  final String iconPath;
}
