import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
    this.currentUserId = '',
    this.currentUserName = '',
    this.currentUserRole = '', // 'customer' o 'driver'
    this.peerName = '',
    this.peerPhone = '',
    this.peerRole = '', // 'Repartidor' o 'Cliente'
    this.peerPhotoUrl,
    this.currentUserPhotoUrl,
  });

  final String orderId;
  final String currentUserId;
  final String currentUserName;
  final String currentUserRole;
  final String peerName;
  final String peerPhone;
  final String peerRole;
  final String? peerPhotoUrl;
  final String? currentUserPhotoUrl;

  /// ID de la orden actualmente abierta en pantalla (usado para silenciar notificaciones push/locales redundantes)
  static String? currentActiveOrderId;

  @override
  State<OrderChatScreen> createState() => _OrderChatScreenState();
}

class _OrderChatScreenState extends State<OrderChatScreen> {
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final ImagePicker _imagePicker = ImagePicker();

  // Datos dinámicos del interlocutor (Repartidor o Cliente)
  late String _peerName;
  late String _peerPhone;
  late String _peerRole;
  String _peerPhotoUrl = '';
  String _peerUserId = '';

  // Datos dinámicos del usuario actual
  late String _currentUserId;
  late String _currentUserName;
  late String _currentUserRole;
  String _currentUserPhotoUrl = '';

  StreamSubscription<DocumentSnapshot>? _orderDocSub;
  StreamSubscription<DocumentSnapshot>? _peerUserSub;
  StreamSubscription<DocumentSnapshot>? _currentUserSub;

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
  int _previousMessageCount = 0;

  CollectionReference get _chatCol => FirebaseFirestore.instance
      .collection('orders')
      .doc(widget.orderId)
      .collection('chat');

