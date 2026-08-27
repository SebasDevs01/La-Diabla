// lib/features/wallet/presentation/screens/wallet_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../domain/entities/payment_card_entity.dart';
import '../widgets/add_card_bottom_sheet.dart';
import 'link_nequi_screen.dart';
import 'link_bancolombia_screen.dart';
import '../../providers/wallet_provider.dart';

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key, this.isSelectionMode = false});

  final bool isSelectionMode;

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  bool _showAllCards = false;

  @override
  Widget build(BuildContext context) {
    final walletState = ref.watch(walletProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cards = walletState.cards;
    final visibleCards = _showAllCards ? cards : cards.take(2).toList();

    return Scaffold(
      backgroundColor: isDark ? AppColors.surfaceDark : const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: isDark ? Colors.white : Colors.black87),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.headset_mic_rounded, color: isDark ? Colors.white : Colors.black87),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Soporte de Billetera La Diabla activo 24/7 🌶️'),
                  backgroundColor: Color(0xFFDC2626),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        children: [
          // Título principal estilo Rappi
          Text(
            'Tu billetera La Diabla',
            style: TextStyle(
              fontFamily: AppTypography.displayFamily,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF1C1C1C),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 24),

          // ─── SECCIÓN: TUS MÉTODOS DE PAGO ─────────────────────────────────
          _buildDividerHeader('Tus métodos de pago', isDark),
          const SizedBox(height: 12),

          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1712) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(isDark ? 20 : 6),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                // 1. Efectivo
                _buildPaymentItem(
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Color(0xFF22C55E),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.attach_money_rounded, color: Colors.white, size: 20),
                  ),
                  title: 'Efectivo',
                  subtitle: '',
                  isSelected: walletState.selectedCard == null,
                  isDark: isDark,
                  onTap: () {
                    if (widget.isSelectionMode) {
                      context.pop(null); // Retorna null para seleccionar Efectivo
                    }
                  },
                ),

                // 2. Lista de tarjetas guardadas
                ...visibleCards.map((card) {
                  final isSelected = walletState.selectedCard?.id == card.id;
                  return Column(
                    children: [
                      Divider(height: 1, color: isDark ? AppColors.dividerDark : Colors.grey.shade100),
                      _buildSavedCardItem(card, isSelected, isDark),
                    ],
                  );
                }),

                // Botón "Ver más" si hay más de 2 tarjetas
                if (cards.length > 2) ...[
                  Divider(height: 1, color: isDark ? AppColors.dividerDark : Colors.grey.shade100),
                  InkWell(
                    onTap: () => setState(() => _showAllCards = !_showAllCards),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _showAllCards ? 'Ver menos' : 'Ver más',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _showAllCards ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ─── SECCIÓN: AGREGAR NUEVO MÉTODO DE PAGO ────────────────────────
          _buildDividerHeader('Agregar nuevo método de pago', isDark),
          const SizedBox(height: 12),

          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1712) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(isDark ? 20 : 6),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                // 1. Tarjeta Crédito o Débito
                _buildAddOptionItem(
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Color(0xFF262626),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.credit_card_rounded, color: Colors.white, size: 18),
                  ),
                  title: 'Crédito o Débito (Con CVV)',
                  brandBadges: _buildCardBadges(),
                  isDark: isDark,
                  onTap: () async {
                    final router = GoRouter.of(context);
                    final added = await AddCardBottomSheet.show(context);
                    if (added == true && widget.isSelectionMode && mounted) {
                      router.pop(ref.read(walletProvider).selectedCard);
                    }
                  },
                ),
                Divider(height: 1, color: isDark ? AppColors.dividerDark : Colors.grey.shade100),

                // 2. Nequi
                _buildAddOptionItem(
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Color(0xFF7800FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.phone_android_rounded, color: Colors.white, size: 18),
                  ),
                  title: 'Nequi',
                  subtitle: 'Vincula tu cuenta o número Nequi',
                  isDark: isDark,
                  onTap: () async {
                    final router = GoRouter.of(context);
                    final added = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(builder: (_) => const LinkNequiScreen()),
                    );
                    if (added == true && widget.isSelectionMode && mounted) {
                      router.pop(ref.read(walletProvider).selectedCard);
                    }
                  },
                ),
                Divider(height: 1, color: isDark ? AppColors.dividerDark : Colors.grey.shade100),

                // 3. Bancolombia / PSE
                _buildAddOptionItem(
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFDDA24),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.account_balance_rounded, color: Colors.black, size: 18),
                  ),
                  title: 'Bancolombia / PSE',
                  subtitle: 'Transferencia bancaria en línea directa',
                  isDark: isDark,
                  onTap: () async {
                    final router = GoRouter.of(context);
                    final added = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(builder: (_) => const LinkBancolombiaScreen()),
                    );
                    if (added == true && widget.isSelectionMode && mounted) {
                      router.pop(ref.read(walletProvider).selectedCard);
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ─── SECCIÓN: MÉTODO DE REEMBOLSO ─────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1712) : Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Método de reembolso', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      'Inmediato en la App',
                      style: TextStyle(fontSize: 12, color: isDark ? AppColors.textMutedDark : Colors.grey.shade600),
                    ),
                  ],
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.grey),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildDividerHeader(String text, bool isDark) {
    return Row(
      children: [
        Expanded(child: Divider(color: isDark ? AppColors.dividerDark : Colors.grey.shade300)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
            ),
          ),
        ),
        Expanded(child: Divider(color: isDark ? AppColors.dividerDark : Colors.grey.shade300)),
      ],
    );
  }

  Widget _buildPaymentItem({
    required Widget icon,
    required String title,
    required String subtitle,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: Color(0xFFDC2626), size: 20)
            else
              const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedCardItem(PaymentCardEntity card, bool isSelected, bool isDark) {
    return InkWell(
      onTap: () {
        ref.read(walletProvider.notifier).selectCard(card);
        if (widget.isSelectionMode) {
          context.pop(card);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            _buildBrandBadge(card.brand),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                card.holderName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              card.maskedNumber,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(width: 8),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: Color(0xFFDC2626), size: 20)
            else
              const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandBadge(String brand) {
    final b = brand.toLowerCase();
    Color bg = const Color(0xFF1A1F71);
    Color textColor = Colors.white;
    String label = brand.toUpperCase();

    if (b == 'nequi') {
      bg = const Color(0xFF7800FF);
      label = 'NEQUI';
    } else if (b == 'bancolombia') {
      bg = const Color(0xFFFDDA24);
      textColor = Colors.black;
      label = 'BANCOLOMBIA';
    } else if (b == 'mastercard') {
      bg = const Color(0xFFEB001B);
    } else if (b == 'amex') {
      bg = const Color(0xFF006FCF);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildAddOptionItem({
    required Widget icon,
    required String title,
    String? subtitle,
    Widget? brandBadges,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: title.contains('Crédito') ? const Color(0xFF16A34A) : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 11.5, color: isDark ? AppColors.textMutedDark : Colors.grey)),
                  ],
                ],
              ),
            ),
            if (brandBadges != null) ...[
              brandBadges,
              const SizedBox(width: 8),
            ],
            const Icon(Icons.add_rounded, color: Colors.black87, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildCardBadges() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildMiniCircle(const Color(0xFF0079BE), 'A'),
        const SizedBox(width: 2),
        _buildMiniCircle(const Color(0xFF1A1F71), 'V'),
        const SizedBox(width: 2),
        _buildMiniCircle(const Color(0xFFEB001B), 'M'),
      ],
    );
  }

  Widget _buildMiniCircle(Color color, String letter) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}
