// lib/features/wallet/presentation/widgets/refund_method_sheet.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/price_formatter.dart';
import '../../../../domain/entities/order_entity.dart';
import '../../../../domain/entities/payment_card_entity.dart';
import '../../../auth/providers/auth_notifier.dart';
import '../../providers/wallet_provider.dart';

class RefundMethodSheet extends ConsumerStatefulWidget {
  const RefundMethodSheet({
    super.key,
    required this.order,
    this.customAmount,
  });

  final OrderEntity order;
  final double? customAmount;

  static Future<void> show(
    BuildContext context, {
    required OrderEntity order,
    double? customAmount,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => RefundMethodSheet(order: order, customAmount: customAmount),
    );
  }

  @override
  ConsumerState<RefundMethodSheet> createState() => _RefundMethodSheetState();
}

class _RefundMethodSheetState extends ConsumerState<RefundMethodSheet> {
  PaymentCardEntity? _selectedMethod;
  String _selectedReason = 'Cancelación de pedido';
  final _customReasonCtrl = TextEditingController();
  bool _isSubmitting = false;

  final List<String> _commonReasons = [
    'Cancelación de pedido',
    'Demora en el tiempo de entrega',
    'Inconveniente con los platillos',
    'Cobro duplicado o incorrecto',
    'Otro motivo',
  ];

  @override
  void initState() {
    super.initState();
    final wallet = ref.read(walletProvider);
    if (wallet.cards.isNotEmpty) {
      _selectedMethod = wallet.selectedCard ?? wallet.cards.first;
    }
  }

  @override
  void dispose() {
    _customReasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitRefundRequest() async {
    final user = ref.read(authNotifierProvider).user;
    final refundAmount = widget.customAmount ?? widget.order.total;

    if (_selectedMethod == null && ref.read(walletProvider).cards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor vincula una tarjeta, Nequi o cuenta para recibir el reembolso'),
          backgroundColor: Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final refundId = const Uuid().v4();
      final destinationTitle = _selectedMethod?.displayTitle ?? widget.order.paymentMethod.displayName;
      final destinationDetails = _selectedMethod?.maskedNumber ?? 'Cuenta de pago original';
      final reasonText = _selectedReason == 'Otro motivo' && _customReasonCtrl.text.trim().isNotEmpty
          ? _customReasonCtrl.text.trim()
          : _selectedReason;

      await FirebaseFirestore.instance.collection('refunds').doc(refundId).set({
        'id': refundId,
        'orderId': widget.order.id,
        'userId': user?.id ?? widget.order.userId,
        'userName': user?.name ?? 'Cliente La Diabla',
        'userPhone': user?.phone ?? '3000000000',
        'amount': refundAmount,
        'paymentMethod': destinationTitle,
        'accountDetails': destinationDetails,
        'methodType': _selectedMethod?.methodType ?? 'card',
        'reason': reasonText,
        'status': 'pending', // pending, processed, rejected
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Actualizar estado de orden a paymentStatus: refundPending o similar
      await FirebaseFirestore.instance.collection('orders').doc(widget.order.id).update({
        'refundStatus': 'pending',
        'refundId': refundId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.of(context).pop();
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Text('🔄', style: TextStyle(fontSize: 24)),
                SizedBox(width: 8),
                Text('Solicitud Enviada'),
              ],
            ),
            content: Text(
              'Tu solicitud de reembolso por ${PriceFormatter.formatSmart(refundAmount)} COP ha sido enviada al administrador.\n\nDestino: $destinationTitle ($destinationDetails).\n\nTe notificaremos en cuanto sea procesado.',
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al procesar solicitud: $e'),
            backgroundColor: Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final walletState = ref.watch(walletProvider);
    final refundAmount = widget.customAmount ?? widget.order.total;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1712) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Barra superior
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Título
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626).withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.currency_exchange_rounded, color: Color(0xFFDC2626), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Solicitar Reembolso',
                        style: TextStyle(
                          fontFamily: AppTypography.displayFamily,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1C1C1C),
                        ),
                      ),
                      Text(
                        'Pedido #${widget.order.id.substring(0, widget.order.id.length > 6 ? 6 : widget.order.id.length).toUpperCase()}',
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
            const SizedBox(height: 20),

            // Monto a Reembolsar
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF261D17) : const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? AppColors.dividerDark : Colors.grey.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Monto a Reembolsar:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  Text(
                    '${PriceFormatter.formatSmart(refundAmount)} COP',
                    style: const TextStyle(
                      fontFamily: AppTypography.displayFamily,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF16A34A),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Selector de Método de Destino
            Text(
              'Selecciona a qué método deseas el reembolso:',
              style: TextStyle(
                fontFamily: AppTypography.bodyFamily,
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 10),

            if (walletState.cards.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFDBA74)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: Color(0xFFEA580C), size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No tienes métodos vinculados. Se procesará al método de la orden original.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF9A3412), fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...walletState.cards.map((card) {
                final isSelected = _selectedMethod?.id == card.id;
                return GestureDetector(
                  onTap: () => setState(() => _selectedMethod = card),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (isDark ? const Color(0xFF3B1E1E) : const Color(0xFFFFEBEE))
                          : (isDark ? const Color(0xFF261D17) : const Color(0xFFF9FAFB)),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? const Color(0xFFDC2626) : (isDark ? AppColors.dividerDark : Colors.grey.shade200),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: isSelected ? const Color(0xFFDC2626) : Colors.grey,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                card.displayTitle,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                              ),
                              Text(
                                card.maskedNumber,
                                style: TextStyle(fontSize: 12, color: isDark ? AppColors.textMutedDark : Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),

            const SizedBox(height: 18),

            // Motivo
            Text(
              'Motivo de la solicitud:',
              style: TextStyle(
                fontFamily: AppTypography.bodyFamily,
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF261D17) : const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isDark ? AppColors.dividerDark : Colors.grey.shade200),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedReason,
                  isExpanded: true,
                  dropdownColor: isDark ? const Color(0xFF261D17) : Colors.white,
                  items: _commonReasons.map((r) {
                    return DropdownMenuItem(
                      value: r,
                      child: Text(r, style: const TextStyle(fontSize: 13)),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedReason = v);
                  },
                ),
              ),
            ),

            if (_selectedReason == 'Otro motivo') ...[
              const SizedBox(height: 10),
              TextField(
                controller: _customReasonCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Describe brevemente el motivo...',
                  hintStyle: const TextStyle(fontSize: 12),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF261D17) : const Color(0xFFF9FAFB),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? AppColors.dividerDark : Colors.grey.shade200),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Botón Solicitar Reembolso
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitRefundRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 4,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Text(
                        'Enviar Solicitud de Reembolso 🔄',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
