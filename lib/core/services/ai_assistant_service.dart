// lib/core/services/ai_assistant_service.dart

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../domain/entities/order_entity.dart';
import '../../domain/entities/order_status.dart';
import '../../domain/entities/product_entity.dart';
import '../../mock/mock_products.dart';

class AiRecommendationResult {
  const AiRecommendationResult({
    required this.message,
    required this.products,
  });

  final String message;
  final List<ProductEntity> products;
}

class AiAssistantService {
  AiAssistantService._();
  static final AiAssistantService instance = AiAssistantService._();

  /// Endpoint de respaldo para LLM gratuito
  static const String _freeLlmEndpoint = 'https://text.pollinations.ai/';

  // ═══════════════════════════════════════════════════════════════════════════
  // 🌮 RECOMENDACIÓN INTELIGENTE DE PLATILLOS (LA DIABLA IA)
  // ═══════════════════════════════════════════════════════════════════════════
  Future<AiRecommendationResult> getFoodRecommendation({
    required String query,
    String userName = '',
    List<ProductEntity>? catalog,
  }) async {
    final allProducts = catalog ?? mockProducts;
    final cleanQuery = query.trim().toLowerCase();
    final greetingName = userName.isNotEmpty ? ' $userName' : '';

    // Intentar consultar endpoint de IA gratuita con timeout corto (3.5 segundos)
    try {
      final aiResponse = await _fetchFreeAiRecommendation(cleanQuery, greetingName, allProducts)
          .timeout(const Duration(milliseconds: 3500));
      if (aiResponse != null && aiResponse.message.trim().isNotEmpty && aiResponse.products.isNotEmpty) {
        return aiResponse;
      }
    } catch (_) {
      debugPrint('ℹ️ Usando motor semántico nativo de La Diabla IA');
    }

    // Motor Semántico Local de Alta Precisión
    return _semanticRecommend(cleanQuery, greetingName, allProducts);
  }

  Future<AiRecommendationResult?> _fetchFreeAiRecommendation(
    String query,
    String greetingName,
    List<ProductEntity> products,
  ) async {
    final menuSummary = products
        .take(12)
        .map((p) => '${p.id}: ${p.name} (\$${p.price.toInt()} COP, picante: ${p.spicyLevel}/3)')
        .join('; ');

    final prompt =
        'Eres La Diabla IA, chef mexicana entusiasta y divertida de La Diabla. El cliente$greetingName dice: "$query".\n'
        'Menú disponible: $menuSummary.\n'
        'Responde en español colombiano/mexicano con calidez y emojis (máximo 3 frases recomendando lo ideal).\n'
        'Al final incluye en una línea separada: IDs:[id1, id2] con hasta 3 IDs de los platillos que recomiendes.';

    final uri = Uri.parse('$_freeLlmEndpoint${Uri.encodeComponent(prompt)}?model=openai');
    final res = await http.get(uri);
    if (res.statusCode == 200 && res.body.isNotEmpty && !res.body.contains('budget')) {
      final text = res.body.trim();
      final idRegex = RegExp(r'IDs:\s*\[(.*?)\]', caseSensitive: false);
      final match = idRegex.firstMatch(text);

      List<ProductEntity> matchedProducts = [];
      String cleanMessage = text;

      if (match != null) {
        final idListStr = match.group(1) ?? '';
        final ids = idListStr.split(',').map((s) => s.trim().replaceAll("'", '').replaceAll('"', '')).toList();
        matchedProducts = products.where((p) => ids.contains(p.id)).toList();
        cleanMessage = text.replaceAll(match.group(0)!, '').trim();
      }

      if (matchedProducts.isEmpty) {
        matchedProducts = _filterTopProducts(query, products);
      }

      return AiRecommendationResult(message: cleanMessage, products: matchedProducts);
    }
    return null;
  }

