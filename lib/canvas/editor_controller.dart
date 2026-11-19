import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../ink/beautify.dart';
import '../models/note_models.dart';
import '../recognition/handwriting.dart';
import '../storage/local_store.dart';
import '../templates/templates.dart';
import 'tools.dart';

enum EraserMode { stroke, partial }

class _Change {
  final NoteElement? before;
  final NoteElement after;
  _Change(this.before, this.after);
}

class EditorController extends ChangeNotifier {
  final NotePage page;
  final LocalStore store;
  final VoidCallback? onPageChanged;
  final HandwritingRecognizer recognizer;

  EditorController({required this.page, required this.store, required this.recognizer, this.onPageChanged});

  PageTemplate get template => templateById(page.templateId);

  // --- Araç durumu
  ToolKind tool = ToolKind.pen;
  ToolKind _beforeTemp = ToolKind.pen;
  PenType penType = PenType.fountain;
  final Map<PenType, PenStyle> pens = {for (final t in PenType.values) t: PenStyle.defaultFor(t)};
  EraserMode eraserMode = EraserMode.stroke;
  double eraserRadius = 2.0; // mm
  ShapeKind shapeKind = ShapeKind.line;
  DimKind dimKind = DimKind.aligned;
  double dimTextHeight = 2.5;
  DimTolerance nextTolerance = const DimTolerance();
  bool ortho = false;
  bool gridSnap = true;
  bool objectSnap = true;
  int smoothing = 2;
  bool shapeHold = true;
  bool stylusOnly = defaultTargetPlatform == TargetPlatform.android; // tablette; telefonda UI kapatır
  double laneWidthM = 2.5;
  int roadLanes = 2;
  int coneColor = 0xFFFF6D00;
  double coneSpacingM = 0; // >0: sürükleyince bu aralıkla koni dizisi (slalom)
  bool gateIsStart = true;
  Map<String, String> gdtParams = {'char': 'position', 'tol': '0,1', 'dia': '1', 'mod': '', 'd1': 'A', 'd2': 'B', 'd3': ''};
  String datumLetter = 'A';
  Map<String, String> surfaceParams = {'ra': '3,2', 'proc': 'remove'};
  Map<String, String> weldParams = {'wt': 'fillet', 'a': 'a4', 'around': '0', 'field': '0'};

  // --- Tuval davranışı
  bool canvasLocked = false; // kaydırma/zoom tamamen kapalı
  bool fingerScroll = false; // "yalnızca kalem" açıkken tek parmakla kaydır
  bool parametric = false; // şekil: dokun → ölçüleri yazarak çiz

  // --- Metin varsayılanları (yeni metinler bunlarla açılır)
  TextElement textDefaults = const TextElement(id: '_', updatedAt: 0, z: 0, pos: Offset.zero, text: '', size: 4);

  PenStyle get currentPen => tool == ToolKind.highlighter ? pens[PenType.highlighter]! : pens[penType]!;

  void setTool(ToolKind t) {
    if (t != ToolKind.lasso && t != ToolKind.select) selection.clear();
    tool = t;
    notifyListeners();
  }

  /// S Pen yan tuşu: geçici silgi
  void beginTempEraser() {
    if (tool == ToolKind.eraser) return;
    _beforeTemp = tool;
    tool = ToolKind.eraser;
    notifyListeners();
  }

  void endTempEraser() {
    if (tool != ToolKind.eraser) return;
    tool = _beforeTemp;
    notifyListeners();
  }

  void setPenType(PenType t) {
    penType = t;
    tool = ToolKind.pen;
    notifyListeners();
  }

  void updatePen(PenType t, PenStyle s) {
    pens[t] = s;
    notifyListeners();
  }

  void update(VoidCallback fn) {
    fn();
    notifyListeners();
  }

  // --- Ölçek yardımcıları
  double paperFromMeters(double m) => page.scale.unit == 'm' ? page.scale.paperFromReal(m) : m * 5; // m sayfası değilse 1 m = 5 mm
  double get coneSizePaper => math.max(2.2, paperFromMeters(0.4));
  double get motorcycleSizePaper => math.max(8, paperFromMeters(2.2));

