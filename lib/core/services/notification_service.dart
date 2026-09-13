// lib/core/services/notification_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';
import '../../app/router/app_router.dart';
import '../../features/orders/presentation/screens/order_chat_screen.dart';

/// Manejador de mensajes en background (debe ser top-level).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('📬 Mensaje en background: ${message.messageId}');
}

/// Servicio de notificaciones push — wrapper de Firebase Cloud Messaging
/// + flutter_local_notifications para mostrar banners en foreground.
class NotificationService {
  factory NotificationService() => _instance;
  NotificationService._internal({FirebaseMessaging? messaging})
      : _messaging = messaging ?? FirebaseMessaging.instance;
  static final NotificationService _instance = NotificationService._internal();

  final FirebaseMessaging _messaging;
  final Logger _logger = Logger();
  String? _currentUserId;
  StreamSubscription<QuerySnapshot>? _realtimeNotifsSub;
  DateTime _sessionStartTime = DateTime.now();

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

      // 6. Al tocar una notificación push en segundo plano
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        final orderId = message.data['orderId'] as String?;
        if (orderId != null && orderId.isNotEmpty) {
          navigateToChat(orderId);
        }
      });

      // 7. Al abrir la app desde estado terminado mediante push
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        final orderId = initialMessage.data['orderId'] as String?;
        if (orderId != null && orderId.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            navigateToChat(orderId);
          });
        }
      }

      // 8. Escuchar renovación de token FCM en tiempo real
      _messaging.onTokenRefresh.listen((newToken) async {
        if (_currentUserId != null && _currentUserId!.isNotEmpty) {
          await _saveTokenToFirestore(_currentUserId!, newToken);
        }
      });

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
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _handleNotificationPayload(payload);
        }
      },
    );

    // Si la app fue lanzada al tocar una notificación local
    final launchDetails = await _localNotifications.getNotificationAppLaunchDetails();
    if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
      final payload = launchDetails.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleNotificationPayload(payload);
        });
      }
    }

    // Crear canal de alta importancia en Android
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channel);
  }

  static void _handleNotificationPayload(String payload) {
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final orderId = data['orderId'] as String?;
      if (orderId != null && orderId.isNotEmpty) {
        navigateToChat(orderId);
      }
    } catch (e) {
      debugPrint('Error procesando payload de notificación: $e');
    }
  }

  /// Redirige al chat del pedido en tiempo real
  static void navigateToChat(String orderId) {
    final nav = rootNavigatorKey.currentState;
    if (nav != null) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => OrderChatScreen(
            orderId: orderId,
          ),
        ),
      );
    }
  }

  /// Muestra una notificación local cuando la app está en foreground.
  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    final orderId = message.data['orderId'] as String? ?? '';

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
      payload: jsonEncode({
        'type': 'chat',
        'orderId': orderId,
      }),
    );
  }

  /// Muestra una notificación local manualmente (con soporte para payload y redirección).
  static Future<void> showLocalNotification({
    required String title,
    required String body,
    int id = 0,
    String? payload,
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
    final notifId = id == 0 ? DateTime.now().millisecondsSinceEpoch.remainder(100000) : id;
    await _localNotifications.show(notifId, title, body, details, payload: payload);
  }

  // ─── Realtime Notification Listener ────────────────────────────────────────

  /// Escucha en tiempo real nuevas notificaciones en Firestore y muestra banners con sonido y vibración
  void startRealtimeNotificationListener(String userId) {
    if (userId.isEmpty || userId == 'guest') return;
    _realtimeNotifsSub?.cancel();
    _sessionStartTime = DateTime.now().subtract(const Duration(seconds: 3));

    _realtimeNotifsSub = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data == null) continue;

          final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
          if (createdAt != null && createdAt.isBefore(_sessionStartTime)) {
            continue;
          }

          final senderId = data['senderId'] as String? ?? '';
          if (senderId == userId) continue;

          final orderId = data['orderId'] as String? ?? '';
          final title = data['title'] as String? ?? 'Nuevo mensaje';
          final body = data['body'] as String? ?? '';
          final type = data['type'] as String? ?? 'chat_message';

          // Si el usuario ya está viendo activamente el chat de esta orden, omitir banner redundante
          if (OrderChatScreen.currentActiveOrderId != null &&
              OrderChatScreen.currentActiveOrderId == orderId) {
            continue;
          }

          showLocalNotification(
            title: title,
            body: body,
            payload: jsonEncode({
              'type': type,
              'orderId': orderId,
              'title': title,
              'body': body,
            }),
          );
        }
      }
    }, onError: (e) {
      _logger.w('Error en listener de notificaciones en tiempo real: $e');
    });
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

  /// Sincroniza el token FCM del usuario en Firestore y opcionalmente sus topics.
  Future<void> syncUserFcmToken(String userId, {String? role}) async {
    if (userId.isEmpty) return;
    _currentUserId = userId;
    try {
      final token = await getToken();
      if (token != null) {
        await _saveTokenToFirestore(userId, token);
        _logger.i('FCM Token sincronizado para $userId (rol: ${role ?? "desconocido"})');
      }

      // Iniciar escucha activa en tiempo real de notificaciones/chat
      startRealtimeNotificationListener(userId);

      // Suscribir al topic general de notificaciones
      await _messaging.subscribeToTopic(NotificationTopics.allUsers);

      // Si es repartidor, suscribir al topic exclusivo de repartidores
      if (role == 'driver') {
        await _messaging.subscribeToTopic(NotificationTopics.drivers);
      } else {
        await _messaging.unsubscribeFromTopic(NotificationTopics.drivers);
      }
    } catch (e) {
      _logger.w('Error sincronizando FCM Token: $e');
    }
  }

  Future<void> _saveTokenToFirestore(String userId, String token) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .set({
        'fcmToken': token,
        'fcmUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      _logger.w('Error guardando FCM token en Firestore: $e');
    }
  }

  /// Limpia el token FCM al cerrar sesión para evitar recibir notificaciones ajenas.
  Future<void> clearFcmToken(String userId) async {
    if (userId.isEmpty) return;
    try {
      _currentUserId = null;
      _realtimeNotifsSub?.cancel();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .update({
        'fcmToken': FieldValue.delete(),
      });
      await _messaging.unsubscribeFromTopic(NotificationTopics.drivers);
      _logger.i('FCM Token removido al cerrar sesión: $userId');
    } catch (e) {
      _logger.w('Error limpiando FCM Token: $e');
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