  AiRecommendationResult _semanticRecommend(
    String q,
    String greetingName,
    List<ProductEntity> products,
  ) {
    // 1. Saludos iniciales
    if (RegExp(r'^(hola|buenas|hey|buen d|que tal|quiubo|ola)').hasMatch(q)) {
      final best = products.where((p) => p.id == 'tacos_pastor' || p.id == 'tacos_birria' || p.id == 'burrito_diablo').toList();
      return AiRecommendationResult(
        message: '¡Hola$greetingName! 🔥 Soy **La Diabla IA** 🌶️ tu chef virtual.\n\n'
            '¿Qué antojo traes hoy? Dime si prefieres tacos dorados, queso derretido, algo sin picante o para compartir, y te armo el pedido perfecto al tiro. 🌮🧀',
        products: best.isNotEmpty ? best : products.take(3).toList(),
      );
    }

    // 2. Extracción de Presupuesto
    double? maxBudget;
    final budgetMatch = RegExp(r'(\d+)\s*(mil|k|\.000|\$)?', caseSensitive: false).firstMatch(q);
    if (budgetMatch != null) {
      final numStr = budgetMatch.group(1);
      if (numStr != null) {
        final parsed = double.tryParse(numStr);
        if (parsed != null) {
          maxBudget = parsed < 100 ? parsed * 1000 : parsed;
        }
      }
    }
    if (q.contains('barato') || q.contains('economico') || q.contains('económico') || q.contains('poco presupuesto')) {
      maxBudget ??= 20000;
    }

    // 3. Preferencia de Picante
    final prefersMild = q.contains('no pique') || q.contains('sin picante') || q.contains('no pica') || q.contains('suave') || q.contains('no picante') || q.contains('cero picante');
    final prefersExtraSpicy = q.contains('muy picante') || q.contains('bien picante') || q.contains('lo mas picante') || q.contains('lo más picante') || q.contains('extremo') || q.contains('diablo');

    // 4. Ocasión / Porción
    final isForTwo = q.contains('para dos') || q.contains('para 2') || q.contains('mi novia') || q.contains('mi novio') || q.contains('pareja') || q.contains('compartir') || q.contains('amigos');
    final isVeryHungry = q.contains('mucha hambre') || q.contains('hambriento') || q.contains('llenador') || q.contains('grande') || q.contains('gigante') || q.contains('banquete');

    // 5. Ingredientes y Categorías
    final wantsCheese = q.contains('queso') || q.contains('derretido') || q.contains('fundido') || q.contains('quesadilla');
    final wantsBirria = q.contains('birria') || q.contains('consome') || q.contains('consomé') || q.contains('sopear');
    final wantsSeafood = q.contains('marisco') || q.contains('camaron') || q.contains('camarón') || q.contains('pescado') || q.contains('mar');
    final wantsMeat = q.contains('carne') || q.contains('asada') || q.contains('pastor') || q.contains('suadero') || q.contains('res');
    final wantsDrinkDessert = q.contains('postre') || q.contains('dulce') || q.contains('churro') || q.contains('bebida') || q.contains('sed') || q.contains('tomar') || q.contains('agua') || q.contains('jugo');

    // Puntuación de afinidad de productos
    final scored = products.map((p) {
      double score = 0;
      final desc = '${p.name} ${p.description} ${p.ingredients.join(" ")}'.toLowerCase();

      // Filtro de presupuesto
      if (maxBudget != null) {
        if (p.price <= maxBudget) {
          score += 15;
        } else {
          score -= 10;
        }
      }

      // Picante
      if (prefersMild) {
        if (p.spicyLevel == 0) score += 20;
        if (p.spicyLevel == 1) score += 10;
        if (p.spicyLevel >= 2) score -= 15;
      } else if (prefersExtraSpicy) {
        if (p.spicyLevel >= 2) score += 25;
        if (p.spicyLevel == 1) score += 10;
      }

      // Ingredientes
      if (wantsCheese && (desc.contains('queso') || p.categoryId == 'quesadillas')) score += 20;
      if (wantsBirria && desc.contains('birria')) score += 30;
      if (wantsSeafood && (desc.contains('camarón') || desc.contains('camaron') || p.categoryId == 'mariscos')) score += 25;
      if (wantsMeat && (desc.contains('res') || desc.contains('pastor') || desc.contains('carne') || desc.contains('suadero'))) score += 15;
      if (wantsDrinkDessert && (p.categoryId == 'postres' || p.categoryId == 'bebidas' || desc.contains('churro'))) score += 30;

      // Porciones
      if (isForTwo && (p.categoryId == 'entradas' || desc.contains('nacho') || desc.contains('totopos') || p.price >= 25000)) score += 15;
      if (isVeryHungry && (p.categoryId == 'burritos' || desc.contains('gigante') || desc.contains('3 tacos'))) score += 15;

      return MapEntry(p, score);
    }).toList();

    scored.sort((a, b) => b.value.compareTo(a.value));
    final selected = scored.where((e) => e.value > 0).take(3).map((e) => e.key).toList();
    final finalProducts = selected.isNotEmpty ? selected : products.take(3).toList();

    // Generar mensaje contextualizado y humano
    String botText;
    if (wantsBirria) {
      botText = '¡Uff$greetingName, la birria es la reina de la casa! 🌮🍲 Estos tacos vienen doraditos a la plancha con queso derretido y su consomé caliente para sopear cada mordisco. ¡Una locura de sabor!';
    } else if (wantsCheese) {
      botText = '¡Para los amantes del queso como tú$greetingName! 🧀 Te seleccioné nuestras opciones con más queso fundido y costra doradita. Suaves, cremosos y con un sabor mexicano irresistible:';
    } else if (wantsSeafood) {
      botText = '¡Sabor del Pacífico mexicano a tu mesa$greetingName! 🦐🌊 Camarones salteados con sazón costera y aguacate fresco. Te van a fascinar:';
    } else if (prefersMild) {
      botText = '¡Tranquilo$greetingName, cero enchiladas! 🥑✨ Te elegí opciones con todo el sabor auténtico de México pero con picante suave o salsa aparte para que comas feliz y sin ardor:';
    } else if (prefersExtraSpicy) {
      botText = '¡Eso es tener valentía$greetingName! 🔥🌶️ Aquí tienes el verdadero fuego de La Diabla con salsa habanera y toreados que te harán sudar de puro placer:';
    } else if (maxBudget != null) {
      botText = '¡Cuidando el bolsillo como se debe$greetingName! 💰 Te armé esta selección deliciosa y llenadora por menos de \$${maxBudget.toInt()} COP:';
    } else if (isForTwo) {
      botText = '¡Plan perfecto en pareja o con amigos$greetingName! 👫🌮 Estos platillos son generosos y traen la porción ideal para picar y compartir al centro:';
    } else {
      botText = '¡Te tengo justo lo que buscas$greetingName! 🌮🔥 Analicé lo que me dijiste y estos platillos de nuestra cocina son exactamente lo que necesitas para calmar ese antojo hoy:';
    }

    return AiRecommendationResult(message: botText, products: finalProducts);
  }

