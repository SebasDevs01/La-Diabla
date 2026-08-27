// lib/features/orders/providers/orders_provider.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/repositories/order_repository_impl.dart';
import '../../../data/models/order_model.dart';
import '../../../domain/entities/order_entity.dart';
import '../../../domain/entities/order_status.dart';
import '../../../domain/repositories/order_repository.dart';
import '../../auth/providers/auth_notifier.dart';

// Repositorio Provider
final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  return OrderRepositoryImpl();
});

// Stream de Pedidos del Usuario (cliente)
final userOrdersStreamProvider = StreamProvider<List<OrderEntity>>((ref) async* {
  final authState = ref.watch(authNotifierProvider);
  final userId = authState.user?.id ?? '';
  final repo = ref.watch(orderRepositoryProvider);
  if (userId.isEmpty) {
    yield [];
    return;
  }
  yield* repo.watchActiveOrders(userId);
});

// Stream de Pedidos PENDIENTES para el Repartidor (TODOS los clientes)
// IMPORTANTE: Solo se muestran pedidos cuyo pago fue confirmado (paid)
// o que no requieren verificación previa (efectivo / datáfono).
final allPendingOrdersStreamProvider = StreamProvider<List<OrderEntity>>((ref) async* {
  try {
    yield* FirebaseFirestore.instance
        .collection('orders')
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((doc) => OrderModel.fromFirestore(doc)).toList();
      list.sort((a, b) {
        final dateA = a.createdAt ?? DateTime.now();
        final dateB = b.createdAt ?? DateTime.now();
        return dateB.compareTo(dateA);
      });

      return list.where((o) {
        // Estado activo (visible al repartidor)
        final activeStatus = o.status == OrderStatus.pending ||
            o.status == OrderStatus.confirmed ||
            o.status == OrderStatus.preparing ||
            o.status == OrderStatus.ready ||
            o.status == OrderStatus.onTheWay;

        if (!activeStatus) return false;

        // Métodos que NO requieren verificación previa de pago online
        final noPreVerification =
            o.paymentMethod == PaymentMethod.cash ||
            o.paymentMethod == PaymentMethod.pos;

        // Para pagos digitales: SOLO mostrar si el pago fue aprobado
        final digitalPaid = !noPreVerification &&
            o.paymentStatus == PaymentStatus.paid;

        return noPreVerification || digitalPaid;
      }).toList();
    });
  } catch (_) {
    yield [];
  }
});

// Stream de Pedidos ENTREGADOS por el Repartidor (100% REALES desde Firestore)
final driverDeliveredOrdersStreamProvider = StreamProvider<List<OrderEntity>>((ref) async* {
  final authState = ref.watch(authNotifierProvider);
  final currentDriverId = authState.user?.id ?? '';

  try {
    yield* FirebaseFirestore.instance
        .collection('orders')
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((doc) => OrderModel.fromFirestore(doc)).toList();
      list.sort((a, b) {
        final dateA = a.updatedAt ?? a.createdAt ?? DateTime.now();
        final dateB = b.updatedAt ?? b.createdAt ?? DateTime.now();
        return dateB.compareTo(dateA);
      });

      return list.where((o) {
        final isDelivered = o.status == OrderStatus.delivered;
        if (!isDelivered) return false;
        if (currentDriverId.isNotEmpty && currentDriverId != 'driver_01') {
          return o.driverId == currentDriverId || o.driverId == null || o.driverId == 'driver_01';
        }
        return true;
      }).toList();
    });
  } catch (_) {
    yield [];
  }
});

// Stream de un Pedido en Tiempo Real
final singleOrderStreamProvider =
    StreamProvider.family<OrderEntity?, String>((ref, orderId) async* {
  final repo = ref.watch(orderRepositoryProvider);
  yield* repo.watchOrder(orderId);
});

// Notifier para Crear Pedidos
class CreateOrderState {
  const CreateOrderState({
    this.isLoading = false,
    this.errorMessage,
    this.createdOrder,
  });
  final bool isLoading;
  final String? errorMessage;
  final OrderEntity? createdOrder;

  CreateOrderState copyWith({
    bool? isLoading,
    String? errorMessage,
    OrderEntity? createdOrder,
  }) {
    return CreateOrderState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      createdOrder: createdOrder ?? this.createdOrder,
    );
  }
}

class CreateOrderNotifier extends StateNotifier<CreateOrderState> {
  CreateOrderNotifier(this._repo, this._ref) : super(const CreateOrderState());
  final OrderRepository _repo;
  final Ref _ref;

  Future<OrderEntity?> placeOrder(OrderEntity order) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final user = _ref.read(authNotifierProvider).user;
      final finalOrder = order.copyWith(userId: user?.id ?? 'guest');
      final result = await _repo.createOrder(finalOrder);
      state = state.copyWith(isLoading: false, createdOrder: result);
      return result;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Error al procesar el pedido: ',
      );
      return null;
    }
  }
}

final createOrderNotifierProvider =
    StateNotifierProvider<CreateOrderNotifier, CreateOrderState>((ref) {
  return CreateOrderNotifier(ref.watch(orderRepositoryProvider), ref);
});