  @override
  void initState() {
    super.initState();
    OrderChatScreen.currentActiveOrderId = widget.orderId;

    _peerName = widget.peerName;
    _peerPhone = widget.peerPhone;
    _peerRole = widget.peerRole.isNotEmpty ? widget.peerRole : 'Contacto';
    _peerPhotoUrl = widget.peerPhotoUrl ?? '';

    final currentAuthUser = FirebaseAuth.instance.currentUser;
    _currentUserId = widget.currentUserId.isNotEmpty
        ? widget.currentUserId
        : (currentAuthUser?.uid ?? 'guest');
    _currentUserName = widget.currentUserName.isNotEmpty
        ? widget.currentUserName
        : (currentAuthUser?.displayName ?? 'Usuario');
    _currentUserRole = widget.currentUserRole.isNotEmpty
        ? widget.currentUserRole
        : 'customer';
    _currentUserPhotoUrl = widget.currentUserPhotoUrl ?? (currentAuthUser?.photoURL ?? '');

    _posSub = _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _audioPosition = pos);
    });
    _durSub = _audioPlayer.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _audioDuration = dur);
    });
    _stateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playerState = state);
    });

    _initChatProfiles();
  }

  @override
  void dispose() {
    if (OrderChatScreen.currentActiveOrderId == widget.orderId) {
      OrderChatScreen.currentActiveOrderId = null;
    }
    _orderDocSub?.cancel();
    _peerUserSub?.cancel();
    _currentUserSub?.cancel();
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

  /// Escucha en tiempo real la orden y los documentos de usuario para mantener fotos y nombres actualizados
  void _initChatProfiles() {
    // 1. Escuchar la orden para saber quién es cliente y quién es repartidor
    _orderDocSub = FirebaseFirestore.instance
        .collection('orders')
        .doc(widget.orderId)
        .snapshots()
        .listen((orderSnap) {
      if (!orderSnap.exists || !mounted) return;
      final dynamic rawOrder = orderSnap.data();
      if (rawOrder == null || rawOrder is! Map<String, dynamic>) return;
      final orderData = rawOrder;

      final customerId = orderData['userId'] as String? ?? '';
      final customerName = orderData['customerName'] as String? ?? 'Cliente';
      final customerPhone = orderData['customerPhone'] as String? ?? '';
      final customerPhoto = orderData['customerPhotoUrl'] as String? ?? '';

      final driverId = orderData['driverId'] as String? ?? '';
      final driverName = orderData['driverName'] as String? ?? 'Repartidor La Diabla';
      final driverPhone = orderData['driverPhone'] as String? ?? '';
      final driverPhoto = orderData['driverPhotoUrl'] as String? ?? '';

      // Determinar si soy el repartidor o el cliente
      final amIDriver = _currentUserRole == 'driver' ||
          _currentUserId == driverId ||
          widget.peerRole == 'Cliente';

      setState(() {
        if (amIDriver) {
          _currentUserRole = 'driver';
          _peerRole = 'Cliente';
          _peerUserId = customerId;
          if (_peerName.isEmpty || _peerName == 'Cliente') _peerName = customerName;
          if (_peerPhone.isEmpty) _peerPhone = customerPhone;
          if (_peerPhotoUrl.isEmpty && customerPhoto.isNotEmpty) _peerPhotoUrl = customerPhoto;
          if (_currentUserPhotoUrl.isEmpty && driverPhoto.isNotEmpty) _currentUserPhotoUrl = driverPhoto;
        } else {
          _currentUserRole = 'customer';
          _peerRole = 'Repartidor';
          _peerUserId = driverId;
          if (_peerName.isEmpty || _peerName == 'Repartidor') _peerName = driverName;
          if (_peerPhone.isEmpty) _peerPhone = driverPhone;
          if (_peerPhotoUrl.isEmpty && driverPhoto.isNotEmpty) _peerPhotoUrl = driverPhoto;
          if (_currentUserPhotoUrl.isEmpty && customerPhoto.isNotEmpty) _currentUserPhotoUrl = customerPhoto;
        }
      });

      // 2. Escuchar perfil en vivo del interlocutor en users/{peerId} para obtener su foto más reciente
      if (_peerUserId.isNotEmpty && _peerUserSub == null) {
        _peerUserSub = FirebaseFirestore.instance
            .collection('users')
            .doc(_peerUserId)
            .snapshots()
            .listen((userSnap) {
          if (!userSnap.exists || !mounted) return;
          final dynamic rawUser = userSnap.data();
          if (rawUser == null || rawUser is! Map<String, dynamic>) return;
          final uData = rawUser;

          final livePhoto = uData['photoUrl'] as String? ?? '';
          final liveName = uData['name'] as String? ?? '';
          final livePhone = uData['phone'] as String? ?? '';

          if (mounted) {
            setState(() {
              if (livePhoto.isNotEmpty) _peerPhotoUrl = livePhoto;
              if (liveName.isNotEmpty && _peerName.isEmpty) _peerName = liveName;
              if (livePhone.isNotEmpty && _peerPhone.isEmpty) _peerPhone = livePhone;
            });
          }
        });
      }

      // 3. Escuchar perfil del usuario actual para asegurar que mi foto esté al día
      if (_currentUserId.isNotEmpty && _currentUserSub == null) {
        _currentUserSub = FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUserId)
            .snapshots()
            .listen((mySnap) {
          if (!mySnap.exists || !mounted) return;
          final dynamic rawMy = mySnap.data();
          if (rawMy != null && rawMy is Map<String, dynamic> && mounted) {
            final myData = rawMy;
            final myPhoto = myData['photoUrl'] as String? ?? '';
            if (myPhoto.isNotEmpty && myPhoto != _currentUserPhotoUrl) {
              setState(() => _currentUserPhotoUrl = myPhoto);
            }
          }
        });
      }
    });
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
    final cleanPhone = _peerPhone.replaceAll(RegExp(r'\D'), '');
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

  /// Notifica al interlocutor en Firestore y actualiza el último mensaje de la orden
  Future<void> _notifyRecipient({
    required String messageText,
    required String type,
  }) async {
    if (_peerUserId.isEmpty) return;

    try {
      final preview = type == 'image'
          ? '📷 Envió una foto'
          : (type == 'audio' ? '🎤 Envió una nota de voz' : messageText);

      final title = _currentUserRole == 'driver'
          ? '💬 Repartidor: $_currentUserName'
          : '💬 Cliente: $_currentUserName';

      // 1. Guardar notificación en Firestore para el destinatario
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_peerUserId)
          .collection('notifications')
          .add({
        'title': title,
        'body': preview,
        'orderId': widget.orderId,
        'type': 'chat_message',
        'senderId': _currentUserId,
        'senderName': _currentUserName,
        'senderRole': _currentUserRole,
        'senderPhotoUrl': _currentUserPhotoUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
      });

      // 2. Actualizar orders/{orderId} con lastChatMessage
      await FirebaseFirestore.instance.collection('orders').doc(widget.orderId).set({
        'lastChatMessage': {
          'text': preview,
          'senderId': _currentUserId,
          'senderName': _currentUserName,
          'senderRole': _currentUserRole,
          'timestamp': FieldValue.serverTimestamp(),
        }
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error enviando notificación en tiempo real: $e');
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
      'senderId': _currentUserId,
      'senderName': _currentUserName,
      'senderRole': _currentUserRole,
      'senderPhotoUrl': _currentUserPhotoUrl,
      'type': 'text',
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
      'isRead': false,
    });

    _notifyRecipient(messageText: text, type: 'text').ignore();
    _scrollToBottom();
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 65,
        maxWidth: 800,
      );
      if (picked == null) return;

      setState(() => _isUploadingMedia = true);
      final file = File(picked.path);
      final imageBytes = await file.readAsBytes();

      String downloadUrl;
      try {
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
        downloadUrl = await uploadTask.ref.getDownloadURL();
      } catch (storageErr) {
        debugPrint('ℹ️ Storage upload fallback a Base64: $storageErr');
        downloadUrl = 'data:image/jpeg;base64,${base64Encode(imageBytes)}';
      }

      final docId = const Uuid().v4();
      await _chatCol.doc(docId).set({
        'id': docId,
        'orderId': widget.orderId,
        'senderId': _currentUserId,
        'senderName': _currentUserName,
        'senderRole': _currentUserRole,
        'senderPhotoUrl': _currentUserPhotoUrl,
        'type': 'image',
        'mediaUrl': downloadUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
      });

      _notifyRecipient(messageText: 'Foto', type: 'image').ignore();
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
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path,
        );
        setState(() {
          _isRecording = true;
          _recordSeconds = 0;
          _recordedAudioPath = path;
        });
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => _recordSeconds++);
        });
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
      try {
        await file.delete();
      } catch (_) {}
      return;
    }

    try {
      setState(() => _isUploadingMedia = true);
      final audioBytes = await file.readAsBytes();

      String downloadUrl;
      try {
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
        downloadUrl = await uploadTask.ref.getDownloadURL();
      } catch (storageErr) {
        debugPrint('ℹ️ Storage audio fallback a Base64: $storageErr');
        downloadUrl = 'data:audio/m4a;base64,${base64Encode(audioBytes)}';
      }

      final docId = const Uuid().v4();
      await _chatCol.doc(docId).set({
        'id': docId,
        'orderId': widget.orderId,
        'senderId': _currentUserId,
        'senderName': _currentUserName,
        'senderRole': _currentUserRole,
        'senderPhotoUrl': _currentUserPhotoUrl,
        'type': 'audio',
        'mediaUrl': downloadUrl,
        'audioDurationSeconds': durationSecs,
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
      });

      _notifyRecipient(messageText: 'Nota de voz', type: 'audio').ignore();
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
      if (url.startsWith('data:audio/')) {
        try {
          final base64String = url.split(',').last;
          final bytes = base64Decode(base64String);
          await _audioPlayer.play(BytesSource(bytes));
        } catch (e) {
          debugPrint('Error reproduciendo audio base64: $e');
        }
      } else {
        await _audioPlayer.play(UrlSource(url));
      }
    }
  }

  // Caché en memoria para evitar redecodificar Base64 en cada frame de la lista
  static final Map<String, Uint8List> _chatBase64Cache = {};

  Uint8List? _getCachedBytes(String source) {
    if (_chatBase64Cache.containsKey(source)) return _chatBase64Cache[source];
    try {
      final clean = source.contains(',') ? source.split(',').last : source;
      final bytes = base64Decode(clean);
      _chatBase64Cache[source] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// Construye un widget de avatar seguro para cualquier tipo de URL o formato Base64 sin parpadeos
  Widget _buildAvatarImageWidget(
    String? photoUrl, {
    double radius = 18,
    String fallbackChar = '👤',
    VoidCallback? onTap,
  }) {
    Widget avatarContent;

    if (photoUrl != null && photoUrl.isNotEmpty) {
      if (photoUrl.startsWith('data:image/')) {
        final bytes = _getCachedBytes(photoUrl);
        if (bytes != null) {
          avatarContent = Image.memory(
            bytes,
            key: ValueKey('b64_${photoUrl.hashCode}'),
            fit: BoxFit.cover,
            width: radius * 2,
            height: radius * 2,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) => _buildFallbackInitial(radius, fallbackChar),
          );
        } else {
          avatarContent = _buildFallbackInitial(radius, fallbackChar);
        }
      } else if (photoUrl.startsWith('http')) {
        avatarContent = CachedNetworkImage(
          key: ValueKey('net_$photoUrl'),
          imageUrl: photoUrl,
          fit: BoxFit.cover,
          width: radius * 2,
          height: radius * 2,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          useOldImageOnUrlChange: true,
          placeholder: (context, url) => Container(
            color: Colors.black12,
            child: const Center(
              child: SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFFDC2626)),
              ),
            ),
          ),
          errorWidget: (context, url, error) => _buildFallbackInitial(radius, fallbackChar),
        );
      } else if (photoUrl.startsWith('assets/')) {
        avatarContent = Image.asset(
          photoUrl,
          fit: BoxFit.cover,
          width: radius * 2,
          height: radius * 2,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => _buildFallbackInitial(radius, fallbackChar),
        );
      } else {
        avatarContent = _buildFallbackInitial(radius, fallbackChar);
      }
    } else {
      avatarContent = _buildFallbackInitial(radius, fallbackChar);
    }

    final avatarWidget = Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withAlpha(200), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(25),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipOval(child: avatarContent),
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: avatarWidget);
    }
    return avatarWidget;
  }

  Widget _buildFallbackInitial(double radius, String char) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFDC2626), Color(0xFF991B1B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          char.isNotEmpty ? char[0].toUpperCase() : '?',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: radius * 0.9,
          ),
        ),
      ),
    );
  }

  Widget _buildChatImageWidget(String url, {double? height, BoxFit fit = BoxFit.cover}) {
    if (url.startsWith('data:image/')) {
      final bytes = _getCachedBytes(url);
      if (bytes != null) {
        return Image.memory(
          bytes,
          key: ValueKey('msg_b64_${url.hashCode}'),
          height: height,
          width: double.infinity,
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => const Center(
            child: Icon(Icons.broken_image, color: Colors.grey),
          ),
        );
      }
      return const Center(child: Icon(Icons.broken_image, color: Colors.grey));
    }
    return CachedNetworkImage(
      key: ValueKey('msg_net_$url'),
      imageUrl: url,
      height: height,
      width: double.infinity,
      fit: fit,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      useOldImageOnUrlChange: true,
      placeholder: (context, url) => Container(
        height: height ?? 170,
        color: Colors.black12,
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFDC2626)),
        ),
      ),
      errorWidget: (context, url, error) => const Center(
        child: Icon(Icons.broken_image, color: Colors.grey),
      ),
    );
  }

  void _showProfilePhotoDialog(BuildContext context, String imageUrl, String name) {
    if (imageUrl.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(180),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              child: InteractiveViewer(
                child: imageUrl.startsWith('data:image/')
                    ? Image.memory(
                        base64Decode(imageUrl.split(',').last),
                        fit: BoxFit.contain,
                      )
                    : CachedNetworkImage(
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
          ],
        ),
      ),
    );
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
                child: imageUrl.startsWith('data:image/')
                    ? Image.memory(
                        base64Decode(imageUrl.split(',').last),
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => Container(
                          padding: const EdgeInsets.all(20),
                          color: Colors.black87,
                          child: const Text('Error al cargar la foto', style: TextStyle(color: Colors.white)),
                        ),
                      )
                    : CachedNetworkImage(
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

    final fallbackChar = _peerName.isNotEmpty
        ? _peerName[0]
        : (_peerRole == 'Repartidor' ? '🛵' : '👤');

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF140F0D) : const Color(0xFFF9F6F0),
      appBar: AppBar(
        backgroundColor: const Color(0xFFDC2626),
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Row(
          children: [
            // Avatar del interlocutor (Repartidor o Cliente) — Foto real con zoom al tocar
            Stack(
              children: [
                _buildAvatarImageWidget(
                  _peerPhotoUrl,
                  radius: 20,
                  fallbackChar: fallbackChar,
                  onTap: _peerPhotoUrl.isNotEmpty
                      ? () => _showProfilePhotoDialog(context, _peerPhotoUrl, _peerName)
                      : null,
                ),
                // Indicador verde en línea
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _peerName.isNotEmpty ? _peerName : _peerRole,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Text(
                        '$_peerRole • Pedido #$shortOrderId',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withAlpha(220),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        '• En línea',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF86EFAC),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Llamar a $_peerName',
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
                      'Chat exclusivo y en tiempo real de la entrega del Pedido #$shortOrderId.',
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
                          _buildAvatarImageWidget(
                            _peerPhotoUrl,
                            radius: 36,
                            fallbackChar: fallbackChar,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Inicia la conversación con ${_peerName.isNotEmpty ? _peerName : "el $_peerRole"}',
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.grey.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Envía un mensaje, foto o nota de voz',
                            style: TextStyle(
                              color: isDark ? Colors.white38 : Colors.grey.shade500,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  if (docs.length > _previousMessageCount) {
                    _previousMessageCount = docs.length;
                    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
                  }

                  return ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final senderId = data['senderId'] as String? ?? '';
                      final isMe = senderId == _currentUserId;
                      final type = data['type'] as String? ?? 'text';
                      final senderName = data['senderName'] as String? ?? '';
                      final senderPhoto = data['senderPhotoUrl'] as String? ?? (isMe ? _currentUserPhotoUrl : _peerPhotoUrl);
                      final timestamp = (data['createdAt'] as Timestamp?)?.toDate();
                      final timeStr = timestamp != null ? DateFormat('hh:mm a').format(timestamp) : '';

                      return Padding(
                        key: ValueKey('msg_${doc.id}'),
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Foto del interlocutor (a la izquierda de sus mensajes)
                            if (!isMe) ...[
                              _buildAvatarImageWidget(
                                senderPhoto,
                                radius: 14,
                                fallbackChar: senderName.isNotEmpty ? senderName[0] : fallbackChar,
                                onTap: senderPhoto.isNotEmpty
                                    ? () => _showProfilePhotoDialog(context, senderPhoto, senderName)
                                    : null,
                              ),
                              const SizedBox(width: 6),
                            ],

                            // Burbuja de mensaje
                            Container(
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.72,
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
                                        child: _buildChatImageWidget(
                                          data['mediaUrl'] as String? ?? '',
                                          height: 170,
                                          fit: BoxFit.cover,
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

                            // Foto mía (a la derecha de mis mensajes)
                            if (isMe) ...[
                              const SizedBox(width: 6),
                              _buildAvatarImageWidget(
                                _currentUserPhotoUrl,
                                radius: 14,
                                fallbackChar: _currentUserName.isNotEmpty ? _currentUserName[0] : 'Yo',
                              ),
                            ],
                          ],
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
