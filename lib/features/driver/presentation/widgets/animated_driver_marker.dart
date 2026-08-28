// lib/features/driver/presentation/widgets/animated_driver_marker.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class AnimatedDriverMarker {
  static BitmapDescriptor? _customIcon;

  /// Genera o devuelve el BitmapDescriptor personalizado para la motito de La Diabla.
  static Future<BitmapDescriptor> getDriverIcon() async {
    if (_customIcon != null) return _customIcon!;

    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    const size = 120.0;
    const center = Offset(size / 2, size / 2);

    // 1. Sombra exterior
    final shadowPaint = Paint()
      ..color = Colors.black.withAlpha(80)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center.translate(0, 4), 44, shadowPaint);

    // 2. Círculo rojo de fondo (La Diabla Brand)
    final circlePaint = Paint()
      ..color = const Color(0xFFDC2626)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 44, circlePaint);

    // 3. Borde dorado/blanco brillante
    final borderPaint = Paint()
      ..color = const Color(0xFFFFD700)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    canvas.drawCircle(center, 44, borderPaint);

    // 4. Icono Emoji de Motocicleta 🛵
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = const TextSpan(
      text: '🛵',
      style: TextStyle(fontSize: 48),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2),
    );

    // 5. Flecha direccional arriba
    final arrowPath = Path();
    arrowPath.moveTo(center.dx, 4);
    arrowPath.lineTo(center.dx - 10, 18);
    arrowPath.lineTo(center.dx + 10, 18);
    arrowPath.close();

    final arrowPaint = Paint()
      ..color = const Color(0xFFFFD700)
      ..style = PaintingStyle.fill;
    canvas.drawPath(arrowPath, arrowPaint);

    final picture = pictureRecorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

    if (byteData != null) {
      _customIcon = BitmapDescriptor.bytes(byteData.buffer.asUint8List());
      return _customIcon!;
    }

    return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose);
  }
}
