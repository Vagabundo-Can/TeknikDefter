// Ekran görüntüleri ve kılavuz için örnek defterler / sayfalar.

import 'dart:math' as math;
import 'dart:ui';

import 'package:teknik_defter/models/note_models.dart';
import 'package:teknik_defter/storage/local_store.dart';
import 'package:teknik_defter/templates/templates.dart';

var _z = 1.0;
double _nz() => _z += 1;

StrokeElement _ink(List<Offset> pts, {PenType type = PenType.fountain, int color = 0xFF1A237E, double width = 0.55}) {
  return StrokeElement(
    id: newId(),
    updatedAt: 1,
    z: _nz(),
    style: PenStyle(type: type, color: color, width: width),
    points: [
      for (var i = 0; i < pts.length; i++)
        InkPoint(pts[i].dx, pts[i].dy, 0.45 + 0.35 * math.sin(i / 3).abs(), i * 12)
    ],
  );
}

/// El yazısına benzeyen kelime izi (sentetik): x0'dan başlayıp genişlik kadar dalgalanır
List<StrokeElement> fakeWord(double x0, double baseline, double width, {double h = 3.2, int seed = 0, int color = 0xFF1A237E}) {
  final rnd = math.Random(seed);
  final pts = <Offset>[];
  final n = (width * 3).round();
  for (var i = 0; i <= n; i++) {
    final t = i / n;
    final x = x0 + t * width + 0.6 * math.sin(t * 22 + seed);
    final y = baseline - h * 0.5 - h * 0.5 * math.sin(t * 22 + seed) * (0.6 + 0.4 * rnd.nextDouble());
    pts.add(Offset(x, y));
  }
  final strokes = [_ink(pts, color: color)];
  // bir harfe üst uzantı
  final ax = x0 + width * (0.2 + 0.5 * rnd.nextDouble());
  strokes.add(_ink([Offset(ax, baseline - h * 0.4), Offset(ax + 0.4, baseline - h * 1.6), Offset(ax + 0.9, baseline - h * 0.5)], color: color));
  return strokes;
}

List<StrokeElement> fakeLine(double x0, double baseline, List<double> words, {int seed = 0, int color = 0xFF1A237E, double jitter = 0}) {
  final out = <StrokeElement>[];
  var x = x0;
  for (var i = 0; i < words.length; i++) {
    out.addAll(fakeWord(x, baseline + (i.isOdd ? jitter : -jitter * 0.6), words[i], seed: seed + i, color: color));
    x += words[i] + 3.2;
  }
  return out;
}

ShapeElement _shape(ShapeKind k, List<Offset> pts, {double w = 0.5, LineType lt = LineType.continuous, int color = 0xFF000000}) => ShapeElement(
    id: newId(),
    updatedAt: 1,
    z: _nz(),
    kind: k,
    points: pts,
    style: PenStyle(type: PenType.technical, color: color, width: w, lineType: lt));

DimensionElement _dim(DimKind k, List<Offset> pts, {DimTolerance tol = const DimTolerance(), double h = 3.5, int color = 0xFF0D47A1}) =>
    DimensionElement(id: newId(), updatedAt: 1, z: _nz(), kind: k, points: pts, tolerance: tol, textHeight: h, color: color);

SymbolElement _sym(SymbolKind k, Offset p, {double size = 5, double rot = 0, Map<String, String> params = const {}, int color = 0xFF000000}) =>
    SymbolElement(id: newId(), updatedAt: 1, z: _nz(), kind: k, pos: p, size: size, rotation: rot, params: params, color: color);

TextElement _text(Offset p, String t, {double size = 4, int color = 0xFF1A237E, bool ink = true}) =>
    TextElement(id: newId(), updatedAt: 1, z: _nz(), pos: p, text: t, size: size, color: color, fromInk: ink);

class SampleIds {
  late String engNotebook, motoNotebook;
  late String bracketPage, gymkhanaPage, roadPage, evalPage, reviewPage, lessonPage;
  late Set<String> handwriting;
}

