// lib/features/assistant/presentation/screens/diabla_assistant_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/services/ai_assistant_service.dart';
import '../../../../core/utils/price_formatter.dart';
import '../../../../domain/entities/product_entity.dart';
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

  Future<void> _sendMessage(String userText) async {
    if (userText.trim().isEmpty) return;

    setState(() {
      _messages.add(_ChatMessage(isUser: true, text: userText.trim()));
      _isTyping = true;
    });
    _textController.clear();
    _scrollToBottom();

    // Delay mínimo de 600ms para sensación de procesamiento real
    final start = DateTime.now();
    final result = await AiAssistantService.instance.getFoodRecommendation(
      query: userText.trim(),
      userName: _userName,
    );
    final elapsed = DateTime.now().difference(start).inMilliseconds;
    if (elapsed < 600) {
      await Future.delayed(Duration(milliseconds: 600 - elapsed));
    }

    if (!mounted) return;
    setState(() {
      _isTyping = false;
      _messages.add(_ChatMessage(
        isUser: false,
        text: result.message,
        recommendedProducts: result.products,
      ));
    });
    _scrollToBottom();
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

  // (Motor de respuestas delegado a AiAssistantService — ver ai_assistant_service.dart)

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
    return _AnimatedAddCard(product: product, isDark: isDark, cartNotifier: ref.read(cartNotifierProvider.notifier));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TARJETA DE PRODUCTO CON BOTÓN ANIMADO "AGREGADO ✓"
// ═══════════════════════════════════════════════════════════════════════════
class _AnimatedAddCard extends StatefulWidget {
  const _AnimatedAddCard({
    required this.product,
    required this.isDark,
    required this.cartNotifier,
  });

  final ProductEntity product;
  final bool isDark;
  final dynamic cartNotifier;

  @override
  State<_AnimatedAddCard> createState() => _AnimatedAddCardState();
}

class _AnimatedAddCardState extends State<_AnimatedAddCard>
    with SingleTickerProviderStateMixin {
  bool _added = false;
  bool _loading = false;
  late AnimationController _scaleCtrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 150),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleAdd(BuildContext ctx) async {
    if (_loading || _added) return;
    setState(() => _loading = true);
    await _scaleCtrl.forward();
    await _scaleCtrl.reverse();
    await widget.cartNotifier.addItem(product: widget.product, quantity: 1);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _added = true;
    });
    // Volver al estado original después de 2.5 segundos
    await Future.delayed(const Duration(milliseconds: 2500));
    if (mounted) setState(() => _added = false);
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final isDark = widget.isDark;

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
          // Imagen del platillo
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
          // Nombre y precio
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
          // Botón animado con feedback visual
          ScaleTransition(
            scale: _scaleAnim,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                color: _added ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _handleAdd(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, anim) =>
                          ScaleTransition(scale: anim, child: child),
                      child: _loading
                          ? const SizedBox(
                              key: ValueKey('loading'),
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : _added
                              ? const Row(
                                  key: ValueKey('added'),
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle_outline_rounded,
                                        size: 14, color: Colors.white),
                                    SizedBox(width: 4),
                                    Text(
                                      'Agregado',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                )
                              : const Row(
                                  key: ValueKey('add'),
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add_shopping_cart_rounded,
                                        size: 14, color: Colors.white),
                                    SizedBox(width: 4),
                                    Text(
                                      'Agregar',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
