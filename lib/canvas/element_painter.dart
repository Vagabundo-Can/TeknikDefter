// Eleman çizimi: şekiller, ölçüler, GD&T, yüzey/kaynak sembolleri, motosiklet sembolleri, şerit.

import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/painting.dart';

import '../core/format.dart';
import '../ink/stroke_renderer.dart';
import '../media/asset_images.dart';
import '../models/note_models.dart';

// ---------------------------------------------------------------------------
// Metin

void drawText(Canvas c, String text, Offset at,
    {double size = 3.5,
    Color color = const Color(0xFF000000),
    double rotation = 0,
    Alignment anchor = Alignment.center,
    FontWeight weight = FontWeight.w400,
    bool italic = false}) {
  final tp = TextPainter(
    text: TextSpan(
        text: text,
        style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: size,
            color: color,
            height: 1.0,
            fontWeight: weight,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal)),
    textDirection: TextDirection.ltr,
  )..layout();
  c.save();
  c.translate(at.dx, at.dy);
  if (rotation != 0) c.rotate(rotation);
  final dx = -tp.width * (anchor.x + 1) / 2;
  final dy = -tp.height * (anchor.y + 1) / 2;
  tp.paint(c, Offset(dx, dy));
  c.restore();
}

Size measureText(String text, double size) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: TextStyle(fontFamily: 'Roboto', fontSize: size, height: 1.0)),
    textDirection: TextDirection.ltr,
  )..layout();
  return tp.size;
}

// ---------------------------------------------------------------------------
// Ok başları

void drawArrowHead(Canvas c, Offset tip, Offset dir, Color color, {double len = 3, double width = 1}) {
  final d = dir.distance < 1e-9 ? const Offset(1, 0) : dir / dir.distance;
  final n = Offset(-d.dy, d.dx);
  final base = tip - d * len;
  final p = Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(base.dx + n.dx * width / 2, base.dy + n.dy * width / 2)
    ..lineTo(base.dx - n.dx * width / 2, base.dy - n.dy * width / 2)
    ..close();
  c.drawPath(p, Paint()..color = color);
}

/// Okunabilir metin açısı (ters yazı olmasın)
double readableAngle(Offset dir) {
  var a = math.atan2(dir.dy, dir.dx);
  if (a > math.pi / 2 + 1e-6) a -= math.pi;
  if (a < -math.pi / 2 - 1e-6) a += math.pi;
  return a;
}

// ---------------------------------------------------------------------------
// Şekiller

void paintShape(Canvas c, ShapeElement s) {
  final st = s.style;
  final color = Color(st.color);
  switch (s.kind) {
    case ShapeKind.line:
      drawStyledPath(c, polylinePath(s.points), st);
    case ShapeKind.centerline:
      drawStyledPath(c, polylinePath(s.points), st.copyWith(lineType: LineType.center));
    case ShapeKind.arrow:
      final a = s.points[0], b = s.points[1];
      final dir = b - a;
      final headLen = math.max(2.5, st.width * 7);
      final shaftEnd = b - (dir / math.max(dir.distance, 1e-6)) * headLen * 0.8;
      drawStyledPath(c, polylinePath([a, shaftEnd]), st);
      drawArrowHead(c, b, dir, color, len: headLen, width: headLen * 0.6);
    case ShapeKind.route:
      final path = smoothPath(s.points);
      drawStyledPath(c, path, st.copyWith(width: math.max(st.width, 0.7)));
      if (s.points.length > 1) {
        final b = s.points.last, a = s.points[math.max(0, s.points.length - 4)];
        drawArrowHead(c, b, b - a, color, len: 3.5, width: 2.4);
      }
    case ShapeKind.rect:
      final r = Rect.fromPoints(s.points[0], s.points[1]);
      if (s.fill != null) c.drawRect(r, Paint()..color = Color(s.fill!));
      drawStyledPath(c, Path()..addRect(r), st);
    case ShapeKind.ellipse:
      final r = Rect.fromPoints(s.points[0], s.points[1]);
      if (s.fill != null) c.drawOval(r, Paint()..color = Color(s.fill!));
      drawStyledPath(c, Path()..addOval(r), st);
    case ShapeKind.triangle:
    case ShapeKind.polygon:
      final p = polylinePath(s.points, close: true);
      if (s.fill != null) c.drawPath(p, Paint()..color = Color(s.fill!));
      drawStyledPath(c, p, st);
  }
}

// ---------------------------------------------------------------------------
// Ölçülendirme (ISO 129-1 düzeni: ölçü çizgisi, yardımcı çizgi, ok, metin ölçü çizgisinin üstünde)

const _extGap = 1.0; // parçadan boşluk
const _extOver = 2.0; // ölçü çizgisinin ötesine taşma

