// lib/features/cart/providers/cart_notifier.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/repositories/cart_repository_impl.dart';
import '../../../domain/entities/cart_item_entity.dart';
import '../../../domain/entities/extra_entity.dart';
import '../../../domain/entities/product_entity.dart';
import '../../../domain/repositories/cart_repository.dart';
import '../../../core/services/maps_service.dart';

final cartRepositoryProvider = Provider<CartRepository>((ref) {
  return CartRepositoryImpl();
});

class CartState {
  const CartState({
    this.items = const [],
    this.deliveryFee = 4500.0,
    this.discount = 0.0,
    this.appliedCoupon,
    this.appliedReferralCode,
    this.distanceKm,
    this.deliveryAddressFormatted,
  });

  final List<CartItemEntity> items;
  final double deliveryFee;
  final double discount;
  final String? appliedCoupon;
  final String? appliedReferralCode;
  final double? distanceKm;
  final String? deliveryAddressFormatted;

  double get subtotal => items.fold(0.0, (sum, item) => sum + item.subtotal);

  double get effectiveDeliveryFee {
    if (items.isEmpty) return 0.0;
    // Cupón de envío gratis, código de referido o compra mayor a $40.000 COP
    if (appliedCoupon == 'DIABLAFREE' || appliedReferralCode != null || subtotal >= 40000.0) {
      return 0.0;
    }
    return deliveryFee;
  }

  bool get isFreeDelivery => effectiveDeliveryFee == 0.0 && items.isNotEmpty;

  double get total {
    if (items.isEmpty) return 0.0;
    final result = subtotal + effectiveDeliveryFee - discount;
    return result < 0 ? 0.0 : result;
  }

  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;

  CartState copyWith({
    List<CartItemEntity>? items,
    double? deliveryFee,
    double? discount,
    String? appliedCoupon,
    String? appliedReferralCode,
    double? distanceKm,
    String? deliveryAddressFormatted,
    bool clearCoupon = false,
    bool clearReferral = false,
  }) {
    return CartState(
      items: items ?? this.items,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      discount: discount ?? this.discount,
      appliedCoupon: clearCoupon ? null : (appliedCoupon ?? this.appliedCoupon),
      appliedReferralCode: clearReferral ? null : (appliedReferralCode ?? this.appliedReferralCode),
      distanceKm: distanceKm ?? this.distanceKm,
      deliveryAddressFormatted: deliveryAddressFormatted ?? this.deliveryAddressFormatted,
    );
  }
}

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier(this._ref) : super(const CartState()) {
    _init();
  }

  final Ref _ref;
  StreamSubscription<List<CartItemEntity>>? _cartSubscription;

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final hasFreeDeliveryCoupon = prefs.getBool('diabla_free_coupon_redeemed') ?? false;

    if (hasFreeDeliveryCoupon) {
      state = state.copyWith(appliedCoupon: 'DIABLAFREE');
    }

    final repo = _ref.read(cartRepositoryProvider);
    _cartSubscription = repo.watchItems().listen((items) {
      double discount = state.discount;
      final subtotal = items.fold(0.0, (sum, item) => sum + item.subtotal);
      if (state.appliedCoupon == 'DIABLITO10') {
        discount = subtotal * 0.10;
      }
      state = state.copyWith(
        items: items,
        discount: discount,
      );
    });
  }

  @override
  void dispose() {
    _cartSubscription?.cancel();
    super.dispose();
  }

  /// Calcula y actualiza la tarifa de envío en base a los kilómetros de distancia.
  void setDeliveryDistance(double distanceKm, {String? addressFormatted}) {
    final calculatedFee = MapsService.calculateDeliveryFee(distanceKm);

    state = state.copyWith(
      distanceKm: distanceKm,
      deliveryFee: calculatedFee,
      deliveryAddressFormatted: addressFormatted,
    );
  }

  /// Aplica un cupón tradicional (DIABLAFREE, DIABLITO10) o código de referido.
  Future<bool> applyCoupon(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    final prefs = await SharedPreferences.getInstance();

    if (code == 'DIABLAFREE') {
      await prefs.setBool('diabla_free_coupon_redeemed', true);
      state = state.copyWith(appliedCoupon: 'DIABLAFREE', discount: 0.0);
      return true;
    } else if (code == 'DIABLITO10') {
      final disc = state.subtotal * 0.10;
      state = state.copyWith(appliedCoupon: 'DIABLITO10', discount: disc);
      return true;
    } else if (code.startsWith('DIABLA-') || code.startsWith('REF-') || code == 'AMIGODIABLE') {
      // Código de referido válido -> Envío gratis + $5.000 COP de descuento
      final disc = (state.discount + 5000.0).clamp(0.0, state.subtotal);
      state = state.copyWith(
        appliedReferralCode: code,
        discount: disc,
      );
      await prefs.setString('applied_referral_code', code);
      return true;
    }
    return false;
  }

  void removeCoupon() {
    state = state.copyWith(clearCoupon: true, clearReferral: true, discount: 0.0);
  }

  Future<void> addItem({
    required ProductEntity product,
    required int quantity,
    List<ExtraEntity> selectedExtras = const [],
    List<String> removedIngredients = const [],
    Map<String, String> selectedOptions = const {},
    String? notes,
  }) async {
    final repo = _ref.read(cartRepositoryProvider);
    await repo.addItem(
      product: product,
      quantity: quantity,
      selectedExtras: selectedExtras,
      removedIngredients: removedIngredients,
      selectedOptions: selectedOptions,
      notes: notes,
    );
  }

  Future<void> removeItem(String itemId) async {
    final repo = _ref.read(cartRepositoryProvider);
    await repo.removeItem(itemId);
  }

  Future<void> updateQuantity(String itemId, int quantity) async {
    final repo = _ref.read(cartRepositoryProvider);
    await repo.updateQuantity(itemId, quantity);
  }

  Future<void> clearCart() async {
    final repo = _ref.read(cartRepositoryProvider);
    await repo.clearCart();
  }

  /// Cancela el carrito limpiándolo localmente (sin guardar en Firestore).
  /// No se persiste en Firestore para evitar pedidos fantasma en cuentas nuevas.
  Future<void> cancelCartAsOrder() async {
    if (state.items.isEmpty) return;
    final repo = _ref.read(cartRepositoryProvider);
    await repo.clearCart();
  }
}

final cartNotifierProvider = StateNotifierProvider<CartNotifier, CartState>((ref) {
  return CartNotifier(ref);
});
