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
/// Se ejecuta cuando la app está en background pero sigue viva en memoria.
/// Para app completamente cerrada, FCM muestra la notificación del sistema
/// automáticamente gracias a la Cloud Function onChatMessageNotification.
/// Manejador de mensajes en background (debe ser top-level).
/// Solo muestra notificación local manual si el mensaje es DATA-ONLY (sin payload de sistema),
/// ya que Android/iOS muestran automáticamente los mensajes con payload de notificación.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('📬 Mensaje en background: ${message.messageId}');

  // Si ya tiene payload de notificación, el SO (Android/iOS) ya lo muestra automáticamente.
  // Solo mostramos banner manual si es un mensaje data-only.
  if (message.notification == null && message.data.isNotEmpty) {
    final title = message.data['title'] as String? ?? 'La Diabla';
    final body = message.data['body'] as String? ?? '';
    if (body.isEmpty) return;

    final localPlugin = FlutterLocalNotificationsPlugin();
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await localPlugin.initialize(initSettings);
    await localPlugin.show(
      message.data.hashCode,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'la_diabla_orders',
          'Pedidos La Diabla',
          channelDescription: 'Notificaciones de La Diabla',
          importance: Importance.max,
          priority: Priority.max,
          visibility: NotificationVisibility.public,
          category: AndroidNotificationCategory.message,
          icon: '@mipmap/ic_launcher',
          playSound: true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }
}

/// Servicio de notificaciones push — wrapper de Firebase Cloud Messaging
/// + flutter_local_notifications para mostrar banners en foreground y pantalla de bloqueo.
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

  // Caché de deduplicación de notificaciones en memoria (TTL de 20 segundos)
  static final Map<String, DateTime> _recentlyShownNotifications = {};

  /// Verifica si una notificación es duplicada para evitar múltiples sonidos/banners
  static bool isDuplicate(String key) {
    if (key.isEmpty) return false;
    final now = DateTime.now();
    // Limpieza de entradas con más de 20 segundos de antigüedad
    _recentlyShownNotifications.removeWhere((_, time) => now.difference(time).inSeconds > 20);
    if (_recentlyShownNotifications.containsKey(key)) {
      return true;
    }
    _recentlyShownNotifications[key] = now;
    return false;
  }

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
    showBadge: true,
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

    // Crear canal de alta importancia en Android con visibilidad pública en bloqueo
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
    final title = notification?.title ?? message.data['title'] as String? ?? '';
    final body = notification?.body ?? message.data['body'] as String? ?? '';
    if (title.isEmpty && body.isEmpty) return;

    final orderId = message.data['orderId'] as String? ?? '';
    final type = message.data['type'] as String? ?? '';
    final status = message.data['status'] as String? ?? '';

    // Clave de deduplicación unificada: idéntica a la que genera el listener de Firestore
    final dedupKey = (orderId.isNotEmpty && (status.isNotEmpty || type == 'order_status'))
        ? 'order_status_${orderId}_$status'
        : (type == 'chat_message'
            ? 'chat_${orderId}_${title}_$body'
            : (message.messageId ?? '${orderId}_${type}_${title}_$body'));

    if (isDuplicate(dedupKey)) {
      _logger.d('Foreground push duplicado omitido: $dedupKey');
      return;
    }

    // Si el usuario ya está viendo activamente el chat de esta orden, no mostrar banner
    if (type == 'chat_message' &&
        OrderChatScreen.currentActiveOrderId != null &&
        OrderChatScreen.currentActiveOrderId == orderId) {
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'la_diabla_orders',
      'Pedidos La Diabla',
      channelDescription: 'Notificaciones de estado de tus pedidos',
      importance: Importance.max,
      priority: Priority.max,
      icon: '@mipmap/ic_launcher',
      largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      styleInformation: BigTextStyleInformation(''),
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.message,
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
      notification.hashCode != 0 ? notification.hashCode : DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      notificationDetails,
      payload: jsonEncode({
        'type': type.isNotEmpty ? type : 'order_status',
        'orderId': orderId,
        'title': title,
        'body': body,
      }),
    );
  }

  /// Muestra una notificación local manualmente con visibilidad en pantalla de bloqueo y deduplicación.
  static Future<void> showLocalNotification({
    required String title,
    required String body,
    int id = 0,
    String? payload,
    String? deduplicationKey,
  }) async {
    final dedup = deduplicationKey ?? '$title|$body|$payload';
    if (isDuplicate(dedup)) {
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'la_diabla_orders',
      'Pedidos La Diabla',
      channelDescription: 'Notificaciones de estado de tus pedidos',
      importance: Importance.max,
      priority: Priority.max,
      icon: '@mipmap/ic_launcher',
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.message,
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

  // --- Realtime Notification Listener ---
  /// Escucha en tiempo real nuevas notificaciones en Firestore y muestra banners.
  /// [isDriver] si true, omite notificaciones tipo order_status (son para el cliente, no el repartidor).
  void startRealtimeNotificationListener(String userId, {bool isDriver = false}) {
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
          if (createdAt != null && createdAt.isBefore(_sessionStartTime)) continue;
          final senderId = data['senderId'] as String? ?? '';
          if (senderId.isNotEmpty && senderId == userId) continue;
          final orderId = data['orderId'] as String? ?? '';
          final title = data['title'] as String? ?? 'Nuevo mensaje';
          final body = data['body'] as String? ?? '';
          final type = data['type'] as String? ?? 'chat_message';
          final status = data['status'] as String? ?? '';
          // Si es repartidor, omitir notificaciones order_status (son para el cliente).
          if (isDriver && type == 'order_status') continue;
          if (type == 'chat_message' && OrderChatScreen.currentActiveOrderId != null && OrderChatScreen.currentActiveOrderId == orderId) continue;
          final dedupKey = (orderId.isNotEmpty && (status.isNotEmpty || type == 'order_status'))
              ? 'order_status_${orderId}_$status'
              : (type == 'chat_message' ? 'chat_${orderId}_${change.doc.id}' : (change.doc.id.isNotEmpty ? change.doc.id : '$title-$body'));
          showLocalNotification(title: title, body: body, deduplicationKey: dedupKey, payload: jsonEncode({'type': type, 'orderId': orderId, 'title': title, 'body': body}));
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
      // Los repartidores reciben push de nuevos pedidos vía FCM (Cloud Function), no vía listener.
      startRealtimeNotificationListener(userId, isDriver: role == 'driver');

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

  /// Registra una notificación de estado de orden en Firestore de forma idempotente para el cliente.
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
      final docId = (orderId != null && status != null)
          ? '${orderId}_$status'
          : null;

      final notifCol = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('notifications');

      final data = {
        'title': title,
        'body': body,
        'orderId': orderId,
        'emoji': emoji,
        'status': status,
        'type': 'order_status',
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
      };

      if (docId != null) {
        await notifCol.doc(docId).set(data, SetOptions(merge: true));
      } else {
        await notifCol.add(data);
      }
      // Nota: showLocalNotification NO se ejecuta aquí para evitar que quien cambia el estado
      // (admin o repartidor) reciba una alerta en su propio teléfono destinada al cliente.
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
