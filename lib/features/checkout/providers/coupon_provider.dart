// lib/features/checkout/providers/coupon_provider.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Tipo de Cupón ────────────────────────────────────────────────────────────
enum CouponType { percent, fixed, freeDelivery }

// ─── Entidad Cupón ────────────────────────────────────────────────────────────
class CouponEntity {
  const CouponEntity({
    required this.code,
    required this.discount,
    required this.type,
    required this.minOrder,
    this.description = '',
    this.singleUse = false,
  });

  final String code;
  final double discount; // porcentaje (0-100) o valor fijo en COP
  final CouponType type;
  final double minOrder;
  final String description;
  final bool singleUse;

  /// Calcula el descuento aplicable sobre el subtotal dado (y domicilio si es freeDelivery).
  double calculateDiscount(double subtotal, {double deliveryFee = 0.0}) {
    if (subtotal < minOrder) return 0.0;
    if (type == CouponType.percent) {
      return (subtotal * discount / 100).ceilToDouble();
    } else if (type == CouponType.freeDelivery) {
      return deliveryFee > 0 ? deliveryFee : (discount > 0 ? discount : 4500.0);
    }
    return discount.clamp(0.0, subtotal);
  }
}

// ─── Estado del cupón ────────────────────────────────────────────────────────
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
    minOrder: 0,
    description: '10% de descuento en tu orden completa 🔥',
  ),
  'ENVIOGRATIS': const CouponEntity(
    code: 'ENVIOGRATIS',
    discount: 4500,
    type: CouponType.freeDelivery,
    minOrder: 25000,
    description: 'Domicilio 100% GRATIS en Bucaramanga 🛵',
    singleUse: true,
  ),
  'TACOLOVER': const CouponEntity(
    code: 'TACOLOVER',
    discount: 5000,
    type: CouponType.fixed,
    minOrder: 30000,
    description: '\$5.000 COP de descuento en Combos y Tacos 🌮',
    singleUse: true,
  ),
  'DIABLAFREE': const CouponEntity(
    code: 'DIABLAFREE',
    discount: 4500,
    type: CouponType.freeDelivery,
    minOrder: 0,
    description: 'Envío gratis de bienvenida 🔥',
    singleUse: true,
  ),
  'DIABLITO10': const CouponEntity(
    code: 'DIABLITO10',
    discount: 10,
    type: CouponType.percent,
    minOrder: 0,
    description: '10% de descuento especial 🎉',
  ),
};

// ─── Notifier ────────────────────────────────────────────────────────────────
class CouponNotifier extends StateNotifier<CouponState> {
  CouponNotifier() : super(const CouponState());

  final _db = FirebaseFirestore.instance;

