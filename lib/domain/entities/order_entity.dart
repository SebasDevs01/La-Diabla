// lib/domain/entities/order_entity.dart
import 'package:equatable/equatable.dart';
import 'address_entity.dart';
import 'cart_item_entity.dart';
import 'order_status.dart';

/// Método de pago del pedido.
enum PaymentMethod {
  card,
  nequi,
  daviplata,
  cash,
  transfer,
  pos;

  String get displayName {
    return switch (this) {
      PaymentMethod.card => 'Tarjeta Débito / Crédito',
      PaymentMethod.nequi => 'Nequi',
      PaymentMethod.daviplata => 'Daviplata',
      PaymentMethod.cash => 'Efectivo contra entrega',
      PaymentMethod.transfer => 'Transferencia bancaria / PSE',
      PaymentMethod.pos => 'Datáfono (Tarjeta al recibir)',
    };
  }

  static PaymentMethod fromString(String value) {
    return switch (value) {
      'card' => PaymentMethod.card,
      'nequi' => PaymentMethod.nequi,
      'daviplata' => PaymentMethod.daviplata,
      'cash' => PaymentMethod.cash,
      'transfer' => PaymentMethod.transfer,
      'pos' => PaymentMethod.pos,
      _ => PaymentMethod.cash,
    };
  }
}

/// Estado del pago.
enum PaymentStatus {
  pending,
  paid,
  refunded,
  failed;

  static PaymentStatus fromString(String value) {
    return PaymentStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => PaymentStatus.pending,
    );
  }
}

/// Tipo de pedido (solo DELIVERY en la fase inicial).
enum OrderType {
  delivery,
  // pickup, // Preparado para el futuro
}

/// Entidad de pedido del dominio.
class OrderEntity extends Equatable {
  const OrderEntity({
    required this.id,
    required this.userId,
    required this.items,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    required this.status,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.orderType,
    this.address,
    this.addressId,
    this.latitude,
    this.longitude,
    this.placeId,
    this.discount = 0.0,
    this.cashPaymentAmount,
    this.cashChangeAmount,
    this.transactionReference,
    this.notes,
    this.driverId,
    this.driverLatitude,
    this.driverLongitude,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String userId;
  final List<CartItemEntity> items;
  final double subtotal;
  final double deliveryFee;
  final double discount;
  final double total;
  final OrderStatus status;
  final PaymentMethod paymentMethod;
  final PaymentStatus paymentStatus;
  final OrderType orderType;
  final AddressEntity? address;
  final String? addressId;
  final double? latitude;
  final double? longitude;
  final String? placeId;
  final double? cashPaymentAmount;
  final double? cashChangeAmount;
  final String? transactionReference;
  final String? notes;
  final String? driverId;
  final double? driverLatitude;
  final double? driverLongitude;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  bool get hasDriver => driverId != null;

  OrderEntity copyWith({
    String? id,
    String? userId,
    List<CartItemEntity>? items,
    double? subtotal,
    double? deliveryFee,
    double? discount,
    double? total,
    OrderStatus? status,
    PaymentMethod? paymentMethod,
    PaymentStatus? paymentStatus,
    OrderType? orderType,
    AddressEntity? address,
    String? addressId,
    double? latitude,
    double? longitude,
    String? placeId,
    double? cashPaymentAmount,
    double? cashChangeAmount,
    String? transactionReference,
    String? notes,
    String? driverId,
    double? driverLatitude,
    double? driverLongitude,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return OrderEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      items: items ?? this.items,
      subtotal: subtotal ?? this.subtotal,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      discount: discount ?? this.discount,
      total: total ?? this.total,
      status: status ?? this.status,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      orderType: orderType ?? this.orderType,
      address: address ?? this.address,
      addressId: addressId ?? this.addressId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      placeId: placeId ?? this.placeId,
      cashPaymentAmount: cashPaymentAmount ?? this.cashPaymentAmount,
      cashChangeAmount: cashChangeAmount ?? this.cashChangeAmount,
      transactionReference: transactionReference ?? this.transactionReference,
      notes: notes ?? this.notes,
      driverId: driverId ?? this.driverId,
      driverLatitude: driverLatitude ?? this.driverLatitude,
      driverLongitude: driverLongitude ?? this.driverLongitude,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
    id, userId, items, subtotal, deliveryFee, discount, total,
    status, paymentMethod, paymentStatus, orderType,
    cashPaymentAmount, cashChangeAmount, transactionReference,
    driverId, driverLatitude, driverLongitude,
  ];
}