void paintDimension(Canvas c, DimensionElement d, ScaleSpec scale) {
  final color = Color(d.color);
  final thin = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.18;
  final h = d.textHeight;
  final arrowLen = math.max(2.5, h);
  final main = dimensionMainText(d, scale);
  final overridden = d.textOverride != null && d.textOverride!.isNotEmpty;
  final suffix = dimensionInlineSuffix(d);
  final label = '$main$suffix';
  final textColor = overridden ? const Color(0xFFE65100) : color;

  void dimText(Offset mid, Offset dir, Offset normalOut) {
    final ang = readableAngle(dir);
    final at = mid + normalOut * (h * 0.6 + 0.8);
    drawText(c, label, at, size: h, color: textColor, rotation: ang, italic: overridden);
    final t = d.tolerance;
    if (!t.isEmpty && !t.symmetric && (t.upper != null || t.lower != null)) {
      final w = measureText(label, h).width;
      final along = Offset(math.cos(ang), math.sin(ang));
      final perp = Offset(-along.dy, along.dx);
      final base = at + along * (w / 2 + 0.6);
      drawText(c, formatTolValue(t.upper ?? 0), base - perp * (h * 0.32),
          size: h * 0.6, color: textColor, rotation: ang, anchor: Alignment.centerLeft);
      drawText(c, formatTolValue(t.lower ?? 0), base + perp * (h * 0.32),
          size: h * 0.6, color: textColor, rotation: ang, anchor: Alignment.centerLeft);
    }
  }

  void linear(Offset p1, Offset p2, Offset a, Offset b) {
    // a,b: ölçü çizgisi uçları; p1,p2: ölçülen noktalar
    for (final (p, q) in [(p1, a), (p2, b)]) {
      final v = q - p;
      final len = v.distance;
      if (len > _extGap) {
        final u = v / len;
        c.drawLine(p + u * _extGap, q + u * _extOver, thin);
      }
    }
    c.drawLine(a, b, thin);
    final dir = b - a;
    final dl = dir.distance;
    if (dl < 1e-6) return;
    final u = dir / dl;
    if (dl > 2.2 * arrowLen) {
      drawArrowHead(c, a, -u, color, len: arrowLen, width: arrowLen / 3);
      drawArrowHead(c, b, u, color, len: arrowLen, width: arrowLen / 3);
    } else {
      // dar ölçü: oklar dışarıdan
      c.drawLine(a - u * arrowLen * 2, a, thin);
      c.drawLine(b, b + u * arrowLen * 2, thin);
      drawArrowHead(c, a, u, color, len: arrowLen, width: arrowLen / 3);
      drawArrowHead(c, b, -u, color, len: arrowLen, width: arrowLen / 3);
    }
    var n = Offset(-u.dy, u.dx);
    // metin ölçülen nesneden uzak tarafta
    final away = ((a + b) / 2) - ((p1 + p2) / 2);
    if (away.distance < 1e-6) {
      if (n.dy > 0) n = -n; // ofset yoksa metin yukarıda
    } else if (n.dx * away.dx + n.dy * away.dy < 0) {
      n = -n;
    }
    dimText((a + b) / 2, u, n);
  }

  final p = d.points;
  switch (d.kind) {
    case DimKind.aligned:
      final u0 = p[1] - p[0];
      final l = u0.distance;
      if (l < 1e-6) return;
      final u = u0 / l;
      final n = Offset(-u.dy, u.dx);
      final off = (p[2] - p[0]).dx * n.dx + (p[2] - p[0]).dy * n.dy;
      linear(p[0], p[1], p[0] + n * off, p[1] + n * off);
    case DimKind.horizontal:
      final y = p[2].dy;
      linear(p[0], p[1], Offset(p[0].dx, y), Offset(p[1].dx, y));
    case DimKind.vertical:
      final x = p[2].dx;
      linear(p[0], p[1], Offset(x, p[0].dy), Offset(x, p[1].dy));
    case DimKind.radius:
    case DimKind.diameter:
      final center = p[0];
      final r = (p[1] - center).distance;
      if (r < 1e-6) return;
      final txt = p[2];
      final dirToText = txt - center;
      final u = dirToText.distance < 1e-6 ? (p[1] - center) / r : dirToText / dirToText.distance;
      final onCircle = center + u * r;
      if (d.kind == DimKind.radius) {
        c.drawLine(center, onCircle, thin);
        drawArrowHead(c, onCircle, u, color, len: arrowLen, width: arrowLen / 3);
      } else {
        final opposite = center - u * r;
        c.drawLine(opposite, onCircle, thin);
        drawArrowHead(c, onCircle, u, color, len: arrowLen, width: arrowLen / 3);
        drawArrowHead(c, opposite, -u, color, len: arrowLen, width: arrowLen / 3);
      }
      // kılavuz: daire dışına, yatay omuz
      final out = (txt - center).distance > r ? txt : onCircle + u * 4;
      c.drawLine(onCircle, out, thin);
      final w = measureText(label, h).width + 1;
      final shoulderDir = u.dx >= 0 ? 1.0 : -1.0;
      final shoulderEnd = out + Offset(shoulderDir * w, 0);
      c.drawLine(out, shoulderEnd, thin);
      drawText(c, label, Offset((out.dx + shoulderEnd.dx) / 2, out.dy - h * 0.6 - 0.4),
          size: h, color: textColor, italic: overridden);
    case DimKind.angle:
      final v = p[0];
      final a1 = p[1] - v, a2 = p[2] - v;
      final rad = math.max((p[3] - v).distance, 4.0);
      final s1 = math.atan2(a1.dy, a1.dx);
      var sweep = math.atan2(a2.dy, a2.dx) - s1;
      while (sweep > math.pi) {
        sweep -= 2 * math.pi;
      }
      while (sweep < -math.pi) {
        sweep += 2 * math.pi;
      }
      // kollar (yardımcı çizgi) yay yarıçapına kadar
      for (final a in [a1, a2]) {
        final l = a.distance;
        if (l < 1e-6) continue;
        final u = a / l;
        if (rad > l) c.drawLine(v + u * (l + _extGap), v + u * (rad + _extOver), thin);
      }
      c.drawArc(Rect.fromCircle(center: v, radius: rad), s1, sweep, false, thin);
      final e1 = v + Offset(math.cos(s1), math.sin(s1)) * rad;
      final e2 = v + Offset(math.cos(s1 + sweep), math.sin(s1 + sweep)) * rad;
      final t1 = Offset(-math.sin(s1), math.cos(s1)) * (sweep >= 0 ? -1.0 : 1.0);
      final t2 = Offset(-math.sin(s1 + sweep), math.cos(s1 + sweep)) * (sweep >= 0 ? 1.0 : -1.0);
      drawArrowHead(c, e1, t1, color, len: arrowLen, width: arrowLen / 3);
      drawArrowHead(c, e2, t2, color, len: arrowLen, width: arrowLen / 3);
      final midA = s1 + sweep / 2;
      final mid = v + Offset(math.cos(midA), math.sin(midA)) * (rad + h * 0.9);
      drawText(c, label, mid, size: h, color: textColor, italic: overridden);
  }
}