  // --- Değişiklik geçmişi
  final List<List<_Change>> _undo = [];
  final List<List<_Change>> _redo = [];
  static const _historyLimit = 200;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void commit(List<NoteElement> after) {
    if (after.isEmpty) return;
    final changes = [for (final a in after) _Change(page.elements[a.id], a)];
    for (final a in after) {
      page.elements[a.id] = a;
    }
    page.touch();
    _undo.add(changes);
    if (_undo.length > _historyLimit) _undo.removeAt(0);
    _redo.clear();
    _changed();
  }

  void add(NoteElement e) => commit([e]);

  void deleteIds(Iterable<String> ids) {
    commit([
      for (final id in ids)
        if (page.elements[id] != null && !page.elements[id]!.deleted) page.elements[id]!.tombstone()
    ]);
  }

  NoteElement _restamp(NoteElement? before, NoteElement after) {
    if (before == null || before.deleted) return after.tombstone();
    return before.translated(Offset.zero); // aynı içerik, yeni zaman damgası (senkronda kazanması için)
  }

  void undo() {
    if (_undo.isEmpty) return;
    final changes = _undo.removeLast();
    final redoBatch = <_Change>[];
    for (final c in changes.reversed) {
      final restored = _restamp(c.before, c.after);
      redoBatch.add(_Change(restored, c.after));
      page.elements[c.after.id] = restored;
    }
    _redo.add(redoBatch);
    page.touch();
    selection.removeWhere((id) => page.elements[id]?.deleted ?? true);
    _changed();
  }

  void redo() {
    if (_redo.isEmpty) return;
    final changes = _redo.removeLast();
    final undoBatch = <_Change>[];
    for (final c in changes) {
      final again = c.after.deleted ? c.before!.tombstone() : c.after.translated(Offset.zero);
      undoBatch.add(_Change(c.before, again));
      page.elements[again.id] = again;
    }
    _undo.add(undoBatch);
    page.touch();
    _changed();
  }

  void _changed() {
    store.savePageDebounced(page);
    onPageChanged?.call();
    notifyListeners();
  }

  /// Sayfa dışarıdan (senkron) değiştiğinde
  void externalRefresh() => notifyListeners();

  // --- Yakalama
  Offset snap(Offset p, double zoom, {Offset? from, bool forceOrtho = false}) {
    final tol = 8 / zoom; // ekranda ~8 px
    if (objectSnap) {
      Offset? best;
      var bestD = tol;
      for (final e in page.visible) {
        if (!e.bounds.inflate(tol).contains(p)) continue;
        final pts = switch (e) {
          ShapeElement s => s.snapPoints,
          DimensionElement _ => const <Offset>[],
          LaneElement l => [l.centerline.first, l.centerline.last],
          SymbolElement s => [s.pos],
          _ => const <Offset>[],
        };
        for (final q in pts) {
          final d = (q - p).distance;
          if (d < bestD) {
            bestD = d;
            best = q;
          }
        }
      }
      if (best != null) return best;
    }
    var out = p;
    if (from != null && (ortho || forceOrtho)) out = snapAngle(from, out);
    final g = template.gridMm;
    if (gridSnap && g != null && from == null) {
      final gx = (out.dx / g).round() * g, gy = (out.dy / g).round() * g;
      if ((Offset(gx, gy) - out).distance < tol) out = Offset(gx, gy);
    }
    return out;
  }

  /// Ölçü aracı için daire/elips yakalama
  ShapeElement? circleAt(Offset p, double zoom) {
    final tol = 10 / zoom;
    for (final e in page.visible.reversed) {
      if (e is ShapeElement && e.kind == ShapeKind.ellipse) {
        final r = Rect.fromPoints(e.points[0], e.points[1]);
        final rad = (r.width + r.height) / 4;
        final d = ((p - r.center).distance - rad).abs();
        if (d < tol || (p - r.center).distance < tol) return e;
      }
    }
    return null;
  }

