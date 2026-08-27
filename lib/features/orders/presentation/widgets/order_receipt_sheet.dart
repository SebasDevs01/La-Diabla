// lib/features/orders/presentation/widgets/order_receipt_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/price_formatter.dart';
import '../../../../domain/entities/order_entity.dart';

class OrderReceiptSheet extends StatelessWidget {
  const OrderReceiptSheet({
    super.key,
    required this.order,
  });

  final OrderEntity order;

  static Future<String?> show(BuildContext context, OrderEntity order) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => OrderReceiptSheet(order: order),
    );
  }

  Future<void> _shareReceiptOnWhatsApp(BuildContext context) async {
    final shortId = order.id.length > 6
        ? order.id.substring(order.id.length - 6).toUpperCase()
        : order.id.toUpperCase();

    final dateFormat = DateFormat('dd/MM/yyyy hh:mm a');
    final formattedDate = dateFormat.format(order.createdAt ?? DateTime.now());

    final itemsList = order.items
        .map((i) => '• ${i.quantity}x ${i.product.name} (${PriceFormatter.formatSmart(i.product.price * i.quantity)})')
        .join('\n');

    final paymentText = switch (order.paymentMethod) {
      PaymentMethod.cash => '💵 Efectivo contra entrega (Paga con ${PriceFormatter.formatSmart(order.cashPaymentAmount ?? order.total)}, Cambio: ${PriceFormatter.formatSmart(order.cashChangeAmount ?? 0)})',
      PaymentMethod.nequi => '🟣 Nequi (#3171166497)',
      PaymentMethod.daviplata => '🔴 Daviplata (#3171166497)',
      PaymentMethod.card => '💳 Tarjeta Débito/Crédito (Aprobado)',
      PaymentMethod.transfer => '🏦 Transferencia / PSE',
      PaymentMethod.pos => '📟 Datáfono (Pago con tarjeta en la puerta)',
    };

    final message = '''
🌶️ *RECIBO DIGITAL — LA DIABLA* 🔥
*Orden:* #LD-$shortId
*Fecha:* $formattedDate
*Cliente:* ${order.address?.formattedAddress ?? 'Domicilio'}

🛒 *ITEMS DEL PEDIDO:*
$itemsList

💰 *RESUMEN DE PAGO:*
• Subtotal: ${PriceFormatter.formatSmart(order.subtotal)}
• Domicilio: ${PriceFormatter.formatSmart(order.deliveryFee)}
${order.discount > 0 ? '• Descuento: -${PriceFormatter.formatSmart(order.discount)}\n' : ''}*TOTAL:* ${PriceFormatter.formatSmart(order.total)}

💳 *MÉTODO:* $paymentText

¡Gracias por tu compra en La Diabla Comida Mexicana! 🌮✨
''';

    const phone = '573171166497';
    final waUri = Uri.parse('whatsapp://send?phone=$phone&text=${Uri.encodeComponent(message)}');
    final webUri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');

    if (await canLaunchUrl(waUri)) {
      await launchUrl(waUri, mode: LaunchMode.externalApplication);
    } else if (await canLaunchUrl(webUri)) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } else {
      await Clipboard.setData(ClipboardData(text: message));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recibo copiado al portapapeles 📋'),
            backgroundColor: Color(0xFF16A34A),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shortId = order.id.length > 6
        ? order.id.substring(order.id.length - 6).toUpperCase()
        : order.id.toUpperCase();

    final dateFormat = DateFormat('dd/MM/yyyy - hh:mm a');
    final formattedDate = dateFormat.format(order.createdAt ?? DateTime.now());

    final screenH = MediaQuery.of(context).size.height;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1410) : const Color(0xFFF9F6F0),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      constraints: BoxConstraints(maxHeight: screenH * 0.88),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.dividerDark : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Scroll region (recibo)
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 4),

            // Encabezado de éxito
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Color(0xFF16A34A),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 10),
            Text(
              '¡PEDIDO CONFIRMADO!',
              style: TextStyle(
                fontFamily: AppTypography.displayFamily,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: isDark ? const Color(0xFFFF5252) : const Color(0xFFDC2626),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Tu orden ya está en la cocina de La Diabla 🔥',
              style: TextStyle(
                fontFamily: AppTypography.bodyFamily,
                fontSize: 13,
                color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),

            // ─── TICKET RECIBO DIGITAL ────────────────────────────────────────
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF261C16) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark ? AppColors.dividerDark : const Color(0xFFFFE0B2),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(isDark ? 30 : 10),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cabecera del ticket
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'LA DIABLA 🌶️',
                            style: TextStyle(
                              fontFamily: AppTypography.displayFamily,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFDC2626),
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            'Recibo Digital Oficial',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white60 : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626).withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFDC2626).withAlpha(60)),
                        ),
                        child: Text(
                          '#LD-$shortId',
                          style: const TextStyle(
                            fontFamily: AppTypography.displayFamily,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                  Divider(color: isDark ? AppColors.dividerDark : Colors.grey.shade200),
                  const SizedBox(height: 8),

                  // Datos generales
                  _buildReceiptRow('Fecha & Hora:', formattedDate, isDark),
                  _buildReceiptRow(
                    'Dirección:',
                    order.address?.formattedAddress ?? 'Dirección registrada',
                    isDark,
                    isAddress: true,
                  ),

                  const SizedBox(height: 10),
                  Divider(color: isDark ? AppColors.dividerDark : Colors.grey.shade200),
                  const SizedBox(height: 8),

                  // Items
                  const Text(
                    'PLATILLOS:',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.6),
                  ),
                  const SizedBox(height: 6),
                  ...order.items.map((item) {
                    final itemTotal = item.product.price * item.quantity;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item.quantity}x ',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFDC2626)),
                          ),
                          Expanded(
                            child: Text(
                              item.product.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                          Text(
                            PriceFormatter.formatSmart(itemTotal),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 10),
                  Divider(color: isDark ? AppColors.dividerDark : Colors.grey.shade200),
                  const SizedBox(height: 8),

                  // Desglose
                  _buildSummaryRow('Subtotal:', PriceFormatter.formatSmart(order.subtotal), isDark),
                  _buildSummaryRow('Domicilio:', PriceFormatter.formatSmart(order.deliveryFee), isDark),
                  if (order.discount > 0)
                    _buildSummaryRow(
                      'Descuento:',
                      '-${PriceFormatter.formatSmart(order.discount)}',
                      isDark,
                      isDiscount: true,
                    ),

                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1712) : const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'TOTAL PAGADO:',
                          style: TextStyle(
                            fontFamily: AppTypography.displayFamily,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                        Text(
                          PriceFormatter.formatSmart(order.total),
                          style: const TextStyle(
                            fontFamily: AppTypography.displayFamily,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Método de Pago Badge
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black26 : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isDark ? AppColors.dividerDark : Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _getPaymentIcon(order.paymentMethod),
                              size: 18,
                              color: const Color(0xFFDC2626),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Método: ${order.paymentMethod.displayName}',
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        if (order.paymentMethod == PaymentMethod.cash && order.cashPaymentAmount != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Pagas con: ${PriceFormatter.formatSmart(order.cashPaymentAmount!)} • Cambio a recibir: ${PriceFormatter.formatSmart(order.cashChangeAmount ?? 0)}',
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFF16A34A), fontWeight: FontWeight.w600),
                          ),
                        ] else if (order.paymentMethod == PaymentMethod.nequi || order.paymentMethod == PaymentMethod.daviplata) ...[
                          const SizedBox(height: 4),
                          const Text(
                            'Transferencia oficial al celular: 317 116 6497',
                            style: TextStyle(fontSize: 11.5, color: Color(0xFF16A34A), fontWeight: FontWeight.w600),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // Botón Compartir Recibo a WhatsApp
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          // ── Botones sticky al fondo ──────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              MediaQuery.of(context).padding.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Botón WhatsApp
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: () => _shareReceiptOnWhatsApp(context),
                    icon: const Icon(Icons.share_rounded, size: 18, color: Color(0xFF16A34A)),
                    label: const Text(
                      'ENVIAR RECIBO POR WHATSAPP 📲',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF16A34A),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF16A34A), width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Botón Rastrear → navega a mis pedidos
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 2,
                    ),
                    onPressed: () {
                      Navigator.pop(context, order.id);
                    },
                    icon: const Icon(Icons.two_wheeler_rounded, size: 22),
                    label: const Text(
                      'VER MIS PEDIDOS 🛵💨',
                      style: TextStyle(
                        fontFamily: AppTypography.displayFamily,
                        fontSize: 16.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getPaymentIcon(PaymentMethod method) {
    return switch (method) {
      PaymentMethod.cash => Icons.payments_outlined,
      PaymentMethod.nequi => Icons.phone_android_rounded,
      PaymentMethod.daviplata => Icons.account_balance_wallet_rounded,
      PaymentMethod.card => Icons.credit_card_rounded,
      PaymentMethod.transfer => Icons.account_balance_rounded,
      PaymentMethod.pos => Icons.credit_score_rounded,
    };
  }

  Widget _buildReceiptRow(String label, String value, bool isDark, {bool isAddress = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: isAddress ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 95,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
              maxLines: isAddress ? 2 : 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, bool isDark, {bool isDiscount = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: isDiscount ? const Color(0xFF16A34A) : (isDark ? Colors.white70 : Colors.grey.shade700),
              fontWeight: isDiscount ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: isDiscount ? const Color(0xFF16A34A) : (isDark ? Colors.white : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