// ---------------------------------------------------------------------------
// GD&T karakteristik sembolleri (ISO 1101 / ASME Y14.5)

const gdtCharacteristics = <String, String>{
  'flatness': 'Düzlük',
  'straightness': 'Doğrusallık',
  'circularity': 'Dairesellik',
  'cylindricity': 'Silindiriklik',
  'profileLine': 'Çizgi profili',
  'profileSurface': 'Yüzey profili',
  'parallelism': 'Paralellik',
  'perpendicularity': 'Diklik',
  'angularity': 'Açısallık',
  'position': 'Konum',
  'concentricity': 'Eş merkezlilik',
  'symmetry': 'Simetri',
  'runout': 'Salgı',
  'totalRunout': 'Toplam salgı',
};

/// s: kutu kenarı (mm). Sembolü (cx,cy) merkezli çizer.
void drawGdtSymbol(Canvas c, String kind, Offset ctr, double s, Color color) {
  final p = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.18, s * 0.05);
  final k = s * 0.32; // sembol yarı boyutu
  final x = ctr.dx, y = ctr.dy;
  switch (kind) {
    case 'flatness':
      c.drawPath(
          Path()
            ..moveTo(x - k, y + k * 0.45)
            ..lineTo(x - k * 0.4, y - k * 0.45)
            ..lineTo(x + k, y - k * 0.45)
            ..lineTo(x + k * 0.4, y + k * 0.45)
            ..close(),
          p);
    case 'straightness':
      c.drawLine(Offset(x - k, y), Offset(x + k, y), p);
    case 'circularity':
      c.drawCircle(ctr, k * 0.8, p);
    case 'cylindricity':
      c.drawCircle(ctr, k * 0.6, p);
      c.drawLine(Offset(x - k * 0.9, y + k * 0.9), Offset(x - k * 0.2, y - k * 0.9), p);
      c.drawLine(Offset(x + k * 0.2, y + k * 0.9), Offset(x + k * 0.9, y - k * 0.9), p);
    case 'profileLine':
      c.drawArc(Rect.fromCircle(center: Offset(x, y + k * 0.4), radius: k * 0.85), math.pi, math.pi, false, p);
    case 'profileSurface':
      c.drawArc(Rect.fromCircle(center: Offset(x, y + k * 0.4), radius: k * 0.85), math.pi, math.pi, true, p);
    case 'parallelism':
      c.drawLine(Offset(x - k * 0.7, y + k), Offset(x - k * 0.1, y - k), p);
      c.drawLine(Offset(x + k * 0.1, y + k), Offset(x + k * 0.7, y - k), p);
    case 'perpendicularity':
      c.drawLine(Offset(x - k, y + k * 0.8), Offset(x + k, y + k * 0.8), p);
      c.drawLine(Offset(x, y + k * 0.8), Offset(x, y - k), p);
    case 'angularity':
      c.drawLine(Offset(x - k, y + k * 0.8), Offset(x + k, y + k * 0.8), p);
      c.drawLine(Offset(x - k, y + k * 0.8), Offset(x + k * 0.8, y - k * 0.6), p);
    case 'position':
      c.drawCircle(ctr, k * 0.6, p);
      c.drawLine(Offset(x - k, y), Offset(x + k, y), p);
      c.drawLine(Offset(x, y - k), Offset(x, y + k), p);
    case 'concentricity':
      c.drawCircle(ctr, k * 0.85, p);
      c.drawCircle(ctr, k * 0.4, p);
    case 'symmetry':
      c.drawLine(Offset(x - k, y), Offset(x + k, y), p);
      c.drawLine(Offset(x - k * 0.6, y - k * 0.55), Offset(x + k * 0.6, y - k * 0.55), p);
      c.drawLine(Offset(x - k * 0.6, y + k * 0.55), Offset(x + k * 0.6, y + k * 0.55), p);
    case 'runout':
      final a = Offset(x - k * 0.6, y + k), b = Offset(x + k * 0.6, y - k);
      c.drawLine(a, b, p);
      drawArrowHead(c, b, b - a, color, len: k * 0.7, width: k * 0.5);
    case 'totalRunout':
      final a1 = Offset(x - k * 0.9, y + k * 0.6), b1 = Offset(x - k * 0.1, y - k);
      final a2 = Offset(x + k * 0.1, y + k * 0.6), b2 = Offset(x + k * 0.9, y - k);
      c.drawLine(a1, b1, p);
      c.drawLine(a2, b2, p);
      c.drawLine(Offset(x - k, y + k * 0.6), Offset(x + k * 0.2, y + k * 0.6), p);
      drawArrowHead(c, b1, b1 - a1, color, len: k * 0.6, width: k * 0.45);
      drawArrowHead(c, b2, b2 - a2, color, len: k * 0.6, width: k * 0.45);
  }
}

