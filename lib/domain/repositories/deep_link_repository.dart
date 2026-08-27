// lib/domain/repositories/deep_link_repository.dart

/// Resultado de resolver un deep link.
class DeepLinkResult {
  const DeepLinkResult({
    required this.path,
    this.params = const {},
  });

  /// Ruta interna de la app (ejemplo: '/product/tacos-al-pastor')
  final String path;

  /// Parámetros de la ruta.
  final Map<String, String> params;
}

/// Interfaz del repositorio de deep links y QR.
/// Abstrae la lógica de resolución de links, deferred deep linking,
/// y la detección de la plataforma.
abstract interface class DeepLinkRepository {
  /// Resuelve una URL externa al path interno de la app.
  /// Ejemplo: 'https://ladiabla.app/go?type=product&id=abc' → '/product/abc'
  DeepLinkResult? resolveUrl(String url);

  /// Guarda una intención diferida (para deferred deep linking).
  /// Se llama cuando el usuario llega desde un QR/link antes de instalar.
  Future<void> saveDeferredIntent(DeepLinkResult intent);

  /// Recupera la intención diferida guardada y la limpia del storage.
  Future<DeepLinkResult?> getDeferredIntent();

  /// Stream de deep links recibidos mientras la app está abierta.
  Stream<DeepLinkResult> get onDeepLink;

  /// Inicializa el servicio de deep links (se llama en el startup).
  Future<void> initialize();
}
