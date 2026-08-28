import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/services/maps_service.dart';
import '../../../../core/services/mercadopago_service.dart';
import '../../../../core/utils/price_formatter.dart';
import '../../../../core/widgets/diabla_button.dart';
import '../../../../core/widgets/diabla_card.dart';
import '../../../../domain/entities/address_entity.dart';
import '../../../../domain/entities/order_entity.dart';
import '../../../../domain/entities/order_status.dart';
import '../../../addresses/providers/addresses_provider.dart';
import '../../../auth/providers/auth_notifier.dart';
import '../../../cart/providers/cart_notifier.dart';
import '../../../checkout/providers/coupon_provider.dart';
import '../../../orders/presentation/widgets/order_receipt_sheet.dart';
import '../../../orders/providers/orders_provider.dart';
import '../../../wallet/presentation/widgets/add_card_bottom_sheet.dart';
import '../../../wallet/providers/wallet_provider.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  PaymentMethod? _selectedPaymentMethod;
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _customCashCtrl = TextEditingController();
  final TextEditingController _couponCtrl = TextEditingController();
  double? _selectedCashBill; // null: monto exacto
  bool _isCustomCashBill = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _calculateDistanceAndFee());
  }

  void _calculateDistanceAndFee() {
    final addressesState = ref.read(addressesProvider);
    final user = ref.read(authNotifierProvider).user;
    final selectedAddress = addressesState.defaultAddress;

    double lat = 7.092758;
    double lng = -73.142590;

    if (selectedAddress != null) {
      lat = selectedAddress.latitude;
      lng = selectedAddress.longitude;
    }

    final distanceKm = MapsService.calculateDistanceKm(
      MapsService.defaultLocation,
      LatLng(lat, lng),
    );

    ref.read(cartNotifierProvider.notifier).setDeliveryDistance(
          distanceKm,
          addressFormatted: selectedAddress?.formattedAddress ?? user?.guestAddress,
        );
  }

  @override
  void dispose() {
    _notesController.dispose();
    _customCashCtrl.dispose();
    _couponCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleConfirmOrder() async {
    final messenger = ScaffoldMessenger.of(context);
    final cartState = ref.read(cartNotifierProvider);
    final addressesState = ref.read(addressesProvider);
    final authState = ref.read(authNotifierProvider);
    final walletState = ref.read(walletProvider);
    final user = authState.user;
    final selectedAddress = addressesState.defaultAddress;

    // 0. VALIDACIÓN OBLIGATORIA DE MÉTODO DE PAGO
    if (_selectedPaymentMethod == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('⚠️ Por favor selecciona un método de pago antes de continuar 💳'),
          backgroundColor: Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // 1. VALIDACIÓN OBLIGATORIA DE DIRECCIÓN
    final hasAddress = selectedAddress != null ||
        (user?.guestAddress != null && user!.guestAddress!.trim().isNotEmpty);

    if (!hasAddress) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('⚠️ Por favor agrega tu dirección de entrega antes de confirmar el pedido 📍'),
          backgroundColor: Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.push('/addresses');
      return;
    }

    // 2. VALIDACIÓN OBLIGATORIA DE NÚMERO DE TELÉFONO
    final userPhone = user?.phone?.trim() ?? '';
    final hasValidPhone = userPhone.isNotEmpty &&
        userPhone != '3000000000' &&
        userPhone.length >= 7;

    // Si no tiene celular válido, mostramos el diálogo
    if (!hasValidPhone) {
      final enteredPhone = await _showRequirePhoneDialog(context);
      if (!mounted) return;
      if (enteredPhone == null || enteredPhone.trim().length < 7) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('⚠️ Tu celular es obligatorio para que el repartidor te contacte al entregar 📱'),
            backgroundColor: Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      // Actualizar en Auth y Firestore en segundo plano
      if (user != null) {
        final updatedUser = user.copyWith(phone: enteredPhone);
        ref.read(authNotifierProvider.notifier).updateUser(updatedUser);
        FirebaseFirestore.instance
            .collection('users')
            .doc(updatedUser.id)
            .set({'phone': enteredPhone}, SetOptions(merge: true))
            .catchError((_) {});
      }
    }

    final orderId = const Uuid().v4();

    final fallbackGuestAddress = AddressEntity(
      id: 'addr_guest',
      userId: user?.id ?? 'guest',
      label: AddressLabel.home,
      latitude: 7.092758,
      longitude: -73.142590,
      formattedAddress: user?.guestAddress ?? 'Cl. 59 # 39W-24, Estoraques 1, Bucaramanga',
    );

    final effectiveOrderAddress = selectedAddress ?? fallbackGuestAddress;
    final couponState = ref.read(couponProvider);
    final couponDiscount = couponState.coupon?.calculateDiscount(cartState.total) ?? 0;
    final total = (cartState.total - couponDiscount).clamp(0.0, double.infinity);

    // Calcular cambio si es efectivo
    double? cashPayment;
    double? cashChange;

    if (_selectedPaymentMethod == PaymentMethod.cash) {
      if (_isCustomCashBill) {
        final parsed = double.tryParse(_customCashCtrl.text.replaceAll('.', '').replaceAll(',', '').trim());
        cashPayment = (parsed != null && parsed >= total) ? parsed : total;
      } else {
        cashPayment = _selectedCashBill ?? total;
      }
      cashChange = (cashPayment - total) > 0 ? (cashPayment - total) : 0.0;
    }

    // ─── Flujo de Pagos Digitales con Mercado Pago (Tarjetas, PSE) ──────────────
    // Para Nequi/Daviplata: el cliente transfiere manualmente y el negocio confirma
    // Para Efectivo/Datáfono: no requiere verificación previa
    String? mpTransactionRef;
    bool isPaid = false;

    // Métodos que usan Checkout Pro de Mercado Pago (PSE en línea o nueva pasarela externa)
    final hasSavedCard = _selectedPaymentMethod == PaymentMethod.card && walletState.selectedCard != null;
    final isMercadoPagoMethod = _selectedPaymentMethod == PaymentMethod.transfer ||
        (_selectedPaymentMethod == PaymentMethod.card && !hasSavedCard);

    // Métodos manuales / directos (Efectivo, Datáfono, Nequi, Daviplata, o Tarjeta vinculada)
    final isManualPayment = _selectedPaymentMethod == PaymentMethod.nequi ||
        _selectedPaymentMethod == PaymentMethod.daviplata ||
        _selectedPaymentMethod == PaymentMethod.cash ||
        _selectedPaymentMethod == PaymentMethod.pos ||
        hasSavedCard;

    if (isMercadoPagoMethod) {
      final methodTitle = MercadoPagoService.methodDisplayName(_selectedPaymentMethod!);
      final methodEmoji = MercadoPagoService.methodEmoji(_selectedPaymentMethod!);

      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Conectando pasarela de pago segura ($methodTitle $methodEmoji)... 🔒',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF009EE3),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );

      // 1. Crear preferencia y abrir la URL de Checkout Pro
      final checkoutUrl = await MercadoPagoService.createCheckoutPreference(
        orderId: orderId,
        items: cartState.items,
        deliveryFee: cartState.effectiveDeliveryFee,
        discount: cartState.discount,
        user: user,
        paymentMethod: _selectedPaymentMethod!,
      );

      if (!mounted) return;

      if (checkoutUrl == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Error al generar la pasarela de pago. Intenta nuevamente.'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final launched = await MercadoPagoService.launchCheckoutUrl(checkoutUrl);
      if (!mounted) return;

      if (!launched) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir la pasarela de pagos. Verifica tu navegador.'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      // 2. Verificar con la API de MP que el pago fue REALMENTE aprobado
      //    (el usuario pudo haber cancelado o vuelto sin pagar)
      if (!mounted) return;
      _showPaymentVerifyingDialog();

      bool paymentApproved = false;
      // Polling: hasta 3 intentos con 8s de intervalo (para PSE que puede demorar)
      for (int attempt = 0; attempt < 3; attempt++) {
        await Future.delayed(const Duration(seconds: 8));
        if (!mounted) break;
        paymentApproved = await MercadoPagoService.checkPaymentApproved(orderId);
        if (paymentApproved) break;
      }

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // cerrar diálogo de verificación

      if (!paymentApproved) {
        // ⛔ PAGO NO CONFIRMADO — NO se crea el pedido
        messenger.showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.error_outline_rounded, color: Colors.white),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Pago no completado o cancelado. El pedido NO fue enviado. Inténtalo de nuevo.',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
        return; // ← No se continúa, no se crea el pedido
      }

      // ✅ Pago aprobado por Mercado Pago
      isPaid = true;
      final prefix = switch (_selectedPaymentMethod) {
        PaymentMethod.card => 'MP-CARD',
        PaymentMethod.transfer => 'MP-PSE',
        _ => 'MP-PAY',
      };
      mpTransactionRef = '$prefix-${orderId.substring(0, 8).toUpperCase()}';

    } else if (isManualPayment) {
      // Nequi / Daviplata: el cliente transfirió manualmente.
      // Se crea el pedido con paymentStatus = pending para que el negocio confirme.
      isPaid = false;
      final prefix = _selectedPaymentMethod == PaymentMethod.nequi ? 'NEQUI' : 'DAVIPLATA';
      mpTransactionRef = '$prefix-MANUAL-${orderId.substring(0, 6).toUpperCase()}';
    }

    final savedCard = walletState.selectedCard;
    final order = OrderEntity(
      id: orderId,
      userId: user?.id ?? 'guest',
      items: cartState.items,
      subtotal: cartState.subtotal,
      deliveryFee: cartState.effectiveDeliveryFee,
      discount: cartState.discount,
      total: total,
      status: OrderStatus.pending,
      paymentMethod: _selectedPaymentMethod!,
      paymentStatus: isPaid ? PaymentStatus.paid : PaymentStatus.pending,
      orderType: OrderType.delivery,
      address: effectiveOrderAddress,
      cashPaymentAmount: cashPayment,
      cashChangeAmount: cashChange,
      transactionReference: mpTransactionRef ??
          (_selectedPaymentMethod == PaymentMethod.card
              ? '${savedCard?.brand.toUpperCase() ?? "CARD"} *${savedCard?.lastFourDigits ?? "2151"}'
              : ((_selectedPaymentMethod == PaymentMethod.nequi || _selectedPaymentMethod == PaymentMethod.daviplata)
                  ? '3171166497'
                  : null)),
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final created = await ref
        .read(createOrderNotifierProvider.notifier)
        .placeOrder(order);

    if (!mounted) return;
    if (created != null) {
      // Registrar uso del cupón en Firestore
      final couponState = ref.read(couponProvider);
      if (couponState.coupon != null && user?.id != null) {
        await ref.read(couponProvider.notifier).registerCouponUsage(
          code: couponState.coupon!.code,
          userId: user!.id,
          orderId: created.id,
        );
        ref.read(couponProvider.notifier).clearCoupon();
      }
      await ref.read(cartNotifierProvider.notifier).clearCart();
      if (!mounted) return;
      // Mostrar Recibo Digital — retorna el orderId si el usuario pulsa "Ver mis pedidos"
      final resultId = await OrderReceiptSheet.show(context, created);
      if (mounted) {
        // Si retornó un ID navega al tracking de ese pedido, sino a la lista de pedidos
        if (resultId != null && resultId.isNotEmpty) {
          context.go('/tracking/$resultId');
        } else {
          context.go('/orders');
        }
      }
    } else {
      final err = ref.read(createOrderNotifierProvider).errorMessage;
      messenger.showSnackBar(
        SnackBar(
          content: Text(err ?? 'Error al realizar el pedido'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copiado al portapapeles 📋'),
        backgroundColor: const Color(0xFF16A34A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cartState = ref.watch(cartNotifierProvider);
    final addressesState = ref.watch(addressesProvider);
    final authState = ref.watch(authNotifierProvider);
    final createOrderState = ref.watch(createOrderNotifierProvider);
    final couponState = ref.watch(couponProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 🐛 DEBUG: Ayuda a diagnosticar pantalla en blanco
    debugPrint('🛒 CheckoutScreen.build: items=${cartState.items.length}, isEmpty=${cartState.items.isEmpty}, user=${authState.user?.id ?? "null"}');

    final subtotal = cartState.total;
    final couponDiscount = couponState.coupon?.calculateDiscount(subtotal) ?? 0;
    final total = (subtotal - couponDiscount).clamp(0.0, double.infinity);
    final distanceKm = cartState.distanceKm ?? 2.8;
    final isLoading = createOrderState.isLoading;

    return Scaffold(
      backgroundColor: isDark ? AppColors.surfaceDark : const Color(0xFFFAF7F2),
      appBar: AppBar(
        title: const Text('Confirmar y Pagar 🌶️', style: TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 22)),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: cartState.items.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.shopping_cart_outlined, size: 64, color: AppColors.textMuted),
                    const SizedBox(height: 16),
                    Text(
                      'Tu carrito está vacío',
                      style: TextStyle(
                        fontSize: 16,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Agrega productos desde el menú para continuar',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? AppColors.textMutedDark : AppColors.textMuted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    DiablaButton(
                      text: 'Ver Menú 🔥',
                      onPressed: () => context.go('/menu'),
                    ),
                  ],
                ),
              )
            : ListView(
              padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
              children: [
                // ─── 1. DIRECCIÓN DE ENTREGA ────────────────────────────────
                _buildSectionTitle('1. Dirección de Entrega 📍', isDark),
                const SizedBox(height: 8),
                DiablaCard(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626).withAlpha(20),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.location_on_rounded, color: Color(0xFFDC2626), size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                authState.user?.isGuest == true
                                    ? 'Entrega Invitado: ${authState.user?.name ?? 'Invitado'}'
                                    : (addressesState.defaultAddress?.label.displayName ?? 'Mi Dirección'),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                addressesState.defaultAddress?.formattedAddress ??
                                    (authState.user?.guestAddress ?? 'Selecciona una dirección'),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                                ),
                              ),
                              if (distanceKm > 0) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.two_wheeler_rounded, size: 14, color: Color(0xFF16A34A)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'A ${distanceKm.toStringAsFixed(1)} km del restaurante',
                                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF16A34A), fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // ─── 2. MÉTODO DE PAGO ──────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildSectionTitle('2. Método de Pago 💳', isDark),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16A34A).withAlpha(20),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.lock_outline_rounded, size: 12, color: Color(0xFF16A34A)),
                          SizedBox(width: 4),
                          Text(
                            '100% SEGURO',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF16A34A),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DiablaCard(
                  child: Column(
                    children: [
                      // 💳 SECCIÓN DE TARJETAS VINCULADAS (ESTILO RAPPI)
                      ...ref.watch(walletProvider).cards.map((card) {
                        final isSelected = _selectedPaymentMethod == PaymentMethod.card &&
                            ref.watch(walletProvider).selectedCard?.id == card.id;
                        return Column(
                          children: [
                            InkWell(
                              onTap: () {
                                ref.read(walletProvider.notifier).selectCard(card);
                                setState(() => _selectedPaymentMethod = PaymentMethod.card);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: card.brand == 'visa' ? const Color(0xFF1A1F71) : const Color(0xFFEB001B),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        card.brand.toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            card.holderName,
                                            style: TextStyle(
                                              fontFamily: AppTypography.bodyFamily,
                                              fontSize: 13.5,
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                              color: isDark ? Colors.white : Colors.black87,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            '${card.cardType} *${card.lastFourDigits} • Expira ${card.expiryDate}',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                                      color: isSelected ? const Color(0xFFDC2626) : Colors.grey,
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const Divider(height: 1),
                          ],
                        );
                      }),

                      // ➕ AGREGAR NUEVA TARJETA
                      InkWell(
                        onTap: () async {
                          final added = await AddCardBottomSheet.show(context);
                          if (added == true && mounted) {
                            setState(() => _selectedPaymentMethod = PaymentMethod.card);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF262626),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.credit_card_rounded, color: Colors.white, size: 16),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Crédito o Débito (Con CVV)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF16A34A),
                                  ),
                                ),
                              ),
                              const Icon(Icons.add_rounded, color: Color(0xFF16A34A), size: 20),
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 1),

                      // 💵 EFECTIVO
                      _buildPaymentRadioTile(
                        value: PaymentMethod.cash,
                        title: 'Efectivo',
                        subtitle: 'Pagas en efectivo cuando el repartidor llegue',
                        icon: Icons.payments_outlined,
                        iconColor: const Color(0xFF16A34A),
                        isDark: isDark,
                      ),
                      if (_selectedPaymentMethod == PaymentMethod.cash)
                        _buildCashOptionsWidget(total, isDark),
                      const Divider(height: 1),

                      // 🟣 NEQUI
                      _buildPaymentRadioTile(
                        value: PaymentMethod.nequi,
                        title: 'Nequi (Transferencia Directa)',
                        subtitle: 'Transfiere a nuestra cuenta oficial Nequi',
                        icon: Icons.phone_android_rounded,
                        iconColor: const Color(0xFF7800FF),
                        isDark: isDark,
                      ),
                      if (_selectedPaymentMethod == PaymentMethod.nequi)
                        _buildDirectTransferBanner('Nequi', '3171166497', const Color(0xFF7800FF), isDark),
                      const Divider(height: 1),

                      // 🔴 DAVIPLATA
                      _buildPaymentRadioTile(
                        value: PaymentMethod.daviplata,
                        title: 'Daviplata (Transferencia Directa)',
                        subtitle: 'Transfiere a nuestra cuenta oficial Daviplata',
                        icon: Icons.account_balance_wallet_rounded,
                        iconColor: const Color(0xFFE50914),
                        isDark: isDark,
                      ),
                      if (_selectedPaymentMethod == PaymentMethod.daviplata)
                        _buildDirectTransferBanner('Daviplata', '3171166497', const Color(0xFFE50914), isDark),
                      const Divider(height: 1),

                      // 🏦 PSE / BANCOLOMBIA
                      _buildPaymentRadioTile(
                        value: PaymentMethod.transfer,
                        title: 'PSE / Bancolombia en línea',
                        subtitle: 'Débito bancario en línea instantáneo por Mercado Pago',
                        icon: Icons.account_balance_rounded,
                        iconColor: const Color(0xFF009EE3),
                        isDark: isDark,
                      ),
                      const Divider(height: 1),

                      // 📟 DATÁFONO (Pago con tarjeta al recibir)
                      _buildPaymentRadioTile(
                        value: PaymentMethod.pos,
                        title: 'Datáfono (Tarjeta al recibir)',
                        subtitle: 'El repartidor lleva datáfono. Pagas con tu tarjeta en la puerta.',
                        icon: Icons.credit_score_rounded,
                        iconColor: const Color(0xFF0EA5E9),
                        isDark: isDark,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // ─── 3. CUPÓN DE DESCUENTO ─────────────────────────────────
                _buildSectionTitle('3. Cupón de Descuento 🏷️', isDark),
                const SizedBox(height: 8),
                DiablaCard(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _couponCtrl,
                                textCapitalization: TextCapitalization.characters,
                                enabled: couponState.coupon == null,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: isDark ? Colors.white : Colors.black87,
                                  letterSpacing: 1.2,
                                ),
                                decoration: InputDecoration(
                                  hintText: couponState.coupon != null
                                      ? couponState.coupon!.code
                                      : 'Código de cupón...',
                                  hintStyle: TextStyle(
                                    fontSize: 13,
                                    letterSpacing: 0,
                                    fontWeight: FontWeight.normal,
                                    color: isDark ? AppColors.textMutedDark : Colors.grey.shade500,
                                  ),
                                  prefixIcon: const Icon(Icons.local_offer_rounded, size: 20, color: Color(0xFFDC2626)),
                                  suffixIcon: couponState.coupon == null
                                      ? IconButton(
                                          icon: const Icon(Icons.content_paste_rounded, size: 18, color: Color(0xFFDC2626)),
                                          tooltip: 'Pegar portapapeles',
                                          onPressed: () async {
                                            final data = await Clipboard.getData(Clipboard.kTextPlain);
                                            if (data?.text != null && data!.text!.trim().isNotEmpty) {
                                              _couponCtrl.text = data.text!.trim().toUpperCase();
                                              ref.read(couponProvider.notifier).validateCoupon(
                                                    code: _couponCtrl.text,
                                                    userId: authState.user?.id ?? 'guest',
                                                    subtotal: cartState.subtotal,
                                                  );
                                            }
                                          },
                                        )
                                      : null,
                                  isDense: true,
                                  filled: true,
                                  fillColor: isDark ? const Color(0xFF16100C) : const Color(0xFFF9F6F0),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(color: const Color(0xFFDC2626).withAlpha(80), width: 1.5),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(color: const Color(0xFFDC2626).withAlpha(80), width: 1.5),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(color: Color(0xFFDC2626), width: 2),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            if (couponState.coupon == null)
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFDC2626),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                  minimumSize: Size.zero,
                                  elevation: 2,
                                ),
                                onPressed: couponState.isLoading
                                    ? null
                                    : () {
                                        final code = _couponCtrl.text.trim();
                                        if (code.isNotEmpty) {
                                          ref.read(couponProvider.notifier).validateCoupon(
                                                code: code,
                                                userId: authState.user?.id ?? 'guest',
                                                subtotal: cartState.subtotal,
                                              );
                                        }
                                      },
                                child: couponState.isLoading
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Text('Aplicar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                              )
                            else
                              IconButton(
                                icon: const Icon(Icons.close_rounded, color: Colors.red, size: 24),
                                tooltip: 'Quitar cupón',
                                onPressed: () {
                                  _couponCtrl.clear();
                                  ref.read(couponProvider.notifier).clearCoupon();
                                },
                              ),
                          ],
                        ),

                        // Cupones de Fidelidad — visibles solo si el cliente tiene suficientes órdenes
                        if (couponState.coupon == null) ...[
                          _LoyaltyCouponsSection(
                            isDark: isDark,
                            userId: authState.user?.id ?? '',
                            subtotal: cartState.subtotal,
                            couponCtrl: _couponCtrl,
                          ),
                        ],

                        // Banner de Cupón Aplicado con Éxito
                        if (couponState.coupon != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF16A34A).withAlpha(25),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF16A34A).withAlpha(80)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF16A34A),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.check, color: Colors.white, size: 14),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '¡Cupón ${couponState.coupon!.code} activado!',
                                        style: const TextStyle(
                                          color: Color(0xFF16A34A),
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        'Descuento aplicado: ${PriceFormatter.formatSmart(couponDiscount)}',
                                        style: TextStyle(
                                          color: isDark ? Colors.white70 : Colors.grey.shade800,
                                          fontSize: 11.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    _couponCtrl.clear();
                                    ref.read(couponProvider.notifier).clearCoupon();
                                  },
                                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                                  child: const Text('Quitar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (couponState.errorMessage != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Colors.red, size: 15),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  couponState.errorMessage!,
                                  style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // ─── 4. NOTAS DEL PEDIDO ─────────────────────────────────────
                _buildSectionTitle('4. Notas Adicionales 📝', isDark),
                const SizedBox(height: 8),
                TextField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Ej: Timbre no funciona, dejar en portería...',
                    hintStyle: TextStyle(fontSize: 13, color: isDark ? AppColors.textMutedDark : Colors.grey),
                    filled: true,
                    fillColor: isDark ? AppColors.cardDark : Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // ─── 5. RESUMEN DEL PEDIDO ──────────────────────────────────
                _buildSectionTitle('5. Resumen de la Orden 🧾', isDark),
                const SizedBox(height: 8),
                DiablaCard(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Subtotal Productos', style: TextStyle(color: isDark ? AppColors.textMutedDark : Colors.grey.shade700, fontSize: 13)),
                            Text(PriceFormatter.formatSmart(cartState.subtotal), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Domicilio (${distanceKm.toStringAsFixed(1)} km)', style: TextStyle(color: isDark ? AppColors.textMutedDark : Colors.grey.shade700, fontSize: 13)),
                            Text(PriceFormatter.formatSmart(cartState.effectiveDeliveryFee), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          ],
                        ),
                        if (couponDiscount > 0) ...[
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.local_offer_rounded, size: 14, color: Color(0xFF16A34A)),
                                  const SizedBox(width: 4),
                                  Text('Descuento Cupón (${couponState.coupon?.code})', style: const TextStyle(color: Color(0xFF16A34A), fontSize: 13, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              Text('-${PriceFormatter.formatSmart(couponDiscount)}', style: const TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ],
                        const Divider(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total a Pagar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            Text(PriceFormatter.formatSmart(total), style: const TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 20, color: Color(0xFFDC2626))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // ─── BOTÓN CONFIRMAR ORDEN ──────────────────────────────────
                DiablaButton(
                  text: isLoading
                      ? 'Procesando pedido...'
                      : 'Confirmar Pedido • ${PriceFormatter.formatSmart(total)} 🔥',
                  isLoading: isLoading,
                  onPressed: isLoading ? null : _handleConfirmOrder,
                ),
                const SizedBox(height: 30),
              ],
            ),
        ),
    );
  }

  // Eliminado _buildQuickCouponChip — reemplazado por _LoyaltyCouponsSection

  Widget _buildSectionTitle(String title, bool isDark) {
    return Text(
      title,
      style: TextStyle(
        fontFamily: AppTypography.displayFamily,
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: isDark ? const Color(0xFFFF5252) : const Color(0xFFC62828),
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildPaymentRadioTile({
    required PaymentMethod value,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required bool isDark,
  }) {
    final isSelected = _selectedPaymentMethod == value;
    return InkWell(
      onTap: () => setState(() => _selectedPaymentMethod = value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: iconColor.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: AppTypography.bodyFamily,
                      fontSize: 13.5,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? const Color(0xFFDC2626) : Colors.grey,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  /// Banner interactivo para pagos Nequi y Daviplata con botón de copiado
  Widget _buildDirectTransferBanner(String platformName, String accountNumber, Color brandColor, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: brandColor.withAlpha(isDark ? 30 : 15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: brandColor.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Número $platformName:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: isDark ? Colors.white : Colors.black87),
              ),
              GestureDetector(
                onTap: () => _copyToClipboard(accountNumber, platformName),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: brandColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy_rounded, size: 13, color: Colors.white),
                      SizedBox(width: 4),
                      Text('Copiar', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            accountNumber,
            style: TextStyle(
              fontFamily: AppTypography.displayFamily,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: brandColor,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Titular: La Diabla Comida Mexicana • Envía el soporte a nuestro WhatsApp para despacho prioritario.',
            style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  /// Widget de selección de billete y cálculo de cambio para Efectivo
  Widget _buildCashOptionsWidget(double total, bool isDark) {
    final cashAmount = _isCustomCashBill
        ? (double.tryParse(_customCashCtrl.text.replaceAll('.', '').replaceAll(',', '').trim()) ?? total)
        : (_selectedCashBill ?? total);

    final change = (cashAmount - total) > 0 ? (cashAmount - total) : 0.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C1E14) : const Color(0xFFFFF8E7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFB74D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '¿Con cuánto billete vas a pagar? 💵',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildCashChip(label: 'Monto exacto', isSelected: _selectedCashBill == null && !_isCustomCashBill, onTap: () {
                  setState(() {
                    _selectedCashBill = null;
                    _isCustomCashBill = false;
                  });
                }),
                const SizedBox(width: 6),
                _buildCashChip(label: '\$50.000', isSelected: _selectedCashBill == 50000 && !_isCustomCashBill, onTap: () {
                  setState(() {
                    _selectedCashBill = 50000;
                    _isCustomCashBill = false;
                  });
                }),
                const SizedBox(width: 6),
                _buildCashChip(label: '\$100.000', isSelected: _selectedCashBill == 100000 && !_isCustomCashBill, onTap: () {
                  setState(() {
                    _selectedCashBill = 100000;
                    _isCustomCashBill = false;
                  });
                }),
                const SizedBox(width: 6),
                _buildCashChip(label: 'Otro billete', isSelected: _isCustomCashBill, onTap: () {
                  setState(() {
                    _isCustomCashBill = true;
                    _selectedCashBill = null;
                  });
                }),
              ],
            ),
          ),
          if (_isCustomCashBill) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _customCashCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: 'Ej: 70000',
                isDense: true,
                filled: true,
                fillColor: isDark ? AppColors.surfaceDark : Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF16A34A)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  change > 0
                      ? 'El repartidor llevará ${PriceFormatter.formatSmart(change)} de cambio.'
                      : 'Pagas con el monto exacto. No se requiere cambio.',
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF16A34A), fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCashChip({required String label, required bool isSelected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF16A34A) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? const Color(0xFF16A34A) : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  void _showPaymentVerifyingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E1712) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            content: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 50,
                    height: 50,
                    child: CircularProgressIndicator(
                      color: Color(0xFFDC2626),
                      strokeWidth: 3.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Verificando Pago en Vivo 🔒',
                    style: TextStyle(
                      fontFamily: AppTypography.displayFamily,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Estamos validando con la entidad bancaria la acreditación de tu dinero para despachar tu pedido a la cocina...',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDark ? AppColors.textMutedDark : Colors.grey.shade700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<String?> _showRequirePhoneDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1712) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.phone_android_rounded, color: Color(0xFFDC2626)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Número de Celular 📱',
                style: TextStyle(fontFamily: AppTypography.displayFamily, fontSize: 20),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ingresa tu número de WhatsApp o celular para que el repartidor te contacte al momento de la entrega:',
              style: TextStyle(fontSize: 12.5, color: isDark ? AppColors.textMutedDark : Colors.grey.shade700),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.phone,
              autofocus: true,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              decoration: InputDecoration(
                prefixText: '+57 ',
                prefixStyle: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                hintText: '317 116 6497',
                filled: true,
                fillColor: isDark ? const Color(0xFF140D09) : const Color(0xFFF9F6F0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFDC2626)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              minimumSize: const Size(120, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              final phone = ctrl.text.trim();
              if (phone.length >= 7) {
                Navigator.of(ctx, rootNavigator: true).pop(phone);
              }
            },
            child: const Text('Guardar y Continuar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ─── Widget de Cupones de Fidelidad ──────────────────────────────────────────
/// Muestra los cupones de fidelidad de La Diabla SOLO cuando el cliente
/// ha completado el número mínimo de órdenes efectivas requeridas.
///
/// • DIABLA5   → 5% descuento  → visible tras 5 órdenes  → aplica en la 6ª
/// • DIABLA10  → 10% descuento → visible tras 10 órdenes → aplica en la 11ª
class _LoyaltyCouponsSection extends ConsumerWidget {
  const _LoyaltyCouponsSection({
    required this.isDark,
    required this.userId,
    required this.subtotal,
    required this.couponCtrl,
  });

  final bool isDark;
  final String userId;
  final double subtotal;
  final TextEditingController couponCtrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (userId.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<int>(
      future: _countEffectiveOrders(userId),
      builder: (context, snapshot) {
        final orderCount = snapshot.data ?? 0;

        final bool show5Percent = orderCount >= 5;
        final bool show10Percent = orderCount >= 10;

        if (!show5Percent && !show10Percent) {
          // El cliente todavía no tiene suficientes órdenes — no mostramos nada
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Text(
              '🎁 Tus cupones de fidelidad:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.textMutedDark : Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (show5Percent)
                  _buildLoyaltyChip(
                    ref: ref,
                    code: 'DIABLA5',
                    label: '🌶️ 5% Descuento Fiel',
                    sublabel: '$orderCount pedidos completados',
                    color: const Color(0xFF16A34A),
                  ),
                if (show10Percent)
                  _buildLoyaltyChip(
                    ref: ref,
                    code: 'DIABLA10',
                    label: '🔥 10% Cliente VIP',
                    sublabel: '$orderCount pedidos completados',
                    color: const Color(0xFFDC2626),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildLoyaltyChip({
    required WidgetRef ref,
    required String code,
    required String label,
    required String sublabel,
    required Color color,
  }) {
    return GestureDetector(
      onTap: () {
        couponCtrl.text = code;
        ref.read(couponProvider.notifier).validateCoupon(
              code: code,
              userId: userId,
              subtotal: subtotal,
            );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withAlpha(isDark ? 35 : 18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(90)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_offer_rounded, color: color, size: 14),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  sublabel,
                  style: TextStyle(
                    fontSize: 10,
                    color: color.withAlpha(180),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Cuenta las órdenes efectivas (delivered) del usuario desde Firestore.
  Future<int> _countEffectiveOrders(String userId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('orders')
          .where('userId', isEqualTo: userId)
          .where('status', isEqualTo: 'delivered')
          .get()
          .timeout(const Duration(seconds: 2));
      return snapshot.docs.length;
    } catch (_) {
      return 0;
    }
  }
}