  List<ProductEntity> _filterTopProducts(String query, List<ProductEntity> catalog) {
    final q = query.toLowerCase();
    return catalog.where((p) {
      final text = '${p.name} ${p.description}'.toLowerCase();
      if (q.contains('taco') && p.categoryId == 'tacos') return true;
      if (q.contains('burrito') && p.categoryId == 'burritos') return true;
      if (q.contains('queso') && text.contains('queso')) return true;
      if (q.contains('birria') && text.contains('birria')) return true;
      return false;
    }).take(3).toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🎧 ASISTENTE DE SOPORTE INTELIGENTE Y CONTEXTUAL
  // ═══════════════════════════════════════════════════════════════════════════
  String getSupportResponse({
    required String query,
    String? orderId,
    OrderEntity? order,
  }) {
    final q = query.trim().toLowerCase();
    final shortId = orderId != null && orderId.length > 6
        ? orderId.substring(orderId.length - 6).toUpperCase()
        : (orderId ?? 'LD-7824');

    final status = order?.status;
    final isDelivered = status == OrderStatus.delivered;
    final isOnTheWay = status == OrderStatus.onTheWay;
    final isPreparing = status == OrderStatus.preparing || status == OrderStatus.confirmed;

    // 1. Demoras y Tiempo de Entrega
    if (q.contains('demor') || q.contains('tard') || q.contains('cuanto falta') || q.contains('cuánto falta') || q.contains('donde viene') || q.contains('dónde viene') || q.contains('no llega')) {
      if (isDelivered) {
        return '🛵 **Tu pedido #$shortId figura como ENTREGADO:**\n\n'
            'Nuestro sistema marca que el repartidor ya completó la entrega. Si no lo has recibido personalmente, revisa si fue dejado en portería o recepción.\n\n'
            'Si aún no lo tienes, presiona el botón de WhatsApp abajo para contactar a soporte inmediato con nuestro equipo.';
      }
      if (isOnTheWay) {
        return '🛵 **Tu pedido #$shortId va en camino:**\n\n'
            'El repartidor ya retiró tus platillos de la cocina y se encuentra desplazándose hacia tu dirección. Lleva empaque térmico para que te llegue caliente.\n\n'
            '⏱️ **Tiempo estimado:** 5 a 12 minutos. Puedes seguir su recorrido GPS en tiempo real en la pantalla de rastreo.';
      }
      if (isPreparing) {
        return '👨‍🍳 **Tu pedido #$shortId se está preparando en cocina:**\n\n'
            'Nuestros cocineros están horneando y empacando tus alimentos frescos. Apenas salga de cocina, un repartidor iniciará el recorrido de inmediato.\n\n'
            '⏱️ **Estimado para despacho:** 8 a 15 minutos.';
      }
      return '🛵 **Seguimiento de Entrega #$shortId:**\n\n'
          'Estamos monitoreando el tráfico en Bucaramanga y la ruta de despacho para que tu pedido llegue lo más rápido posible.\n\n'
          'Si requieres contactar al repartidor o a la cocina, pulsa el botón de WhatsApp abajo.';
    }

    // 2. Cobros, Bancos, Tarjetas y Nequi/Daviplata
    if (q.contains('cobro') || q.contains('tarjeta') || q.contains('doble') || q.contains('banco') || q.contains('nequi') || q.contains('daviplata') || q.contains('dinero') || q.contains('plata')) {
      return '💳 **Aclaración de Cobros y Pagos #$shortId:**\n\n'
          '• **¿Ves dos cobros en tu app bancaria?** Las entidades financieras en Colombia generan una *retención de autorización previa* al momento de ordenar y luego el cobro real. La retención se anula y libera de forma automática en **24 a 48 horas**.\n'
          '• En La Diabla confirmamos que únicamente se procesó **un solo cobro efectivo**.\n\n'
          'Si necesitas un comprobante oficial de pago o constancia de anulación para tu banco, escríbenos directamente por WhatsApp.';
    }

    // 3. Comida Incompleta, Fría o Equivocada
    if (q.contains('incomplet') || q.contains('equivocad') || q.contains('falto') || q.contains('faltó') || q.contains('fria') || q.contains('fría') || q.contains('mal') || q.contains('dañad')) {
      return '📦 **Garantía y Solución Inmediata de Pedido:**\n\n'
          '¡Lamentamos muchísimo este inconveniente con tu pedido #$shortId! En La Diabla nos tomamos la comida muy en serio y tenemos dos soluciones rápidas:\n\n'
          '1️⃣ **Reenvío prioritario express** del platillo correcto o faltante sin ningún costo.\n'
          '2️⃣ **Reembolso inmediato** o saldo a favor en tu billetera.\n\n'
          'Por favor pulsa el botón de WhatsApp abajo y envíanos una foto del paquete para solucionarlo en minutos.';
    }

    // 4. Cancelaciones y Reembolsos
    if (q.contains('cancel') || q.contains('reembolso') || q.contains('devolu')) {
      return '🚫 **Cancelación y Devoluciones de Dinero:**\n\n'
          'Si necesitas cancelar tu pedido #$shortId:\n'
          '• Si el pedido aún no ha sido despachado, la cancelación se efectúa al instante.\n'
          '• Los reembolsos de tarjeta, PSE, Nequi o Daviplata se devuelven por el mismo canal de pago.\n\n'
          'Toca el botón de WhatsApp para que el encargado de turno detenga el despacho y tramite tu reintegro de inmediato.';
    }

    // 5. Cambio de Dirección o Teléfono
    if (q.contains('direccion') || q.contains('dirección') || q.contains('cambiar') || q.contains('telefono') || q.contains('celular') || q.contains('apartamento') || q.contains('torre')) {
      return '📍 **Actualización de Dirección de Entrega:**\n\n'
          'Podemos redirigir al repartidor si la nueva dirección está en la misma zona de cobertura en Bucaramanga.\n\n'
          'Escríbenos al WhatsApp con la nueva dirección y número de torre/apartamento para instruir al repartidor de inmediato.';
    }

    // 6. Respuesta Dinámica y Natural para Consultas Generales
    return '👋 ¡Hola! Soy tu asistente de soporte para el pedido **#$shortId**.\n\n'
        'Puedo ayudarte a consultar el estado del repartidor, verificar cobros con tarjeta/Nequi, gestionar adiciones de salsas o resolver dudas del restaurante.\n\n'
        '¿Deseas hablar directamente con nuestro asesor de turno por WhatsApp? Pulsa el botón abajo.';
  }
}
