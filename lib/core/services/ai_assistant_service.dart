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

  /// Endpoint gratuito para LLM rápido y sin API key obligatoria
  static const String _freeLlmEndpoint = 'https://text.pollinations.ai/';

  // ═══════════════════════════════════════════════════════════════════════════
  // 🌮 1. LA DIABLA IA — CHEF Y ASESOR GASTRONÓMICO EN VIVO
  // ═══════════════════════════════════════════════════════════════════════════
  Future<AiRecommendationResult> getFoodRecommendation({
    required String query,
    String userName = '',
    List<ProductEntity>? catalog,
  }) async {
    final liveCatalog = (catalog != null && catalog.isNotEmpty)
        ? catalog.where((p) => p.available).toList()
        : mockProducts.where((p) => p.available).toList();

    final cleanQuery = query.trim();
    final greetingName = userName.isNotEmpty ? ' $userName' : '';

    // 1. Intentar consultar LLM dinámico con el menú activo inyectado
    try {
      final aiResponse = await _fetchFreeAiRecommendation(cleanQuery, greetingName, liveCatalog)
          .timeout(const Duration(milliseconds: 4000));
      if (aiResponse != null && aiResponse.message.trim().isNotEmpty && aiResponse.products.isNotEmpty) {
        return aiResponse;
      }
    } catch (e) {
      debugPrint('ℹ️ La Diabla IA: usando motor de conocimiento gastronómico local sincronizado ($e)');
    }

    // 2. Motor de Conocimiento Gastronómico Local de Alta Fidelidad
    return _localGastronomicReasoning(cleanQuery, greetingName, liveCatalog);
  }

  Future<AiRecommendationResult?> _fetchFreeAiRecommendation(
    String query,
    String greetingName,
    List<ProductEntity> products,
  ) async {
    // Tomar los platillos actuales para contexto enriquecido
    final menuSummary = products.take(25).map((p) {
      final ingStr = p.ingredients.isNotEmpty ? ' (Ingredientes: ${p.ingredients.join(", ")})' : '';
      final originStr = (p.origin != null && p.origin!.isNotEmpty) ? ' [Origen: ${p.origin}]' : '';
      return '- ID:${p.id} | ${p.name} | \$${p.price.toInt()} COP | Picante:${p.spicyLevel}/3 | Cat:${p.categoryId}$ingStr$originStr';
    }).join('\n');

    final prompt = '''
Eres "La Diabla IA", chef mexicana apasionada, carismática y auténtica del restaurante "La Diabla" en Bucaramanga.
El cliente$greetingName te pregunta o comenta: "$query".

Catálogo real y sincronizado disponible en el restaurante actualmente:
$menuSummary

Instrucciones:
1. Si el cliente pregunta qué es un platillo, qué tiene o cuál es su origen, explícaselo con detalle culinario mexicano, mencionando sus ingredientes reales y su historia gastronómica.
2. Si pide recomendación, sugiere opciones del menú disponible que se ajusten a su antojo, presupuesto o nivel de picante.
3. Habla en español con tono cálido, emojis mexicanos (🌮, 🌶️, 🔥, 🥑, 🧀) y sazón auténtico.
4. Al final de tu respuesta, en una línea EXACTA por separado, escribe:
IDs:[id1, id2]
(poniendo entre corchetes los IDs de los platillos que mencionaste o recomiendas, máximo 3).
''';

    final uri = Uri.parse('$_freeLlmEndpoint${Uri.encodeComponent(prompt)}?model=openai');
    final res = await http.get(uri);
    if (res.statusCode == 200 && res.body.isNotEmpty && !res.body.contains('budget') && !res.body.contains('error')) {
      final text = res.body.trim();
      final idRegex = RegExp(r'IDs:\s*\[(.*?)\]', caseSensitive: false);
      final match = idRegex.firstMatch(text);

      List<ProductEntity> matchedProducts = [];
      String cleanMessage = text;

      if (match != null) {
        final idListStr = match.group(1) ?? '';
        final ids = idListStr
            .split(',')
            .map((s) => s.trim().replaceAll("'", '').replaceAll('"', ''))
            .where((s) => s.isNotEmpty)
            .toList();

        matchedProducts = products.where((p) => ids.contains(p.id)).toList();
        cleanMessage = text.replaceAll(match.group(0)!, '').trim();
      }

      if (matchedProducts.isEmpty) {
        matchedProducts = _findRelevantProductsFromQuery(query, products);
      }

      if (cleanMessage.isNotEmpty) {
        return AiRecommendationResult(message: cleanMessage, products: matchedProducts);
      }
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🌮 MOTOR LOCAL DE CONOCIMIENTO Y RAZONAMIENTO GASTRONÓMICO
  // ═══════════════════════════════════════════════════════════════════════════
  AiRecommendationResult _localGastronomicReasoning(
    String rawQuery,
    String greetingName,
    List<ProductEntity> catalog,
  ) {
    final q = rawQuery.toLowerCase().trim();

    // ─── A. Saludo casual ──────────────────────────────────────────────────
    if (RegExp(r'^(hola|buenas|hey|buen d|que tal|quiubo|ola|menu|menú|carta)').hasMatch(q) && q.length < 25) {
      final featured = catalog.where((p) => p.spicyLevel > 0).take(3).toList();
      return AiRecommendationResult(
        message: '¡Hola$greetingName! 🔥 Soy **La Diabla IA** 🌶️, tu chef y guía gastronómica personal.\n\n'
            'Tengo todo el menú sincronizado al segundo con nuestra cocina: sé qué lleva cada platillo, sus ingredientes secretos, su historia tradicional mexicana y qué marida mejor con tu antojo.\n\n'
            '¿Qué se te antoja hoy? Puedes preguntarme "¿Qué es la Birria?", "¿Qué tiene la Gringa?", pedirme algo sin picante o decirme tu presupuesto y te armo el pedido ideal. 🌮✨',
        products: featured.isNotEmpty ? featured : catalog.take(3).toList(),
      );
    }

    // ─── B. Detección de platillo específico en el catálogo ────────────────
    final specificProduct = _matchSpecificProduct(q, catalog);
    if (specificProduct != null) {
      return _generateProductSpecificAnswer(q, specificProduct, greetingName);
    }

    // ─── C. Preguntas de origen gastronómico general ──────────────────────
    if (q.contains('origen') || q.contains('historia') || q.contains('de donde viene') || q.contains('tradicion') || q.contains('tradición')) {
      final found = _findProductsByCategoryOrKeywords(q, catalog);
      final p = found.isNotEmpty ? found.first : catalog.first;
      final originText = _getDishOrigin(p);
      return AiRecommendationResult(
        message: '📜 **Historia & Origen Tradicional Mexicano:**\n\n'
            '$originText\n\n'
            'En **La Diabla** respetamos esta receta tradicional preparándola al momento con ingredientes frescos y el toque ardiente de nuestra cocina. ¡Pruébalo aquí abajo! 👇',
        products: [p],
      );
    }

    // ─── D. Preguntas sobre qué es o qué tiene ──────────────────────────────
    final isAskingWhatIs = q.contains('que es') || q.contains('qué es') || q.contains('como es') || q.contains('cómo es');
    final isAskingIngredients = q.contains('que tiene') || q.contains('qué tiene') || q.contains('ingredientes') || q.contains('que lleva') || q.contains('qué lleva');

    if (isAskingWhatIs || isAskingIngredients) {
      final found = _findProductsByCategoryOrKeywords(q, catalog);
      if (found.isNotEmpty) {
        final p = found.first;
        return _generateProductSpecificAnswer(q, p, greetingName);
      }
    }

    // ─── E. Búsqueda y Recomendación Semántica Multivariable ───────────────
    return _filterAndRankCatalog(q, greetingName, catalog);
  }

  ProductEntity? _matchSpecificProduct(String q, List<ProductEntity> catalog) {
    for (final p in catalog) {
      final nameLower = p.name.toLowerCase();
      // Búsqueda por nombre completo o palabras clave significativas
      if (q.contains(nameLower)) return p;

      final pWords = nameLower
          .replaceAll(RegExp(r'[^a-záéíóúñ0-9\s]'), '')
          .split(' ')
          .where((w) => w.length > 3 && !['taco', 'tacos', 'especial', 'diabla', 'prueba'].contains(w));

      for (final w in pWords) {
        if (q.contains(w)) return p;
      }
    }
    return null;
  }

  AiRecommendationResult _generateProductSpecificAnswer(
    String q,
    ProductEntity p,
    String greetingName,
  ) {
    final spicyDesc = switch (p.spicyLevel) {
      0 => 'Cero picante (suave y amigable para todo público) 🥑',
      1 => 'Picante Suave 🌶️ (toque sabroso sin abrumar)',
      2 => 'Picante Medio 🌶️🌶️ (sabor mexicano auténtico con buen picor)',
      3 => 'FUEGO LA DIABLA 🔥 (solo para valientes)',
      _ => 'Equilibrado',
    };

    final ingredientsList = p.ingredients.isNotEmpty
        ? p.ingredients.map((i) => '• $i').join('\n')
        : '• Preparación artesanal fresca de la casa con especias mexicanas y tortillas calientes';

    final originStory = _getDishOrigin(p);

    // 1. Pregunta sobre Origen / Historia
    if (q.contains('origen') || q.contains('historia') || q.contains('de donde') || q.contains('de dónde') || q.contains('raiz') || q.contains('raíz')) {
      return AiRecommendationResult(
        message: '🇲🇽 **Origen & Tradición de ${p.name}:**\n\n'
            '$originStory\n\n'
            '🌶️ **Nivel de Picante:** $spicyDesc\n'
            '💰 **Precio:** \$${p.price.toInt()} COP\n\n'
            '¿Te gustaría probarlo hoy$greetingName? Puedes tocar "Agregar" aquí abajo:',
        products: [p],
      );
    }

    // 2. Pregunta sobre Ingredientes / Qué tiene
    if (q.contains('que tiene') || q.contains('qué tiene') || q.contains('ingrediente') || q.contains('lleva') || q.contains('viene con')) {
      return AiRecommendationResult(
        message: '🌮 **${p.name} — Ingredientes & Preparación:**\n\n'
            'Este platillo contiene:\n$ingredientsList\n\n'
            '🌶️ **Picante:** $spicyDesc\n'
            '📝 **Descripción:** ${p.description}\n'
            '💰 **Valor:** \$${p.price.toInt()} COP\n\n'
            '¡Sale recién hecho de la plancha para ti!',
        products: [p],
      );
    }

    // 3. Pregunta de ¿Qué es?
    return AiRecommendationResult(
      message: '✨ **${p.name}:**\n\n'
          '${p.description}\n\n'
          '📋 **Ingredientes:** ${p.ingredients.isNotEmpty ? p.ingredients.join(", ") : "Receta de la casa"}.\n'
          '🌶️ **Picor:** $spicyDesc\n'
          '📜 **Origen:** $originStory\n'
          '💰 **Precio:** \$${p.price.toInt()} COP',
      products: [p],
    );
  }

  String _getDishOrigin(ProductEntity p) {
    if (p.origin != null && p.origin!.trim().isNotEmpty) {
      return p.origin!.trim();
    }

    final lower = '${p.name} ${p.categoryId}'.toLowerCase();

    if (lower.contains('pastor')) {
      return 'Nacidos en Puebla y la Ciudad de México en la década de 1960. Inspirados en la técnica del trompo vertical traída por inmigrantes libaneses, adaptada magistralmente con carne de cerdo en adobo tradicional de achiote, especias mexicanas y la icónica piña caramelizada al asador.';
    }
    if (lower.contains('birria')) {
      return 'Joya culinaria del estado de Jalisco (Cocula y Guadalajara). Tradicionalmente cocinada a fuego lento en un adobo aromático de chiles secos (guajillo y ancho) con hierbas de olor. Se acompaña con su consomé caliente para sopear y queso fundido con costra dorada.';
    }
    if (lower.contains('suadero')) {
      return 'El rey indiscutible de las taquerías callejeras de la Ciudad de México. Es un corte de res tierno y suave que se confita lentamente en el centro cóncavo del comal en sus propios jugos, logrando una textura crujiente por fuera y jugosa por dentro.';
    }
    if (lower.contains('burrito')) {
      return 'Originario de la frontera norte de México en Ciudad Juárez, Chihuahua, durante la época de la Revolución Mexicana. El comerciante Juan Méndez los envolvía en grandes tortillas de trigo para mantenerlos calientes y los transportaba en burro, dándoles su famoso nombre.';
    }
    if (lower.contains('gringa')) {
      return 'Creadas en los años 70 en la Ciudad de México, cuando dos estudiantes estadounidenses pidieron su carne al pastor servida en tortillas de harina con doble queso fundido en lugar de tortillas de maíz.';
    }
    if (lower.contains('gobernador') || lower.contains('camaron') || lower.contains('camarón') || lower.contains('marisco')) {
      return 'Tradición de las costas del Pacífico (Mazatlán, Sinaloa y Nayarit). Los Tacos Gobernador nacieron en 1990 combinando camarones frescos salteados con pimientos, cebolla y queso derretido a la plancha.';
    }
    if (lower.contains('nacho') || lower.contains('totopo')) {
      return 'Inventados en 1940 en Piedras Negras, Coahuila, por el mayordomo Ignacio "Nacho" Anaya, quien frió tortillas en triángulos, las cubrió con queso fundido y rodajas de jalapeño encurtido.';
    }
    if (lower.contains('quesadilla') || lower.contains('queso')) {
      return 'Pilar fundamental de la cocina mexicana desde tiempos virreinales, doblando tortillas calientes con abundante queso derretido en comal.';
    }
    if (lower.contains('churro')) {
      return 'Tradición repostera popularizada en las churrerías del centro histórico de México, fritos al instante y espolvoreados con azúcar y canela, acompañados de arequipe o chocolate.';
    }

    return 'Receta emblemática inspirada en la auténtica gastronomía mexicana, preparada con técnicas tradicionales, marinados en chiles secos y sazón de la cocina de La Diabla.';
  }

  AiRecommendationResult _filterAndRankCatalog(
    String q,
    String greetingName,
    List<ProductEntity> products,
  ) {
    // 1. Presupuesto
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

    // 2. Picante
    final prefersMild = q.contains('no pique') || q.contains('sin picante') || q.contains('no pica') || q.contains('suave') || q.contains('cero picante');
    final prefersExtraSpicy = q.contains('muy picante') || q.contains('bien picante') || q.contains('lo mas picante') || q.contains('lo más picante') || q.contains('diablo') || q.contains('fuego');

    // 3. Ingredientes y Categorías
    final wantsCheese = q.contains('queso') || q.contains('derretido') || q.contains('fundido') || q.contains('quesadilla') || q.contains('gringa');
    final wantsBirria = q.contains('birria') || q.contains('consome') || q.contains('consomé') || q.contains('sopear');
    final wantsSeafood = q.contains('marisco') || q.contains('camaron') || q.contains('camarón') || q.contains('pescado');
    final wantsMeat = q.contains('carne') || q.contains('pastor') || q.contains('suadero') || q.contains('res') || q.contains('asada');
    final wantsDrinkDessert = q.contains('postre') || q.contains('dulce') || q.contains('churro') || q.contains('bebida') || q.contains('tomar') || q.contains('gaseosa') || q.contains('coca');

    // 4. Ocasión
    final isForTwo = q.contains('para dos') || q.contains('para 2') || q.contains('pareja') || q.contains('compartir') || q.contains('amigos');
    final isVeryHungry = q.contains('mucha hambre') || q.contains('hambre') || q.contains('llenador') || q.contains('grande') || q.contains('gigante');

    final scored = products.map((p) {
      double score = 0;
      final desc = '${p.name} ${p.description} ${p.ingredients.join(" ")} ${p.categoryId}'.toLowerCase();

      // Filtro de presupuesto
      if (maxBudget != null) {
        if (p.price <= maxBudget) {
          score += 25;
        } else {
          score -= 30;
        }
      }

      // Picante
      if (prefersMild) {
        if (p.spicyLevel == 0) score += 30;
        if (p.spicyLevel == 1) score += 15;
        if (p.spicyLevel >= 2) score -= 25;
      } else if (prefersExtraSpicy) {
        if (p.spicyLevel >= 2) score += 35;
        if (p.spicyLevel == 1) score += 5;
      }

      // Antojos
      if (wantsCheese && (desc.contains('queso') || p.categoryId == 'quesadillas')) score += 30;
      if (wantsBirria && desc.contains('birria')) score += 40;
      if (wantsSeafood && (desc.contains('camarón') || desc.contains('camaron') || p.categoryId == 'mariscos')) score += 35;
      if (wantsMeat && (desc.contains('pastor') || desc.contains('suadero') || desc.contains('carne') || desc.contains('res'))) score += 20;
      if (wantsDrinkDessert && (p.categoryId == 'postres' || p.categoryId == 'bebidas' || desc.contains('churro'))) score += 35;

      // Porción
      if (isForTwo && (p.categoryId == 'entradas' || desc.contains('nacho') || desc.contains('totopos') || p.price >= 25000)) score += 20;
      if (isVeryHungry && (p.categoryId == 'burritos' || desc.contains('gigante') || desc.contains('3 tacos'))) score += 25;

      return MapEntry(p, score);
    }).toList();

    scored.sort((a, b) => b.value.compareTo(a.value));
    final topList = scored.where((e) => e.value > 0).take(3).map((e) => e.key).toList();
    final finalProducts = topList.isNotEmpty ? topList : products.take(3).toList();

    String botText;
    if (wantsBirria) {
      botText = '¡Uff$greetingName, la birria es la reina indiscutible de La Diabla! 🌮🍲 Estos tacos vienen dorados a la plancha con queso fundido y consomé caliente para sopear cada bocado:';
    } else if (wantsCheese) {
      botText = '¡Para los amantes del queso como tú$greetingName! 🧀 Te seleccioné nuestras opciones con más queso fundido y costra doradita a la plancha:';
    } else if (wantsSeafood) {
      botText = '¡Sabor fresco de mar a tu mesa$greetingName! 🦐🌊 Con camarones salteados, aguacate y aderezo especial de la casa:';
    } else if (prefersMild) {
      botText = '¡Tranquilo$greetingName, cero enchiladas! 🥑✨ Te elegí opciones con todo el sabor mexicano pero sin picor fuerte para que comas tranquilo:';
    } else if (prefersExtraSpicy) {
      botText = '¡Eso es tener valentía$greetingName! 🔥🌶️ Aquí tienes el verdadero fuego de La Diabla con salsas habaneras y toreados que te harán vibrar de sabor:';
    } else if (maxBudget != null) {
      botText = '¡Cuidando el bolsillo como se debe$greetingName! 💰 Te armé esta selección deliciosa y llenadora por menos de \$${maxBudget.toInt()} COP:';
    } else if (isForTwo) {
      botText = '¡Plan perfecto en pareja o amigos$greetingName! 👫🌮 Porciones generosas e ideales para picar y compartir al centro:';
    } else {
      botText = '¡Te tengo justo lo que buscas$greetingName! 🌮🔥 Revisé nuestro menú en cocina y estos platillos son exactamente lo que necesitas para calmar ese antojo hoy:';
    }

    return AiRecommendationResult(message: botText, products: finalProducts);
  }

  List<ProductEntity> _findProductsByCategoryOrKeywords(String q, List<ProductEntity> catalog) {
    return catalog.where((p) {
      final text = '${p.name} ${p.description} ${p.categoryId}'.toLowerCase();
      if (q.contains('birria') && text.contains('birria')) return true;
      if (q.contains('pastor') && text.contains('pastor')) return true;
      if (q.contains('suadero') && text.contains('suadero')) return true;
      if (q.contains('taco') && p.categoryId == 'tacos') return true;
      if (q.contains('burrito') && p.categoryId == 'burritos') return true;
      if (q.contains('quesadilla') && p.categoryId == 'quesadillas') return true;
      if (q.contains('nacho') && text.contains('nacho')) return true;
      if (q.contains('gringa') && text.contains('gringa')) return true;
      if (q.contains('churro') && text.contains('churro')) return true;
      return false;
    }).toList();
  }

  List<ProductEntity> _findRelevantProductsFromQuery(String query, List<ProductEntity> catalog) {
    final q = query.toLowerCase();
    final matched = _findProductsByCategoryOrKeywords(q, catalog);
    return matched.isNotEmpty ? matched.take(3).toList() : catalog.take(2).toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🎧 2. ASISTENTE DE SOPORTE AL CLIENTE INTELIGENTE Y ACTUALIZADO
  // ═══════════════════════════════════════════════════════════════════════════
  Future<String> getSupportResponse({
    required String query,
    String? orderId,
    OrderEntity? order,
  }) async {
    final q = query.trim().toLowerCase();
    final shortId = (orderId != null && orderId.length > 6)
        ? orderId.substring(orderId.length - 6).toUpperCase()
        : (orderId ?? '');

    final status = order?.status;
    final isDelivered = status == OrderStatus.delivered;
    final isOnTheWay = status == OrderStatus.onTheWay;
    final isPreparing = status == OrderStatus.preparing || status == OrderStatus.confirmed;

    // 1. Demoras y Tiempos de Entrega
    if (q.contains('demor') || q.contains('tard') || q.contains('cuanto falta') || q.contains('cuánto falta') || q.contains('donde viene') || q.contains('dónde viene') || q.contains('no llega') || q.contains('tiempo')) {
      if (shortId.isNotEmpty) {
        if (isDelivered) {
          return '🛵 **Tu pedido #$shortId figura como ENTREGADO:**\n\n'
              'Nuestro sistema registra que el repartidor finalizó la entrega en tu dirección. Si no lo has recibido personalmente, por favor verifica en portería o recepción del edificio.\n\n'
              'Si aún no lo tienes, presiona el botón de WhatsApp abajo para comunicarte con nuestro equipo en tiempo real.';
        }
        if (isOnTheWay) {
          return '🛵 **Tu pedido #$shortId va en camino:**\n\n'
              'El repartidor ya retiró tus platillos de la cocina y se desplaza hacia tu ubicación con empaque térmico especial.\n\n'
              '⏱️ **Tiempo estimado:** 5 a 12 minutos. Puedes seguir el mapa GPS en tiempo real en la pantalla de seguimiento.';
        }
        if (isPreparing) {
          return '👨‍🍳 **Tu pedido #$shortId está en el fuego en cocina:**\n\n'
              'Nuestros cocineros están horneando y empacando todo fresco. Apenas quede empacado, el repartidor iniciará el recorrido de inmediato.\n\n'
              '⏱️ **Tiempo estimado para despacho:** 8 a 15 minutos.';
        }
      }
      return '🛵 **Tiempos de Entrega & Domicilios La Diabla:**\n\n'
          '• **Tiempo promedio estándar:** 30 a 45 minutos en el área metropolitana de Bucaramanga, Floridablanca, Cañaveral y Girón.\n'
          '• Si tu pedido ya está confirmado, puedes ver el estado exacto en la sección de **"Mis Pedidos"** o rastrear la moto en el mapa GPS.\n\n'
          '¿Tienes un número de pedido o deseas asistencia directa con el supervisor de turno? Pulsa el botón de WhatsApp abajo.';
    }

    // 2. Cobros, Bancos, Tarjetas, Nequi y Daviplata
    if (q.contains('cobro') || q.contains('tarjeta') || q.contains('doble') || q.contains('banco') || q.contains('nequi') || q.contains('daviplata') || q.contains('dinero') || q.contains('plata') || q.contains('pago')) {
      return '💳 **Aclaración sobre Cobros y Pasarelas de Pago:**\n\n'
          '• **¿Ves dos movimientos en tu banco o app bancaria?** Las entidades financieras en Colombia generan una *retención previa de fondos* al presionar pagar y luego procesan el cobro definitivo. La retención se libera y anula automáticamente en un plazo de **24 a 48 horas hábiles**.\n'
          '• En La Diabla confirmamos que únicamente se efectúa **un solo cobro real** por cada pedido confirmado.\n\n'
          '• **Métodos aceptados:** Tarjetas de Crédito/Débito (Visa, Mastercard), Nequi, Daviplata, PSE, Addi (pago a cuotas) y Efectivo contra entrega.\n\n'
          'Si necesitas un comprobante oficial de pago para tu banco, presiona el botón de WhatsApp y te lo enviamos en minutos.';
    }

    // 3. Comida Incompleta, Fría o Equivocada (Garantía Diabla)
    if (q.contains('incomplet') || q.contains('equivocad') || q.contains('falto') || q.contains('faltó') || q.contains('fria') || q.contains('fría') || q.contains('mal') || q.contains('dañad') || q.contains('queja')) {
      return '📦 **Garantía Total La Diabla — Solución Inmediata:**\n\n'
          '¡Lamentamos profundamente cualquier novedad ${shortId.isNotEmpty ? "con tu pedido #$shortId" : "con tu pedido"}! En La Diabla la calidad de la comida es sagrada y te ofrecemos 2 soluciones inmediatas:\n\n'
          '1️⃣ **Reenvío prioritario express** del platillo correcto o faltante sin costo alguno.\n'
          '2️⃣ **Reembolso inmediato** del valor del producto a tu medio de pago o saldo en billetera.\n\n'
          'Por favor pulsa el botón de WhatsApp abajo y envíanos una foto del paquete para que el supervisor te lo resuelva al instante.';
    }

    // 4. Cancelaciones y Reembolsos
    if (q.contains('cancel') || q.contains('reembolso') || q.contains('devolu')) {
      return '🚫 **Políticas de Cancelación y Reembolso:**\n\n'
          '• **Si el pedido está pendiente o recién confirmado:** Se puede cancelar inmediatamente y el dinero se reintegra al 100% por el mismo canal (Nequi, Daviplata, PSE o Tarjeta).\n'
          '• **Si el pedido ya está en cocción o en camino:** Por normas de alimentos preparados no se puede cancelar el envío en ruta, salvo que presente demora injustificada.\n\n'
          'Para solicitar la anulación inmediata de un pedido en proceso, toca el botón de WhatsApp para que cocina detenga el despacho.';
    }

    // 5. Cambio de Dirección, Teléfono o Datos de Entrega
    if (q.contains('direccion') || q.contains('dirección') || q.contains('cambiar') || q.contains('telefono') || q.contains('celular') || q.contains('apartamento') || q.contains('torre') || q.contains('porteria') || q.contains('portería')) {
      return '📍 **Actualización de Dirección o Teléfono:**\n\n'
          'Podemos actualizar la dirección o darle indicaciones adicionales al repartidor (como torre, apartamento o dejar en portería) siempre que esté dentro de nuestra zona de cobertura en Bucaramanga y su área metropolitana.\n\n'
          'Escríbenos directamente por WhatsApp con la nueva información para notificar al domiciliario de inmediato.';
    }

    // 6. Horarios y Ubicación del Restaurante
    if (q.contains('horario') || q.contains('abren') || q.contains('cierran') || q.contains('abierto') || q.contains('donde estan') || q.contains('dónde están') || q.contains('ubicacion') || q.contains('ubicación')) {
      return '🕒 **Horarios & Cobertura de La Diabla:**\n\n'
          '• **Horario de atención:** Lunes a Domingo de **11:30 AM a 10:30 PM** en jornada continua.\n'
          '• **Cobertura de Domicilios:** Bucaramanga (Cabecera, Centro, Provenza, San Francisco, Ciudadela), Floridablanca, Cañaveral y Girón.\n'
          '• Todos los pedidos van empacados en recipientes térmicos sellados para mantener la temperatura y frescura.';
    }

    // 7. Saludo General o Respuesta Asertiva
    final orderReference = shortId.isNotEmpty ? ' para tu pedido **#$shortId**' : '';
    return '👋 ¡Hola! Soy tu **Asistente de Soporte La Diabla**$orderReference.\n\n'
        'Estoy capacitado para ayudarte con:\n'
        '• Rastrear el estado de tu pedido y tiempos de llegada 🛵\n'
        '• Resolver dudas sobre cobros en tarjeta, Nequi o Daviplata 💳\n'
        '• Gestionar garantías si tu comida llegó incompleta o fría 📦\n'
        '• Actualizar direcciones, teléfonos o cancelaciones 📍\n\n'
        '¿Deseas atención personalizada con nuestro supervisor de turno? Pulsa el botón de WhatsApp abajo y te atenderemos con gusto.';
  }
}