  // --- Silgi
  void eraseAt(Offset p, double zoom) {
    final r = eraserRadius + 4 / zoom;
    final changes = <NoteElement>[];
    for (final e in page.visible) {
      if (!e.bounds.inflate(r).contains(p)) continue;
      if (e is StrokeElement) {
        final hit = e.points.any((q) => (q.o - p).distance <= r) ||
            Iterable<int>.generate(math.max(0, e.points.length - 1), (i) => i)
                .any((i) => distToSegment(p, e.points[i].o, e.points[i + 1].o) <= r);
        if (!hit) continue;
        if (eraserMode == EraserMode.stroke) {
          changes.add(e.tombstone());
        } else {
          // kısmi: silgi dairesinin dışında kalan parçaları ayrı çizgiler olarak tut
          final parts = <List<InkPoint>>[];
          var cur = <InkPoint>[];
          for (final q in e.points) {
            if ((q.o - p).distance > r) {
              cur.add(q);
            } else if (cur.isNotEmpty) {
              parts.add(cur);
              cur = [];
            }
          }
          if (cur.isNotEmpty) parts.add(cur);
          changes.add(e.tombstone());
          for (final part in parts.where((x) => x.length > 1)) {
            changes.add(e.withPoints(part, newIdentity: true));
          }
        }
      } else {
        // diğer elemanlar: bütün olarak
        changes.add(e.tombstone());
      }
    }
    if (changes.isNotEmpty) commit(changes);
  }

  // --- Seçim
  final Set<String> selection = {};

  List<NoteElement> get selected => [for (final id in selection) if (page.elements[id] case final e? when !e.deleted) e];

  Rect? get selectionBounds {
    final s = selected;
    if (s.isEmpty) return null;
    return s.map((e) => e.bounds).reduce((a, b) => a.expandToInclude(b));
  }

  void selectByLasso(List<Offset> poly) {
    selection.clear();
    if (poly.length < 3) {
      notifyListeners();
      return;
    }
    for (final e in page.visible) {
      if (e is StrokeElement) {
        final inside = e.points.where((q) => pointInPolygon(q.o, poly)).length;
        if (inside >= e.points.length * 0.6) selection.add(e.id);
      } else if (pointInPolygon(e.bounds.center, poly)) {
        selection.add(e.id);
      }
    }
    notifyListeners();
  }

  void clearSelection() {
    selection.clear();
    notifyListeners();
  }

  void moveSelection(Offset d) {
    if (selection.isEmpty || d == Offset.zero) return;
    commit([for (final e in selected) e.translated(d)]);
  }

  void deleteSelection() {
    deleteIds(selection.toList());
    selection.clear();
    notifyListeners();
  }

  void duplicateSelection() {
    const d = Offset(6, 6);
    final copies = <NoteElement>[];
    for (final e in selected) {
      final j = e.translated(d).toJson()
        ..['id'] = newId()
        ..['z'] = newZ();
      copies.add(NoteElement.fromJson(j));
    }
    commit(copies);
    selection
      ..clear()
      ..addAll(copies.map((e) => e.id));
    notifyListeners();
  }

  void recolorSelection(int color) {
    final out = <NoteElement>[];
    for (final e in selected) {
      if (e is StrokeElement) out.add(e.withStyle(e.style.copyWith(color: color)));
      if (e is ShapeElement) out.add(e.withStyle(e.style.copyWith(color: color)));
    }
    commit(out);
  }

  /// El yazısını hizala
  void alignSelection() {
    final strokes = selected.whereType<StrokeElement>().toList();
    if (strokes.length < 2) return;
    commit(alignHandwriting(strokes, ruleSpacing: template.ruleMm, ruleOffset: template.ruleOffsetMm));
  }

  /// Seçili çizgileri tek tek şekle oturt
  int beautifySelection() {
    final out = <NoteElement>[];
    for (final s in selected.whereType<StrokeElement>()) {
      final shape = recognizeShape([for (final p in s.points) p.o]);
      if (shape == null) continue;
      out.add(s.tombstone());
      out.add(ShapeElement(
          id: newId(),
          updatedAt: nowMs(),
          z: s.z,
          kind: shape.kind,
          points: shape.points,
          style: s.style.type == PenType.highlighter ? s.style : s.style.copyWith(type: PenType.technical)));
    }
    commit(out);
    selection.clear();
    notifyListeners();
    return out.length ~/ 2;
  }

