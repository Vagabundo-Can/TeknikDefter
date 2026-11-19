// Tuval: kalem/parmak/fare girişini sayfa milimetresine çevirir, araçları uygular, çizer.
// - "Yalnızca kalem" açıkken parmak çizmez: tek parmak kaydırır, iki parmak zoom/kaydırma.
// - İki parmakla dokunma = geri al.
// - S Pen yan tuşu / ters kalem = geçici silgi.
// - Biten çizgiler bir Picture önbelleğinde tutulur; her karede yalnız aktif çizgi boyanır.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ink/beautify.dart';
import '../ink/stroke_renderer.dart';
import '../models/note_models.dart';
import 'editor_controller.dart';
import 'element_painter.dart';
import 'tools.dart';

typedef TextRequest = Future<TextElement?> Function(TextElement initial, bool isNew);
typedef ElementEdit = Future<void> Function(NoteElement e);
typedef ShapeParamsRequest = Future<Map<String, double>?> Function(ShapeKind kind, Map<String, double> defaults);
typedef DimValueRequest = Future<String?> Function(DimensionElement d);

class NoteCanvas extends StatefulWidget {
  final EditorController controller;
  final TextRequest onRequestText;
  final ElementEdit onEditElement;
  final ShapeParamsRequest onRequestShapeParams;
  final DimValueRequest onRequestDimValue;
  final bool darkPaper;
  const NoteCanvas({
    super.key,
    required this.controller,
    required this.onRequestText,
    required this.onEditElement,
    required this.onRequestShapeParams,
    required this.onRequestDimValue,
    this.darkPaper = false,
  });

  @override
  State<NoteCanvas> createState() => NoteCanvasState();
}

class NoteCanvasState extends State<NoteCanvas> {
  EditorController get c => widget.controller;

  // Görünüm: ekran = sayfa_mm * zoom + pan
  double zoom = 3;
  Offset pan = const Offset(16, 16);
  bool _fitted = false;
  Size _size = Size.zero;

  // Dokunma takibi
  final Map<int, Offset> _touches = {};
  final Map<int, Offset> _touchStart = {};
  DateTime? _multiTouchStart;
  bool _multiMoved = false;
  double? _pinchStartDist;
  double _pinchStartZoom = 1;
  Offset _pinchStartFocalPage = Offset.zero;
  int? _panPointer;
  Offset? _panLast;

  // Çizim durumu
  int? _drawPointer;
  int _strokeStartMs = 0;
  List<InkPoint> _live = [];
  PointFilter? _filter;
  Timer? _holdTimer;
  Offset _holdAnchor = Offset.zero;
  RecognizedShape? _snapped;
  Offset? _shapeA, _shapeB;
  final List<Offset> _dimPts = [];
  List<Offset> _lasso = [];
  Offset? _dragStart;
  bool _handleDrag = false; // tek seçili ölçünün ofset noktasını sürükleme
  String? _lastTapId;
  DateTime _lastTapTime = DateTime(2000);
  final Set<int> _ignored = {}; // avuç / kalem varken parmak
  bool _drawIsPen = false;
  DateTime _lastPenUp = DateTime(2000);
  Offset _dragDelta = Offset.zero;
  final List<SymbolElement> _pendingCones = [];
  bool _tempEraser = false;

  // Önbellek
  ui.Picture? _cache;
  Object? _cacheKey;

  @override
  void initState() {
    super.initState();
    c.addListener(_onController);
  }

