// lib/features/driver/presentation/widgets/animated_driver_marker.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class AnimatedDriverMarker {
  static BitmapDescriptor? _customIcon;

  /// Genera o devuelve el BitmapDescriptor con la moto 3D al estilo Rappi.
  static Future<BitmapDescriptor> getDriverIcon() async {
    if (_customIcon != null) return _customIcon!;

    try {
      // Cargar la imagen 3D de la moto desde assets
      final ByteData assetData =
          await rootBundle.load('assets/icons/moto_3d_marker.jpg');
      final Uint8List assetBytes = assetData.buffer.asUint8List();

      // Decodificar la imagen original
      final ui.Codec codec = await ui.instantiateImageCodec(
        assetBytes,
        targetWidth: 140,
        targetHeight: 140,
      );
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image motoImage = frameInfo.image;

      // Crear el canvas para componer el marcador completo
      const double size = 160.0;
      const double circleRadius = 62.0;
      const Offset center = Offset(size / 2, size / 2 + 6);

      final pictureRecorder = ui.PictureRecorder();
      final canvas = Canvas(pictureRecorder);

      // 1. Sombra exterior difusa
      final shadowPaint = Paint()
        ..color = Colors.black.withAlpha(90)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawCircle(center.translate(0, 6), circleRadius, shadowPaint);

      // 2. Círculo rojo La Diabla (gradiente radial)
      final gradientPaint = Paint()
        ..shader = ui.Gradient.radial(
          center.translate(-10, -10),
          circleRadius * 1.2,
          [
            const Color(0xFFFF3A3A),
            const Color(0xFFDC2626),
            const Color(0xFFAA1A1A),
          ],
          [0.0, 0.5, 1.0],
        );
      canvas.drawCircle(center, circleRadius, gradientPaint);

      // 3. Borde dorado con brillo
      final borderPaintOuter = Paint()
        ..color = const Color(0xFFFFD700)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.5;
      canvas.drawCircle(center, circleRadius, borderPaintOuter);

      final borderPaintInner = Paint()
        ..color = Colors.white.withAlpha(80)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, circleRadius - 4, borderPaintInner);

      // 4. Dibujar la imagen 3D de la moto centrada en el círculo
      final motoSize = circleRadius * 1.65;
      final motoRect = Rect.fromCenter(
        center: center,
        width: motoSize,
        height: motoSize,
      );

      // Clipear para que no salga del círculo
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: circleRadius - 3)));
      paintImage(
        canvas: canvas,
        rect: motoRect,
        image: motoImage,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      );
      canvas.restore();

      // 5. Brillo/highlight superior izquierdo (efecto 3D)
      final highlightPaint = Paint()
        ..shader = ui.Gradient.radial(
          center.translate(-circleRadius * 0.35, -circleRadius * 0.35),
          circleRadius * 0.6,
          [
            Colors.white.withAlpha(60),
            Colors.white.withAlpha(0),
          ],
        );
      canvas.drawCircle(center, circleRadius, highlightPaint);

      // 6. Flecha direccional dorada arriba
      final arrowPath = Path();
      arrowPath.moveTo(center.dx, center.dy - circleRadius - 2);
      arrowPath.lineTo(center.dx - 11, center.dy - circleRadius + 14);
      arrowPath.lineTo(center.dx + 11, center.dy - circleRadius + 14);
      arrowPath.close();

      final arrowPaint = Paint()
        ..color = const Color(0xFFFFD700)
        ..style = PaintingStyle.fill;
      canvas.drawPath(arrowPath, arrowPaint);

      final arrowBorderPaint = Paint()
        ..color = Colors.white.withAlpha(150)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawPath(arrowPath, arrowBorderPaint);

      // Finalizar imagen
      final picture = pictureRecorder.endRecording();
      final img = await picture.toImage(size.toInt(), size.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        _customIcon = BitmapDescriptor.bytes(byteData.buffer.asUint8List());
        return _customIcon!;
      }
    } catch (e) {
      // Fallback: ícono generado en canvas con emoji si falla la imagen
      _customIcon = await _buildFallbackIcon();
      return _customIcon!;
    }

    return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose);
  }

  /// Ícono de respaldo con emoji en caso de que falle la carga del asset
  static Future<BitmapDescriptor> _buildFallbackIcon() async {
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    const size = 140.0;
    const center = Offset(size / 2, size / 2);

    final shadowPaint = Paint()
      ..color = Colors.black.withAlpha(80)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center.translate(0, 4), 50, shadowPaint);

    final circlePaint = Paint()
      ..color = const Color(0xFFDC2626)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 50, circlePaint);

    final borderPaint = Paint()
      ..color = const Color(0xFFFFD700)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    canvas.drawCircle(center, 50, borderPaint);

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = const TextSpan(
      text: '🛵',
      style: TextStyle(fontSize: 52),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2),
    );

    final arrowPath = Path()
      ..moveTo(center.dx, 4)
      ..lineTo(center.dx - 10, 18)
      ..lineTo(center.dx + 10, 18)
      ..close();
    canvas.drawPath(arrowPath, Paint()..color = const Color(0xFFFFD700));

    final picture = pictureRecorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

    if (byteData != null) {
      return BitmapDescriptor.bytes(byteData.buffer.asUint8List());
    }
    return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose);
  }

  /// Limpia el ícono cacheado (útil para forzar recarga)
  static void clearCache() => _customIcon = null;
}