  /// Seçili el yazısını tanı: adayları döndürür (UI seçtirir, sonra [replaceSelectionWithText])
  Future<List<String>> recognizeSelection() async {
    final strokes = selected.whereType<StrokeElement>().where((s) => s.style.type != PenType.highlighter).toList();
    if (strokes.isEmpty) return const [];
    return recognizer.recognize(strokes);
  }

  void replaceSelectionWithText(String text, {bool keepInk = false}) {
    final strokes = selected.whereType<StrokeElement>().toList();
    if (strokes.isEmpty) return;
    final b = strokes.map((s) => s.bounds).reduce((a, c) => a.expandToInclude(c));
    final lines = '\n'.allMatches(text).length + 1;
    final size = (b.height / lines / 1.3).clamp(2.5, 12.0);
    final out = <NoteElement>[
      TextElement(
          id: newId(), updatedAt: nowMs(), z: newZ(), pos: b.topLeft, text: text, size: size, color: strokes.first.style.color, fromInk: true),
      if (!keepInk) for (final s in strokes) s.tombstone(),
    ];
    commit(out);
    if (!page.recognizedText.contains(text)) {
      page.recognizedText = '${page.recognizedText} $text'.trim();
    }
    selection.clear();
    notifyListeners();
  }

  // --- Sayfa ayarları
  void setMode(PageMode m) {
    page.mode = m;
    page.touchMeta();
    if (!toolsFor(m).contains(tool)) tool = ToolKind.pen;
    _changed();
  }

  void setScale(ScaleSpec s) {
    page.scale = s;
    page.touchMeta();
    _changed();
  }

  void rename(String t) {
    page.title = t;
    page.touchMeta();
    _changed();
  }

  int get coneCount => page.visible.whereType<SymbolElement>().where((s) => s.kind == SymbolKind.cone).length;

  // ---------------------------------------------------------------------------
  // Tekil seçim ve düzenleme

  /// Noktadaki en üstteki eleman
  NoteElement? hitTest(Offset p, double zoom) {
    final tol = 10 / zoom;
    for (final e in page.visible.reversed) {
      if (!e.bounds.inflate(tol).contains(p)) continue;
      switch (e) {
        case StrokeElement s:
          for (var i = 0; i + 1 < s.points.length; i++) {
            if (distToSegment(p, s.points[i].o, s.points[i + 1].o) <= tol + s.style.width / 2) return e;
          }
          if (s.points.length == 1 && (s.points.first.o - p).distance <= tol) return e;
        case ShapeElement s when s.kind == ShapeKind.rect || s.kind == ShapeKind.ellipse:
          final r = Rect.fromPoints(s.points[0], s.points[1]);
          if (s.fill != null && r.contains(p)) return e;
          if (s.kind == ShapeKind.rect) {
            final edges = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
            for (var i = 0; i < 4; i++) {
              if (distToSegment(p, edges[i], edges[(i + 1) % 4]) <= tol) return e;
            }
          } else {
            final rx = math.max(r.width / 2, 1e-6), ry = math.max(r.height / 2, 1e-6);
            final q = p - r.center;
            final k = math.sqrt(q.dx * q.dx / (rx * rx) + q.dy * q.dy / (ry * ry));
            if ((k - 1).abs() * math.min(rx, ry) <= tol) return e;
          }
        case ShapeElement s:
          for (var i = 0; i + 1 < s.points.length; i++) {
            if (distToSegment(p, s.points[i], s.points[i + 1]) <= tol) return e;
          }
          if (s.kind == ShapeKind.triangle || s.kind == ShapeKind.polygon) {
            if (distToSegment(p, s.points.last, s.points.first) <= tol) return e;
          }
        default:
          return e; // ölçü, metin, sembol, şerit: kutu içi yeterli
      }
    }
    return null;
  }

  void selectOnly(String? id) {
    selection.clear();
    if (id != null) selection.add(id);
    notifyListeners();
  }

  NoteElement? get singleSelected => selection.length == 1 ? page.elements[selection.first] : null;

