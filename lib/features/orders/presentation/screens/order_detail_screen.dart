// lib/features/orders/presentation/screens/order_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/price_formatter.dart';
import '../../../../core/widgets/diabla_card.dart';
import '../../../../core/widgets/navigation_app_picker.dart';
import '../../../wallet/presentation/widgets/refund_method_sheet.dart';
import '../../providers/orders_provider.dart';

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final orderAsync = ref.watch(singleOrderStreamProvider(orderId));
    final shortId = orderId.length > 6 ? orderId.substring(orderId.length - 6).toUpperCase() : orderId.toUpperCase();

    return Scaffold(
      backgroundColor: isDark ? AppColors.surfaceDark : const Color(0xFFFAF7F2),
      appBar: AppBar(
        title: Text('PEDIDO #$shortId', style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFDC2626))),
        error: (err, _) => Center(child: Text('Error al cargar pedido: $err')),
        data: (order) {
          if (order == null) {
            return const Center(child: Text('Pedido no encontrado'));
          }

          final addr = order.address;
          final lat = order.latitude ?? addr?.latitude ?? 7.092758;
          final lng = order.longitude ?? addr?.longitude ?? -73.142590;
          final formattedAddr = addr?.formattedAddress ?? 'Dirección registrada en el pedido';

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
            children: [
              // 1. Header de Estado
              DiablaCard(
                backgroundColor: const Color(0xFFDC2626),
                child: Row(
                  children: [
                    const Text('🌮', style: TextStyle(fontSize: 32)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.status.displayName.toUpperCase(),
                            style: const TextStyle(
                              fontFamily: AppTypography.displayFamily,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Método: ${order.paymentMethod.displayName}',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 2. Resumen de Productos
              DiablaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Resumen del Pedido', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const Divider(height: 20),
                    ...order.items.map((item) {
                      final extrasName = item.selectedExtras.isNotEmpty
                          ? '\n+ ${item.selectedExtras.map((e) => e.name).join(', ')}'
                          : '';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '${item.quantity}x ${item.product.name}$extrasName',
                                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                              ),
                            ),
                            Text(
                              PriceFormatter.formatSmart(item.unitPrice * item.quantity),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Domicilio', style: TextStyle(fontSize: 13)),
                        Text(PriceFormatter.formatSmart(order.deliveryFee), style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                    if (order.discount > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Descuento Cupón', style: TextStyle(fontSize: 13, color: Color(0xFF16A34A))),
                          Text('-${PriceFormatter.formatSmart(order.discount)}', style: const TextStyle(fontSize: 13, color: Color(0xFF16A34A), fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Pagado', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(
                          '${PriceFormatter.formatSmart(order.total)} COP',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFDC2626)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 3. Dirección de Entrega + Botón Navegación
              DiablaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.location_on_rounded, color: Color(0xFFDC2626), size: 20),
                            SizedBox(width: 8),
                            Text('Dirección de Entrega', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ],
                        ),
                        TextButton.icon(
                          onPressed: () {
                            NavigationAppPicker.show(
                              context,
                              latitude: lat,
                              longitude: lng,
                              destinationName: 'Cliente La Diabla #$shortId',
                              addressText: formattedAddr,
                            );
                          },
                          icon: const Icon(Icons.navigation_rounded, size: 16, color: Color(0xFF00A3DA)),
                          label: const Text('Navegar 🗺️', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF00A3DA))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(formattedAddr, style: const TextStyle(fontSize: 13.5)),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 4. Botón Solicitar Reembolso
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.currency_exchange_rounded, size: 20),
                  label: const Text('Solicitar Reembolso del Pedido 🔄', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                  onPressed: () => RefundMethodSheet.show(context, order: order),
                ),
              ),
              const SizedBox(height: 20),
            ],
          );
        },
      ),
    );
  }
}
