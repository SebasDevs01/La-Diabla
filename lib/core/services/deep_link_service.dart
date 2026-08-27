// lib/core/services/deep_link_service.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import '../../domain/repositories/deep_link_repository.dart';

/// Implementación del servicio de deep links.
/// Maneja la resolución de URLs y el deferred deep linking.
class DeepLinkService implements DeepLinkRepository {
  DeepLinkService({SharedPreferences? prefs}) : _prefs = prefs;

  SharedPreferences? _prefs;
  final Logger _logger = Logger();

  static const String _deferredIntentKey = 'deferred_deep_link';

  final _deepLinkController = _SimpleStreamController<DeepLinkResult>();

  @override
  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
    _logger.d('DeepLinkService inicializado');
    // Aquí se integraría app_links o uni_links para escuchar deep links reales
  }

  @override
  DeepLinkResult? resolveUrl(String url) {
    try {
      final uri = Uri.parse(url);

      // Rutas conocidas del dominio ladiabla.app
      if (uri.host != 'ladiabla.app' && uri.scheme != 'ladiabla') {
        return null;
      }

      final path = uri.path;
      final params = uri.queryParameters;

      // /go?type=product&id=xxx → /product/xxx
      if (path == '/go') {
        final type = params['type'];
        final id = params['id'];

        if (type == null || id == null) return null;

        return switch (type) {
          'product' => DeepLinkResult(path: '/product/$id', params: {'productId': id}),
          'promo' => DeepLinkResult(path: '/promo/$id', params: {'promotionId': id}),
          'category' => DeepLinkResult(path: '/menu/$id', params: {'categoryId': id}),
          'menu' => const DeepLinkResult(path: '/menu'),
          _ => null,
        };
      }

      // URLs directas: /product/xxx, /menu/xxx
      final segments = uri.pathSegments;
      if (segments.isEmpty) return const DeepLinkResult(path: '/home');

      return switch (segments.first) {
        'product' when segments.length > 1 =>
          DeepLinkResult(path: '/product/${segments[1]}'),
        'menu' when segments.length > 1 =>
          DeepLinkResult(path: '/menu/${segments[1]}'),
        'menu' => const DeepLinkResult(path: '/menu'),
        'promo' when segments.length > 1 =>
          DeepLinkResult(path: '/promo/${segments[1]}'),
        _ => null,
      };
    } catch (e) {
      _logger.e('Error resolviendo URL: $url', error: e);
      return null;
    }
  }

  @override
  Future<void> saveDeferredIntent(DeepLinkResult intent) async {
    await _prefs?.setString(_deferredIntentKey, intent.path);
    _logger.d('Intención diferida guardada: ${intent.path}');
  }

  @override
  Future<DeepLinkResult?> getDeferredIntent() async {
    final path = _prefs?.getString(_deferredIntentKey);
    if (path == null) return null;

    // Limpiar después de recuperar
    await _prefs?.remove(_deferredIntentKey);
    _logger.d('Intención diferida recuperada: $path');

    return DeepLinkResult(path: path);
  }

  @override
  Stream<DeepLinkResult> get onDeepLink => _deepLinkController.stream;

  /// Emite un nuevo deep link (llamar cuando se recibe uno externamente).
  void emitDeepLink(String url) {
    final result = resolveUrl(url);
    if (result != null) {
      _deepLinkController.add(result);
    }
  }

  void dispose() {
    _deepLinkController.close();
  }
}

/// Stream controller simple sin dependencias extra.
class _SimpleStreamController<T> {
  final _listeners = <void Function(T)>[];

  Stream<T> get stream => Stream.multi((controller) {
        _listeners.add(controller.add);
        controller.onCancel = () => _listeners.remove(controller.add);
      });

  void add(T value) {
    for (final listener in List.of(_listeners)) {
      listener(value);
    }
  }

  void close() {
    _listeners.clear();
  }
}