void _paintGdtFrame(Canvas c, SymbolElement s) {
  final color = Color(s.color);
  final h = s.size; // çerçeve yüksekliği (≈ 2× metin yüksekliği)
  final th = h * 0.5;
  final p = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.18, h * 0.035);
  final kind = s.params['char'] ?? 'position';
  final dia = s.params['dia'] == '1';
  final mod = s.params['mod'] ?? '';
  final tol = '${dia ? 'Ø' : ''}${s.params['tol'] ?? '0,1'}${mod.isNotEmpty ? ' ($mod)' : ''}';
  final datums = [s.params['d1'], s.params['d2'], s.params['d3']].whereType<String>().where((d) => d.isNotEmpty).toList();

  final cells = <double>[h, measureText(tol, th).width + h * 0.6, for (final d in datums) math.max(h, measureText(d, th).width + h * 0.5)];
  final total = cells.fold<double>(0, (a, b) => a + b);
  c.save();
  c.translate(s.pos.dx, s.pos.dy);
  c.rotate(s.rotation);
  var x = -total / 2;
  final y0 = -h / 2;
  c.drawRect(Rect.fromLTWH(x, y0, total, h), p);
  for (var i = 0; i < cells.length; i++) {
    final w = cells[i];
    if (i > 0) c.drawLine(Offset(x, y0), Offset(x, y0 + h), p);
    final cx = x + w / 2;
    if (i == 0) {
      drawGdtSymbol(c, kind, Offset(cx, 0), h, color);
    } else if (i == 1) {
      drawText(c, tol, Offset(cx, 0), size: th, color: color);
    } else {
      drawText(c, datums[i - 2], Offset(cx, 0), size: th, color: color);
    }
    x += w;
  }
  c.restore();
}

