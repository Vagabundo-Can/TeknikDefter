// Mürekkep güzelleştirme: canlı titreşim filtresi, yumuşatma, şekil tanıma ve el yazısı hizalama.

import 'dart:math' as math;
import 'dart:ui';

import '../models/note_models.dart';

// ---------------------------------------------------------------------------
// 1 € filtresi (Casiez vd. 2012) — kalem titreşimini gecikme yaratmadan bastırır.

class _LowPass {
  double? _y;
  double filter(double x, double alpha) {
    final y = _y == null ? x : alpha * x + (1 - alpha) * _y!;
    _y = y;
    return y;
  }

  double? get last => _y;
}

class OneEuroFilter {
  final double minCutoff; // Hz
  final double beta;
  final double dCutoff;
  final _x = _LowPass(), _dx = _LowPass();
  double? _lastT;
  double? _lastRaw;

  OneEuroFilter({this.minCutoff = 2.0, this.beta = 0.05, this.dCutoff = 1.0});

  static double _alpha(double cutoff, double dt) {
    final tau = 1.0 / (2 * math.pi * cutoff);
    return 1.0 / (1.0 + tau / dt);
  }

  /// t saniye cinsinden
  double filter(double x, double t) {
    if (_lastT == null) {
      _lastT = t;
      _lastRaw = x;
      return _x.filter(x, 1);
    }
    final dt = math.max(1e-3, t - _lastT!);
    _lastT = t;
    final dx = (x - _lastRaw!) / dt;
    _lastRaw = x;
    final edx = _dx.filter(dx, _alpha(dCutoff, dt));
    final cutoff = minCutoff + beta * edx.abs();
    return _x.filter(x, _alpha(cutoff, dt));
  }
}

class PointFilter {
  final OneEuroFilter fx, fy;
  PointFilter({double minCutoff = 2.0, double beta = 0.05})
      : fx = OneEuroFilter(minCutoff: minCutoff, beta: beta),
        fy = OneEuroFilter(minCutoff: minCutoff, beta: beta);
  Offset filter(Offset p, double tSec) => Offset(fx.filter(p.dx, tSec), fy.filter(p.dy, tSec));
}

// ---------------------------------------------------------------------------
// Yumuşatma

/// Chaikin köşe kesme; uç noktalar korunur. level 0..3
List<InkPoint> chaikin(List<InkPoint> pts, int level) {
  var cur = pts;
  for (var k = 0; k < level && cur.length > 2; k++) {
    final out = <InkPoint>[cur.first];
    for (var i = 0; i + 1 < cur.length; i++) {
      final a = cur[i], b = cur[i + 1];
      out.add(InkPoint(0.75 * a.x + 0.25 * b.x, 0.75 * a.y + 0.25 * b.y, 0.75 * a.p + 0.25 * b.p,
          (0.75 * a.t + 0.25 * b.t).round()));
      out.add(InkPoint(0.25 * a.x + 0.75 * b.x, 0.25 * a.y + 0.75 * b.y, 0.25 * a.p + 0.75 * b.p,
          (0.25 * a.t + 0.75 * b.t).round()));
    }
    out.add(cur.last);
    cur = out;
  }
  return cur;
}

List<Offset> chaikinOffsets(List<Offset> pts, int level) {
  var cur = pts;
  for (var k = 0; k < level && cur.length > 2; k++) {
    final out = <Offset>[cur.first];
    for (var i = 0; i + 1 < cur.length; i++) {
      out.add(cur[i] * 0.75 + cur[i + 1] * 0.25);
      out.add(cur[i] * 0.25 + cur[i + 1] * 0.75);
    }
    out.add(cur.last);
    cur = out;
  }
  return cur;
}

/// Çok yakın noktaları ayıkla (mm)
List<InkPoint> decimate(List<InkPoint> pts, double minDist) {
  if (pts.length < 3) return pts;
  final out = <InkPoint>[pts.first];
  for (var i = 1; i < pts.length - 1; i++) {
    if ((pts[i].o - out.last.o).distance >= minDist) out.add(pts[i]);
  }
  out.add(pts.last);
  return out;
}

// ---------------------------------------------------------------------------
// Geometri yardımcıları

double pathLength(List<Offset> p) {
  var l = 0.0;
  for (var i = 0; i + 1 < p.length; i++) {
    l += (p[i + 1] - p[i]).distance;
  }
  return l;
}

double distToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 < 1e-12) return (p - a).distance;
  var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2;
  t = t.clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