  /// Aynı id'li elemanı değiştir (geri alınabilir)
  void replace(NoteElement e) => commit([e]);

  /// Ölçünün bağlı olduğu şekil (uçları şeklin yakalama noktalarına denk geliyorsa)
  ShapeElement? linkedShape(DimensionElement d) {
    const eps = 0.05;
    bool near(Offset a, Offset b) => (a - b).distance < eps;
    for (final s in page.visible.whereType<ShapeElement>()) {
      if (d.kind == DimKind.radius || d.kind == DimKind.diameter) {
        if (s.kind != ShapeKind.ellipse) continue;
        if (near(Rect.fromPoints(s.points[0], s.points[1]).center, d.points[0])) return s;
        continue;
      }
      if (d.kind == DimKind.angle) continue;
      final sp = s.kind == ShapeKind.rect
          ? () {
              final r = Rect.fromPoints(s.points[0], s.points[1]);
              return [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight];
            }()
          : s.points;
      if (sp.any((q) => near(q, d.points[0])) && sp.any((q) => near(q, d.points[1]))) return s;
    }
    return null;
  }

  /// Ölçüye gerçek değer ver: bağlı şekil varsa geometriyi sürer (parametrik), yoksa metni ezer.
  /// Dönüş: şekil güncellendi mi
  bool applyDimensionValue(DimensionElement d, double real) {
    final scale = page.scale;
    final shape = linkedShape(d);
    if (shape == null || scale.isFree || real <= 0) {
      replace(d.copyWith(textOverride: _fmt(real, d.kind)));
      return false;
    }
    final paper = d.kind == DimKind.angle ? real : scale.paperFromReal(real);
    final p1 = d.points[0], p2 = d.points[1];
    ShapeElement newShape;
    List<Offset> newDim;
    if (shape.kind == ShapeKind.ellipse) {
      final r = d.kind == DimKind.diameter ? paper / 2 : paper;
      final c = p1;
      final u = (p2 - c).distance < 1e-9 ? const Offset(1, 0) : (p2 - c) / (p2 - c).distance;
      newShape = ShapeElement(id: shape.id, updatedAt: nowMs(), z: shape.z, kind: shape.kind, style: shape.style, fill: shape.fill,
          points: [c - Offset(r, r), c + Offset(r, r)]);
      newDim = [c, c + u * r, d.points[2]];
    } else if (shape.kind == ShapeKind.rect) {
      // sol/üst kenar sabit; sağ/alt kenar taşınır, o kenardaki ölçü ucu da onunla gider
      final r = Rect.fromPoints(shape.points[0], shape.points[1]);
      final horizontal = d.kind == DimKind.horizontal || (d.kind == DimKind.aligned && (p2.dy - p1.dy).abs() < (p2.dx - p1.dx).abs());
      final Rect nr;
      Offset mv(Offset q) => horizontal
          ? ((q.dx - r.right).abs() < 0.05 ? Offset(r.left + paper, q.dy) : q)
          : ((q.dy - r.bottom).abs() < 0.05 ? Offset(q.dx, r.top + paper) : q);
      nr = horizontal ? Rect.fromLTRB(r.left, r.top, r.left + paper, r.bottom) : Rect.fromLTRB(r.left, r.top, r.right, r.top + paper);
      newDim = [mv(p1), mv(p2), d.points[2]];
      newShape = ShapeElement(id: shape.id, updatedAt: nowMs(), z: shape.z, kind: shape.kind, style: shape.style, fill: shape.fill,
          points: [nr.topLeft, nr.bottomRight]);
    } else {
      // çizgi / ok / eksen: p1 sabit, p2 doğrultu boyunca
      final idx2 = shape.points.indexWhere((q) => (q - p2).distance < 0.05);
      Offset np2;
      if (d.kind == DimKind.horizontal) {
        np2 = Offset(p1.dx + paper * (p2.dx >= p1.dx ? 1 : -1), p2.dy);
      } else if (d.kind == DimKind.vertical) {
        np2 = Offset(p2.dx, p1.dy + paper * (p2.dy >= p1.dy ? 1 : -1));
      } else {
        final v = p2 - p1;
        final u = v.distance < 1e-9 ? const Offset(1, 0) : v / v.distance;
        np2 = p1 + u * paper;
      }
      final pts = List.of(shape.points);
      if (idx2 >= 0) pts[idx2] = np2;
      newShape = ShapeElement(id: shape.id, updatedAt: nowMs(), z: shape.z, kind: shape.kind, style: shape.style, fill: shape.fill, points: pts);
      newDim = [p1, np2, d.points[2] + (np2 - p2)];
    }
    commit([newShape, d.copyWith(points: newDim, clearOverride: true)]);
    return true;
  }