  @override
  void didUpdateWidget(NoteCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != c) {
      oldWidget.controller.removeListener(_onController);
      c.addListener(_onController);
      _fitted = false;
      _invalidate();
    }
  }

  @override
  void dispose() {
    c.removeListener(_onController);
    _holdTimer?.cancel();
    _cache?.dispose();
    super.dispose();
  }

  void _onController() {
    if (c.tool != ToolKind.dimension && c.tool != ToolKind.distance) _dimPts.clear();
    setState(() {});
  }

  void _invalidate() {
    _cache?.dispose();
    _cache = null;
    _cacheKey = null;
  }

  Offset toPage(Offset screen) => (screen - pan) / zoom;

  void fitWidth() {
    if (_size.isEmpty) return;
    setState(() {
      zoom = (_size.width - 32) / c.page.widthMm;
      pan = const Offset(16, 16);
    });
  }

  void fitPage() {
    if (_size.isEmpty) return;
    setState(() {
      zoom = math.min((_size.width - 32) / c.page.widthMm, (_size.height - 32) / c.page.heightMm);
      pan = Offset((_size.width - c.page.widthMm * zoom) / 2, 16);
    });
  }

  /// Sayfadaki bir dikdörtgeni (mm) ekrana sığdır
  void zoomToRect(Rect r) {
    if (_size.isEmpty) return;
    setState(() {
      zoom = math.min((_size.width - 32) / r.width, (_size.height - 32) / r.height);
      pan = Offset((_size.width - r.width * zoom) / 2, (_size.height - r.height * zoom) / 2) - r.topLeft * zoom;
    });
  }

  void zoomAt(Offset focal, double factor) {
    final before = toPage(focal);
    setState(() {
      zoom = (zoom * factor).clamp(0.5, 60.0);
      pan = focal - before * zoom;
    });
  }

  // -------------------------------------------------------------------------
  // Giriş sınıflandırma

  bool _isTouch(PointerEvent e) => e.kind == PointerDeviceKind.touch;
  bool _isPen(PointerEvent e) => e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus;

  double _pressure(PointerEvent e) {
    if (_isPen(e) && e.pressureMax > e.pressureMin) {
      return ((e.pressure - e.pressureMin) / (e.pressureMax - e.pressureMin)).clamp(0.0, 1.0);
    }
    return 0.5;
  }

  bool get _spaceDown => HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.space);
  bool get _shiftDown => HardwareKeyboard.instance.isShiftPressed;

  bool _isPalm(PointerEvent e) => e.radiusMajor > 24 || (e.size > 0 && e.size > 0.35);

  void _onDown(PointerDownEvent e) {
    if (_isTouch(e)) {
      // Avuç reddi: büyük temas, kalem yazarken ya da kalem yeni kalktıysa parmak yok sayılır
      final penBusy = (_drawPointer != null && _drawIsPen) || DateTime.now().difference(_lastPenUp) < const Duration(milliseconds: 400);
      if (_isPalm(e) || (c.stylusOnly && penBusy) || c.canvasLocked && (c.stylusOnly || c.tool == ToolKind.pan)) {
        _ignored.add(e.pointer);
        return;
      }
      final navigate = c.stylusOnly || _touches.isNotEmpty || c.tool == ToolKind.pan;
      _touches[e.pointer] = e.localPosition;
      _touchStart[e.pointer] = e.localPosition;
      if (_touches.length == 2) {
        _cancelDrawing(); // ikinci parmak gelince parmak çizimi iptal → zoom
        if (!c.canvasLocked) _startPinch();
        _multiTouchStart = DateTime.now();
        _multiMoved = false;
        _panPointer = null;
        return;
      }
      if (_touches.length > 2) return;
      if (navigate) {
        // "Yalnızca kalem": tek parmak varsayılan olarak kaydırmaz (avuç ekranı oynatmasın)
        if (!c.canvasLocked && (c.fingerScroll || !c.stylusOnly || c.tool == ToolKind.pan)) {
          _panPointer = e.pointer;
          _panLast = e.localPosition;
        }
        return;
      }
      // aksi halde parmak çizer
    } else if (c.tool == ToolKind.pan || _spaceDown || (e.kind == PointerDeviceKind.mouse && e.buttons == kMiddleMouseButton)) {
      _panPointer = e.pointer;
      _panLast = e.localPosition;
      return;
    }
    if (_drawPointer != null) return;
    // Geçici silgi: ters kalem ucu veya S Pen yan tuşu
    _tempEraser = e.kind == PointerDeviceKind.invertedStylus || (_isPen(e) && (e.buttons & kPrimaryStylusButton) != 0);
    if (_tempEraser) c.beginTempEraser();
    _drawPointer = e.pointer;
    _drawIsPen = _isPen(e);
    _beginTool(e);
  }

  void _onMove(PointerMoveEvent e) {
    if (_ignored.contains(e.pointer)) return;
    if (_touches.containsKey(e.pointer)) {
      _touches[e.pointer] = e.localPosition;
      if ((e.localPosition - (_touchStart[e.pointer] ?? e.localPosition)).distance > 12) _multiMoved = true;
      if (_touches.length >= 2 && _pinchStartDist != null) {
        _updatePinch();
        return;
      }
    }
    if (_panPointer == e.pointer && _panLast != null) {
      setState(() {
        pan += e.localPosition - _panLast!;
        _panLast = e.localPosition;
      });
      return;
    }
    if (_drawPointer == e.pointer) _moveTool(e);
  }

  void _onUp(PointerEvent e) {
    if (_ignored.remove(e.pointer)) return;
    final wasTouch = _touches.containsKey(e.pointer);
    if (wasTouch) {
      if (_touches.length == 2 && !_multiMoved && _multiTouchStart != null &&
          DateTime.now().difference(_multiTouchStart!) < const Duration(milliseconds: 300) && e is PointerUpEvent) {
        c.undo(); // iki parmak dokunma
        _multiTouchStart = null;
      }
      _touches.remove(e.pointer);
      _touchStart.remove(e.pointer);
      if (_touches.length < 2) _pinchStartDist = null;
      if (_touches.length == 1 && !c.canvasLocked && (c.fingerScroll || !c.stylusOnly || c.tool == ToolKind.pan)) {
        _panPointer = _touches.keys.first;
        _panLast = _touches.values.first;
      }
    }
    if (_panPointer == e.pointer) {
      _panPointer = null;
      _panLast = null;
    }
    if (_drawPointer == e.pointer) {
      if (e is PointerCancelEvent) {
        _cancelDrawing();
      } else {
        _endTool(e);
      }
      _drawPointer = null;
      if (_drawIsPen) _lastPenUp = DateTime.now();
      if (_tempEraser) {
        c.endTempEraser();
        _tempEraser = false;
      }
    }
  }

  void _onHover(PointerHoverEvent e) {
    if ((c.tool == ToolKind.dimension || c.tool == ToolKind.distance) && _dimPts.length >= 2) {
      setState(() => _dimPts[_dimPts.length - 1] = _dimSnap(toPage(e.localPosition)));
    }
  }

  void _onSignal(PointerSignalEvent e) {
    if (c.canvasLocked) return;
    if (e is PointerScrollEvent) {
      if (HardwareKeyboard.instance.isControlPressed) {
        zoomAt(e.localPosition, e.scrollDelta.dy < 0 ? 1.12 : 1 / 1.12);
      } else {
        setState(() => pan -= _shiftDown ? Offset(e.scrollDelta.dy, 0) : e.scrollDelta);
      }
    } else if (e is PointerScaleEvent) {
      zoomAt(e.localPosition, e.scale);
    }
  }

  void _startPinch() {
    final pts = _touches.values.toList();
    _pinchStartDist = (pts[0] - pts[1]).distance;
    _pinchStartZoom = zoom;
    _pinchStartFocalPage = toPage((pts[0] + pts[1]) / 2);
  }

  void _updatePinch() {
    if (c.canvasLocked) return;
    final pts = _touches.values.take(2).toList();
    final d = (pts[0] - pts[1]).distance;
    final focal = (pts[0] + pts[1]) / 2;
    setState(() {
      zoom = (_pinchStartZoom * d / math.max(_pinchStartDist!, 1)).clamp(0.5, 60.0);
      pan = focal - _pinchStartFocalPage * zoom;
    });
  }

  // -------------------------------------------------------------------------
  // Araçlar

  void _cancelDrawing() {
    _holdTimer?.cancel();
    _live = [];
    _snapped = null;
    _shapeA = _shapeB = null;
    _lasso = [];
    _pendingCones.clear();
    _drawPointer = null;
    setState(() {});
  }

  InkPoint _inkPoint(PointerEvent e) {
    final t = e.timeStamp.inMilliseconds - _strokeStartMs;
    var p = toPage(e.localPosition);
    if (_filter != null) p = _filter!.filter(p, t / 1000.0);
    return InkPoint(p.dx, p.dy, _pressure(e), math.max(0, t));
  }

  Offset _dimSnap(Offset p) {
    final from = _dimPts.length >= 2 ? _dimPts[_dimPts.length - 2] : null;
    return c.snap(p, zoom, from: from, forceOrtho: _shiftDown);
  }

  void _beginTool(PointerDownEvent e) {
    final p = toPage(e.localPosition);
    _strokeStartMs = e.timeStamp.inMilliseconds;
    switch (c.tool) {
      case ToolKind.pen:
      case ToolKind.highlighter:
      case ToolKind.lane:
      case ToolKind.road:
      case ToolKind.route:
        _filter = c.tool == ToolKind.pen ? PointFilter() : null;
        _live = [_inkPoint(e)];
        _snapped = null;
        _holdAnchor = p;
        _armHold();
      case ToolKind.select:
        _beginSelect(p);
      case ToolKind.eraser:
        c.eraseAt(p, zoom);
      case ToolKind.lasso:
        final b = c.selectionBounds;
        if (b != null && b.inflate(3).contains(p)) {
          _dragStart = p;
          _dragDelta = Offset.zero;
          _invalidate();
        } else {
          c.clearSelection();
          _lasso = [p];
        }
      case ToolKind.shape:
      case ToolKind.gate:
      case ToolKind.motorcycle:
        _shapeA = c.tool == ToolKind.shape ? c.snap(p, zoom) : p;
        _shapeB = _shapeA;
      case ToolKind.dimension:
      case ToolKind.distance:
        final kind = c.tool == ToolKind.distance ? DimKind.aligned : c.dimKind;
        if (_dimPts.isEmpty) {
          if (kind == DimKind.radius || kind == DimKind.diameter) {
            final circ = c.circleAt(p, zoom);
            if (circ != null) {
              final r = Rect.fromPoints(circ.points[0], circ.points[1]);
              final rad = (r.width + r.height) / 4;
              final dir = p - r.center;
              final u = dir.distance < 1e-6 ? const Offset(1, 0) : dir / dir.distance;
              _dimPts.addAll([r.center, r.center + u * rad, p]);
              break;
            }
          }
          final s = c.snap(p, zoom);
          _dimPts.addAll([s, s]);
        } else {
          _dimPts[_dimPts.length - 1] = _dimSnap(p);
        }
      case ToolKind.cone:
        _pendingCones.add(_cone(p));
      case ToolKind.text:
      case ToolKind.gdt:
      case ToolKind.datum:
      case ToolKind.surface:
      case ToolKind.weld:
      case ToolKind.north:
      case ToolKind.pan:
        _shapeA = p;
    }
    setState(() {});
  }

  void _armHold() {
    _holdTimer?.cancel();
    if (!c.shapeHold || c.tool != ToolKind.pen) return;
    _holdTimer = Timer(const Duration(milliseconds: 450), () {
      if (_drawPointer == null || _live.length < 4) return;
      final shape = recognizeShape([for (final q in _live) q.o]);
      if (shape != null) {
        HapticFeedback.lightImpact();
        setState(() => _snapped = shape);
      }
    });
  }

  void _moveTool(PointerMoveEvent e) {
    final p = toPage(e.localPosition);
    switch (c.tool) {
      case ToolKind.pen:
      case ToolKind.highlighter:
      case ToolKind.lane:
      case ToolKind.road:
      case ToolKind.route:
        if (_snapped != null) return; // şekle oturtuldu, bırakmayı bekle
        final ip = _inkPoint(e);
        if ((ip.o - _live.last.o).distance < 0.08) return;
        _live.add(ip);
        if ((p - _holdAnchor).distance > 0.8) {
          _holdAnchor = p;
          _armHold();
        }
      case ToolKind.select:
        if (_dragStart != null) _dragDelta = p - _dragStart!;
      case ToolKind.eraser:
        c.eraseAt(p, zoom);
      case ToolKind.lasso:
        if (_dragStart != null) {
          _dragDelta = p - _dragStart!;
        } else {
          _lasso.add(p);
        }
      case ToolKind.shape:
        _shapeB = c.snap(p, zoom, from: _shapeA, forceOrtho: _shiftDown);
      case ToolKind.gate:
      case ToolKind.motorcycle:
        _shapeB = p;
      case ToolKind.dimension:
      case ToolKind.distance:
        if (_dimPts.isNotEmpty) _dimPts[_dimPts.length - 1] = _dimSnap(p);
      case ToolKind.cone:
        final spacing = c.paperFromMeters(c.coneSpacingM);
        if (c.coneSpacingM > 0 && _pendingCones.isNotEmpty && (p - _pendingCones.last.pos).distance >= spacing) {
          final last = _pendingCones.last.pos;
          final u = (p - last) / (p - last).distance;
          _pendingCones.add(_cone(last + u * spacing));
        }
      default:
        break;
    }
    setState(() {});
  }

  SymbolElement _cone(Offset p) => SymbolElement(
        id: newId(),
        updatedAt: nowMs(),
        z: newZ(),
        kind: SymbolKind.cone,
        pos: p,
        size: c.coneSizePaper,
        params: {'color': '${c.coneColor}'},
      );

  Future<void> _endTool(PointerEvent e) async {
    _holdTimer?.cancel();
    final p = toPage(e.localPosition);
    switch (c.tool) {
      case ToolKind.pen:
      case ToolKind.highlighter:
        final style = c.currentPen;
        if (_snapped != null) {
          c.add(ShapeElement(
              id: newId(),
              updatedAt: nowMs(),
              z: newZ(),
              kind: _snapped!.kind,
              points: _snapped!.points,
              style: style.type == PenType.highlighter ? style : style.copyWith(type: PenType.technical, width: math.max(style.width, 0.35))));
        } else if (_live.isNotEmpty) {
          final pts = chaikin(decimate(_live, 0.15), c.smoothing);
          c.add(StrokeElement(id: newId(), updatedAt: nowMs(), z: c.tool == ToolKind.highlighter ? newZ() - 1e12 : newZ(), points: pts, style: style));
        }
        _live = [];
        _snapped = null;
      case ToolKind.lane:
      case ToolKind.road:
      case ToolKind.route:
        if (_live.length > 2) {
          final simplified = chaikinOffsets(simplify([for (final q in _live) q.o], 0.6), 2);
          if (c.tool == ToolKind.route) {
            c.add(ShapeElement(
                id: newId(),
                updatedAt: nowMs(),
                z: newZ(),
                kind: ShapeKind.route,
                points: simplified,
                style: PenStyle(type: PenType.technical, color: 0xFF1565C0, width: 0.7, lineType: LineType.hidden)));
          } else {
            final lanes = c.tool == ToolKind.road ? c.roadLanes : 1;
            final w = c.tool == ToolKind.road ? 3.5 : c.laneWidthM;
            c.add(LaneElement(
                id: newId(), updatedAt: nowMs(), z: newZ() - 1e11, centerline: simplified, widthPaper: c.paperFromMeters(w), widthReal: w, lanes: lanes));
          }
        }
        _live = [];
      case ToolKind.lasso:
        if (_dragStart != null) {
          c.moveSelection(_dragDelta);
          _dragStart = null;
          _dragDelta = Offset.zero;
          _invalidate();
        } else {
          final pathLen = pathLength(_lasso);
          if (pathLen < 12 / zoom) {
            c.selectOnly(c.hitTest(p, zoom)?.id); // dokunarak seç
          } else {
            c.selectByLasso(_lasso);
          }
          _lasso = [];
        }
      case ToolKind.shape:
        final a = _shapeA, b = _shapeB;
        final style = c.pens[PenType.technical]!;
        _shapeA = _shapeB = null;
        if (a != null && b != null && (b - a).distance > 0.8) {
          c.add(ShapeElement(id: newId(), updatedAt: nowMs(), z: newZ(), kind: c.shapeKind, points: [a, b], style: style));
        } else if (a != null && c.parametric) {
          final kind = c.shapeKind;
          final defaults = switch (kind) {
            ShapeKind.rect => {'Genişlik': 40.0, 'Yükseklik': 20.0},
            ShapeKind.ellipse => {'Çap Ø': 20.0},
            _ => {'Uzunluk': 50.0, 'Açı °': 0.0},
          };
          final v = await widget.onRequestShapeParams(kind, defaults);
          if (v != null) {
            c.add(ShapeElement(id: newId(), updatedAt: nowMs(), z: newZ(), kind: kind, points: c.pointsFromParams(kind, a, v), style: style));
          }
        }
      case ToolKind.gate:
        final a = _shapeA, b = _shapeB;
        if (a != null && b != null) {
          final d = b - a;
          final w = d.distance < 2 ? c.paperFromMeters(4) : d.distance;
          c.add(SymbolElement(
              id: newId(),
              updatedAt: nowMs(),
              z: newZ(),
              kind: c.gateIsStart ? SymbolKind.startGate : SymbolKind.finishGate,
              pos: d.distance < 2 ? a : (a + b) / 2,
              rotation: d.distance < 2 ? 0 : math.atan2(d.dy, d.dx),
              size: c.coneSizePaper * 1.4,
              params: {'w': w.toStringAsFixed(2)}));
        }
        _shapeA = _shapeB = null;
      case ToolKind.motorcycle:
        final a = _shapeA, b = _shapeB;
        if (a != null) {
          final d = (b ?? a) - a;
          c.add(SymbolElement(
              id: newId(),
              updatedAt: nowMs(),
              z: newZ(),
              kind: SymbolKind.motorcycle,
              pos: a,
              rotation: d.distance < 1 ? 0 : math.atan2(d.dy, d.dx),
              size: c.motorcycleSizePaper,
              color: 0xFF263238));
        }
        _shapeA = _shapeB = null;
      case ToolKind.dimension:
      case ToolKind.distance:
        _advanceDimension();
      case ToolKind.cone:
        if (_pendingCones.isNotEmpty) c.commit(List.of(_pendingCones));
        _pendingCones.clear();
      case ToolKind.text:
        final hit = c.hitTest(p, zoom);
        if (hit is TextElement) {
          if (hit.kind == TextKind.checklist) {
            for (var i = 0; i < hit.lines.length; i++) {
              if (hit.checkboxRect(i).inflate(1).contains(p)) {
                c.replace(hit.toggleLine(i));
                break;
              }
            }
            if (hit.checkboxRect(0).left + hit.size * 1.2 > p.dx) break;
          }
          final edited = await widget.onRequestText(hit, false);
          if (edited != null) edited.text.trim().isEmpty ? c.deleteIds([hit.id]) : c.replace(edited);
        } else {
          final d = c.textDefaults;
          final fresh = TextElement(
              id: newId(), updatedAt: nowMs(), z: newZ(), pos: p, text: d.kind == TextKind.checklist ? '[ ] ' : '', size: d.size,
              color: d.color, background: d.background, bold: d.bold, italic: d.italic, underline: d.underline, font: d.font, kind: d.kind);
          final created = await widget.onRequestText(fresh, true);
          if (created != null && created.text.replaceAll('[ ]', '').trim().isNotEmpty) c.add(created);
        }
      case ToolKind.gdt:
        c.add(SymbolElement(id: newId(), updatedAt: nowMs(), z: newZ(), kind: SymbolKind.gdtFrame, pos: p, size: 5, params: Map.of(c.gdtParams)));
      case ToolKind.datum:
        c.add(SymbolElement(id: newId(), updatedAt: nowMs(), z: newZ(), kind: SymbolKind.datum, pos: p, size: 5, params: {'letter': c.datumLetter}));
        c.update(() => c.datumLetter = String.fromCharCode(math.min(c.datumLetter.codeUnitAt(0) + 1, 'Z'.codeUnitAt(0))));
      case ToolKind.surface:
        c.add(SymbolElement(id: newId(), updatedAt: nowMs(), z: newZ(), kind: SymbolKind.surface, pos: p, size: 3.5, params: Map.of(c.surfaceParams)));
      case ToolKind.weld:
        c.add(SymbolElement(id: newId(), updatedAt: nowMs(), z: newZ(), kind: SymbolKind.weld, pos: p, size: 3.5, params: Map.of(c.weldParams)));
      case ToolKind.north:
        c.add(SymbolElement(id: newId(), updatedAt: nowMs(), z: newZ(), kind: SymbolKind.northArrow, pos: p, size: 6, color: 0xFF263238));
      case ToolKind.select:
        await _endSelect();
      case ToolKind.eraser:
      case ToolKind.pan:
        break;
    }
    _filter = null;
    if (mounted) setState(() {});
  }

  void _beginSelect(Offset p) {
    final sel = c.singleSelected;
    _handleDrag = false;
    if (sel is DimensionElement && (p - sel.points.last).distance < 16 / zoom) {
      _handleDrag = true;
      _dragStart = p;
      _dragDelta = Offset.zero;
      _invalidate();
      return;
    }
    final hit = c.hitTest(p, zoom);
    if (hit is TextElement && hit.kind == TextKind.checklist) {
      for (var i = 0; i < hit.lines.length; i++) {
        if (hit.checkboxRect(i).inflate(1).contains(p)) {
          c.replace(hit.toggleLine(i));
          return;
        }
      }
    }
    final b = c.selectionBounds;
    if (hit != null || (b != null && b.inflate(2).contains(p))) {
      if (hit != null && !c.selection.contains(hit.id)) c.selectOnly(hit.id);
      _dragStart = p;
      _dragDelta = Offset.zero;
      _invalidate();
    } else {
      c.selectOnly(null);
    }
  }

  Future<void> _endSelect() async {
    final start = _dragStart;
    final delta = _dragDelta;
    final handle = _handleDrag;
    _dragStart = null;
    _dragDelta = Offset.zero;
    _handleDrag = false;
    _invalidate();
    if (start == null) return;
    final sel = c.singleSelected;
    if (handle && sel is DimensionElement) {
      final pts = List.of(sel.points);
      pts[pts.length - 1] = pts.last + delta;
      c.replace(sel.copyWith(points: pts));
      return;
    }
    if (delta.distance > 0.5) {
      c.moveSelection(delta);
      return;
    }
    // dokunma: çift dokunma → düzenle
    final now = DateTime.now();
    if (sel != null && _lastTapId == sel.id && now.difference(_lastTapTime) < const Duration(milliseconds: 450)) {
      _lastTapId = null;
      await widget.onEditElement(sel);
    } else {
      _lastTapId = sel?.id;
      _lastTapTime = now;
    }
  }

  void _advanceDimension() {
    final kind = c.tool == ToolKind.distance ? DimKind.aligned : c.dimKind;
    final required = kind == DimKind.angle ? 4 : 3;
    if (_dimPts.length == 2 && (_dimPts[1] - _dimPts[0]).distance < 1.0) return; // tıklama: ikinci noktayı bekle
    if (_dimPts.length < required) {
      _dimPts.add(_dimPts.last);
      return;
    }
    final dim = DimensionElement(
      id: newId(),
      updatedAt: nowMs(),
      z: newZ(),
      kind: kind,
      points: List.of(_dimPts),
      tolerance: c.tool == ToolKind.distance ? const DimTolerance() : c.nextTolerance,
      textHeight: c.tool == ToolKind.distance ? 3.0 : c.dimTextHeight,
      color: c.tool == ToolKind.distance ? 0xFF6A1B9A : 0xFF0D47A1,
    );
    c.add(dim);
    _dimPts.clear();
    if (c.page.scale.isFree && kind != DimKind.angle) {
      widget.onRequestDimValue(dim).then((v) {
        final cur = c.page.elements[dim.id];
        if (v != null && v.trim().isNotEmpty && cur is DimensionElement) c.replace(cur.copyWith(textOverride: v.trim()));
      });
    }
  }

  /// Esc
  void cancelPending() {
    _dimPts.clear();
    _cancelDrawing();
  }

  // -------------------------------------------------------------------------

  ui.Picture _buildCache() {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    final page = c.page;
    final paper = Rect.fromLTWH(0, 0, page.widthMm, page.heightMm);
    canvas.drawRect(paper, Paint()..color = widget.darkPaper ? const Color(0xFF1E2226) : const Color(0xFFFFFFFF));
    canvas.save();
    canvas.clipRect(paper);
    c.template.painter(canvas, page);
    final hide = _dragStart != null ? c.selection : const <String>{};
    for (final e in page.visible) {
      if (hide.contains(e.id)) continue;
      paintElement(canvas, e, page.scale);
    }
    canvas.restore();
    return rec.endRecording();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      _size = box.biggest;
      if (!_fitted && _size.width > 0) {
        _fitted = true;
        zoom = math.max(0.5, (_size.width - 32) / c.page.widthMm);
        pan = Offset(math.max(16, (_size.width - c.page.widthMm * zoom) / 2), 16);
      }
      final key = (c.page.version, c.page.templateId, _dragStart != null ? Object.hashAll(c.selection) : null, widget.darkPaper);
      if (_cache == null || _cacheKey != key) {
        _cache?.dispose();
        _cache = _buildCache();
        _cacheKey = key;
      }
      return ClipRect(child: MouseRegion(
        cursor: switch (c.tool) {
          ToolKind.pan => SystemMouseCursors.grab,
          ToolKind.text => SystemMouseCursors.text,
          ToolKind.lasso => SystemMouseCursors.basic,
          _ => SystemMouseCursors.precise,
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onDown,
          onPointerMove: _onMove,
          onPointerUp: _onUp,
          onPointerCancel: _onUp,
          onPointerHover: _onHover,
          onPointerSignal: _onSignal,
          child: CustomPaint(
            size: Size.infinite,
            painter: _CanvasPainter(this),
          ),
        ),
      ));
    });
  }
}

