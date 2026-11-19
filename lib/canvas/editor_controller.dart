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

  PenStyle get currentPen => tool == ToolKind.highlighter ? pens[PenType.highlighter]! : pens[penType]!;

  void setTool(ToolKind t) {
    if (t != ToolKind.lasso) selection.clear();
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
}
