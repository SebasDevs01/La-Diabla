// lib/domain/entities/order_status.dart

/// Estados del ciclo de vida de un pedido.
enum OrderStatus {
  pending,
  confirmed,
  preparing,
  ready,
  assigned,
  onTheWay,
  delivered,
  cancelled;

  String get displayName {
    return switch (this) {
      OrderStatus.pending => 'Pedido recibido',
      OrderStatus.confirmed => 'Confirmado',
      OrderStatus.preparing => 'Preparando',
      OrderStatus.ready => 'Listo',
      OrderStatus.assigned => 'Repartidor asignado',
      OrderStatus.onTheWay => 'En camino',
      OrderStatus.delivered => 'Entregado',
      OrderStatus.cancelled => 'Cancelado',
    };
  }

  String get firestoreValue {
    return switch (this) {
      OrderStatus.pending => 'pending',
      OrderStatus.confirmed => 'confirmed',
      OrderStatus.preparing => 'preparing',
      OrderStatus.ready => 'ready',
      OrderStatus.assigned => 'assigned',
      OrderStatus.onTheWay => 'on_the_way',
      OrderStatus.delivered => 'delivered',
      OrderStatus.cancelled => 'cancelled',
    };
  }

  static OrderStatus fromString(String value) {
    return switch (value) {
      'pending' => OrderStatus.pending,
      'confirmed' => OrderStatus.confirmed,
      'preparing' => OrderStatus.preparing,
      'ready' => OrderStatus.ready,
      'assigned' => OrderStatus.assigned,
      'on_the_way' => OrderStatus.onTheWay,
      'delivered' => OrderStatus.delivered,
      'cancelled' => OrderStatus.cancelled,
      _ => OrderStatus.pending,
    };
  }

  bool get isActive => !isTerminal;

  bool get isTerminal =>
      this == OrderStatus.delivered || this == OrderStatus.cancelled;

  bool get isDelivering => this == OrderStatus.onTheWay;

  /// Índice para la barra de progreso del tracking.
  int get progressIndex {
    return switch (this) {
      OrderStatus.pending => 0,
      OrderStatus.confirmed => 1,
      OrderStatus.preparing => 2,
      OrderStatus.ready => 3,
      OrderStatus.assigned => 4,
      OrderStatus.onTheWay => 5,
      OrderStatus.delivered => 6,
      OrderStatus.cancelled => -1,
    };
  }
}
