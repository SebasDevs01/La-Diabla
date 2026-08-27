// lib/domain/repositories/notification_repository.dart

/// Modelo de notificación (simplificado para la capa de dominio).
class NotificationEntity {
  const NotificationEntity({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    this.data = const {},
    this.isRead = false,
    this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final String type;
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime? createdAt;
}

/// Tipos de notificación de La Diabla.
abstract final class NotificationTypes {
  static const String orderReceived = 'order_received';
  static const String orderConfirmed = 'order_confirmed';
  static const String orderPreparing = 'order_preparing';
  static const String orderReady = 'order_ready';
  static const String driverAssigned = 'driver_assigned';
  static const String orderOnTheWay = 'order_on_the_way';
  static const String orderDelivered = 'order_delivered';
  static const String promotion = 'promotion';
}

/// Interfaz del repositorio de notificaciones.
abstract interface class NotificationRepository {
  /// Obtiene las notificaciones del usuario.
  Future<List<NotificationEntity>> getNotifications(String userId);

  /// Stream de notificaciones en tiempo real.
  Stream<List<NotificationEntity>> watchNotifications(String userId);

  /// Marca una notificación como leída.
  Future<void> markAsRead(String notificationId);

  /// Marca todas las notificaciones como leídas.
  Future<void> markAllAsRead(String userId);

  /// Número de notificaciones no leídas.
  Stream<int> watchUnreadCount(String userId);
}
