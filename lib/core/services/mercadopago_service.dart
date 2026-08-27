// lib/core/services/mercadopago_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../domain/entities/cart_item_entity.dart';
import '../../domain/entities/order_entity.dart';
import '../../domain/entities/user_entity.dart';

class MercadoPagoService {
  static final Logger _logger = Logger();

  // ─── CREDENCIALES OFICIALES MERCADO PAGO COLOMBIA ─────────────────────────
  static const String publicKey =
      'APP_USR-c748f7a8-88e7-4b2a-ba39-aad0eed00370';
  static const String accessToken =
      'APP_USR-5205155784156847-082020-84186916b70d8cfb2d140f61d0a46720-3629551179';

  static const String _preferencesUrl =
      'https://api.mercadopago.com/checkout/preferences';

  // ─── IDs de metodos de pago reconocidos por MP Colombia ───────────────────
  static const _mpDefaultMethodId = <PaymentMethod, String?>{
    PaymentMethod.transfer: 'pse',
    PaymentMethod.nequi: 'nequi',
    PaymentMethod.daviplata: 'daviplata',
    PaymentMethod.card: null,
    PaymentMethod.cash: null,
    PaymentMethod.pos: null,
  };

  // Tipos de pago a excluir segun metodo elegido
  static const _mpTypeExclusions = <PaymentMethod, List<String>>{
    PaymentMethod.card: ['bank_transfer', 'atm'],
    PaymentMethod.transfer: ['credit_card', 'debit_card', 'atm'],
    PaymentMethod.nequi: ['credit_card', 'debit_card', 'atm'],
    PaymentMethod.daviplata: ['credit_card', 'debit_card', 'atm'],
    PaymentMethod.cash: [],
    PaymentMethod.pos: [],
  };

  /// Crea una preferencia de Checkout Pro en Mercado Pago Colombia.
  /// Soporta: Tarjetas Visa/MC/Amex, PSE/Bancolombia, Nequi y Daviplata.
  /// [paymentMethod] pre-selecciona el metodo en la pantalla de Mercado Pago.
  static Future<String?> createCheckoutPreference({
    required String orderId,
    required List<CartItemEntity> items,
    required double deliveryFee,
    required double discount,
    required UserEntity? user,
    PaymentMethod paymentMethod = PaymentMethod.transfer,
  }) async {
    try {
      final itemsList = <Map<String, dynamic>>[];

      for (final item in items) {
        final extrasName = item.selectedExtras.isNotEmpty
            ? ' (+ ${item.selectedExtras.map((e) => e.name).join(', ')})'
            : '';
        itemsList.add({
          'id': item.product.id,
          'title': '${item.product.name}$extrasName',
          'description': item.product.description.length > 100
              ? item.product.description.substring(0, 100)
              : item.product.description,
          'picture_url': item.product.imageUrl,
          'category_id': 'food_and_drink',
          'quantity': item.quantity,
          'currency_id': 'COP',
          'unit_price': item.unitPrice,
        });
      }

      if (deliveryFee > 0) {
        itemsList.add({
          'id': 'delivery_fee',
          'title': 'Costo de Domicilio La Diabla',
          'description': 'Envio a direccion del cliente',
          'category_id': 'shipping',
          'quantity': 1,
          'currency_id': 'COP',
          'unit_price': deliveryFee,
        });
      }

      final payerEmail = (user?.email != null &&
              user!.email.contains('@') &&
              !user.email.contains('guest'))
          ? user.email
          : 'cliente@ladiabla.app';

      final payerName =
          (user?.displayName != null && user!.displayName.isNotEmpty)
              ? user.displayName
              : 'Cliente La Diabla';

      final payerPhone = user?.phone ?? '3001234567';

      final exclusions = _mpTypeExclusions[paymentMethod] ?? [];
      final defaultMethodId = _mpDefaultMethodId[paymentMethod];

      final paymentMethods = <String, dynamic>{
        'excluded_payment_types':
            exclusions.map((t) => {'id': t}).toList(),
        'installments': paymentMethod == PaymentMethod.card ? 12 : 1,
      };

      if (defaultMethodId != null) {
        paymentMethods['default_payment_method_id'] = defaultMethodId;
      }

      final body = <String, dynamic>{
        'items': itemsList,
        'payer': {
          'name': payerName,
          'email': payerEmail,
          'phone': {
            'area_code': '57',
            'number': payerPhone.replaceAll(RegExp(r'\D'), ''),
          },
        },
        'payment_methods': paymentMethods,
        'back_urls': {
          'success': 'https://ladiabla.app/payment-success?order_id=$orderId',
          'pending': 'https://ladiabla.app/payment-pending?order_id=$orderId',
          'failure': 'https://ladiabla.app/payment-failure?order_id=$orderId',
        },
        'auto_return': 'approved',
        'external_reference': orderId,
        'statement_descriptor': 'LA DIABLA COMIDA',
      };

      final response = await http
          .post(
            Uri.parse(_preferencesUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final initPoint = data['init_point'] as String?;
        _logger.i(
            'Preferencia MP creada: $orderId | metodo: $paymentMethod | url: $initPoint');
        return initPoint;
      }
      _logger.e(
          'Error creando preferencia MP (${response.statusCode}): ${response.body}');
      return null;
    } catch (e) {
      _logger.e('Excepcion en createCheckoutPreference: $e');
      return null;
    }
  }

  /// Abre el Checkout Pro de Mercado Pago en el navegador integrado.
  /// El usuario completa el pago y regresa automaticamente a la app.
  static Future<bool> launchCheckoutUrl(String checkoutUrl) async {
    try {
      final uri = Uri.parse(checkoutUrl);
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      }
      return false;
    } catch (e) {
      _logger.e('Error abriendo checkout: $e');
      return false;
    }
  }

  /// Consulta la API oficial de Mercado Pago para verificar si el pago con [orderId]
  /// fue efectivamente APROBADO y acreditado en tiempo real.
  static Future<bool> checkPaymentApproved(String orderId) async {
    try {
      final searchUrl =
          'https://api.mercadopago.com/v1/payments/search?external_reference=$orderId&sort=date_created&criteria=desc';
      final response = await http.get(
        Uri.parse(searchUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final results = data['results'] as List<dynamic>? ?? [];
        if (results.isNotEmpty) {
          final firstPayment = results.first as Map<String, dynamic>;
          final status = firstPayment['status'] as String?;
          _logger.i('Verificacion de pago MP #$orderId: status=$status');
          return status == 'approved';
        }
      }
      return false;
    } catch (e) {
      _logger.e('Error verificando pago MP: $e');
      return false;
    }
  }

  /// Nombre descriptivo del metodo de pago.
  static String methodDisplayName(PaymentMethod method) {
    return switch (method) {
      PaymentMethod.card => 'Tarjeta de Credito / Debito (En linea)',
      PaymentMethod.transfer => 'PSE / Bancolombia en linea',
      PaymentMethod.nequi => 'Nequi (En linea)',
      PaymentMethod.daviplata => 'Daviplata (En linea)',
      PaymentMethod.cash => 'Efectivo contra entrega',
      PaymentMethod.pos => 'Datafono (Tarjeta contra entrega)',
    };
  }

  /// Emoji representativo del metodo de pago.
  static String methodEmoji(PaymentMethod method) {
    return switch (method) {
      PaymentMethod.card => '💳',
      PaymentMethod.transfer => '🏦',
      PaymentMethod.nequi => '🟣',
      PaymentMethod.daviplata => '🔴',
      PaymentMethod.cash => '💵',
      PaymentMethod.pos => '📟',
    };
  }
}
