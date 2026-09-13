import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../../../../app/theme/app_colors.dart';

class OrderChatScreen extends StatefulWidget {
  const OrderChatScreen({
    super.key,
    required this.orderId,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserRole, // 'customer' o 'driver'
    required this.peerName,
    required this.peerPhone,
    required this.peerRole, // 'Repartidor' o 'Cliente'
  });

  final String orderId;
  final String currentUserId;
  final String currentUserName;
  final String currentUserRole;
  final String peerName;
  final String peerPhone;
  final String peerRole;

  @override
  State<OrderChatScreen> createState() => _OrderChatScreenState();
}

class _OrderChatScreenState extends State<OrderChatScreen> {
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  String? _recordedAudioPath;
  bool _isUploadingMedia = false;

  // Reproductor de audios
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentlyPlayingUrl;
  PlayerState _playerState = PlayerState.stopped;
  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _stateSub;

  CollectionReference get _chatCol => FirebaseFirestore.instance
      .collection('orders')
      .doc(widget.orderId)
      .collection('chat');

  @override
  void initState() {
    super.initState();
    _posSub = _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _audioPosition = pos);
    });
    _durSub = _audioPlayer.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _audioDuration = dur);
    });
    _stateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playerState = state);
    });
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _audioRecorder.dispose();
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _audioPlayer.dispose();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _makeCall() async {
    final cleanPhone = widget.peerPhone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Número de teléfono no disponible.'),
          backgroundColor: Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final uri = Uri.parse('tel:$cleanPhone');
    try {
      await launchUrl(uri);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo abrir el marcador para llamar al $cleanPhone'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _sendTextMessage() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();

    final docId = const Uuid().v4();
    await _chatCol.doc(docId).set({
      'id': docId,
      'orderId': widget.orderId,
      'senderId': widget.currentUserId,
      'senderName': widget.currentUserName,
      'senderRole': widget.currentUserRole,
      'type': 'text',
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'isRead': false,
    });
    _scrollToBottom();
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1080,
      );
      if (picked == null) return;

      setState(() => _isUploadingMedia = true);
      final file = File(picked.path);
      final fileName = 'chat_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance
          .ref()
          .child('orders')
          .child(widget.orderId)
          .child('chat_images')
          .child(fileName);

      final uploadTask = await ref.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      final docId = const Uuid().v4();
      await _chatCol.doc(docId).set({
        'id': docId,
        'orderId': widget.orderId,
        'senderId': widget.currentUserId,
        'senderName': widget.currentUserName,
        'senderRole': widget.currentUserRole,
        'type': 'image',
        'mediaUrl': downloadUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
      });

      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar imagen: $e'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingMedia = false);
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000),
          path: path,
        );
        setState(() {
          _isRecording = true;
          _recordSeconds = 0;
          _recordedAudioPath = path;
        });

        _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) {
            setState(() => _recordSeconds++);
          }
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permiso de micrófono no concedido.'),
              backgroundColor: Color(0xFFDC2626),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al iniciar grabación: $e'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    try {
      await _audioRecorder.stop();
    } catch (_) {}
    if (_recordedAudioPath != null) {
      try {
        final file = File(_recordedAudioPath!);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    setState(() {
      _isRecording = false;
      _recordSeconds = 0;
      _recordedAudioPath = null;
    });
  }

  Future<void> _stopAndSendRecording() async {
    _recordTimer?.cancel();
    final durationSecs = _recordSeconds;
    String? path;
    try {
      path = await _audioRecorder.stop();
    } catch (_) {}

    setState(() {
      _isRecording = false;
      _recordSeconds = 0;
    });

    final effectivePath = path ?? _recordedAudioPath;
    if (effectivePath == null) return;
    final file = File(effectivePath);
    if (!await file.exists()) return;

    if (durationSecs < 1) {
      // Audio demasiado corto
      try {
        await file.delete();
      } catch (_) {}
      return;
    }

    try {
      setState(() => _isUploadingMedia = true);
      final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('orders')
          .child(widget.orderId)
          .child('chat_audios')
          .child(fileName);

      final uploadTask = await storageRef.putFile(
        file,
        SettableMetadata(contentType: 'audio/mp4'),
      );
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      final docId = const Uuid().v4();
      await _chatCol.doc(docId).set({
        'id': docId,
        'orderId': widget.orderId,
        'senderId': widget.currentUserId,
        'senderName': widget.currentUserName,
        'senderRole': widget.currentUserRole,
        'type': 'audio',
        'mediaUrl': downloadUrl,
        'audioDurationSeconds': durationSecs,
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
      });

      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar nota de voz: $e'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingMedia = false);
    }
  }

  Future<void> _playAudio(String url) async {
    if (_currentlyPlayingUrl == url && _playerState == PlayerState.playing) {
      await _audioPlayer.pause();
    } else {
      _currentlyPlayingUrl = url;
      await _audioPlayer.play(UrlSource(url));
    }
  }

  void _showImagePreview(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: InteractiveViewer(
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => const Center(
                    child: CircularProgressIndicator(color: Color(0xFFDC2626)),
                  ),
                  errorWidget: (context, url, error) => Container(
                    padding: const EdgeInsets.all(20),
                    color: Colors.black87,
                    child: const Text('Error al cargar la foto', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(ctx),
              icon: const CircleAvatar(
                backgroundColor: Colors.black54,
                child: Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shortOrderId = widget.orderId.length > 6
        ? widget.orderId.substring(widget.orderId.length - 6).toUpperCase()
        : widget.orderId.toUpperCase();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF140F0D) : const Color(0xFFF9F6F0),
      appBar: AppBar(
        backgroundColor: const Color(0xFFDC2626),
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white.withAlpha(35),
              child: Text(
                widget.peerRole == 'Repartidor' ? '🛵' : '👤',
                style: const TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.peerName.isNotEmpty ? widget.peerName : widget.peerRole,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${widget.peerRole} • Pedido #$shortOrderId',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withAlpha(210),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Llamar a ${widget.peerName}',
            icon: const Icon(Icons.phone_rounded, color: Colors.white),
            onPressed: _makeCall,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Banner de seguridad
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              color: isDark ? const Color(0xFF1E1712) : const Color(0xFFFFF7ED),
              child: Row(
                children: [
                  const Icon(Icons.lock_rounded, size: 13, color: Color(0xFFD97706)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Chat exclusivo de la entrega del Pedido #$shortOrderId.',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? const Color(0xFFF59E0B) : const Color(0xFFB45309),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Lista de mensajes en vivo
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _chatCol.orderBy('createdAt', descending: false).snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFFDC2626)));
                  }

                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.forum_outlined,
                            size: 48,
                            color: isDark ? Colors.white24 : Colors.grey.shade400,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Inicia la conversación con el ${widget.peerRole.toLowerCase()}',
                            style: TextStyle(
                              color: isDark ? Colors.white54 : Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                  return ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      final senderId = data['senderId'] as String? ?? '';
                      final isMe = senderId == widget.currentUserId;
                      final type = data['type'] as String? ?? 'text';
                      final senderName = data['senderName'] as String? ?? '';
                      final timestamp = (data['createdAt'] as Timestamp?)?.toDate();
                      final timeStr = timestamp != null ? DateFormat('hh:mm a').format(timestamp) : '';

                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.78,
                          ),
                          decoration: BoxDecoration(
                            color: isMe
                                ? const Color(0xFFDC2626)
                                : (isDark ? const Color(0xFF261D18) : Colors.white),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(isMe ? 16 : 4),
                              bottomRight: Radius.circular(isMe ? 4 : 16),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(isDark ? 30 : 12),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                            border: Border.all(
                              color: isMe
                                  ? const Color(0xFFDC2626)
                                  : (isDark ? AppColors.dividerDark : Colors.grey.shade200),
                              width: 1,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isMe && senderName.isNotEmpty) ...[
                                Text(
                                  senderName,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                                const SizedBox(height: 3),
                              ],

                              // Contenido según el tipo
                              if (type == 'text') ...[
                                Text(
                                  data['text'] as String? ?? '',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: isMe ? Colors.white : (isDark ? Colors.white : Colors.black87),
                                  ),
                                ),
                              ] else if (type == 'image') ...[
                                GestureDetector(
                                  onTap: () => _showImagePreview(context, data['mediaUrl'] as String? ?? ''),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: CachedNetworkImage(
                                      imageUrl: data['mediaUrl'] as String? ?? '',
                                      height: 170,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(
                                        height: 170,
                                        color: Colors.black12,
                                        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                      ),
                                    ),
                                  ),
                                ),
                              ] else if (type == 'audio') ...[
                                _buildAudioBubble(
                                  data['mediaUrl'] as String? ?? '',
                                  (data['audioDurationSeconds'] as num?)?.toInt() ?? 0,
                                  isMe,
                                ),
                              ],

                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    timeStr,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isMe
                                          ? Colors.white.withAlpha(200)
                                          : (isDark ? Colors.white38 : Colors.grey.shade500),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            if (_isUploadingMedia)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: isDark ? const Color(0xFF1E1712) : Colors.grey.shade100,
                child: const Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFDC2626)),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Subiendo archivo multimedia...',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),

            // Barra inferior de entrada
            _buildInputBar(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioBubble(String url, int durationSecs, bool isMe) {
    final isPlaying = _currentlyPlayingUrl == url && _playerState == PlayerState.playing;
    final pos = (_currentlyPlayingUrl == url) ? _audioPosition : Duration.zero;
    final dur = (_currentlyPlayingUrl == url && _audioDuration > Duration.zero)
        ? _audioDuration
        : Duration(seconds: durationSecs);

    final currentSecs = pos.inSeconds;
    final totalSecs = dur.inSeconds > 0 ? dur.inSeconds : durationSecs;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          padding: EdgeInsets.zero,
          icon: Icon(
            isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
            color: isMe ? Colors.white : const Color(0xFFDC2626),
            size: 34,
          ),
          onPressed: () => _playAudio(url),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.graphic_eq_rounded,
                  size: 16,
                  color: isMe ? Colors.white.withAlpha(220) : const Color(0xFFDC2626),
                ),
                const SizedBox(width: 4),
                Text(
                  isPlaying ? 'Reproduciendo...' : 'Nota de Voz',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isMe ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${_formatDuration(currentSecs)} / ${_formatDuration(totalSecs)}',
              style: TextStyle(
                fontSize: 10.5,
                color: isMe ? Colors.white.withAlpha(200) : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(1, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildInputBar(bool isDark) {
    if (_isRecording) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1712) : Colors.white,
          border: Border(top: BorderSide(color: isDark ? AppColors.dividerDark : Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 6,
              backgroundColor: Color(0xFFDC2626),
            ),
            const SizedBox(width: 8),
            Text(
              'Grabando audio: ${_formatDuration(_recordSeconds)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFDC2626)),
            ),
            const Spacer(),
            TextButton(
              onPressed: _cancelRecording,
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ),
            IconButton(
              icon: const CircleAvatar(
                backgroundColor: Color(0xFFDC2626),
                radius: 18,
                child: Icon(Icons.send_rounded, color: Colors.white, size: 18),
              ),
              onPressed: _stopAndSendRecording,
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1712) : Colors.white,
        border: Border(top: BorderSide(color: isDark ? AppColors.dividerDark : Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          // Botón Fotos (Cámara / Galería)
          IconButton(
            icon: const Icon(Icons.photo_camera_rounded, color: Color(0xFFDC2626)),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: isDark ? const Color(0xFF1E1712) : Colors.white,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.camera_alt_rounded, color: Color(0xFFDC2626)),
                        title: const Text('Tomar Foto'),
                        onTap: () {
                          Navigator.pop(ctx);
                          _pickAndSendImage(ImageSource.camera);
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.photo_library_rounded, color: Color(0xFF0284C7)),
                        title: const Text('Elegir de Galería'),
                        onTap: () {
                          Navigator.pop(ctx);
                          _pickAndSendImage(ImageSource.gallery);
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Campo de texto
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.black26 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
              ),
              child: TextField(
                controller: _textCtrl,
                maxLines: 4,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Escribe un mensaje...',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
                onSubmitted: (_) => _sendTextMessage(),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Botón Micrófono / Enviar
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _textCtrl,
            builder: (context, value, _) {
              if (value.text.trim().isNotEmpty) {
                return IconButton(
                  icon: const CircleAvatar(
                    backgroundColor: Color(0xFFDC2626),
                    radius: 20,
                    child: Icon(Icons.send_rounded, color: Colors.white, size: 18),
                  ),
                  onPressed: _sendTextMessage,
                );
              }
              return IconButton(
                icon: const CircleAvatar(
                  backgroundColor: Color(0xFFDC2626),
                  radius: 20,
                  child: Icon(Icons.mic_rounded, color: Colors.white, size: 20),
                ),
                tooltip: 'Grabar nota de voz',
                onPressed: _startRecording,
              );
            },
          ),
        ],
      ),
    );
  }
}
