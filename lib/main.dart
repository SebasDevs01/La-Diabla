// lib/main.dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'app/app.dart';
import 'core/constants/app_constants.dart';
import 'core/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Orientación vertical preferida para app móvil de delivery
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Inicializar almacenamiento local Hive
  await Hive.initFlutter();
  await Hive.openBox(AppConstants.cartHiveBoxName);

  // Inicialización de Firebase
  try {
    await Firebase.initializeApp();
    // Registrar handler de mensajes en background (debe hacerse antes de runApp)
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    // Inicializar servicio de notificaciones (solicita permisos FCM)
    await NotificationService().initialize();
  } catch (e) {
    debugPrint('Firebase init info: $e');
  }

  runApp(
    const ProviderScope(
      child: LaDiablaApp(),
    ),
  );
}
