// lib/data/repositories/order_repository_impl.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import '../../domain/entities/order_entity.dart';
import '../../domain/entities/order_status.dart';
import '../../domain/repositories/order_repository.dart';
import '../models/order_model.dart';

class OrderRepositoryImpl implements OrderRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Logger _logger = Logger();

  final List<OrderEntity> _inMemoryOrders = [];

  CollectionReference<Map<String, dynamic>> get _ordersCol =>
      _firestore.collection('orders');

  @override
  Future<OrderEntity> createOrder(OrderEntity order) async {
    final effectiveId = order.id.isEmpty ? 'ord_${DateTime.now().millisecondsSinceEpoch}' : order.id;
    final orderWithId = order.copyWith(
      id: effectiveId,
      createdAt: order.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    try {
      final data = OrderModel.toFirestore(orderWithId);
      // Guardar directamente en Firestore con el ID exacto de la orden
      await _ordersCol.doc(effectiveId).set(data);
      _inMemoryOrders.insert(0, orderWithId);
      return orderWithId;
    } catch (e) {
      _logger.w('Error saving order to Firestore, falling back to local memory: $e');
      _inMemoryOrders.insert(0, orderWithId);
      return orderWithId;
    }
  }

  @override
  Future<List<OrderEntity>> getOrders(String userId) async {
    try {
      final query = await _ordersCol
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .get();
      if (query.docs.isNotEmpty) {
        return query.docs.map((doc) => OrderModel.fromFirestore(doc)).toList();
      }
    } catch (e) {
      _logger.w('Error fetching orders from Firestore: $e');
    }
    return _inMemoryOrders.where((o) => o.userId == userId || userId.isEmpty).toList();
  }

  @override
  Future<OrderEntity?> getOrderById(String orderId) async {
    try {
      final doc = await _ordersCol.doc(orderId).get();
      if (doc.exists) {
        return OrderModel.fromFirestore(doc);
      }
    } catch (e) {
      _logger.w('Error getting order by id from Firestore: $e');
    }
    return _inMemoryOrders.where((o) => o.id == orderId).firstOrNull;
  }

  @override
  Stream<OrderEntity?> watchOrder(String orderId) async* {
    final local = _inMemoryOrders.where((o) => o.id == orderId).firstOrNull;
    if (local != null) {
      yield local;
    }
    try {
      yield* _ordersCol.doc(orderId).snapshots().map((doc) {
        if (doc.exists) {
          final fromDb = OrderModel.fromFirestore(doc);
          final idx = _inMemoryOrders.indexWhere((o) => o.id == orderId);
          if (idx != -1) {
            _inMemoryOrders[idx] = fromDb;
          } else {
            _inMemoryOrders.insert(0, fromDb);
          }
          return fromDb;
        }
        return _inMemoryOrders.where((o) => o.id == orderId).firstOrNull;
      });
    } catch (e) {
      _logger.w('watchOrder snapshot error: $e');
      yield _inMemoryOrders.where((o) => o.id == orderId).firstOrNull;
    }
  }

  @override
  Stream<List<OrderEntity>> watchActiveOrders(String userId) async* {
    if (userId.isEmpty) {
      yield const [];
      return;
    }
    try {
      yield* _ordersCol
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) {
        return snapshot.docs
            .map((doc) => OrderModel.fromFirestore(doc))
            .toList();
      });
    } catch (e) {
      _logger.w('watchActiveOrders error: $e');
      yield _inMemoryOrders.where((o) => o.userId == userId).toList();
    }
  }

  @override
  Future<void> cancelOrder(String orderId) async {
    try {
      await _ordersCol.doc(orderId).update({
        'status': OrderStatus.cancelled.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _logger.w('cancelOrder error: $e');
    }

    final idx = _inMemoryOrders.indexWhere((o) => o.id == orderId);
    if (idx != -1) {
      _inMemoryOrders[idx] = _inMemoryOrders[idx].copyWith(
        status: OrderStatus.cancelled,
        updatedAt: DateTime.now(),
      );
    }
  }

  @override
  Future<void> updateOrderStatus(String orderId, OrderStatus status) async {
    try {
      await _ordersCol.doc(orderId).update({
        'status': status.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _logger.w('updateOrderStatus error: $e');
    }

    final idx = _inMemoryOrders.indexWhere((o) => o.id == orderId);
    if (idx != -1) {
      _inMemoryOrders[idx] = _inMemoryOrders[idx].copyWith(
        status: status,
        updatedAt: DateTime.now(),
      );
    }
  }
}