/// Douglas–Peucker
List<Offset> simplify(List<Offset> pts, double eps) {
  if (pts.length < 3) return List.of(pts);
  final keep = List<bool>.filled(pts.length, false);
  keep[0] = keep[pts.length - 1] = true;
  final stack = <(int, int)>[(0, pts.length - 1)];
  while (stack.isNotEmpty) {
    final (s, e) = stack.removeLast();
    var maxD = 0.0;
    var idx = -1;
    for (var i = s + 1; i < e; i++) {
      final d = distToSegment(pts[i], pts[s], pts[e]);
      if (d > maxD) {
        maxD = d;
        idx = i;
      }
    }
    if (idx >= 0 && maxD > eps) {
      keep[idx] = true;
      stack.add((s, idx));
      stack.add((idx, e));
    }
  }
  return [for (var i = 0; i < pts.length; i++) if (keep[i]) pts[i]];
}

double _angleDeg(Offset v) => math.atan2(v.dy, v.dx) * 180 / math.pi;

/// Açıyı en yakın 15°'ye (veya verilen adıma) kilitle
Offset snapAngle(Offset from, Offset to, {double stepDeg = 15}) {
  final v = to - from;
  final len = v.distance;
  if (len < 1e-6) return to;
  final a = (_angleDeg(v) / stepDeg).round() * stepDeg * math.pi / 180;
  return from + Offset(math.cos(a), math.sin(a)) * len;
}

bool pointInPolygon(Offset p, List<Offset> poly) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if (((a.dy > p.dy) != (b.dy > p.dy)) && (p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx)) {
      inside = !inside;
    }
  }
  return inside;
}

// ---------------------------------------------------------------------------
// Şekil tanıma (çizgi bitince kalem 450 ms sabit tutulursa)

class RecognizedShape {
  final ShapeKind kind;
  final List<Offset> points;
  const RecognizedShape(this.kind, this.points);
}

RecognizedShape? recognizeShape(List<Offset> raw) {
  if (raw.length < 4) return null;
  final pts = raw;
  final len = pathLength(pts);
  if (len < 4) return null;
  final first = pts.first, last = pts.last;
  final bb = Rect.fromPoints(first, first).expandToInclude(Rect.fromPoints(last, last));
  var box = bb;
  for (final p in pts) {
    box = box.expandToInclude(Rect.fromPoints(p, p));
  }
  final diag = math.sqrt(box.width * box.width + box.height * box.height);

  // --- Doğru
  final chord = (last - first).distance;
  if (chord > 0.85 * len) {
    var maxDev = 0.0;
    for (final p in pts) {
      maxDev = math.max(maxDev, distToSegment(p, first, last));
    }
    if (maxDev < 0.04 * len) {
      var end = last;
      final a = _angleDeg(last - first);
      // 0/45/90° yakınsa (±5°) oturt
      final snapped = (a / 45).round() * 45.0;
      if ((a - snapped).abs() < 5) end = snapAngle(first, last, stepDeg: 45);
      return RecognizedShape(ShapeKind.line, [first, end]);
    }
    return null;
  }

  // --- Kapalı şekiller
  final closed = (last - first).distance < 0.12 * len;
  if (!closed) return null;

  // Poligon testi
  var poly = simplify(pts, 0.06 * diag);
  if (poly.length > 2 && (poly.first - poly.last).distance < 0.12 * len) poly = poly.sublist(0, poly.length - 1);
  poly = _dropStraightVertices(poly, 25);
  // poligon gerçekten noktalara oturuyor mu?
  bool fits(List<Offset> pg) {
    for (final p in pts) {
      var d = double.infinity;
      for (var i = 0; i < pg.length; i++) {
        d = math.min(d, distToSegment(p, pg[i], pg[(i + 1) % pg.length]));
      }
      if (d > 0.08 * diag) return false;
    }
    return true;
  }

  if ((poly.length == 3 || poly.length == 4) && !fits(poly)) poly = const [];
  if (poly.length == 3) {
    return RecognizedShape(ShapeKind.triangle, poly);
  }
  if (poly.length == 4) {
    // Kenarlar eksene ±8° yakınsa eksen hizalı dikdörtgen
    var axisAligned = true;
    for (var i = 0; i < 4; i++) {
      final a = _angleDeg(poly[(i + 1) % 4] - poly[i]).abs() % 90;
      if (!(a < 8 || a > 82)) axisAligned = false;
    }
    if (axisAligned) {
      return RecognizedShape(ShapeKind.rect, [box.topLeft, box.bottomRight]);
    }
    return RecognizedShape(ShapeKind.polygon, poly);
  }

  // Elips / daire testi
  final c = box.center;
  final rx = box.width / 2, ry = box.height / 2;
  if (rx < 1 || ry < 1) return null;
  final rs = [
    for (final p in pts)
      math.sqrt(math.pow((p.dx - c.dx) / rx, 2) + math.pow((p.dy - c.dy) / ry, 2))
  ];
  final mean = rs.reduce((a, b) => a + b) / rs.length;
  final variance = rs.map((r) => (r - mean) * (r - mean)).reduce((a, b) => a + b) / rs.length;
  final cv = math.sqrt(variance) / mean;
  if (cv < 0.12) {
    if ((rx - ry).abs() / math.max(rx, ry) < 0.15) {
      final r = (rx + ry) / 2;
      return RecognizedShape(ShapeKind.ellipse, [c - Offset(r, r), c + Offset(r, r)]);
    }
    return RecognizedShape(ShapeKind.ellipse, [box.topLeft, box.bottomRight]);
  }
  return null;
}

