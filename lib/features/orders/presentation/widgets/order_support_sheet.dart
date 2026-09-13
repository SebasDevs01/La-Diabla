// lib/features/orders/presentation/widgets/order_support_sheet.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/services/ai_assistant_service.dart';
import '../../../../domain/entities/order_entity.dart';

class OrderSupportSheet extends StatefulWidget {
  const OrderSupportSheet({super.key, this.orderId, this.order});

  final String? orderId;
  final OrderEntity? order;

  @override
  State<OrderSupportSheet> createState() => _OrderSupportSheetState();
}

class _SupportMessage {
  const _SupportMessage({
    required this.isUser,
    required this.text,
    this.showEscalateButton = false,
  });

  final bool isUser;
  final String text;
  final bool showEscalateButton;
}

class _OrderSupportSheetState extends State<OrderSupportSheet> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_SupportMessage> _messages = [];
  bool _isTyping = false;

  final List<String> _quickIssues = [
    '🛵 Mi pedido está demorado',
    '💳 Me cobraron doble en la tarjeta',
    '📦 Llegó incompleto o equivocado',
    '🚫 Mi pedido fue cancelado',
    '❓ Mi pedido no ha llegado',
  ];

  @override
  void initState() {
    super.initState();
    final initialId = widget.orderId ?? 'LD-7824';
    _messages.add(
      _SupportMessage(
        isUser: false,
        text: '¡Hola! 🌶️ Soy tu **Asistente de Soporte La Diabla**.\n\n'
            'Estoy aquí para resolver de inmediato cualquier novedad con tu pedido **#$initialId** o cualquier otra inquietud.\n\n'
            '¿Qué inconveniente presentas?',
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
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

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    setState(() {
      _messages.add(_SupportMessage(isUser: true, text: text.trim()));
      _isTyping = true;
    });
    _textController.clear();
    _scrollToBottom();

    // Delay mínimo para sensación de respuesta real (700ms)
    final start = DateTime.now();
    final responseText = AiAssistantService.instance.getSupportResponse(
      query: text.trim(),
      orderId: widget.orderId,
      order: widget.order,
    );
    final elapsed = DateTime.now().difference(start).inMilliseconds;
    if (elapsed < 700) {
      await Future.delayed(Duration(milliseconds: 700 - elapsed));
    }

    if (!mounted) return;
    // Determinar si la respuesta debe mostrar el botón de escalar a WhatsApp
    final shouldEscalate = !responseText.contains('soy tu asistente') ||
        responseText.contains('WhatsApp') ||
        responseText.contains('asesor');

    setState(() {
      _isTyping = false;
      _messages.add(_SupportMessage(
        isUser: false,
        text: responseText,
        showEscalateButton: shouldEscalate,
      ));
    });
    _scrollToBottom();
  }

  Future<void> _launchWhatsApp() async {
    const phone = '573171166497';
    final initialId = widget.orderId ?? 'LD-7824';
    final msg = Uri.encodeComponent('¡Hola La Diabla! 🌶️ Necesito soporte con mi pedido #$initialId.');
    final waUri = Uri.parse('whatsapp://send?phone=$phone&text=$msg');
    final webUri = Uri.parse('https://wa.me/$phone?text=$msg');

    if (await canLaunchUrl(waUri)) {
      await launchUrl(waUri, mode: LaunchMode.externalApplication);
    } else if (await canLaunchUrl(webUri)) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

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
          Container(
            width: 44,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: isDark ? AppColors.dividerDark : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(4),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
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
                        'SOPORTE LA DIABLA IA',
                        style: TextStyle(
                          fontFamily: AppTypography.displayFamily,
                          fontSize: 18,
                          color: isDark ? const Color(0xFFFF5252) : const Color(0xFFDC2626),
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        'Atención de incidencias y pedidos 24/7',
                        style: TextStyle(
                          fontFamily: AppTypography.bodyFamily,
                          fontSize: 12,
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

          // Chips de preguntas frecuentes
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _quickIssues.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final issue = _quickIssues[index];
                return ActionChip(
                  label: Text(issue, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  backgroundColor: isDark ? AppColors.cardDark : Colors.grey.shade100,
                  side: BorderSide(color: isDark ? AppColors.dividerDark : Colors.grey.shade300),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  onPressed: () => _sendMessage(issue),
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
                    margin: const EdgeInsets.only(bottom: 12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
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
                        if (msg.showEscalateButton) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _launchWhatsApp,
                              icon: const Icon(Icons.support_agent_rounded, size: 18, color: Color(0xFF16A34A)),
                              label: const Text(
                                'Hablar con un asesor (+57 320 221 2856)',
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFF16A34A), width: 1.2),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
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
                  'La Diabla Soporte está escribiendo...',
                  style: TextStyle(
                    fontFamily: AppTypography.bodyFamily,
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic,
                    color: isDark ? AppColors.textMutedDark : Colors.grey,
                  ),
                ),
              ),
            ),

          // Input field
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 12,
            ),
            decoration: BoxDecoration(
              color: isDark ? AppColors.cardDark : Colors.white,
              border: Border(top: BorderSide(color: isDark ? AppColors.dividerDark : Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _sendMessage,
                    decoration: InputDecoration(
                      hintText: 'Cuéntanos qué pasó con tu pedido...',
                      hintStyle: const TextStyle(fontSize: 13),
                      filled: true,
                      fillColor: isDark ? AppColors.surfaceDark : Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: const Color(0xFFDC2626),
                  radius: 22,
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
}