void _paintDatum(Canvas c, SymbolElement s) {
  final color = Color(s.color);
  final h = s.size;
  final p = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.18, h * 0.035);
  c.save();
  c.translate(s.pos.dx, s.pos.dy);
  c.rotate(s.rotation);
  // pos = üçgenin tabanı (yüzeye oturur), kutu yukarıda
  final tri = Path()
    ..moveTo(-h * 0.3, 0)
    ..lineTo(h * 0.3, 0)
    ..lineTo(0, -h * 0.5)
    ..close();
  c.drawPath(tri, Paint()..color = color);
  c.drawLine(Offset(0, -h * 0.5), Offset(0, -h * 1.2), p);
  c.drawRect(Rect.fromCenter(center: Offset(0, -h * 1.7), width: h, height: h), p);
  c.restore();
  // harf her zaman dik okunur
  final boxCenter = s.pos + Offset(math.sin(s.rotation), -math.cos(s.rotation)) * (h * 1.7);
  drawText(c, s.params['letter'] ?? 'A', boxCenter, size: h * 0.5, color: color);
}

void _paintSurface(Canvas c, SymbolElement s) {
  final color = Color(s.color);
  final h = s.size; // ≈ 1.4 × metin yüksekliği
  final p = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.18, h * 0.04)
    ..strokeJoin = StrokeJoin.round;
  final proc = s.params['proc'] ?? 'remove';
  final ra = s.params['ra'] ?? '3,2';
  c.save();
  c.translate(s.pos.dx, s.pos.dy);
  c.rotate(s.rotation);
  // pos = sembolün ucu (yüzeye değer). 60° V, sağ kol uzun.
  final t60 = math.tan(math.pi / 6);
  final leftTop = Offset(-h * t60, -h);
  final rightTop = Offset(2 * h * t60 * 1.0 + h * 0.2, -2 * h);
  c.drawLine(Offset.zero, leftTop, p);
  c.drawLine(Offset.zero, rightTop, p);
  if (proc == 'remove') {
    final rx = h * t60; // sağ kolun y=-h'deki x'i
    c.drawLine(leftTop, Offset(rx * 1.0 + h * 0.1, -h), p);
  } else if (proc == 'keep') {
    c.drawCircle(Offset(0, -h * 0.55), h * 0.3, p);
  }
  // uzun kolun ucunda yatay çizgi + Ra
  final barEnd = rightTop + Offset(h * 2.6, 0);
  c.drawLine(rightTop, barEnd, p);
  drawText(c, 'Ra $ra', Offset((rightTop.dx + barEnd.dx) / 2, rightTop.dy + h * 0.45), size: h * 0.55, color: color);
  c.restore();
}

void _paintWeld(Canvas c, SymbolElement s) {
  final color = Color(s.color);
  final h = s.size;
  final p = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.18, h * 0.05);
  final wt = s.params['wt'] ?? 'fillet';
  final a = s.params['a'] ?? '';
  c.save();
  c.translate(s.pos.dx, s.pos.dy);
  c.rotate(s.rotation);
  // pos = ok ucu (birleşim). Ok çizgisi 45° yukarı sağa, referans çizgisi yatay.
  final joint = Offset(h * 2, -h * 2);
  c.drawLine(Offset.zero, joint, p);
  drawArrowHead(c, Offset.zero, -joint, color, len: h * 0.8, width: h * 0.35);
  final refEnd = joint + Offset(h * 5, 0);
  c.drawLine(joint, refEnd, p);
  final sx = joint.dx + h * 2.2;
  final base = joint.dy;
  switch (wt) {
    case 'fillet':
      c.drawPath(
          Path()
            ..moveTo(sx - h * 0.45, base)
            ..lineTo(sx - h * 0.45, base + h * 0.9)
            ..lineTo(sx + h * 0.45, base)
            ..close(),
          p);
    case 'v':
      c.drawLine(Offset(sx - h * 0.5, base + h * 0.9), Offset(sx, base), p);
      c.drawLine(Offset(sx + h * 0.5, base + h * 0.9), Offset(sx, base), p);
    case 'square':
      c.drawLine(Offset(sx - h * 0.25, base), Offset(sx - h * 0.25, base + h * 0.9), p);
      c.drawLine(Offset(sx + h * 0.25, base), Offset(sx + h * 0.25, base + h * 0.9), p);
  }
  if (a.isNotEmpty) {
    drawText(c, a, Offset(sx - h * 0.8, base + h * 0.5), size: h * 0.6, color: color, anchor: Alignment.centerRight);
  }
  if (s.params['around'] == '1') c.drawCircle(joint, h * 0.35, p);
  if (s.params['field'] == '1') {
    c.drawLine(joint, joint + Offset(0, -h * 1.4), p);
    c.drawPath(
        Path()
          ..moveTo(joint.dx, joint.dy - h * 1.4)
          ..lineTo(joint.dx + h * 0.8, joint.dy - h * 1.15)
          ..lineTo(joint.dx, joint.dy - h * 0.9)
          ..close(),
        Paint()..color = color);
  }
  c.restore();
}

