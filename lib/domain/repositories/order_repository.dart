// lib/domain/repositories/order_repository.dart
import '../entities/order_entity.dart';
import '../entities/order_status.dart';

/// Interfaz del repositorio de pedidos.
abstract interface class OrderRepository {
  /// Crea un nuevo pedido. Los precios se validan en Cloud Functions.
  Future<OrderEntity> createOrder(OrderEntity order);

  /// Obtiene todos los pedidos del usuario.
  Future<List<OrderEntity>> getOrders(String userId);

  /// Obtiene un pedido específico por ID.
  Future<OrderEntity?> getOrderById(String orderId);

  /// Stream de un pedido para seguimiento en tiempo real.
  Stream<OrderEntity?> watchOrder(String orderId);

  /// Stream en tiempo real de todos los pedidos del usuario (activos, entregados y cancelados).
  Stream<List<OrderEntity>> watchActiveOrders(String userId);

  /// Cancela un pedido (solo si está en estado 'pending').
  Future<void> cancelOrder(String orderId);

  /// Actualiza el estado de un pedido (solo para admin/kitchen/driver).
  Future<void> updateOrderStatus(String orderId, OrderStatus status);
}
