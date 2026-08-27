// lib/features/cart/presentation/screens/cart_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:la_diabla/features/cart/providers/cart_notifier.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/price_formatter.dart';
import '../../../../core/widgets/diabla_button.dart';
import '../../../../core/widgets/diabla_empty_state.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final _couponController = TextEditingController();
  bool _isApplyingCoupon = false;

  @override
  void dispose() {
    _couponController.dispose();
    super.dispose();
  }

  Future<void> _handleApplyCoupon() async {
    final code = _couponController.text.trim();
    if (code.isEmpty) return;

    setState(() => _isApplyingCoupon = true);
    final success = await ref.read(cartNotifierProvider.notifier).applyCoupon(code);
    setState(() => _isApplyingCoupon = false);

    if (!mounted) return;
    if (success) {
      _couponController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎉 Cupón / Código $code aplicado con éxito.'),
          backgroundColor: AppColors.secondary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cupón no válido o expirado ❌'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartState = ref.watch(cartNotifierProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (cartState.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            'TU CARRITO 🛒',
            style: TextStyle(
              fontFamily: AppTypography.displayFamily,
              fontSize: 22,
              letterSpacing: 1.0,
            ),
          ),
        ),
        body: DiablaEmptyState(
          title: 'Tu carrito está vacío 🌮',
          message: 'Parece que aún no has agregado ningún antojo mexicano.',
          actionLabel: 'Ver el menú',
          onAction: () => context.go('/menu'),
        ),
      );
    }

    // Progreso para envío gratis (meta $40.000 COP)
    final freeShippingThreshold = 40000.0;
    final progress = (cartState.subtotal / freeShippingThreshold).clamp(0.0, 1.0);
    final amountLeftForFree = (freeShippingThreshold - cartState.subtotal).clamp(0.0, freeShippingThreshold);

    return Scaffold(
      backgroundColor: isDark ? AppColors.surfaceDark : const Color(0xFFFAF7F2),
      appBar: AppBar(
        title: Text(
          'TU CARRITO (${cartState.itemCount}) 🛒',
          style: const TextStyle(
            fontFamily: AppTypography.displayFamily,
            fontSize: 22,
            letterSpacing: 1.0,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)),
            tooltip: 'Vaciar carrito',
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('¿Vaciar carrito?'),
                  content: const Text(
                    '¿Deseas eliminar todos los productos de tu carrito de compra?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('No, continuar'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Sí, vaciar'),
                    ),
                  ],
                ),
              );
              if (confirm == true && mounted) {
                await ref.read(cartNotifierProvider.notifier).clearCart();
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Carrito vaciado 🗑️'),
                    backgroundColor: Color(0xFFDC2626),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
        children: [
          // ─── BARRA DE PROGRESO ENVÍO GRATIS ─────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cartState.isFreeDelivery
                  ? (isDark ? const Color(0xFF1B3820) : const Color(0xFFE8F5E9))
                  : (isDark ? const Color(0xFF2C1E14) : const Color(0xFFFFF8E7)),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cartState.isFreeDelivery ? const Color(0xFF81C784) : const Color(0xFFFFCC80),
                width: 1.2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      cartState.isFreeDelivery ? '🎉' : '🛵',
                      style: const TextStyle(fontSize: 18),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        cartState.isFreeDelivery
                            ? '¡ENVÍO GRATIS ACTIVADO! 💨'
                            : 'Agrega ${PriceFormatter.formatSmart(amountLeftForFree)} más para ENVÍO GRATIS',
                        style: TextStyle(
                          fontFamily: AppTypography.bodyFamily,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: cartState.isFreeDelivery ? const Color(0xFF2E7D32) : const Color(0xFFD97706),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: isDark ? Colors.black38 : Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      cartState.isFreeDelivery ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ─── LISTA DE ITEMS ──────────────────────────────────────────────
          ...cartState.items.map((item) {
            final product = item.product;

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
                    color: Colors.black.withAlpha(isDark ? 25 : 8),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Foto del Platillo
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      product.imageUrl,
                      width: 75,
                      height: 75,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 75,
                        height: 75,
                        color: isDark ? AppColors.surfaceDark : Colors.grey.shade200,
                        child: const Icon(Icons.fastfood, color: Colors.orange),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Datos del ítem
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: TextStyle(
                            fontFamily: AppTypography.bodyFamily,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: isDark ? AppColors.textLight : const Color(0xFF1E1E1E),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          PriceFormatter.formatSmart(item.unitPrice),
                          style: const TextStyle(
                            fontFamily: AppTypography.bodyFamily,
                            color: Color(0xFFDC2626),
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),

                        // Opciones de variante (ej: Licor, Proteína)
                        if (item.selectedOptions.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Wrap(
                              spacing: 4,
                              children: item.selectedOptions.entries.map((opt) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF3E0),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFFFB74D), width: 0.8),
                                  ),
                                  child: Text(
                                    '${opt.key}: ${opt.value}',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFE65100)),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),

                        // Ingredientes removidos (ej: ❌ Sin cebolla)
                        if (item.removedIngredients.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              '❌ Sin: ${item.removedIngredients.join(', ')}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                          ),

                        // Extras seleccionados
                        if (item.selectedExtras.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              '+ Extras: ${item.selectedExtras.map((e) => e.name).join(', ')}',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppColors.textMutedDark : Colors.grey.shade700,
                              ),
                            ),
                          ),

                        // Notas
                        if (item.notes != null && item.notes!.isNotEmpty)
                          Text(
                            '📝 Nota: ${item.notes}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontStyle: FontStyle.italic,
                              color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Control de Cantidad
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surfaceDark : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          icon: const Icon(Icons.add_rounded, size: 18, color: Color(0xFFDC2626)),
                          onPressed: () {
                            ref.read(cartNotifierProvider.notifier).updateQuantity(item.id, item.quantity + 1);
                          },
                        ),
                        Text(
                          '${item.quantity}',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          icon: Icon(
                            item.quantity <= 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
                            size: 18,
                            color: const Color(0xFFDC2626),
                          ),
                          onPressed: () {
                            if (item.quantity <= 1) {
                              ref.read(cartNotifierProvider.notifier).removeItem(item.id);
                            } else {
                              ref.read(cartNotifierProvider.notifier).updateQuantity(item.id, item.quantity - 1);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 12),

          // ─── SECCIÓN CUPONES & REFERIDOS ──────────────────────────────────
          if (cartState.appliedCoupon != null || cartState.appliedReferralCode != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF16A34A).withAlpha(25),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF16A34A), width: 1.2),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_offer_rounded, color: Color(0xFF16A34A), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cartState.appliedReferralCode != null
                              ? 'Referido: ${cartState.appliedReferralCode}'
                              : 'Cupón: ${cartState.appliedCoupon}',
                          style: const TextStyle(
                            fontFamily: AppTypography.displayFamily,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF16A34A),
                          ),
                        ),
                        Text(
                          cartState.appliedReferralCode != null
                              ? '¡Envío Gratis + \$5.000 COP Descuento Amigo! 🎁'
                              : cartState.appliedCoupon == 'DIABLAFREE'
                                  ? '¡Envío Gratis activado! 🛵💨'
                                  : '¡10% de descuento aplicado! 🔥',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF16A34A)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 20),
                    tooltip: 'Quitar cupón',
                    onPressed: () {
                      ref.read(cartNotifierProvider.notifier).removeCoupon();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _couponController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'Cupón o Código de Referido (ej. DIABLAFREE)',
                      hintStyle: const TextStyle(fontSize: 12.5),
                      prefixIcon: const Icon(Icons.local_offer_outlined, color: Color(0xFFDC2626), size: 20),
                      filled: true,
                      fillColor: isDark ? AppColors.cardDark : Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: isDark ? AppColors.dividerDark : Colors.grey.shade300,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isApplyingCoupon ? null : _handleApplyCoupon,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  ),
                  child: _isApplyingCoupon
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Aplicar', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // ─── RESUMEN DEL PEDIDO CON ESTILO DIABLA ─────────────────────────
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isDark ? AppColors.cardDark : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
                width: 1.2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'RESUMEN DE TU ORDEN',
                  style: TextStyle(
                    fontFamily: AppTypography.displayFamily,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Color(0xFFDC2626),
                    letterSpacing: 0.8,
                  ),
                ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Subtotal de Platillos', style: TextStyle(fontSize: 14)),
                    Text(
                      PriceFormatter.formatSmart(cartState.subtotal),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Costo de Domicilio (Delivery)', style: TextStyle(fontSize: 14)),
                    if (cartState.isFreeDelivery) ...[
                      const Text(
                        '¡GRATIS! 🛵💨',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF16A34A),
                          fontSize: 14,
                        ),
                      ),
                    ] else ...[
                      Text(
                        PriceFormatter.formatSmart(cartState.effectiveDeliveryFee),
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ],
                  ],
                ),
                if (cartState.discount > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Descuento de Cupón / Referido', style: TextStyle(color: Color(0xFF16A34A), fontSize: 14)),
                      Text(
                        '-${PriceFormatter.formatSmart(cartState.discount)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF16A34A),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TOTAL A PAGAR',
                      style: TextStyle(
                        fontFamily: AppTypography.displayFamily,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      PriceFormatter.formatSmart(cartState.total),
                      style: const TextStyle(
                        fontFamily: AppTypography.displayFamily,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Botón Checkout
          DiablaButton(
            text: 'Proceder al Checkout • ${PriceFormatter.formatSmart(cartState.total)}',
            onPressed: () => context.push('/checkout'),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
