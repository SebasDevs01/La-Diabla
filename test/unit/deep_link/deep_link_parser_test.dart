// test/unit/deep_link/deep_link_parser_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:la_diabla/core/services/deep_link_service.dart';

void main() {
  late DeepLinkService service;

  setUp(() {
    service = DeepLinkService();
  });

  group('DeepLinkService - Resolution', () {
    test('resuelve URL de QR /go?type=product&id=tacos_pastor', () {
      const url = 'https://ladiabla.app/go?type=product&id=tacos_pastor';
      final result = service.resolveUrl(url);

      expect(result, isNotNull);
      expect(result!.path, '/product/tacos_pastor');
    });

    test('resuelve URL de QR /go?type=category&id=burritos', () {
      const url = 'https://ladiabla.app/go?type=category&id=burritos';
      final result = service.resolveUrl(url);

      expect(result, isNotNull);
      expect(result!.path, '/menu/burritos');
    });

    test('resuelve URL directa /product/burrito-diablo', () {
      const url = 'https://ladiabla.app/product/burrito-diablo';
      final result = service.resolveUrl(url);

      expect(result, isNotNull);
      expect(result!.path, '/product/burrito-diablo');
    });

    test('retorna null para dominios no autorizados', () {
      const url = 'https://malicious-site.com/go?type=product';
      final result = service.resolveUrl(url);

      expect(result, isNull);
    });
  });
}