// ---------------------------------------------------------------------------
// Motosiklet eğitim sembolleri

const coneOrange = Color(0xFFFF6D00);

void _paintCone(Canvas c, SymbolElement s) {
  final r = s.size / 2;
  final col = s.params['color'] != null ? Color(int.parse(s.params['color']!)) : coneOrange;
  c.drawCircle(s.pos, r, Paint()..color = col);
  c.drawCircle(s.pos, r * 0.45, Paint()..color = const Color(0xFFFFFFFF));
  c.drawCircle(s.pos, r * 0.22, Paint()..color = col);
}

void _paintMotorcycle(Canvas c, SymbolElement s) {
  // Üstten görünüş; size = toplam uzunluk (mm). Yön: +x (rotation ile döner)
  final l = s.size;
  final w = l * 0.16;
  final col = Color(s.color);
  final fill = Paint()..color = col;
  final stroke = Paint()
    ..color = col
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.2, l * 0.02)
    ..strokeCap = StrokeCap.round;
  c.save();
  c.translate(s.pos.dx, s.pos.dy);
  c.rotate(s.rotation);
  // tekerlekler
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(l * 0.36, 0), width: l * 0.26, height: w * 0.5), Radius.circular(w * 0.25)), fill);
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(-l * 0.36, 0), width: l * 0.28, height: w * 0.6), Radius.circular(w * 0.3)), fill);
  // gövde
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(0, 0), width: l * 0.55, height: w), Radius.circular(w * 0.5)),
      Paint()..color = col.withValues(alpha: 0.75));
  // gidon
  c.drawLine(Offset(l * 0.2, -l * 0.22), Offset(l * 0.2, l * 0.22), stroke);
  // sürücü kaskı
  c.drawCircle(Offset(-l * 0.02, 0), w * 0.55, Paint()..color = const Color(0xFFFFFFFF));
  c.drawCircle(Offset(-l * 0.02, 0), w * 0.55, stroke);
  c.restore();
}

void _paintGate(Canvas c, SymbolElement s, String fallback) {
  final w = double.tryParse(s.params['w'] ?? '') ?? s.size * 6;
  final col = s.kind == SymbolKind.startGate ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
  c.save();
  c.translate(s.pos.dx, s.pos.dy);
  c.rotate(s.rotation);
  final band = math.max(1.0, s.size * 0.5);
  // damalı şerit
  final n = math.max(4, (w / band).round());
  final cw = w / n;
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < 2; j++) {
      if ((i + j).isEven) {
        c.drawRect(Rect.fromLTWH(-w / 2 + i * cw, -band + j * band, cw, band), Paint()..color = const Color(0xFF212121));
      }
    }
  }
  c.drawRect(Rect.fromLTWH(-w / 2, -band, w, 2 * band),
      Paint()
        ..color = col
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.3);
  for (final x in [-w / 2, w / 2]) {
    c.drawCircle(Offset(x, 0), s.size / 2, Paint()..color = coneOrange);
  }
  drawText(c, s.params['label'] ?? fallback, Offset(0, -band - s.size * 0.8),
      size: math.max(2.5, s.size * 0.7), color: col, weight: FontWeight.w700);
  c.restore();
}

void _paintNorth(Canvas c, SymbolElement s) {
  final h = s.size;
  final col = Color(s.color);
  c.save();
  c.translate(s.pos.dx, s.pos.dy);
  c.rotate(s.rotation);
  c.drawPath(
      Path()
        ..moveTo(0, -h)
        ..lineTo(h * 0.4, h * 0.6)
        ..lineTo(0, h * 0.3)
        ..close(),
      Paint()..color = col);
  c.drawPath(
      Path()
        ..moveTo(0, -h)
        ..lineTo(-h * 0.4, h * 0.6)
        ..lineTo(0, h * 0.3)
        ..close(),
      Paint()
        ..color = col
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.25);
  drawText(c, 'K', Offset(0, -h * 1.45), size: h * 0.6, color: col, weight: FontWeight.w700);
  c.restore();
}

void paintSymbol(Canvas c, SymbolElement s) {
  switch (s.kind) {
    case SymbolKind.cone:
      _paintCone(c, s);
    case SymbolKind.motorcycle:
      _paintMotorcycle(c, s);
    case SymbolKind.startGate:
      _paintGate(c, s, 'START');
    case SymbolKind.finishGate:
      _paintGate(c, s, 'FİNİŞ');
    case SymbolKind.northArrow:
      _paintNorth(c, s);
    case SymbolKind.gdtFrame:
      _paintGdtFrame(c, s);
    case SymbolKind.datum:
      _paintDatum(c, s);
    case SymbolKind.surface:
      _paintSurface(c, s);
    case SymbolKind.weld:
      _paintWeld(c, s);
  }
}