class _CanvasPainter extends CustomPainter {
  final NoteCanvasState s;
  _CanvasPainter(this.s);

  @override
  void paint(Canvas canvas, Size size) {
    final c = s.c;
    final page = c.page;
    canvas.drawRect(Offset.zero & size, Paint()..color = s.widget.darkPaper ? const Color(0xFF101315) : const Color(0xFFE9ECEF));
    canvas.save();
    canvas.translate(s.pan.dx, s.pan.dy);
    canvas.scale(s.zoom);
    final paper = Rect.fromLTWH(0, 0, page.widthMm, page.heightMm);
    canvas.drawRect(paper.shift(Offset(0.6, 0.9)), Paint()..color = const Color(0x22000000));
    if (s._cache != null) canvas.drawPicture(s._cache!);

    // Taşınan seçim
    if (s._dragStart != null) {
      final sel = c.singleSelected;
      if (s._handleDrag && sel is DimensionElement) {
        final pts = List.of(sel.points);
        pts[pts.length - 1] = pts.last + s._dragDelta;
        paintDimension(canvas, sel.copyWith(points: pts), page.scale);
      } else {
        canvas.save();
        canvas.translate(s._dragDelta.dx, s._dragDelta.dy);
        for (final e in c.selected) {
          paintElement(canvas, e, page.scale);
        }
        canvas.restore();
      }
    }
    // tek seçili ölçünün tutamacı
    final one = c.singleSelected;
    if (one is DimensionElement && s._dragStart == null) {
      canvas.drawCircle(one.points.last, 6 / s.zoom, Paint()..color = const Color(0xFF1E88E5));
      canvas.drawCircle(one.points.last, 3 / s.zoom, Paint()..color = const Color(0xFFFFFFFF));
    }

    // Canlı önizleme
    if (s._live.isNotEmpty) {
      if (s._snapped != null) {
        paintShape(
            canvas,
            ShapeElement(
                id: '_',
                updatedAt: 0,
                z: 0,
                kind: s._snapped!.kind,
                points: s._snapped!.points,
                style: c.currentPen.copyWith(type: PenType.technical, width: math.max(c.currentPen.width, 0.35))));
      } else if (c.tool == ToolKind.lane || c.tool == ToolKind.road) {
        final w = c.paperFromMeters(c.tool == ToolKind.road ? 3.5 : c.laneWidthM) * (c.tool == ToolKind.road ? c.roadLanes : 1);
        canvas.drawPath(
            polylinePath([for (final p in s._live) p.o]),
            Paint()
              ..color = const Color(0x33455A64)
              ..style = PaintingStyle.stroke
              ..strokeWidth = w
              ..strokeJoin = StrokeJoin.round);
      } else if (c.tool == ToolKind.route) {
        paintStroke(canvas, s._live, const PenStyle(type: PenType.technical, color: 0xFF1565C0, width: 0.7, lineType: LineType.hidden));
      } else {
        paintStroke(canvas, s._live, c.currentPen);
      }
    }
    if (s._shapeA != null && s._shapeB != null && c.tool == ToolKind.shape) {
      paintShape(canvas, ShapeElement(id: '_', updatedAt: 0, z: 0, kind: c.shapeKind, points: [s._shapeA!, s._shapeB!], style: c.pens[PenType.technical]!));
    }
    if (s._shapeA != null && s._shapeB != null && (c.tool == ToolKind.gate || c.tool == ToolKind.motorcycle)) {
      canvas.drawLine(s._shapeA!, s._shapeB!, Paint()
        ..color = const Color(0xFF1E88E5)
        ..strokeWidth = 0.3);
    }
    for (final cone in s._pendingCones) {
      paintSymbol(canvas, cone);
    }
    // Ölçü önizlemesi
    if (s._dimPts.length >= 2) {
      final kind = c.tool == ToolKind.distance ? DimKind.aligned : c.dimKind;
      final need = kind == DimKind.angle ? 4 : 3;
      final pts = List.of(s._dimPts);
      while (pts.length < need) {
        pts.add(pts.last);
      }
      final preview = DimensionElement(id: '_', updatedAt: 0, z: 0, kind: kind, points: pts, textHeight: c.dimTextHeight, tolerance: c.nextTolerance);
      paintDimension(canvas, preview, page.scale);
      for (final p in s._dimPts) {
        canvas.drawCircle(p, 2.5 / s.zoom, Paint()..color = const Color(0xFF1E88E5));
      }
    }
    // Kement
    if (s._lasso.length > 1) {
      canvas.drawPath(
          dashPath(polylinePath(s._lasso), [6 / s.zoom, 4 / s.zoom]),
          Paint()
            ..color = const Color(0xFF1E88E5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2 / s.zoom);
    }
    final sb = c.selectionBounds;
    if (sb != null) paintSelection(canvas, s._handleDrag ? sb : sb.shift(s._dragDelta), s.zoom);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter old) => true;
}
