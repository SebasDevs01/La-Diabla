// lib/firebase_options.dart
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Placeholder para `FirebaseOptions`.
/// Reemplazar con el archivo real generado por `flutterfire configure`.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions no están configuradas para windows',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions no están configuradas para linux',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions no están configuradas para esta plataforma.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyPlaceholderWebApiKeyForLaDiablaApp',
    appId: '1:100000000000:web:placeholderappId',
    messagingSenderId: '100000000000',
    projectId: 'la-diabla-app',
    authDomain: 'la-diabla-app.firebaseapp.com',
    storageBucket: 'la-diabla-app.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyPlaceholderAndroidApiKeyForLaDiablaApp',
    appId: '1:100000000000:android:placeholderappId',
    messagingSenderId: '100000000000',
    projectId: 'la-diabla-app',
    storageBucket: 'la-diabla-app.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyPlaceholderIosApiKeyForLaDiablaApp',
    appId: '1:100000000000:ios:placeholderappId',
    messagingSenderId: '100000000000',
    projectId: 'la-diabla-app',
    storageBucket: 'la-diabla-app.appspot.com',
    iosBundleId: 'com.ladiabla.app',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyPlaceholderMacosApiKeyForLaDiablaApp',
    appId: '1:100000000000:ios:placeholderappId',
    messagingSenderId: '100000000000',
    projectId: 'la-diabla-app',
    storageBucket: 'la-diabla-app.appspot.com',
    iosBundleId: 'com.ladiabla.app',
  );
}