SampleIds seedSamples(LocalStore store) {
  final ids = SampleIds();
  store.notebooks.clear();
  store.pages.clear();
  final eng = store.createNotebook('Mühendislik', 0xFF1565C0);
  final moto = store.createNotebook('Akıncı Eğitim', 0xFFEF6C00);
  store.createNotebook('Kişisel', 0xFF2E7D32);
  ids.engNotebook = eng.id;
  ids.motoNotebook = moto.id;

  // ---------------- Braket tasarım notu
  final b = store.createPage(notebookId: eng.id, mode: PageMode.engineering, template: templateById('engpad'), title: 'REDET braket — eskiz');
  ids.bracketPage = b.id;
  final els = <NoteElement>[
    _shape(ShapeKind.rect, const [Offset(40, 60), Offset(120, 110)]),
    _shape(ShapeKind.ellipse, const [Offset(52, 77), Offset(68, 93)]),
    _shape(ShapeKind.ellipse, const [Offset(92, 77), Offset(108, 93)]),
    _shape(ShapeKind.centerline, const [Offset(60, 72), Offset(60, 98)], w: 0.25),
    _shape(ShapeKind.centerline, const [Offset(100, 72), Offset(100, 98)], w: 0.25),
    _shape(ShapeKind.centerline, const [Offset(46, 85), Offset(114, 85)], w: 0.25),
    _shape(ShapeKind.line, const [Offset(40, 70), Offset(120, 70)], w: 0.35, lt: LineType.hidden),
    _dim(DimKind.horizontal, const [Offset(40, 110), Offset(120, 110), Offset(80, 124)]),
    _dim(DimKind.vertical, const [Offset(120, 60), Offset(120, 110), Offset(134, 85)]),
    _dim(DimKind.horizontal, const [Offset(60, 85), Offset(100, 85), Offset(80, 50)], tol: const DimTolerance(upper: 0.05, lower: -0.05)),
    _dim(DimKind.diameter, const [Offset(100, 85), Offset(108, 85), Offset(140, 62)], tol: const DimTolerance(fit: 'H7')),
    _sym(SymbolKind.gdtFrame, const Offset(80, 140), size: 6, params: {'char': 'position', 'tol': '0,1', 'dia': '1', 'mod': 'M', 'd1': 'A', 'd2': 'B', 'd3': ''}),
    _sym(SymbolKind.gdtFrame, const Offset(80, 150), size: 6, params: {'char': 'flatness', 'tol': '0,05', 'dia': '0', 'mod': ''}),
    _sym(SymbolKind.datum, const Offset(62, 110), size: 5, rot: math.pi, params: {'letter': 'A'}),
    _sym(SymbolKind.datum, const Offset(40, 98), size: 5, rot: -math.pi / 2, params: {'letter': 'B'}),
    _sym(SymbolKind.surface, const Offset(88, 60), size: 3.5, params: {'ra': '1,6', 'proc': 'remove'}),
    _sym(SymbolKind.weld, const Offset(120, 104), size: 3, params: {'wt': 'fillet', 'a': 'a4', 'around': '1', 'field': '0'}),
    _text(const Offset(24, 168), 'Malzeme: Al 6061-T6, siyah eloksal', size: 4.5),
    _text(const Offset(24, 176), 'Delikler raybalı · genel tol. ISO 2768-mK', size: 4.5),
    _text(const Offset(24, 184), 'Kenarlar 0,5×45° pah', size: 4.5),
  ];
  // fosforlu vurgu + elle daire içine alma
  els.add(_ink([const Offset(23, 176.5), const Offset(110, 176.5)], type: PenType.highlighter, color: 0xFFFFEB3B, width: 5));
  final circ = [
    for (var i = 0; i <= 40; i++) Offset(153 + 16 * math.cos(i / 40 * 2.1 * math.pi) + 0.6 * math.sin(i * 1.7), 80 + 10 * math.sin(i / 40 * 2.1 * math.pi))
  ];
  els.add(_ink(circ, color: 0xFFC62828, width: 0.5));
  // el yazısı not (seçim için)
  final hw = [
    ...fakeLine(140, 82, [9, 7], seed: 3, color: 0xFFC62828),
    ...fakeLine(24, 205, [12, 8, 16, 10], seed: 11, jitter: 1.4),
    ...fakeLine(24, 214, [14, 9, 11], seed: 21, jitter: 1.0),
  ];
  els.addAll(hw);
  ids.handwriting = {for (final s in hw.skip(4)) s.id};
  for (final e in els) {
    b.put(e);
  }

  // ---------------- Gymkhana parkuru (1:200 → 1 m = 5 mm)
  final g = store.createPage(notebookId: moto.id, mode: PageMode.moto, template: templateById('gymkhana'), title: 'Gymkhana — Cumartesi');
  ids.gymkhanaPage = g.id;
  double m(double meters) => meters * 5;
  const cone = 2.4;
  final gEls = <NoteElement>[
    LaneElement(id: newId(), updatedAt: 1, z: _nz(), centerline: [Offset(30, m(10)), Offset(150, m(10))], widthPaper: m(2.5), widthReal: 2.5),
    _sym(SymbolKind.startGate, Offset(m(6), m(34)), size: 2.1, rot: -math.pi / 2, params: {'w': '${m(4)}'}),
    _sym(SymbolKind.finishGate, Offset(30, m(10)), size: 2.1, rot: -math.pi / 2, params: {'w': '${m(4)}'}),
    _sym(SymbolKind.northArrow, const Offset(276, 36), size: 6, color: 0xFF263238),
    _sym(SymbolKind.motorcycle, Offset(m(6), m(37.5)), size: m(2.2), rot: -math.pi / 2, color: 0xFF263238),
  ];
  // slalom: x = 15..39 m, y = 30 m, 4 m ara
  for (var x = 15.0; x <= 39; x += 4) {
    gEls.add(_sym(SymbolKind.cone, Offset(m(x), m(30)), size: cone, params: {'color': '${0xFFFF6D00}'}));
  }
  // sekiz: merkezler (46,24) ve (46,12), r=5 m
  for (final c in [const Offset(46, 24), const Offset(46, 13)]) {
    gEls.add(_sym(SymbolKind.cone, Offset(m(c.dx), m(c.dy)), size: cone, params: {'color': '${0xFF2962FF}'}));
    for (var i = 0; i < 10; i++) {
      final a = i / 10 * 2 * math.pi;
      gEls.add(_sym(SymbolKind.cone, Offset(m(c.dx + 5 * math.cos(a)), m(c.dy + 5 * math.sin(a))), size: cone, params: {'color': '${0xFFFFD600}'}));
    }
  }
  // fren koridoru konileri
  for (var x = 8.0; x <= 28; x += 4) {
    for (final y in [8.75, 11.25]) {
      gEls.add(_sym(SymbolKind.cone, Offset(m(x), m(y)), size: cone * 0.8, params: {'color': '${0xFFD50000}'}));
    }
  }
  // rota: start → slalom → sekiz (Gerono eğrisi) → fren koridoru → finiş
  final route = <Offset>[Offset(m(6), m(33)), Offset(m(10), m(31.5)), Offset(m(13), m(30))];
  for (var x = 15.0; x <= 39; x += 4) {
    final odd = ((x - 15) / 4).round().isOdd;
    route.add(Offset(m(x + 2), m(odd ? 32.0 : 28.0)));
  }
  route.add(Offset(m(43), m(26)));
  for (var i = 0; i <= 48; i++) {
    final t = math.pi + i / 48 * 2 * math.pi; // merkezden başla, iki ilmek
    route.add(Offset(m(46 + 7.5 * math.sin(t) * math.cos(t) * 2), m(18.5 - 11.5 * math.sin(t))));
  }
  route.addAll([Offset(m(40), m(13)), Offset(m(33), m(10)), Offset(m(8), m(10))]);
  gEls.add(ShapeElement(
      id: newId(),
      updatedAt: 1,
      z: _nz(),
      kind: ShapeKind.route,
      points: route,
      style: const PenStyle(type: PenType.technical, color: 0xFF1565C0, width: 0.7, lineType: LineType.hidden)));
  gEls.add(_dim(DimKind.aligned, [Offset(m(15), m(30)), Offset(m(19), m(30)), Offset(m(17), m(33.5))], h: 3, color: 0xFF6A1B9A));
  gEls.add(_dim(DimKind.aligned, [Offset(m(41), m(24)), Offset(m(51), m(24)), Offset(m(46), m(36))], h: 3, color: 0xFF6A1B9A));
  gEls.add(_text(Offset(m(14), m(36.5)), 'Slalom 7 koni · 4 m', size: 3.5));
  gEls.add(_text(Offset(m(54), m(19)), 'Sekiz · r = 5 m', size: 3.5));
  gEls.add(_text(Offset(m(8), m(5.5)), 'Fren koridoru 2,5 m: 40 km/s sonra tam duruş', size: 3.5));
  for (final e in gEls) {
    g.put(e);
  }

  // ---------------- Yol ve viraj
  final r = store.createPage(notebookId: moto.id, mode: PageMode.moto, template: templateById('road'), title: 'Viraj hattı — Roadcraft');
  ids.roadPage = r.id;
  final line = <Offset>[];
  for (var i = 0; i <= 30; i++) {
    final t = i / 30;
    final a = -t * math.pi / 2;
    final rad = 70 + 7 * 0.9 * (1 - 2 * (0.5 - (t - 0.5).abs()));
    line.add(Offset(60 + rad * math.cos(a), 120 + rad * math.sin(a)));
  }
  r.put(ShapeElement(
      id: newId(), updatedAt: 1, z: _nz(), kind: ShapeKind.route, points: [Offset(136, 240), Offset(136, 150), ...line], style: const PenStyle(type: PenType.technical, color: 0xFFC62828, width: 0.6)));
  r.put(_text(const Offset(140, 175), 'Dış hattan gir,\ngeç apeks,\nçıkışa bak', size: 4, color: 0xFFC62828));

  // ---------------- Diğer sayfalar
  ids.evalPage = store.createPage(notebookId: moto.id, mode: PageMode.moto, template: templateById('eval'), title: 'Değerlendirme — Kursiyer 3').id;
  ids.lessonPage = store.createPage(notebookId: moto.id, mode: PageMode.moto, template: templateById('lesson'), title: 'Ders planı — Seviye 2').id;
  store.createPage(notebookId: moto.id, mode: PageMode.moto, template: templateById('track'), title: 'Kapalı alan planı');
  ids.reviewPage = store.createPage(notebookId: eng.id, mode: PageMode.engineering, template: templateById('review'), title: 'Tasarım gözden geçirme').id;
  store.createPage(notebookId: eng.id, mode: PageMode.engineering, template: templateById('drawA4'), title: 'Kapak — teknik resim');
  store.createPage(notebookId: eng.id, mode: PageMode.engineering, template: templateById('inspection'), title: 'Giriş muayenesi');
  store.createPage(notebookId: eng.id, mode: PageMode.both, template: templateById('iso'), title: 'İzometrik eskiz');
  for (final p in store.pages.values) {
    p.dirty = false;
  }
  return ids;
}
