// lib/data/models/order_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/address_entity.dart';
import '../../domain/entities/cart_item_entity.dart';
import '../../domain/entities/order_entity.dart';
import '../../domain/entities/order_status.dart';
import '../../domain/entities/product_entity.dart';

class OrderModel {
  static Map<String, dynamic> toFirestore(OrderEntity order) {
    return {
      'id': order.id,
      'userId': order.userId,
      'items': order.items
          .map((item) => {
                'productId': item.product.id,
                'productName': item.product.name,
                'price': item.product.price,
                'imageUrl': item.product.imageUrl,
                'quantity': item.quantity,
                'selectedExtras': item.selectedExtras.map((e) => e.name).toList(),
                'notes': item.notes,
              })
          .toList(),
      'subtotal': order.subtotal,
      'deliveryFee': order.deliveryFee,
      'discount': order.discount,
      'total': order.total,
      'status': order.status.name,
      'paymentMethod': order.paymentMethod.name,
      'paymentStatus': order.paymentStatus.name,
      'cashPaymentAmount': order.cashPaymentAmount,
      'cashChangeAmount': order.cashChangeAmount,
      'transactionReference': order.transactionReference,
      'orderType': order.orderType.name,
      'formattedAddress': order.address?.formattedAddress ?? 'Dirección de entrega',
      'addressLabel': order.address?.label.name ?? 'home',
      'latitude': order.latitude ?? order.address?.latitude ?? 7.09859,
      'longitude': order.longitude ?? order.address?.longitude ?? -73.15183,
      'reference': order.address?.reference ?? order.notes,
      'notes': order.notes,
      'driverId': order.driverId,
      'driverLatitude': order.driverLatitude,
      'driverLongitude': order.driverLongitude,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static OrderEntity fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    final rawItems = data['items'] as List<dynamic>? ?? [];
    final items = rawItems.map((i) {
      final itemMap = i as Map<String, dynamic>;
      return CartItemEntity(
        id: itemMap['productId'] as String? ?? doc.id,
        product: ProductEntity(
          id: itemMap['productId'] as String? ?? '',
          name: itemMap['productName'] as String? ?? 'Producto',
          description: '',
          price: (itemMap['price'] as num? ?? 0).toDouble(),
          imageUrl: itemMap['imageUrl'] as String? ?? '',
          categoryId: '',
          spicyLevel: 1,
        ),
        quantity: itemMap['quantity'] as int? ?? 1,
        selectedExtras: const [],
        notes: itemMap['notes'] as String?,
      );
    }).toList();

    final statusStr = data['status'] as String? ?? 'pending';
    final paymentMethodStr = data['paymentMethod'] as String? ?? 'card';
    final paymentStatusStr = data['paymentStatus'] as String? ?? 'pending';

    final createdTs = data['createdAt'] as Timestamp?;
    final updatedTs = data['updatedAt'] as Timestamp?;

    final address = AddressEntity(
      id: doc.id,
      userId: data['userId'] as String? ?? '',
      label: AddressLabel.fromString(data['addressLabel'] as String? ?? 'home'),
      formattedAddress: data['formattedAddress'] as String? ?? 'Cl. 59 # 39W-24, Bucaramanga, Santander',
      latitude: (data['latitude'] as num? ?? 7.09859).toDouble(),
      longitude: (data['longitude'] as num? ?? -73.15183).toDouble(),
      reference: data['reference'] as String?,
    );

    return OrderEntity(
      id: doc.id,
      userId: data['userId'] as String? ?? '',
      items: items,
      subtotal: (data['subtotal'] as num? ?? 0).toDouble(),
      deliveryFee: (data['deliveryFee'] as num? ?? 0).toDouble(),
      discount: (data['discount'] as num? ?? 0).toDouble(),
      total: (data['total'] as num? ?? 0).toDouble(),
      status: OrderStatus.fromString(statusStr),
      paymentMethod: PaymentMethod.fromString(paymentMethodStr),
      paymentStatus: PaymentStatus.fromString(paymentStatusStr),
      cashPaymentAmount: (data['cashPaymentAmount'] as num?)?.toDouble(),
      cashChangeAmount: (data['cashChangeAmount'] as num?)?.toDouble(),
      transactionReference: data['transactionReference'] as String?,
      orderType: OrderType.delivery,
      address: address,
      latitude: address.latitude,
      longitude: address.longitude,
      notes: data['notes'] as String?,
      driverId: data['driverId'] as String?,
      driverLatitude: (data['driverLatitude'] as num?)?.toDouble(),
      driverLongitude: (data['driverLongitude'] as num?)?.toDouble(),
      createdAt: createdTs?.toDate() ?? DateTime.now(),
      updatedAt: updatedTs?.toDate() ?? DateTime.now(),
    );
  }
}

