// lib/features/checkout/providers/coupon_provider.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── Entidad Cupon ────────────────────────────────────────────────────────────
class CouponEntity {
  const CouponEntity({
    required this.code,
    required this.discount,
    required this.type,
    required this.minOrder,
    this.description = '',
  });

  final String code;
  final double discount; // porcentaje (0-100) o valor fijo en COP
  final CouponType type;
  final double minOrder;
  final String description;

  /// Calcula el descuento aplicable sobre el subtotal dado.
  double calculateDiscount(double subtotal) {
    if (subtotal < minOrder) return 0;
    if (type == CouponType.percent) {
      return (subtotal * discount / 100).ceilToDouble();
    }
    return discount.clamp(0, subtotal);
  }
}

enum CouponType { percent, fixed }

// ─── Estado del cupon ────────────────────────────────────────────────────────
class CouponState {
  const CouponState({
    this.coupon,
    this.isLoading = false,
    this.errorMessage,
  });

  final CouponEntity? coupon;
  final bool isLoading;
  final String? errorMessage;

  bool get hasDiscount => coupon != null;

  CouponState copyWith({
    CouponEntity? coupon,
    bool? isLoading,
    String? errorMessage,
    bool clearCoupon = false,
    bool clearError = false,
  }) =>
      CouponState(
        coupon: clearCoupon ? null : (coupon ?? this.coupon),
        isLoading: isLoading ?? this.isLoading,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

// ─── Catálogo de Cupones Oficiales de La Diabla ──────────────────────────────
/// Solo 2 cupones de fidelidad automatizados:
/// - DIABLA5:  5%  → se desbloquea tras 5  pedidos entregados (visible en el 6º)
/// - DIABLA10: 10% → se desbloquea tras 10 pedidos entregados (visible en el 11º)
///
/// El cupón de envío gratis para cuentas nuevas se aplica automáticamente
/// en el carrito y ya no requiere código manual.
final Map<String, CouponEntity> _defaultCoupons = {
  'DIABLA5': const CouponEntity(
    code: 'DIABLA5',
    discount: 5,
    type: CouponType.percent,
    minOrder: 15000,
    description: '5% de descuento para clientes fieles 🌶️',
  ),
  'DIABLA10': const CouponEntity(
    code: 'DIABLA10',
    discount: 10,
    type: CouponType.percent,
    minOrder: 15000,
    description: '10% de descuento VIP 🔥',
  ),
};

// ─── Notifier ────────────────────────────────────────────────────────────────
class CouponNotifier extends StateNotifier<CouponState> {
  CouponNotifier() : super(const CouponState());

  final _db = FirebaseFirestore.instance;

  /// Valida el cupón contra catálogo local y Firestore, aplicando el descuento si es válido.
  Future<void> validateCoupon({
    required String code,
    required String userId,
    required double subtotal,
  }) async {
    final upperCode = code.trim().toUpperCase();
    if (upperCode.isEmpty) return;

    state = state.copyWith(isLoading: true, clearError: true);

    // 1. Verificar primero en catálogo oficial predeterminado (garantía instantánea)
    if (_defaultCoupons.containsKey(upperCode)) {
      final defaultCoupon = _defaultCoupons[upperCode]!;
      if (subtotal < defaultCoupon.minOrder) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Requiere pedido mínimo de \$${defaultCoupon.minOrder.toInt()} COP.',
        );
        return;
      }

      // Auto-sembrar el cupón en Firestore en segundo plano para que el admin lo vea
      _seedCouponToFirestore(defaultCoupon);

      state = state.copyWith(coupon: defaultCoupon, isLoading: false, clearError: true);
      return;
    }

    // 2. Si no es de los fijos, consultar Firestore (cupones personalizados creados por el admin)
    try {
      final doc = await _db.collection('coupons').doc(upperCode).get();

      if (!doc.exists) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Cupón "$upperCode" no es válido.',
        );
        return;
      }

      final data = doc.data()!;

      // Verificar que esté activo
      if (data['active'] != true) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Este cupón ya no está disponible.',
        );
        return;
      }

      // Verificar expiración
      final expiresAt = data['expiresAt'];
      if (expiresAt != null) {
        final expDate = (expiresAt as Timestamp).toDate();
        if (expDate.isBefore(DateTime.now())) {
          state = state.copyWith(
            isLoading: false,
            errorMessage: 'Este cupón expiró el ${expDate.day}/${expDate.month}/${expDate.year}.',
          );
          return;
        }
      }

      // Construir entidad
      final type = data['type'] == 'percent' ? CouponType.percent : CouponType.fixed;
      final discount = (data['discount'] as num).toDouble();
      final minOrder = (data['minOrder'] as num? ?? 0).toDouble();

      // Verificar orden mínima
      if (subtotal < minOrder) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Requiere un pedido mínimo de \$${minOrder.toInt()} COP.',
        );
        return;
      }

      final coupon = CouponEntity(
        code: upperCode,
        discount: discount,
        type: type,
        minOrder: minOrder,
        description: data['description'] as String? ?? '',
      );

      state = state.copyWith(coupon: coupon, isLoading: false, clearError: true);
    } catch (e) {
      // Fallback amigable
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Cupón "$upperCode" no encontrado.',
      );
    }
  }

  void _seedCouponToFirestore(CouponEntity coupon) {
    try {
      _db.collection('coupons').doc(coupon.code).set({
        'code': coupon.code,
        'discount': coupon.discount,
        'type': coupon.type == CouponType.percent ? 'percent' : 'fixed',
        'minOrder': coupon.minOrder,
        'description': coupon.description,
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Registra el uso del cupón en Firestore al confirmar el pedido.
  Future<void> registerCouponUsage({
    required String code,
    required String userId,
    required String orderId,
  }) async {
    if (code.isEmpty || userId.isEmpty) return;
    try {
      await _db
          .collection('coupons')
          .doc(code.toUpperCase())
          .collection('usages')
          .doc(userId)
          .set({
        'userId': userId,
        'orderId': orderId,
        'usedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// Limpia el cupón aplicado.
  void clearCoupon() {
    state = state.copyWith(clearCoupon: true, clearError: true);
  }
}

// ─── Provider ────────────────────────────────────────────────────────────────
final couponProvider = StateNotifierProvider<CouponNotifier, CouponState>(
  (ref) => CouponNotifier(),
);
