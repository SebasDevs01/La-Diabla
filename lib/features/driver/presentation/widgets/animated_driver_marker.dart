// lib/features/driver/presentation/widgets/animated_driver_marker.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class AnimatedDriverMarker {
  static BitmapDescriptor? _customIcon;

  /// Genera o devuelve el BitmapDescriptor con la Flecha de Navegación 3D Roja al estilo Waze / Google Maps.
  static Future<BitmapDescriptor> getDriverIcon() async {
    if (_customIcon != null) return _customIcon!;

    try {
      const double size = 120.0;
      const Offset center = Offset(size / 2, size / 2);

      final pictureRecorder = ui.PictureRecorder();
      final canvas = Canvas(pictureRecorder);

      // 1. Sombra de suelo realista proyectada
      final groundShadowPaint = Paint()
        ..color = Colors.black.withAlpha(70)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(center.dx, center.dy + 8),
          width: 70,
          height: 70,
        ),
        groundShadowPaint,
      );

      // 2. Halo/Disco de ubicación Waze (Pulse Aura)
      final auraPaint = Paint()
        ..color = const Color(0xFFDC2626).withAlpha(35)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, 44, auraPaint);

      final auraBorderPaint = Paint()
        ..color = const Color(0xFFDC2626).withAlpha(120)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(center, 44, auraBorderPaint);

      // 3. Flecha de Navegación 3D Waze / Google Maps (Roja)
      final arrowPathLeft = Path();
      arrowPathLeft.moveTo(center.dx, 14); // Punta superior
      arrowPathLeft.lineTo(center.dx - 28, 92); // Ala izquierda
      arrowPathLeft.lineTo(center.dx, 74); // Muesca central
      arrowPathLeft.close();

      final arrowPathRight = Path();
      arrowPathRight.moveTo(center.dx, 14); // Punta superior
      arrowPathRight.lineTo(center.dx + 28, 92); // Ala derecha
      arrowPathRight.lineTo(center.dx, 74); // Muesca central
      arrowPathRight.close();

      // Gradiente rojo brillante para el lado izquierdo (Luz)
      final paintLeft = Paint()
        ..shader = ui.Gradient.linear(
          Offset(center.dx - 28, 14),
          Offset(center.dx, 92),
          [const Color(0xFFFF4D4D), const Color(0xFFEF4444)],
        );

      // Rojo más oscuro para el lado derecho (Sombra 3D)
      final paintRight = Paint()
        ..shader = ui.Gradient.linear(
          Offset(center.dx, 14),
          Offset(center.dx + 28, 92),
          [const Color(0xFFDC2626), const Color(0xFF991B1B)],
        );

      canvas.drawPath(arrowPathLeft, paintLeft);
      canvas.drawPath(arrowPathRight, paintRight);

      // 4. Contorno blanco nítido (Waze Style White Outline)
      final fullArrowPath = Path();
      fullArrowPath.moveTo(center.dx, 14);
      fullArrowPath.lineTo(center.dx - 28, 92);
      fullArrowPath.lineTo(center.dx, 74);
      fullArrowPath.lineTo(center.dx + 28, 92);
      fullArrowPath.close();

      final outlinePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5;
      canvas.drawPath(fullArrowPath, outlinePaint);

      final picture = pictureRecorder.endRecording();
      final img = await picture.toImage(size.toInt(), size.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        _customIcon = BitmapDescriptor.bytes(byteData.buffer.asUint8List());
        return _customIcon!;
      }
    } catch (e) {
      _customIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
      return _customIcon!;
    }
    return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
  }

  /// Limpia el ícono cacheado (útil para forzar recarga)
  static void clearCache() => _customIcon = null;
}