  /// Helper robusto para parsear montos de dinero o porcentajes.
  /// Maneja formatos con puntos de miles colombianos (ej: "25.000", "5.000", "29.000"),
  /// comas, porcentajes, números enteros y dobles.
  static double parseMoneyOrPercent(dynamic value, {bool isPercent = false}) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) {
      var s = value.trim();
      if (s.isEmpty) return 0.0;
      if (isPercent) {
        s = s.replaceAll('%', '').replaceAll(',', '.').trim();
        return double.tryParse(s) ?? 0.0;
      }
      if (s.contains('.') && s.contains(',')) {
        s = s.replaceAll('.', '').replaceAll(',', '.');
      } else if (s.contains('.')) {
        final parts = s.split('.');
        if (parts.length > 1 && parts.last.length == 3) {
          s = s.replaceAll('.', '');
        }
      } else if (s.contains(',')) {
        final parts = s.split(',');
        if (parts.length > 1 && parts.last.length == 3) {
          s = s.replaceAll(',', '');
        } else {
          s = s.replaceAll(',', '.');
        }
      }
      return double.tryParse(s) ?? 0.0;
    }
    return 0.0;
  }

  static DateTime? parseDate(dynamic val) {
    if (val == null) return null;
    if (val is Timestamp) return val.toDate();
    if (val is DateTime) return val;
    if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
    if (val is String) return DateTime.tryParse(val);
    return null;
  }

  /// Valida el cupón contra catálogo local y Firestore, aplicando el descuento si es válido.
  Future<bool> validateCoupon({
    required String code,
    required String userId,
    required double subtotal,
    double deliveryFee = 4500.0,
  }) async {
    final upperCode = code.trim().toUpperCase();
    if (upperCode.isEmpty) return false;

    state = state.copyWith(isLoading: true, clearError: true);

    // 1. Si es cupón de un solo uso, verificar si ya fue canjeado en esta cuenta localmente
    final prefs = await SharedPreferences.getInstance();
    final localUsed = prefs.getBool('coupon_used_${upperCode}_$userId') ?? false;
    if (localUsed) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Este cupón de un solo uso ya fue canjeado en tu cuenta.',
      );
      return false;
    }

    // 2. Verificar catálogo local oficial
    if (_defaultCoupons.containsKey(upperCode)) {
      final defaultCoupon = _defaultCoupons[upperCode]!;

      // Si es de un solo uso, consultar también en Firestore subcolección 'usages'
      if (defaultCoupon.singleUse && userId.isNotEmpty && userId != 'guest') {
        try {
          final usageDoc = await _db
              .collection('coupons')
              .doc(upperCode)
              .collection('usages')
              .doc(userId)
              .get();
          if (usageDoc.exists) {
            state = state.copyWith(
              isLoading: false,
              errorMessage: 'Este cupón de un solo uso ya fue utilizado en tu cuenta.',
            );
            return false;
          }
        } catch (_) {}
      }

      if (subtotal < defaultCoupon.minOrder) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Requiere pedido mínimo de \$${defaultCoupon.minOrder.toInt()} COP.',
        );
        return false;
      }

      // Auto-sembrar el cupón en Firestore para que el admin lo vea
      _seedCouponToFirestore(defaultCoupon);

      state = state.copyWith(coupon: defaultCoupon, isLoading: false, clearError: true);
      return true;
    }

    // 3. Consultar Firestore para cupones dinámicos creados por el admin
    try {
      final doc = await _db.collection('coupons').doc(upperCode).get();

      if (!doc.exists) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Cupón "$upperCode" no es válido o no existe.',
        );
        return false;
      }

      final data = doc.data()!;

      // Verificar que esté activo
      if (data['active'] != true) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Este cupón ya no está disponible.',
        );
        return false;
      }

      // Verificar expiración (1 mes / 30 días de caducidad automática)
      final expiresAt = parseDate(data['expiresAt']);
      final createdAt = parseDate(data['createdAt']);
      final now = DateTime.now();

      if (expiresAt != null) {
        if (now.isAfter(expiresAt)) {
          state = state.copyWith(
            isLoading: false,
            errorMessage: 'Este cupón expiró el ${expiresAt.day}/${expiresAt.month}/${expiresAt.year}.',
          );
          return false;
        }
      } else if (createdAt != null) {
        final autoExpire = createdAt.add(const Duration(days: 30));
        if (now.isAfter(autoExpire)) {
          state = state.copyWith(
            isLoading: false,
            errorMessage: 'Este cupón caducó (validez de 30 días tras su creación).',
          );
          return false;
        }
      }

      // Verificar uso único por cliente
      final isSingleUse = data['singleUse'] == true ||
          data['isSingleUse'] == true ||
          data['maxUsesPerUser'] == 1 ||
          data['usageLimit'] == 1;

      if (isSingleUse && userId.isNotEmpty && userId != 'guest') {
        final usageDoc = await _db
            .collection('coupons')
            .doc(upperCode)
            .collection('usages')
            .doc(userId)
            .get();
        if (usageDoc.exists) {
          state = state.copyWith(
            isLoading: false,
            errorMessage: 'Este cupón es de un solo uso y ya fue utilizado en tu cuenta.',
          );
          return false;
        }
      }

      // Parsear tipo, discount y minOrder con soporte tolerante a strings con puntos decimales/miles
      final typeStr = (data['type'] as String? ?? 'fixed').toLowerCase();
      final type = typeStr == 'percent'
          ? CouponType.percent
          : (typeStr == 'delivery' || typeStr == 'freedelivery' || upperCode.contains('ENVIO')
              ? CouponType.freeDelivery
              : CouponType.fixed);

      final discount = parseMoneyOrPercent(data['discount'], isPercent: type == CouponType.percent);
      final minOrder = parseMoneyOrPercent(data['minOrder']);

      if (subtotal < minOrder) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Requiere un pedido mínimo de \$${minOrder.toInt()} COP.',
        );
        return false;
      }

      final coupon = CouponEntity(
        code: upperCode,
        discount: discount > 0 ? discount : (type == CouponType.freeDelivery ? deliveryFee : 0),
        type: type,
        minOrder: minOrder,
        description: data['description'] as String? ?? '',
        singleUse: isSingleUse,
      );

      state = state.copyWith(coupon: coupon, isLoading: false, clearError: true);
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Cupón "$upperCode" no válido.',
      );
      return false;
    }
  }

  void _seedCouponToFirestore(CouponEntity coupon) {
    try {
      _db.collection('coupons').doc(coupon.code).set({
        'code': coupon.code,
        'discount': coupon.discount,
        'type': coupon.type == CouponType.percent
            ? 'percent'
            : (coupon.type == CouponType.freeDelivery ? 'freeDelivery' : 'fixed'),
        'minOrder': coupon.minOrder,
        'description': coupon.description,
        'active': true,
        'singleUse': coupon.singleUse,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
      }, SetOptions(merge: true)).ignore();
    } catch (_) {}
  }

  /// Registra el uso del cupón en Firestore y SharedPreferences al confirmar el pedido.
  Future<void> registerCouponUsage({
    required String code,
    required String userId,
    required String orderId,
  }) async {
    if (code.isEmpty) return;
    final upperCode = code.trim().toUpperCase();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('coupon_used_${upperCode}_$userId', true);
      if (userId.isNotEmpty && userId != 'guest') {
        await _db
            .collection('coupons')
            .doc(upperCode)
            .collection('usages')
            .doc(userId)
            .set({
          'userId': userId,
          'orderId': orderId,
          'usedAt': FieldValue.serverTimestamp(),
        });
      }
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
