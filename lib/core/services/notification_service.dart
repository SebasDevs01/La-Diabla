// lib/core/services/notification_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';

/// Manejador de mensajes en background (debe ser top-level).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('📬 Mensaje en background: ${message.messageId}');
}

/// Servicio de notificaciones push — wrapper de Firebase Cloud Messaging
/// + flutter_local_notifications para mostrar banners en foreground.
class NotificationService {
  NotificationService({FirebaseMessaging? messaging})
      : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;
  final Logger _logger = Logger();

  // ─── Plugin de notificaciones locales ────────────────────────────────────
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'la_diabla_orders', // id
    'Pedidos La Diabla', // name
    description: 'Notificaciones de estado de tus pedidos en La Diabla',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  // ─── Inicialización ───────────────────────────────────────────────────────

  /// Inicializa FCM, solicita permisos y configura notificaciones locales.
  Future<void> initialize() async {
    try {
      // 1. Registrar handler de background
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // 2. Solicitar permisos de notificaciones (Android 13+ / iOS)
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      _logger.i('Permisos FCM: ${settings.authorizationStatus}');

      // 3. Configurar presentación en foreground (iOS)
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // 4. Inicializar flutter_local_notifications
      await _initLocalNotifications();

      // 5. Escuchar mensajes en foreground y mostrar banner local
      FirebaseMessaging.onMessage.listen(_showForegroundNotification);

      _logger.i('NotificationService inicializado correctamente');
    } catch (e) {
      _logger.e('Error inicializando NotificationService', error: e);
    }
  }

  // ─── Local Notifications Setup ────────────────────────────────────────────

  Future<void> _initLocalNotifications() async {
    const initSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: initSettingsAndroid,
      iOS: initSettingsIOS,
    );
    await _localNotifications.initialize(initSettings);

    // Crear canal de alta importancia en Android
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channel);
  }

  /// Muestra una notificación local cuando la app está en foreground.
  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    const androidDetails = AndroidNotificationDetails(
      'la_diabla_orders',
      'Pedidos La Diabla',
      channelDescription: 'Notificaciones de estado de tus pedidos',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      styleInformation: BigTextStyleInformation(''),
      playSound: true,
      enableVibration: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      notificationDetails,
    );
  }

  /// Muestra una notificación local manualmente (sin FCM, útil para repartidores).
  static Future<void> showLocalNotification({
    required String title,
    required String body,
    int id = 0,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'la_diabla_orders',
      'Pedidos La Diabla',
      channelDescription: 'Notificaciones de estado de tus pedidos',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      playSound: true,
      enableVibration: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
    await _localNotifications.show(id, title, body, details);
  }

  // ─── FCM Token ────────────────────────────────────────────────────────────

  Future<String?> getToken() async {
    try {
      return await _messaging.getToken();
    } catch (e) {
      _logger.e('Error obteniendo FCM token', error: e);
      return null;
    }
  }

  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;
  Stream<RemoteMessage> get onMessage => FirebaseMessaging.onMessage;
  Stream<RemoteMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp;
  Future<RemoteMessage?> getInitialMessage() => _messaging.getInitialMessage();

  /// Sincroniza el token FCM del usuario en Firestore.
  Future<void> syncUserFcmToken(String userId) async {
    if (userId.isEmpty) return;
    try {
      final token = await getToken();
      if (token != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .set({
          'fcmToken': token,
          'fcmUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        _logger.i('FCM Token sincronizado: $userId');
      }
    } catch (e) {
      _logger.w('Error sincronizando FCM Token: $e');
    }
  }

  /// Registra una notificación de estado de orden en Firestore
  /// y muestra un banner local si la app está en foreground.
  Future<void> saveOrderNotification({
    required String userId,
    required String title,
    required String body,
    String? orderId,
    String? emoji,
    String? status,
  }) async {
    if (userId.isEmpty) return;
    try {
      // Guardar en Firestore para el historial
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .add({
        'title': title,
        'body': body,
        'orderId': orderId,
        'emoji': emoji,
        'status': status,
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
      });

      // También mostrar banner local inmediato
      await showLocalNotification(title: title, body: body);
    } catch (e) {
      _logger.w('Error guardando notificación: $e');
    }
  }
}

/// Temas de FCM predefinidos.
abstract final class NotificationTopics {
  static const String allUsers = 'all_users';
  static const String promotions = 'promotions';
  static const String newProducts = 'new_products';
  static const String drivers = 'drivers'; // Nuevo: notificar a todos los repartidores
}
