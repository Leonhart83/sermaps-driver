import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Genera marcatori personalizzati (pin numerati e di stato) per la mappa.
class MarkerHelper {
  /// Risoluzione di disegno (px). Resa nitida; la dimensione a schermo è
  /// controllata da [BitmapDescriptor.bytes] tramite width logico.
  static const double _render = 120.0;

  /// Larghezza a schermo (px logici) di un pin normale.
  static const double _displayWidth = 32.0;

  /// Crea un pin con il numero della tappa. [scale] > 1 lo ingrandisce
  /// (usato per la tappa selezionata).
  static Future<BitmapDescriptor> numberedMarker(
    int number, {
    Color color = const Color(0xFF1A73E8),
    double scale = 1.0,
  }) async {
    const size = _render;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    const center = Offset(size / 2, size / 2.7);
    const radius = size / 2.9;
    _drawPin(canvas, size, center, radius, color);

    final tp = TextPainter(
      text: TextSpan(
        text: '$number',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 46,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));

    return _toBitmap(recorder, size, _displayWidth * scale);
  }

  /// Pin di stato per le tappe completate: verde con spunta (consegnata)
  /// o rosso con croce (non riuscita).
  static Future<BitmapDescriptor> statusMarker({required bool delivered}) async {
    const size = _render;
    final color = delivered ? const Color(0xFF1E8E3E) : const Color(0xFFD93025);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    const center = Offset(size / 2, size / 2.7);
    const radius = size / 2.9;
    _drawPin(canvas, size, center, radius, color);

    final icon = delivered ? Icons.check : Icons.close;
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          color: Colors.white,
          fontSize: 52,
          fontWeight: FontWeight.bold,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));

    return _toBitmap(recorder, size, _displayWidth * 0.9);
  }

  /// Marcatore pulito per la posizione attuale dell'utente: punto pieno
  /// con bordo bianco e alone morbido. Visibile ma non invasivo.
  static Future<BitmapDescriptor> positionMarker({
    Color color = const Color(0xFF1A73E8),
  }) async {
    const size = _render; // 120 px
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const center = Offset(size / 2, size / 2);

    // Alone esterno morbido
    final glow = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(center, 46, glow);

    // Ombra sotto il punto
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawCircle(center.translate(0, 3), 30, shadow);

    // Bordo bianco
    canvas.drawCircle(center, 30, Paint()..color = Colors.white);

    // Punto pieno
    canvas.drawCircle(center, 22, Paint()..color = color);

    return _toBitmap(recorder, size, 30);
  }

  /// Disegna la forma del pin (coda + cerchio con bordo + ombra).
  static void _drawPin(
    Canvas canvas,
    double size,
    Offset center,
    double radius,
    Color color,
  ) {
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(center.translate(0, 3), radius, shadow);

    final paint = Paint()..color = color;
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size * 0.06;

    final path = Path()
      ..moveTo(center.dx - size * 0.12, center.dy + radius * 0.6)
      ..lineTo(center.dx, size - size * 0.06)
      ..lineTo(center.dx + size * 0.12, center.dy + radius * 0.6)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawCircle(center, radius, paint);
    canvas.drawCircle(center, radius, border);
  }

  static Future<BitmapDescriptor> _toBitmap(
    ui.PictureRecorder recorder,
    double size,
    double displayWidth,
  ) async {
    final img =
        await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      data!.buffer.asUint8List(),
      width: displayWidth,
    );
  }

  /// Versione sincrona di fallback (marcatore colorato standard).
  static BitmapDescriptor fallback() =>
      BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
}