/// Kapalı poligonda ~düz açılı (sapma < tolDeg) köşeleri at
List<Offset> _dropStraightVertices(List<Offset> poly, double tolDeg) {
  var p = List.of(poly);
  var changed = true;
  while (changed && p.length > 3) {
    changed = false;
    for (var i = 0; i < p.length; i++) {
      final a = p[(i - 1 + p.length) % p.length], b = p[i], c = p[(i + 1) % p.length];
      final d = (_angleDeg(c - b) - _angleDeg(b - a)).abs() % 360;
      final dev = math.min(d, 360 - d);
      if (dev < tolDeg) {
        p.removeAt(i);
        changed = true;
        break;
      }
    }
  }
  return p;
}

// ---------------------------------------------------------------------------
// El yazısı hizalama

class _Item {
  final StrokeElement s;
  final Rect b;
  _Item(this.s) : b = s.bounds;
}

double _percentile(List<double> v, double q) {
  final s = List.of(v)..sort();
  final i = ((s.length - 1) * q).round().clamp(0, s.length - 1);
  return s[i];
}

/// Seçili el yazısı çizgilerini satır/kelime olarak gruplar; her kelimenin taban çizgisini
/// satırın ortak tabanına (ya da [ruleSpacing] verilirse en yakın sayfa çizgisine) taşır,
/// kelime aralıklarını medyana eşitler. Dönüş: yeni (aynı id'li) çizgiler.
List<StrokeElement> alignHandwriting(List<StrokeElement> strokes, {double? ruleSpacing, double ruleOffset = 0}) {
  final items = [
    for (final s in strokes)
      if (s.style.type != PenType.highlighter && s.points.length > 1) _Item(s)
  ];
  if (items.length < 2) return strokes;
  final hMed = _percentile([for (final i in items) math.max(i.b.height, 0.5)], 0.5);

  // Satırlar
  items.sort((a, b) => a.b.center.dy.compareTo(b.b.center.dy));
  final lines = <List<_Item>>[];
  double? lineCy;
  for (final it in items) {
    if (lineCy == null || it.b.center.dy - lineCy > 0.9 * hMed) {
      lines.add([it]);
      lineCy = it.b.center.dy;
    } else {
      lines.last.add(it);
      final l = lines.last;
      lineCy = l.map((e) => e.b.center.dy).reduce((a, b) => a + b) / l.length;
    }
  }

  final out = <StrokeElement>[];
  for (final line in lines) {
    line.sort((a, b) => a.b.left.compareTo(b.b.left));
    // Kelimeler
    final words = <List<_Item>>[];
    double right = -double.infinity;
    for (final it in line) {
      if (words.isEmpty || it.b.left - right > 0.5 * hMed) {
        words.add([it]);
      } else {
        words.last.add(it);
      }
      right = math.max(right, it.b.right);
    }
    // Kelime tabanları (y'nin %80 yüzdeliği = alttan %20)
    final baselines = <double>[];
    for (final w in words) {
      final ys = [for (final it in w) for (final p in it.s.points) p.y];
      baselines.add(_percentile(ys, 0.8));
    }
    var target = _percentile(baselines, 0.5);
    if (ruleSpacing != null && ruleSpacing > 0) {
      target = ((target - ruleOffset) / ruleSpacing).round() * ruleSpacing + ruleOffset;
    }
    // Aralıklar
    final gaps = <double>[];
    for (var i = 0; i + 1 < words.length; i++) {
      final r = words[i].map((e) => e.b.right).reduce(math.max);
      final l = words[i + 1].map((e) => e.b.left).reduce(math.min);
      gaps.add(math.max(0.0, l - r));
    }
    final gapMed = gaps.isEmpty ? 0.0 : _percentile(gaps, 0.5);

    double? cursor;
    for (var wi = 0; wi < words.length; wi++) {
      final w = words[wi];
      final left = w.map((e) => e.b.left).reduce(math.min);
      final wRight = w.map((e) => e.b.right).reduce(math.max);
      final dx = cursor == null ? 0.0 : cursor - left;
      final dy = target - baselines[wi];
      for (final it in w) {
        out.add(it.s.translated(Offset(dx, dy)));
      }
      cursor = (wRight + dx) + gapMed;
    }
  }
  return out;
}
