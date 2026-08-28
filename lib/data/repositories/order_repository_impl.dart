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
          .get()
          .timeout(const Duration(seconds: 4));
      if (query.docs.isNotEmpty) {
        final list = query.docs.map((doc) {
          try {
            return OrderModel.fromFirestore(doc);
          } catch (_) {
            return null;
          }
        }).whereType<OrderEntity>().toList();

        list.sort((a, b) {
          final dateA = a.createdAt ?? DateTime.now();
          final dateB = b.createdAt ?? DateTime.now();
          return dateB.compareTo(dateA);
        });
        return list;
      }
    } catch (e) {
      _logger.w('Error fetching orders from Firestore: $e');
    }
    return _inMemoryOrders.where((o) => o.userId == userId || userId.isEmpty).toList();
  }

  @override
  Future<OrderEntity?> getOrderById(String orderId) async {
    try {
      final doc = await _ordersCol.doc(orderId).get().timeout(const Duration(seconds: 3));
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
          try {
            final fromDb = OrderModel.fromFirestore(doc);
            final idx = _inMemoryOrders.indexWhere((o) => o.id == orderId);
            if (idx != -1) {
              _inMemoryOrders[idx] = fromDb;
            } else {
              _inMemoryOrders.insert(0, fromDb);
            }
            return fromDb;
          } catch (_) {}
        }
        return _inMemoryOrders.where((o) => o.id == orderId).firstOrNull;
      }).handleError((_) {
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

    // 1. Emitir inmediatamente lo que esté en memoria para evitar estado offline/vacío
    final local = _inMemoryOrders.where((o) => o.userId == userId).toList();
    if (local.isNotEmpty) {
      yield local;
    }

    // 2. Escuchar Firestore con ordenamiento en memoria (sin requerir índices compuestos)
    try {
      yield* _ordersCol
          .where('userId', isEqualTo: userId)
          .snapshots()
          .map((snapshot) {
        final list = snapshot.docs.map((doc) {
          try {
            return OrderModel.fromFirestore(doc);
          } catch (e) {
            return null;
          }
        }).whereType<OrderEntity>().toList();

        list.sort((a, b) {
          final dateA = a.createdAt ?? DateTime.now();
          final dateB = b.createdAt ?? DateTime.now();
          return dateB.compareTo(dateA);
        });

        for (final o in list) {
          final idx = _inMemoryOrders.indexWhere((item) => item.id == o.id);
          if (idx != -1) {
            _inMemoryOrders[idx] = o;
          } else {
            _inMemoryOrders.add(o);
          }
        }

        return list;
      }).handleError((error) {
        _logger.w('watchActiveOrders stream error: $error');
        return _inMemoryOrders.where((o) => o.userId == userId).toList();
      });
    } catch (e) {
      _logger.w('watchActiveOrders error: $e');
      yield _inMemoryOrders.where((o) => o.userId == userId).toList();
    }
  }

  @override
  Future<void> cancelOrder(String orderId) async {
    try {
      await _ordersCol.doc(orderId).set({
        'status': OrderStatus.cancelled.name,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
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
      await _ordersCol.doc(orderId).set({
        'status': status.name,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
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

