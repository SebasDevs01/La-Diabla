// lib/features/assistant/presentation/screens/diabla_assistant_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/utils/price_formatter.dart';
import '../../../../domain/entities/product_entity.dart';
import '../../../../mock/mock_products.dart';
import '../../../auth/providers/auth_notifier.dart';
import '../../../cart/providers/cart_notifier.dart';

class DiablaAssistantSheet extends ConsumerStatefulWidget {
  const DiablaAssistantSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const DiablaAssistantSheet(),
    );
  }

  @override
  ConsumerState<DiablaAssistantSheet> createState() => _DiablaAssistantSheetState();
}

class _ChatMessage {
  _ChatMessage({
    required this.isUser,
    required this.text,
    this.recommendedProducts,
  });

  final bool isUser;
  final String text;
  final List<ProductEntity>? recommendedProducts;
}

class _DiablaAssistantSheetState extends ConsumerState<DiablaAssistantSheet> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _isTyping = false;
  String _userName = '';

  final List<String> _quickPrompts = [
    '🌮 ¡Tengo mucha hambre!',
    '🦐 ¿Qué mariscos tienen?',
    '🌶️ Algo no tan picante',
    '🔥 ¿Cuál es el más picante?',
    '💰 ¿Qué es lo más barato?',
    '🎁 ¿Hay promociones hoy?',
    '🥤 ¿Qué bebidas y postres hay?',
  ];

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    final authUser = ref.read(authNotifierProvider).user;
    String name = authUser?.name.trim() ?? '';
    if (name.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      name = prefs.getString('user_registered_name') ?? '';
    }
    if (name.isNotEmpty) {
      name = name.split(' ').first;
      name = name[0].toUpperCase() + name.substring(1);
    }

    if (mounted) {
      setState(() {
        _userName = name;
        _messages.add(
          _ChatMessage(
            isUser: false,
            text: _userName.isNotEmpty
                ? '¡Hola $_userName! 🔥 Soy **La Diabla IA** 🌶️\n\nTu chef y asistente personal de **La Diabla**. Cuéntame qué se te antoja, tus ingredientes favoritos o tu presupuesto y te armo el pedido ideal con todo nuestro menú.'
                : '¡Hola! 🔥 Soy **La Diabla IA** 🌶️\n\nTu chef y asistente personal de **La Diabla**. Cuéntame qué se te antoja, tus ingredientes favoritos o tu presupuesto y te armo el pedido ideal con todo nuestro menú.',
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage(String userText) {
    if (userText.trim().isEmpty) return;

    setState(() {
      _messages.add(_ChatMessage(isUser: true, text: userText.trim()));
      _isTyping = true;
    });
    _textController.clear();
    _scrollToBottom();

    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      final response = _generateBotResponse(userText.trim().toLowerCase());
      setState(() {
        _isTyping = false;
        _messages.add(response);
      });
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MOTOR DE INTELIGENCIA Y RECOMENDACIÓN DINÁMICA
  // ═══════════════════════════════════════════════════════════════════════════
  _ChatMessage _generateBotResponse(String query) {
    final nameGreeting = _userName.isNotEmpty ? ' $_userName' : '';
    final q = query.toLowerCase().trim();

    // ─── 1. SALUDOS Y CORTESÍA ────────────────────────────────────────────────
    if (q == 'hola' || q == 'hi' || q == 'hey' || q == 'ola' ||
        q.startsWith('hola') || q.startsWith('buenas') ||
        q.contains('buenos dias') || q.contains('buenas tardes') ||
        q.contains('buenas noches') || q.contains('buen dia')) {
      final samples = mockProducts.take(3).toList();
      return _ChatMessage(
        isUser: false,
        text: '¡Hola$nameGreeting! 🔥 ¡Bienvenido a **La Diabla**!\n\n'
            'Tengo todo el menú listo para ti: tacos al pastor y de birria, burritos gigantes, mariscos picantes, quesadillas, ensaladas frescas, postres y aguas artesanales. ¿Qué sabor o antojo tienes en mente hoy? 🌮🌶️',
        recommendedProducts: samples,
      );
    }

    // ─── 2. AGRADECIMIENTOS Y DESPEDIDAS ─────────────────────────────────────
    if (q.contains('gracias') || q.contains('muchas gracias') || q.contains('ok gracias') || q.contains('vale gracias') || q.contains('agradecido')) {
      return _ChatMessage(
        isUser: false,
        text: '¡Con muchísimo gusto$nameGreeting! 🌶️❤️ En **La Diabla** cocinamos con pura pasión mexicana. ¡Que disfrutes tu banquete!',
      );
    }
    if (q.contains('adios') || q.contains('adiós') || q.contains('chao') || q.contains('bye') || q.contains('hasta luego') || q.contains('nos vemos')) {
      return _ChatMessage(
        isUser: false,
        text: '¡Hasta pronto$nameGreeting! 🔥 ¡Te esperamos de vuelta cuando ese antojo diabólico ataque de nuevo! 🌮👋',
      );
    }

    // ─── 3. ¿QUIÉN ERES? / IDENTIDAD ──────────────────────────────────────────
    if (q.contains('quien eres') || q.contains('quién eres') ||
        q.contains('como te llamas') || q.contains('cómo te llamas') ||
        q.contains('que eres') || q.contains('qué eres') || q.contains('tu nombre')) {
      return _ChatMessage(
        isUser: false,
        text: '¡Mucho gusto$nameGreeting! Soy **La Diabla IA** 🌶️🔥, la asistente inteligente y chef virtual de **La Diabla Comida Mexicana**.\n\nPuedo analizar tus antojos, recomendarte platillos según tu nivel de picante, buscar combinaciones según tu presupuesto o sugerirte mariscos, tacos y postres. ¡Pregúntame lo que quieras!',
      );
    }

    // ─── 4. MARISCOS Y COCINA DE MAR ──────────────────────────────────────────
    if (q.contains('marisco') || q.contains('camaron') || q.contains('camarón') ||
        q.contains('pulpo') || q.contains('pescado') || q.contains('ceviche') ||
        q.contains('coctel') || q.contains('cóctel') || q.contains('aguachile') ||
        q.contains('levanta muertos') || q.contains('campechana')) {
      final seafood = mockProducts.where((p) => p.categoryId == 'mariscos').toList();
      return _ChatMessage(
        isUser: false,
        text: '¡Nuestra especialidad del Pacífico mexicano$nameGreeting! 🌊🦐\n\n'
            'En **La Diabla** tenemos mariscos frescos preparados con recetas tradicionales ardientes y suaves:\n\n'
            '🔥 **Camarones a la Diabla:** Salteados en salsa explosiva de 3 chiles.\n'
            '🧄 **Camarones al Ajo:** Mantequilla dorada y ajo crocante (0 picante).\n'
            '🥑 **Aguachile Sinaloense:** Camarones curtidos en limón y serrano.\n'
            '⚡ **Caldo Levanta Muertos:** Afrodisíaco con camarón, pulpo y pescado.',
        recommendedProducts: seafood.take(4).toList(),
      );
    }

    // ─── 5. TACOS ─────────────────────────────────────────────────────────────
    if (q.contains('taco') || q.contains('pastor') || q.contains('birria') || q.contains('suadero') || q.contains('carnitas')) {
      final tacos = mockProducts.where((p) => p.categoryId == 'tacos').toList();
      return _ChatMessage(
        isUser: false,
        text: '¡Los tacos de La Diabla son una obra de arte mexicana$nameGreeting! 🌮\n\n'
            'Cada orden incluye **3 tacos bien reportados** con doble tortilla de maíz, cilantro, cebolla y salsas artesanales:\n\n'
            '🥩 **Tacos al Pastor Diabla:** Marinados en achiote con piña asada.\n'
            '🥣 **Tacos de Birria:** Con queso Oaxaca fundido y consomé caliente para chopear.\n'
            '🥩 **Tacos de Suadero Especial:** Confitados a fuego lento y jugosos.',
        recommendedProducts: tacos.take(3).toList(),
      );
    }

    // ─── 6. BURRITOS ──────────────────────────────────────────────────────────
    if (q.contains('burrito') || q.contains('burritos')) {
      final burritos = mockProducts.where((p) => p.categoryId == 'burritos').toList();
      return _ChatMessage(
        isUser: false,
        text: '¡Burritos gigantes y monumentales$nameGreeting! 🌯\n\n'
            'Envueltos en tortilla de trigo extra grande y cargados de carne, arroz mexicano, frijoles refritos y queso derretido:',
        recommendedProducts: burritos.take(3).toList(),
      );
    }

    // ─── 7. QUESADILLAS Y GRINGAS ─────────────────────────────────────────────
    if (q.contains('quesadilla') || q.contains('gringa') || q.contains('quesabirria') || q.contains('queso')) {
      final quesos = mockProducts.where((p) => p.categoryId == 'quesadillas' || p.name.toLowerCase().contains('queso') || p.name.toLowerCase().contains('birria')).toList();
      return _ChatMessage(
        isUser: false,
        text: '¡Para los amantes del queso derretido y las costras doradas$nameGreeting! 🧀✨\n\n'
            'Nuestras quesadillas y gringas vienen cargadas de queso Oaxaca y el mejor sazón:',
        recommendedProducts: quesos.take(3).toList(),
      );
    }

    // ─── 8. BEBIDAS Y POSTRES ─────────────────────────────────────────────────
    if (q.contains('bebida') || q.contains('tomar') || q.contains('refresco') ||
        q.contains('agua') || q.contains('sed') || q.contains('drink') ||
        q.contains('jugo') || q.contains('horchata') || q.contains('jamaica') ||
        q.contains('postre') || q.contains('dulce') || q.contains('churro') || q.contains('cerveza')) {
      final drinksAndDesserts = mockProducts.where((p) => p.categoryId == 'bebidas' || p.categoryId == 'postres').toList();
      return _ChatMessage(
        isUser: false,
        text: '¡Para refrescarte o cerrar con broche de oro$nameGreeting! 🥤🍰\n\n'
            'Tenemos aguas frescas artesanales de **1 Litro**, refrescos mexicanos y postres tradicionales:',
        recommendedProducts: drinksAndDesserts.isNotEmpty ? drinksAndDesserts.take(4).toList() : mockProducts.take(3).toList(),
      );
    }

    // ─── 9. ENSALADAS Y OPCIONES LIGERAS / FITNESS ────────────────────────────
    if (q.contains('ensalada') || q.contains('ligero') || q.contains('fit') ||
        q.contains('saludable') || q.contains('dieta') || q.contains('vegetal') || q.contains('verde')) {
      final salads = mockProducts.where((p) => p.categoryId == 'ensaladas').toList();
      return _ChatMessage(
        isUser: false,
        text: '¡Opciones frescas, crujientes y deliciosas$nameGreeting! 🥗\n\n'
            'Nuestras ensaladas están preparadas al momento con proteína a la parrilla y aderezos de la casa:',
        recommendedProducts: salads.isNotEmpty ? salads.take(3).toList() : mockProducts.take(3).toList(),
      );
    }

    // ─── 10. SIN PICANTE O PICANTE SUAVE ──────────────────────────────────────
    final isNegativeSpice = q.contains('no') || q.contains('sin') || q.contains('poco') ||
        q.contains('nada') || q.contains('bajo') || q.contains('suave') ||
        q.contains('cero') || q.contains('menos') || q.contains('tranquil');

    if ((isNegativeSpice && (q.contains('pican') || q.contains('pique') || q.contains('chile') || q.contains('fuego') || q.contains('ardoso'))) ||
        q.contains('no picante') || q.contains('no tan picante') || q.contains('sin picante') || q.contains('que no pique') || q.contains('poco picante')) {
      final mild = mockProducts.where((p) => p.spicyLevel <= 1).toList();
      return _ChatMessage(
        isUser: false,
        text: '¡En **La Diabla** cuidamos tu paladar$nameGreeting! 🥑\n\n'
            'Aquí tienes opciones deliciosas con **cero o muy bajo picante** para disfrutar tranquilamente:',
        recommendedProducts: mild.take(4).toList(),
      );
    }

    // ─── 11. PICANTE EXTREMO / VALIENTES ──────────────────────────────────────
    if (q.contains('picant') || q.contains('pica') || q.contains('fuerte') ||
        q.contains('ardoso') || q.contains('fuego') || q.contains('chile') || q.contains('habanero') || q.contains('extremo')) {
      final spicy = mockProducts.where((p) => p.spicyLevel >= 2).toList();
      return _ChatMessage(
        isUser: false,
        text: '🔥🌶️ ¡Para los que no le temen al verdadero fuego mexicano$nameGreeting!\n\n'
            'Aquí tienes nuestros platillos con nivel de picante alto y salsas con habanero y chiles toreados:',
        recommendedProducts: spicy.take(4).toList(),
      );
    }

    // ─── 12. LO MÁS BARATO / ECONÓMICO ────────────────────────────────────────
    if (q.contains('barato') || q.contains('más barato') || q.contains('mas barato') ||
        q.contains('econom') || q.contains('económico') || q.contains('precio') ||
        q.contains('presupuesto') || q.contains('poco dinero') || q.contains('asequible')) {
      final cheap = List<ProductEntity>.from(mockProducts)..sort((a, b) => a.price.compareTo(b.price));
      return _ChatMessage(
        isUser: false,
        text: '¡En **La Diabla** disfrutas del auténtico sazón al mejor precio$nameGreeting! 💰\n\n'
            'Mira estos platillos súper rendidores y económicos:',
        recommendedProducts: cheap.take(4).toList(),
      );
    }

    // ─── 13. COMBOS Y COMPARTIR ───────────────────────────────────────────────
    if (q.contains('combo') || q.contains('pareja') || q.contains('amigos') ||
        q.contains('compartir') || q.contains('familia') || q.contains('para 2') ||
        q.contains('para dos') || q.contains('grupo')) {
      final comboItems = [
        mockProducts.firstWhere((p) => p.categoryId == 'nachos', orElse: () => mockProducts.first),
        mockProducts.firstWhere((p) => p.categoryId == 'tacos', orElse: () => mockProducts[1]),
        mockProducts.firstWhere((p) => p.categoryId == 'mariscos', orElse: () => mockProducts.last),
        mockProducts.firstWhere((p) => p.categoryId == 'quesadillas', orElse: () => mockProducts[2]),
      ];
      return _ChatMessage(
        isUser: false,
        text: '¡El festín ideal para compartir en grupo o en pareja$nameGreeting! 🎉🌮\n\n'
            'Te sugiero empezar con unos **Nachos Supremos**, una ronda de **Tacos al Pastor** y una **Quesabirria gigante** al centro:',
        recommendedProducts: comboItems,
      );
    }

    // ─── 14. PROMOCIONES Y DESCUENTOS ────────────────────────────────────────
    if (q.contains('promo') || q.contains('descuento') || q.contains('oferta') ||
        q.contains('cupon') || q.contains('cupón') || q.contains('gratis')) {
      final promoSample = mockProducts.take(3).toList();
      return _ChatMessage(
        isUser: false,
        text: '¡Claro que sí$nameGreeting! 🔥 Tenemos promociones activas hoy en **La Diabla**:\n\n'
            '🛵 **Cupón `DIABLAFREE`:** Envío gratis en tu primer pedido.\n'
            '🌶️ **Cupón `DIABLITO10`:** 10% de descuento en todo el carrito.\n'
            '📦 **Envío Gratis automático** en compras desde \$40.000 COP.\n\n'
            '¡Mira estos recomendados para aplicar tu descuento!',
        recommendedProducts: promoSample,
      );
    }

    // ─── 15. BÚSQUEDA LIBRE Y PONDERACIÓN INTELIGENTE EN EL CATÁLOGO COMPLETO ────
    final scoredProducts = <ProductEntity, int>{};
    final keywords = q.split(RegExp(r'\s+')).where((w) => w.length > 2).toList();

    for (final p in mockProducts) {
      int score = 0;
      final nameLower = p.name.toLowerCase();
      final descLower = p.description.toLowerCase();
      final catLower = p.categoryId.toLowerCase();
      final ingsLower = p.ingredients.map((i) => i.toLowerCase()).join(' ');

      for (final kw in keywords) {
        if (nameLower.contains(kw)) score += 5;
        if (descLower.contains(kw)) score += 3;
        if (catLower.contains(kw)) score += 4;
        if (ingsLower.contains(kw)) score += 4;
      }

      if (score > 0) {
        scoredProducts[p] = score;
      }
    }

    if (scoredProducts.isNotEmpty) {
      final sortedMatches = scoredProducts.keys.toList()
        ..sort((a, b) => scoredProducts[b]!.compareTo(scoredProducts[a]!));
      final topMatches = sortedMatches.take(4).toList();

      return _ChatMessage(
        isUser: false,
        text: '¡Excelente elección$nameGreeting! 🌮🔥 Analicé lo que me escribiste y seleccioné estos **${topMatches.length} platillos ideales** de nuestro menú para ti:',
        recommendedProducts: topMatches,
      );
    }

    // ─── 16. RESPUESTA ABIERTA Y DINÁMICA POR DEFECTO ─────────────────────────
    final randomFeast = [
      mockProducts.firstWhere((p) => p.id == 'burrito_diablo', orElse: () => mockProducts.first),
      mockProducts.firstWhere((p) => p.id == 'tacos_birria', orElse: () => mockProducts[1]),
      mockProducts.firstWhere((p) => p.id == 'camarones_diabla', orElse: () => mockProducts[2]),
      mockProducts.firstWhere((p) => p.id == 'quesadilla_queso_birria', orElse: () => mockProducts.last),
    ];

    return _ChatMessage(
      isUser: false,
      text: '¡Entendido$nameGreeting! 🌶️ En **La Diabla** tenemos más de 20 especialidades: desde tacos y quesabirrias, hasta burritos y mariscos ardientes.\n\n'
          'Aquí tienes 4 de los platillos más pedidos y aclamados por nuestros clientes hoy. Si buscas un ingrediente en específico (pollo, carne, camarón, queso o sin picante), ¡sólo dime y te lo encuentro al instante!',
      recommendedProducts: randomFeast,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RENDERIZADO DE TEXTO CON NEGRITAS PROCESADAS
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildFormattedText(String text, TextStyle baseStyle, Color boldColor) {
    final spans = <InlineSpan>[];
    final regex = RegExp(r'\*\*(.*?)\*\*');
    int lastIndex = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(text: text.substring(lastIndex, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: baseStyle.copyWith(
            fontWeight: FontWeight.w900,
            color: boldColor,
          ),
        ),
      );
      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(text: text.substring(lastIndex)));
    }

    return Text.rich(
      TextSpan(children: spans, style: baseStyle),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.88,
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle superior
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.dividerDark : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFF3E0),
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Image.asset('assets/icons/llamadefuego.png', fit: BoxFit.contain),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'LA DIABLA IA',
                            style: TextStyle(
                              fontFamily: AppTypography.displayFamily,
                              fontSize: 19,
                              color: isDark ? const Color(0xFFFF5252) : const Color(0xFFDC2626),
                              letterSpacing: 0.8,
                            ),
                          ),
                          Text(
                            'Asistente gastronómico & recomendaciones en vivo',
                            style: TextStyle(
                              fontFamily: AppTypography.bodyFamily,
                              fontSize: 11.5,
                              color: isDark ? AppColors.textMutedDark : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Chips de sugerencias rápidas
              SizedBox(
                height: 48,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _quickPrompts.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final prompt = _quickPrompts[index];
                    return ActionChip(
                      label: Text(
                        prompt,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      backgroundColor: isDark ? AppColors.cardDark : Colors.grey.shade100,
                      side: BorderSide(
                        color: isDark ? AppColors.dividerDark : Colors.grey.shade300,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      onPressed: () => _sendMessage(prompt),
                    );
                  },
                ),
              ),
              const Divider(height: 1),

              // Lista de Mensajes
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    final textColor = msg.isUser
                        ? Colors.white
                        : (isDark ? AppColors.textLight : const Color(0xFF2D1500));
                    final boldColor = msg.isUser
                        ? Colors.white
                        : (isDark ? Colors.white : const Color(0xFF1E0E0B));

                    return Align(
                      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: msg.isUser
                              ? const Color(0xFFDC2626)
                              : (isDark ? AppColors.cardDark : const Color(0xFFFFF8F0)),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(18),
                            topRight: const Radius.circular(18),
                            bottomLeft: Radius.circular(msg.isUser ? 18 : 4),
                            bottomRight: Radius.circular(msg.isUser ? 4 : 18),
                          ),
                          border: msg.isUser
                              ? null
                              : Border.all(
                                  color: isDark ? AppColors.dividerDark : const Color(0xFFFFE0B2),
                                  width: 1,
                                ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildFormattedText(
                              msg.text,
                              TextStyle(
                                fontFamily: AppTypography.bodyFamily,
                                fontSize: 13.5,
                                height: 1.4,
                                color: textColor,
                              ),
                              boldColor,
                            ),

                            // Platillos recomendados interactivos
                            if (msg.recommendedProducts != null && msg.recommendedProducts!.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              ...msg.recommendedProducts!.map(
                                (product) => _buildProductMiniCard(product, isDark, textColor),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              if (_isTyping)
                Padding(
                  padding: const EdgeInsets.only(left: 20, bottom: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'La Diabla IA está cocinando una respuesta...',
                      style: TextStyle(
                        fontFamily: AppTypography.bodyFamily,
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                        color: isDark ? AppColors.textMutedDark : Colors.grey,
                      ),
                    ),
                  ),
                ),

              // Campo de texto inferior
              Container(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 8,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                ),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.cardDark : Colors.white,
                  border: Border(
                    top: BorderSide(
                      color: isDark ? AppColors.dividerDark : Colors.grey.shade200,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        style: TextStyle(
                          fontFamily: AppTypography.bodyFamily,
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Pregúntale a La Diabla IA sobre el menú...',
                          hintStyle: TextStyle(
                            fontFamily: AppTypography.bodyFamily,
                            fontSize: 13,
                            color: isDark ? AppColors.textMutedDark : Colors.grey,
                          ),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF1E1712) : const Color(0xFFF5F5F5),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (val) => _sendMessage(val),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFFDC2626),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                        onPressed: () => _sendMessage(_textController.text),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProductMiniCard(ProductEntity product, bool isDark, Color textColor) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1712) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : const Color(0xFFFFE0B2),
          width: 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 25 : 8),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              product.imageUrl,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                width: 52,
                height: 52,
                color: Colors.grey.shade200,
                child: const Icon(Icons.fastfood, size: 22, color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: TextStyle(
                    fontFamily: AppTypography.bodyFamily,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: isDark ? Colors.white : const Color(0xFF1E0E0B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      PriceFormatter.formatSmart(product.price),
                      style: const TextStyle(
                        fontFamily: AppTypography.displayFamily,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFDC2626),
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (product.spicyLevel > 0)
                      Text(
                        '🌶️' * product.spicyLevel,
                        style: const TextStyle(fontSize: 10),
                      ),
                  ],
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              await ref.read(cartNotifierProvider.notifier).addItem(
                    product: product,
                    quantity: 1,
                  );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('¡${product.name} añadido al carrito! 🛒🌮'),
                    backgroundColor: const Color(0xFF16A34A),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 1,
            ),
            icon: const Icon(Icons.add_shopping_cart_rounded, size: 14),
            label: const Text(
              'Agregar',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
