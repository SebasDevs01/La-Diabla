// lib/core/services/connectivity_service.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ConnectivityService {
  static Future<bool> hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}

// Provider de estado de conexión a internet
final isOnlineProvider = FutureProvider.autoDispose<bool>((ref) async {
  return ConnectivityService.hasInternetConnection();
});