  String _fmt(double v, DimKind k) {
    final n = v.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '').replaceAll('.', ',');
    return switch (k) {
      DimKind.radius => 'R$n',
      DimKind.diameter => 'Ø$n',
      DimKind.angle => '$n°',
      _ => page.scale.unit == 'm' ? '$n m' : n,
    };
  }

  /// Şeklin parametreleri (gerçek birim): line → L, A · rect → G, Y · ellipse → Ø (veya G, Y)
  Map<String, double> shapeParams(ShapeElement s) {
    final sc = page.scale;
    double real(double paper) => sc.isFree ? paper : sc.realFromPaper(paper);
    switch (s.kind) {
      case ShapeKind.rect:
        final r = Rect.fromPoints(s.points[0], s.points[1]);
        return {'Genişlik': real(r.width), 'Yükseklik': real(r.height)};
      case ShapeKind.ellipse:
        final r = Rect.fromPoints(s.points[0], s.points[1]);
        if ((r.width - r.height).abs() < 1e-6) return {'Çap Ø': real(r.width)};
        return {'Genişlik': real(r.width), 'Yükseklik': real(r.height)};
      default:
        final v = s.points.last - s.points.first;
        return {'Uzunluk': real(v.distance), 'Açı °': -math.atan2(v.dy, v.dx) * 180 / math.pi};
    }
  }

  /// Parametrelerden şekil noktaları (başlangıç noktası sabit; açı CCW, ekran y aşağı)
  List<Offset> pointsFromParams(ShapeKind k, Offset start, Map<String, double> v) {
    final sc = page.scale;
    double paper(double real) => sc.isFree ? real : sc.paperFromReal(real);
    switch (k) {
      case ShapeKind.rect:
        return [start, start + Offset(paper(v['Genişlik'] ?? 10), paper(v['Yükseklik'] ?? 10))];
      case ShapeKind.ellipse:
        if (v.containsKey('Çap Ø')) {
          final r = paper(v['Çap Ø']!) / 2;
          return [start - Offset(r, r), start + Offset(r, r)];
        }
        final w = paper(v['Genişlik'] ?? 10), h = paper(v['Yükseklik'] ?? 10);
        return [start - Offset(w / 2, h / 2), start + Offset(w / 2, h / 2)];
      default:
        final l = paper(v['Uzunluk'] ?? 10);
        final a = -(v['Açı °'] ?? 0) * math.pi / 180;
        return [start, start + Offset(math.cos(a), math.sin(a)) * l];
    }
  }

  void applyShapeParams(ShapeElement s, Map<String, double> v) {
    final start = s.kind == ShapeKind.ellipse
        ? Rect.fromPoints(s.points[0], s.points[1]).center
        : s.kind == ShapeKind.rect
            ? Rect.fromPoints(s.points[0], s.points[1]).topLeft
            : s.points.first;
    replace(ShapeElement(
        id: s.id, updatedAt: nowMs(), z: s.z, kind: s.kind, style: s.style, fill: s.fill, points: pointsFromParams(s.kind, start, v)));
  }

  /// Seçimi öne/arkaya al
  void bringSelection({required bool front}) {
    final zs = page.visible.map((e) => e.z);
    final target = front ? zs.fold<double>(0, math.max) + 1 : zs.fold<double>(double.infinity, math.min) - 1;
    final out = <NoteElement>[];
    for (final e in selected) {
      final j = e.toJson()..['z'] = target..['u'] = nowMs();
      out.add(NoteElement.fromJson(j));
    }
    commit(out);
  }
}
