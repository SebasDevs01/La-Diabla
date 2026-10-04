// lib/core/services/ai_assistant_service.dart

import 'dart:convert';
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

  static const String _cloudFunctionsEndpoint =
      'https://us-central1-ladiabla-11718.cloudfunctions.net/askDiablaAi';

  // ═══════════════════════════════════════════════════════════════════════════
  // 🌮 1. LA DIABLA IA — CHEF Y ASESOR GASTRONÓMICO EN VIVO
  // ═══════════════════════════════════════════════════════════════════════════
  Future<AiRecommendationResult> getFoodRecommendation({
    required String query,
    String userName = '',
    List<ProductEntity>? catalog,
    List<Map<String, String>>? history,
  }) async {
    final liveCatalog = (catalog != null && catalog.isNotEmpty)
        ? catalog.where((p) => p.available).toList()
        : mockProducts.where((p) => p.available).toList();

    final cleanQuery = query.trim();
    final greetingName = userName.isNotEmpty ? ' $userName' : '';

    // 1. Intentar consultar Cloud Functions (Backend Seguro) o Gemini Directo
    try {
      final aiResponse = await _fetchAiChefRecommendation(
        query: cleanQuery,
        userName: userName,
        greetingName: greetingName,
        catalog: liveCatalog,
        history: history,
      ).timeout(const Duration(milliseconds: 15000));

      if (aiResponse != null && aiResponse.message.trim().isNotEmpty) {
        return aiResponse;
      }
    } catch (e) {
      debugPrint('ℹ️ La Diabla IA: usando motor de conocimiento gastronómico local sincronizado ($e)');
    }

    // 2. Fallback al motor local gastronómico si falla la conexión
    return _localGastronomicReasoning(cleanQuery, greetingName, liveCatalog);
  }

  Future<AiRecommendationResult?> _fetchAiChefRecommendation({
    required String query,
    required String userName,
    required String greetingName,
    required List<ProductEntity> catalog,
    List<Map<String, String>>? history,
  }) async {
    // ── Nivel 1: Firebase Cloud Function ──
    try {
      final catalogPayload = catalog.take(25).map((p) => {
        'id': p.id,
        'name': p.name,
        'price': p.price,
        'categoryId': p.categoryId,
        'spicyLevel': p.spicyLevel,
        'ingredients': p.ingredients,
      }).toList();

      final res = await http.post(
        Uri.parse(_cloudFunctionsEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'type': 'chef',
          'query': query,
          'userName': userName,
          'history': history ?? [],
          'catalog': catalogPayload,
        }),
      ).timeout(const Duration(milliseconds: 14000));

      if (res.statusCode == 200 && res.body.isNotEmpty) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['message'] != null) {
          final message = data['message'].toString().trim();
          List<ProductEntity> matchedProducts = [];
          if (data['productIds'] is List) {
            final List ids = data['productIds'];
            matchedProducts = catalog.where((p) => ids.contains(p.id)).toList();
          }
          if (matchedProducts.isEmpty) {
            matchedProducts = _findRelevantProductsFromQuery(query, catalog);
          }
          return AiRecommendationResult(message: message, products: matchedProducts);
        }
      }
    } catch (cfErr) {
      debugPrint('ℹ️ Cloud Function chef fallback a motor local: $cfErr');
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

    // ─── 0. Desarrollador / Creador ─────────────────────────────────────────
    if (q.contains('desarrollador') || q.contains('programador') || q.contains('quien hizo') || q.contains('quién hizo') || q.contains('creador') || q.contains('sebas')) {
      return const AiRecommendationResult(
        message: '¡Toda la tecnología y la app de **La Diabla** fue desarrollada y diseñada por **Sebastián (SebasDevs / @SebasDevs01)**! 👨‍💻🔥\n\nEs nuestro desarrollador estrella que hace que tus pedidos lleguen volando a tu puerta.',
        products: [],
      );
    }

    // ─── 0.1 Bebidas / Productos no disponibles ────────────────────────────
    if (q.contains('bebida') || q.contains('gaseosa') || q.contains('refresco') || q.contains('tomar') || q.contains('jugo') || q.contains('cerveza')) {
      final tacos = catalog.where((p) => p.name.toLowerCase().contains('taco') || p.name.toLowerCase().contains('birria')).take(2).toList();
      return AiRecommendationResult(
        message: 'Por ahora en nuestra cocina nos enfocamos 100% en los tacos y platillos mexicanos calientes al comal 🔥\n\nNo tenemos bebidas en la carta en este momento, ¡pero te invito a probar nuestros tacos al pastor o birria que están brutales!',
        products: tacos,
      );
    }

    // ─── A. Saludo casual / Cómo vas ───────────────────────────────────────
    final isGreeting = q.length < 70 &&
        RegExp(r'(^hola|^buenas|^hey|^buen d|^que tal|^qu\u00e9 tal|^quiubo|^como vas|^c\u00f3mo vas|^que haces|^qu\u00e9 haces|^como est|^c\u00f3mo est|^que m\u00e1s|^que mas|^epa |^khe|^ *hi *$|^holis)').hasMatch(q);
    if (isGreeting) {
      final featured = catalog.where((p) => p.spicyLevel > 0).take(2).toList();
      return AiRecommendationResult(
        message: '¡Hola$greetingName! 🔥 Aquí con los comales prendidos y el sazón a mil en La Diabla 🌶️\n\n¿Qué antojito se te pasa por la mente hoy?',
        products: featured.isNotEmpty ? featured : catalog.take(2).toList(),
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

    // Si nada encaja bien, respuesta abierta con sugerencias del menú
    if (finalProducts.isEmpty) {
      return AiRecommendationResult(
        message: '¡Aquí contigo$greetingName! 🌶️ No tengo claro qué buscas exactamente, pero te puedo recomendar algo del menú o contarte lo que quieras sobre La Diabla. ¿Qué se te antoja?',
        products: catalog.take(2).toList(),
      );
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
    String userName = '',
    String? userId,
    List<Map<String, String>>? history,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return '¿En qué te podemos colaborar hoy?';

    // 1. Intentar consultar Cloud Functions (Backend Seguro)
    try {
      final aiResponse = await _fetchAiSupportResponse(
        query: cleanQuery,
        orderId: orderId,
        order: order,
        userName: userName,
        userId: userId,
        history: history,
      ).timeout(const Duration(milliseconds: 15000));

      if (aiResponse != null && aiResponse.trim().isNotEmpty) {
        return aiResponse.trim();
      }
    } catch (e) {
      debugPrint('ℹ️ Soporte IA fallback a motor local: $e');
    }

    // 2. Fallback al motor local si no hay conexión o falla la nube
    return _localSupportReasoning(cleanQuery, orderId, order);
  }

  Future<String?> _fetchAiSupportResponse({
    required String query,
    String? orderId,
    OrderEntity? order,
    String userName = '',
    String? userId,
    List<Map<String, String>>? history,
  }) async {
    // ── Nivel 1: Firebase Cloud Function (Consulta en vivo a Firestore) ──
    try {
      final res = await http.post(
        Uri.parse(_cloudFunctionsEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'type': 'support',
          'query': query,
          'userName': userName,
          'userId': userId,
          'orderId': orderId ?? order?.id,
          'history': history ?? [],
        }),
      ).timeout(const Duration(milliseconds: 14000));

      if (res.statusCode == 200 && res.body.isNotEmpty) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['message'] != null) {
          return data['message'].toString();
        }
      }
    } catch (cfErr) {
      debugPrint('ℹ️ Cloud Function soporte fallback a motor local: $cfErr');
    }
    return null;
  }

  String _localSupportReasoning(
    String query,
    String? orderId,
    OrderEntity? order,
  ) {
    final q = query.toLowerCase();
    final shortId = (orderId != null && orderId.length > 6)
        ? orderId.substring(orderId.length - 6).toUpperCase()
        : (orderId ?? '');

    // ── 0. Preguntas sobre el desarrollador ──
    if (q.contains('desarrollador') || q.contains('programador') || q.contains('quien hizo') || q.contains('quién hizo') || q.contains('creador') || q.contains('sebas')) {
      return '¡Hola! La app y plataforma digital de **La Diabla** fue desarrollada y diseñada por **Sebastián (SebasDevs / @SebasDevs01)**, nuestro desarrollador de software 🚀';
    }

    // ── 0.1 Consulta de último pedido o repartidor ──
    if (q.contains('ultimo pedido') || q.contains('último pedido') || q.contains('resumen') || q.contains('quien me entrego') || q.contains('quién me entregó') || q.contains('repartidor')) {
      if (order != null) {
        final itemsStr = order.items.map((i) => '${i.quantity}x ${i.product.name}').join(', ');
        final driver = order.driverName ?? (order.driverId != null ? 'Conductor asignado' : 'Sin repartidor asignado');
        return '📋 **Resumen de tu pedido #${order.id.length > 6 ? order.id.substring(order.id.length - 6).toUpperCase() : order.id}:**\n'
            '• **Platillos:** $itemsStr\n'
            '• **Total:** \$${order.total.toInt()} COP | **Estado:** ${order.status.name}\n'
            '• **Repartidor:** $driver 🛵';
      }
      return 'Para ver el resumen de tu último pedido y el repartidor asignado, puedes consultarlo directamente en la pestaña **"Mis Pedidos"** o escribirnos a WhatsApp si necesitas ayuda inmediata.';
    }

    // ── 0.2 Saludos casuales / Cómo vas ──
    if (RegExp(r'^(hola|buenas|hey|buen d|que tal|quiubo|ola|como vas|cómo vas|como estas|cómo estás)').hasMatch(q) && q.length < 35) {
      return '¡Hola! Todo excelente por acá en La Diabla 🌶️ ¿En qué te podemos colaborar hoy con tus pedidos o entregas?';
    }

    final status = order?.status;
    final isDelivered = status == OrderStatus.delivered;
    final isOnTheWay = status == OrderStatus.onTheWay;
    final isPreparing = status == OrderStatus.preparing || status == OrderStatus.confirmed;

    // 1. Demoras y Tiempos de Entrega
    if (q.contains('demor') || q.contains('tard') || q.contains('cuanto falta') || q.contains('cuánto falta') || q.contains('donde viene') || q.contains('dónde viene') || q.contains('no llega') || q.contains('tiempo')) {
      if (shortId.isNotEmpty) {
        if (isDelivered) {
          return '🛵 **Tu pedido #$shortId figura como ENTREGADO:**\n'
              'Si no lo has recibido personalmente, por favor verifica en portería o recepción. Si necesitas soporte, pulsa WhatsApp abajo.';
        }
        if (isOnTheWay) {
          return '🛵 **Tu pedido #$shortId va en camino:**\n'
              'El repartidor se desplaza hacia tu dirección con maletín térmico. Tiempo estimado: 5 a 12 minutos.';
        }
        if (isPreparing) {
          return '👨‍🍳 **Tu pedido #$shortId está en preparación en cocina:**\n'
              'Nuestros cocineros lo están alistando fresco. Despacho estimado en 8 a 15 minutos.';
        }
      }
      return '🛵 **Tiempos de entrega:** En promedio de 30 a 45 minutos en Bucaramanga y área metropolitana. Puedes ver el estado exacto en "Mis Pedidos" o pulsar WhatsApp para hablar con un asesor.';
    }

    // 2. Cobros, Bancos, Tarjetas, Nequi y Daviplata
    if (q.contains('cobro') || q.contains('tarjeta') || q.contains('doble') || q.contains('banco') || q.contains('nequi') || q.contains('daviplata') || q.contains('dinero') || q.contains('plata') || q.contains('pago')) {
      return '💳 **Aclaración sobre cobros bancarios:**\n'
          'Los bancos en Colombia generan una retención temporal previa que se libera en 24-48h hábiles. En La Diabla nunca realizamos cobros dobles reales. Si necesitas comprobante, pulsa WhatsApp abajo.';
    }

    // 3. Comida Incompleta, Fría o Equivocada (Garantía Diabla)
    if (q.contains('incomplet') || q.contains('equivocad') || q.contains('falto') || q.contains('faltó') || q.contains('fria') || q.contains('fría') || q.contains('mal') || q.contains('dañad') || q.contains('queja')) {
      return '📦 **Garantía Total La Diabla:**\n'
          '¡Lamentamos cualquier inconveniente! Te ofrecemos reenvío prioritario inmediato o reembolso. Pulsa el botón de WhatsApp abajo con una foto para resolverlo al instante.';
    }

    // 4. Cancelaciones y Reembolsos
    if (q.contains('cancel') || q.contains('reembolso') || q.contains('devolu')) {
      return '🚫 **Cancelaciones y Reembolsos:**\n'
          'Si tu pedido está recién hecho y aún no entra a cocción, podemos cancelarlo y reintegrar el 100%. Toca el botón de WhatsApp abajo para que cocina detenga el despacho de inmediato.';
    }

    // 5. Cambio de Dirección, Teléfono o Datos de Entrega
    if (q.contains('direccion') || q.contains('dirección') || q.contains('cambiar') || q.contains('telefono') || q.contains('celular') || q.contains('apartamento') || q.contains('torre') || q.contains('porteria') || q.contains('portería')) {
      return '📍 **Actualización de datos:**\n'
          'Podemos actualizar dirección o indicaciones de portería/torre dentro de nuestra zona de cobertura. Escríbenos por WhatsApp con los nuevos datos para avisar al repartidor.';
    }

    // 6. Horarios y Ubicación
    if (q.contains('horario') || q.contains('abren') || q.contains('cierran') || q.contains('abierto') || q.contains('donde estan') || q.contains('dónde están') || q.contains('ubicacion') || q.contains('ubicación')) {
      return '🕒 **Horarios La Diabla:**\n'
          'Atendemos de Lunes a Domingo de **11:30 AM a 10:30 PM** en jornada continua en Bucaramanga, Floridablanca, Cañaveral y Girón.';
    }

    // 7. Respuesta abierta por defecto — no genérica
    if (shortId.isNotEmpty) {
      return '¡Hola${ userName.isNotEmpty ? " $userName" : ""}! 🌶️ Estoy aquí para ayudarte con tu pedido #$shortId o cualquier duda que tengas. ¿Qué necesitas?';
    }
    return '¡Hola! Soy Sofía de La Diabla 🌶️ ¿En qué te ayudo hoy? Puedo decirte el estado de tu pedido, resolver dudas sobre pagos o entregas, lo que necesites.';
  }
}