// ---------------------------------------------------------------------------
// Şerit / yol

List<Offset> offsetPolyline(List<Offset> pts, double d) {
  if (pts.length < 2) return pts;
  final out = <Offset>[];
  for (var i = 0; i < pts.length; i++) {
    Offset n;
    if (i == 0) {
      final t = pts[1] - pts[0];
      n = Offset(-t.dy, t.dx) / math.max(t.distance, 1e-9);
    } else if (i == pts.length - 1) {
      final t = pts[i] - pts[i - 1];
      n = Offset(-t.dy, t.dx) / math.max(t.distance, 1e-9);
    } else {
      final t1 = pts[i] - pts[i - 1], t2 = pts[i + 1] - pts[i];
      final n1 = Offset(-t1.dy, t1.dx) / math.max(t1.distance, 1e-9);
      final n2 = Offset(-t2.dy, t2.dx) / math.max(t2.distance, 1e-9);
      final m = n1 + n2;
      final ml = m.distance;
      if (ml < 1e-6) {
        n = n1;
      } else {
        final cosHalf = (n1.dx * m.dx + n1.dy * m.dy) / ml;
        n = m / ml / math.max(cosHalf, 0.3); // keskin dönüşte sınırla
      }
    }
    out.add(pts[i] + n * d);
  }
  return out;
}

void paintLane(Canvas c, LaneElement l) {
  if (l.centerline.length < 2) return;
  final half = l.widthPaper * l.lanes / 2;
  final leftEdge = offsetPolyline(l.centerline, half);
  final rightEdge = offsetPolyline(l.centerline, -half);
  final area = Path()..addPolygon([...leftEdge, ...rightEdge.reversed], true);
  c.drawPath(area, Paint()..color = Color(l.color).withValues(alpha: 0.18));
  final edge = Paint()
    ..color = Color(l.color)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.45
    ..strokeJoin = StrokeJoin.round;
  c.drawPath(smoothPath(leftEdge), edge);
  c.drawPath(smoothPath(rightEdge), edge);
  // şerit ayırıcıları
  for (var i = 1; i < l.lanes; i++) {
    final d = -half + i * l.widthPaper;
    final p = smoothPath(offsetPolyline(l.centerline, d));
    final dash = math.max(1.5, l.widthPaper * 0.8);
    c.drawPath(
        dashPath(p, [dash, dash]),
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5);
    c.drawPath(
        dashPath(p, [dash, dash]),
        Paint()
          ..color = Color(l.color)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.25);
  }
  // genişlik etiketi
  final mid = l.centerline[l.centerline.length ~/ 2];
  final a = l.centerline[math.max(0, l.centerline.length ~/ 2 - 1)];
  final b = l.centerline[math.min(l.centerline.length - 1, l.centerline.length ~/ 2 + 1)];
  final label = l.lanes > 1 ? '${l.lanes}×${formatNumber(l.widthReal)} m' : '${formatNumber(l.widthReal)} m';
  drawText(c, label, mid, size: math.max(2.0, math.min(3.5, l.widthPaper * 0.45)), color: Color(l.color), rotation: readableAngle(b - a));
}

// ---------------------------------------------------------------------------

void paintElement(Canvas c, NoteElement e, ScaleSpec scale) {
  switch (e) {
    case StrokeElement s:
      paintStroke(c, s.points, s.style);
    case ShapeElement s:
      paintShape(c, s);
    case DimensionElement d:
      paintDimension(c, d, scale);
    case TextElement t:
      paintText(c, t);
    case SymbolElement s:
      paintSymbol(c, s);
    case LaneElement l:
      paintLane(c, l);
    case ImageElement i:
      paintImage(c, i);
    case AudioElement a:
      paintAudio(c, a);
    default:
      break;
  }
}

/// Seçim kutusu
void paintSelection(Canvas c, Rect r, double zoom) {
  final p = Paint()
    ..color = const Color(0xFF1E88E5)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2 / zoom;
  c.drawPath(dashPath(Path()..addRect(r.inflate(1.5)), [4 / zoom, 3 / zoom]), p);
}

// ---------------------------------------------------------------------------
// Metin: font, kalın/italik/altı çizili, arka plan, kutu, onay listesi, madde işareti

String? fontFamilyFor(FontKind f) => switch (f) {
      FontKind.sans => 'Roboto',
      FontKind.serif => Platform.isWindows ? 'Times New Roman' : 'serif',
      FontKind.mono => Platform.isWindows ? 'Consolas' : 'monospace',
    };

