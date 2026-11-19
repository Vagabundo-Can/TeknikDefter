// Kalem çizimi: değişken genişlikli kontur (dolma kalem), sabit (tükenmez/teknik),
// yarı saydam (kurşun), multiply (fosforlu) ve ISO 128 çizgi tipleri.

import 'dart:math' as math;
import 'dart:ui';

import '../models/note_models.dart';

/// ISO 128-2 desenleri, çizgi kalınlığı d'nin katları olarak [çizgi, boşluk, ...]
List<double> dashPattern(LineType t, double d) {
  final k = math.max(d, 0.25);
  return switch (t) {
    LineType.continuous => const [],
    LineType.hidden => [12 * k, 3 * k],
    LineType.center => [24 * k, 3 * k, 0.5 * k, 3 * k],
    LineType.phantom => [24 * k, 3 * k, 0.5 * k, 3 * k, 0.5 * k, 3 * k],
  };
}

Path dashPath(Path source, List<double> pattern) {
  if (pattern.isEmpty) return source;
  final out = Path();
  for (final m in source.computeMetrics()) {
    var dist = 0.0;
    var i = 0;
    var draw = true;
    while (dist < m.length) {
      final len = pattern[i % pattern.length];
      if (draw) out.addPath(m.extractPath(dist, math.min(dist + len, m.length)), Offset.zero);
      dist += len;
      draw = !draw;
      i++;
    }
  }
  return out;
}

Path polylinePath(List<Offset> pts, {bool close = false}) {
  final path = Path();
  if (pts.isEmpty) return path;
  path.moveTo(pts.first.dx, pts.first.dy);
  if (pts.length == 1) {
    path.lineTo(pts.first.dx + 0.01, pts.first.dy);
  }
  for (var i = 1; i < pts.length; i++) {
    path.lineTo(pts[i].dx, pts[i].dy);
  }
  if (close) path.close();
  return path;
}

/// Orta noktalar üzerinden kuadratik eğri — kırık çizgi görünümünü önler
Path smoothPath(List<Offset> pts) {
  final path = Path();
  if (pts.isEmpty) return path;
  path.moveTo(pts.first.dx, pts.first.dy);
  if (pts.length < 3) {
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    if (pts.length == 1) path.lineTo(pts.first.dx + 0.01, pts.first.dy);
    return path;
  }
  for (var i = 1; i < pts.length - 1; i++) {
    final mid = (pts[i] + pts[i + 1]) / 2;
    path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
  }
  path.lineTo(pts.last.dx, pts.last.dy);
  return path;
}

/// Dolma kalem: basınç ve hıza bağlı genişlikle dolu kontur
Path variableWidthOutline(List<InkPoint> pts, double baseWidth) {
  final path = Path();
  if (pts.isEmpty) return path;
  double widthAt(int i) {
    final p = pts[i];
    var w = baseWidth * (0.35 + 1.25 * p.p);
    if (i > 0) {
      final prev = pts[i - 1];
      final dt = math.max(1, p.t - prev.t);
      final v = (p.o - prev.o).distance / dt; // mm/ms
      w *= (1.0 - (v * 0.6).clamp(0.0, 0.35)); // hızlı çizgi incelir
    }
    return math.max(w, baseWidth * 0.25) / 2;
  }

  if (pts.length == 1) {
    path.addOval(Rect.fromCircle(center: pts.first.o, radius: widthAt(0)));
    return path;
  }
  final left = <Offset>[], right = <Offset>[];
  final radii = <double>[];
  for (var i = 0; i < pts.length; i++) {
    final a = pts[math.max(0, i - 1)].o, b = pts[math.min(pts.length - 1, i + 1)].o;
    var dir = b - a;
    final len = dir.distance;
    dir = len < 1e-9 ? const Offset(1, 0) : dir / len;
    final n = Offset(-dir.dy, dir.dx);
    final r = widthAt(i);
    radii.add(r);
    left.add(pts[i].o + n * r);
    right.add(pts[i].o - n * r);
  }
  path.moveTo(left.first.dx, left.first.dy);
  for (var i = 1; i < left.length; i++) {
    final m = (left[i - 1] + left[i]) / 2;
    path.quadraticBezierTo(left[i - 1].dx, left[i - 1].dy, m.dx, m.dy);
  }
  path.lineTo(left.last.dx, left.last.dy);
  // uç: yarım daire
  path.arcToPoint(right.last, radius: Radius.circular(radii.last), clockwise: false);
  for (var i = right.length - 2; i >= 0; i--) {
    final m = (right[i + 1] + right[i]) / 2;
    path.quadraticBezierTo(right[i + 1].dx, right[i + 1].dy, m.dx, m.dy);
  }
  path.lineTo(right.first.dx, right.first.dy);
  path.arcToPoint(left.first, radius: Radius.circular(radii.first), clockwise: false);
  path.close();
  return path;
}

void paintStroke(Canvas canvas, List<InkPoint> pts, PenStyle style) {
  if (pts.isEmpty) return;
  final color = Color(style.color);
  switch (style.type) {
    case PenType.fountain:
      canvas.drawPath(
          variableWidthOutline(pts, style.width),
          Paint()
            ..color = color
            ..style = PaintingStyle.fill
            ..isAntiAlias = true);
    case PenType.ballpoint:
      final avgP = pts.fold<double>(0, (s, p) => s + p.p) / pts.length;
      canvas.drawPath(
          smoothPath([for (final p in pts) p.o]),
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = style.width * (0.85 + 0.3 * avgP)
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round);
    case PenType.pencil:
      final avgP = pts.fold<double>(0, (s, p) => s + p.p) / pts.length;
      final c = color.withValues(alpha: (0.35 + 0.55 * avgP).clamp(0.0, 1.0));
      final base = smoothPath([for (final p in pts) p.o]);
      canvas.drawPath(
          base,
          Paint()
            ..color = c
            ..style = PaintingStyle.stroke
            ..strokeWidth = style.width
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round);
      // grafit dokusu: ince, daha açık ikinci geçiş
      canvas.drawPath(
          base.shift(Offset(style.width * 0.15, style.width * 0.1)),
          Paint()
            ..color = c.withValues(alpha: c.a * 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = style.width * 0.5);
    case PenType.technical:
      final path = dashPath(polylinePath([for (final p in pts) p.o]), dashPattern(style.lineType, style.width));
      canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = style.width
            ..strokeCap = style.lineType == LineType.continuous ? StrokeCap.round : StrokeCap.butt
            ..strokeJoin = StrokeJoin.round);
    case PenType.highlighter:
      canvas.drawPath(
          polylinePath([for (final p in pts) p.o]),
          Paint()
            ..color = color.withValues(alpha: 0.45)
            ..blendMode = BlendMode.multiply
            ..style = PaintingStyle.stroke
            ..strokeWidth = style.width
            ..strokeCap = StrokeCap.square
            ..strokeJoin = StrokeJoin.round);
  }
}

Paint linePaint(PenStyle s) => Paint()
  ..color = Color(s.color)
  ..style = PaintingStyle.stroke
  ..strokeWidth = s.width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

void drawStyledPath(Canvas canvas, Path path, PenStyle s) {
  canvas.drawPath(dashPath(path, dashPattern(s.lineType, s.width)), linePaint(s));
}