TextStyle textStyleOf(TextElement t, {bool done = false}) => TextStyle(
      fontFamily: fontFamilyFor(t.font),
      fontSize: t.size,
      height: 1.0,
      color: Color(t.color).withValues(alpha: done ? 0.45 : 1),
      fontWeight: t.bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: t.italic ? FontStyle.italic : FontStyle.normal,
      decoration: done ? TextDecoration.lineThrough : (t.underline ? TextDecoration.underline : TextDecoration.none),
    );

void paintText(Canvas c, TextElement t) {
  final b = t.bounds;
  if (t.background != null) {
    c.drawRRect(RRect.fromRectAndRadius(b, Radius.circular(t.size * 0.25)), Paint()..color = Color(t.background!));
  }
  if (t.kind == TextKind.box) {
    c.drawRRect(
        RRect.fromRectAndRadius(b, Radius.circular(t.size * 0.25)),
        Paint()
          ..color = Color(t.color).withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.2, t.size * 0.05));
  }
  final ls = t.lines;
  for (var i = 0; i < ls.length; i++) {
    var line = ls[i];
    final y = t.pos.dy + i * t.lineHeight;
    var done = false;
    if (t.kind == TextKind.checklist) {
      final box = t.checkboxRect(i);
      final checked = line.startsWith('[x] ');
      if (line.startsWith('[x] ') || line.startsWith('[ ] ')) line = line.substring(4);
      done = checked;
      final p = Paint()
        ..color = Color(t.color)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.2, t.size * 0.07);
      c.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(t.size * 0.15)), p);
      if (checked) {
        c.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(t.size * 0.15)), Paint()..color = Color(t.color));
        final tick = Path()
          ..moveTo(box.left + box.width * 0.22, box.top + box.height * 0.52)
          ..lineTo(box.left + box.width * 0.42, box.top + box.height * 0.72)
          ..lineTo(box.left + box.width * 0.8, box.top + box.height * 0.28);
        c.drawPath(
            tick,
            Paint()
              ..color = const Color(0xFFFFFFFF)
              ..style = PaintingStyle.stroke
              ..strokeWidth = t.size * 0.12
              ..strokeCap = StrokeCap.round);
      }
    } else if (t.kind == TextKind.bullet && line.trim().isNotEmpty) {
      c.drawCircle(Offset(t.pos.dx + t.size * 0.35, y + t.size * 0.55), t.size * 0.16, Paint()..color = Color(t.color));
    }
    final tp = TextPainter(
      text: TextSpan(text: line, style: textStyleOf(t, done: done)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: t.boxWidth != null ? math.max(1, t.boxWidth! - t.indent) : double.infinity);
    tp.paint(c, Offset(t.pos.dx + t.indent, y));
  }
}

// ---------------------------------------------------------------------------
// Görsel ve ses

void paintImage(Canvas c, ImageElement e) {
  final img = AssetImages.instance.get(e.assetId);
  c.save();
  if (e.rotation != 0) {
    c.translate(e.rect.center.dx, e.rect.center.dy);
    c.rotate(e.rotation);
    c.translate(-e.rect.center.dx, -e.rect.center.dy);
  }
  if (img == null) {
    c.drawRect(e.rect, Paint()..color = const Color(0xFFECEFF1));
    c.drawRect(
        e.rect,
        Paint()
          ..color = const Color(0xFFB0BEC5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.3);
    drawText(c, 'Görsel yükleniyor…', e.rect.center, size: 3, color: const Color(0xFF78909C));
  } else {
    c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), e.rect,
        Paint()..filterQuality = FilterQuality.medium);
  }
  c.restore();
}

String formatDuration(int ms) {
  final s = (ms / 1000).round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

void paintAudio(Canvas c, AudioElement a) {
  final r = a.bounds;
  c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4.5)), Paint()..color = const Color(0xFFE3F2FD));
  c.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(4.5)),
      Paint()
        ..color = const Color(0xFF1565C0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.3);
  final cx = r.left + 4.5, cy = r.center.dy;
  c.drawCircle(Offset(cx, cy), 3.2, Paint()..color = const Color(0xFF1565C0));
  c.drawPath(
      Path()
        ..moveTo(cx - 1.1, cy - 1.7)
        ..lineTo(cx + 1.9, cy)
        ..lineTo(cx - 1.1, cy + 1.7)
        ..close(),
      Paint()..color = const Color(0xFFFFFFFF));
  drawText(c, a.label.isEmpty ? 'Ses · ${formatDuration(a.durationMs)}' : '${a.label} · ${formatDuration(a.durationMs)}',
      Offset(r.left + 9.5, cy), size: 3, color: const Color(0xFF0D47A1), anchor: Alignment.centerLeft);
}
