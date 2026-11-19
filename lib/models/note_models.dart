// Veri modeli. Tüm koordinatlar sayfa milimetresindedir (A4 = 210 x 297).
// Her eleman kalıcı bir id, updatedAt (ms) ve silinme işareti (mezar taşı) taşır;
// senkron birleştirme eleman düzeyinde "son yazan kazanır" ile yapılır.

import 'dart:math' as math;
import 'dart:ui';

import 'package:uuid/uuid.dart';

const _uuid = Uuid();
String newId() => _uuid.v4().replaceAll('-', '').substring(0, 20);
int nowMs() => DateTime.now().millisecondsSinceEpoch;

double _r(double v) => (v * 100).roundToDouble() / 100; // 0,01 mm çözünürlük
List<double> _o(Offset o) => [_r(o.dx), _r(o.dy)];
Offset _po(dynamic j) => Offset((j[0] as num).toDouble(), (j[1] as num).toDouble());

// ---------------------------------------------------------------------------
// Sayfa modu ve ölçek

enum PageMode { engineering, moto, both }

extension PageModeX on PageMode {
  String get label => switch (this) {
        PageMode.engineering => 'Mühendislik',
        PageMode.moto => 'Motosiklet eğitim',
        PageMode.both => 'Her ikisi',
      };
}

/// Sayfa ölçeği: kağıt üzerindeki 1 mm = den/num mm gerçek. unit 'mm' veya 'm'.
class ScaleSpec {
  final int numerator;
  final int denominator;
  final String unit;
  const ScaleSpec(this.numerator, this.denominator, [this.unit = 'mm']);

  static const oneToOne = ScaleSpec(1, 1);
  static const moto200 = ScaleSpec(1, 200, 'm');
  /// Ölçeksiz eskiz: ölçü değerleri elle yazılır
  static const free = ScaleSpec(1, 1, 'free');

  bool get isFree => unit == 'free';

  /// Kağıt mm -> gerçek değer (unit cinsinden)
  double realFromPaper(double paperMm) {
    final mm = paperMm * denominator / numerator;
    return unit == 'm' ? mm / 1000.0 : mm;
  }

  /// Gerçek değer (unit) -> kağıt mm
  double paperFromReal(double real) {
    final mm = unit == 'm' ? real * 1000.0 : real;
    return mm * numerator / denominator;
  }

  String get label => isFree ? 'Ölçeksiz' : '$numerator:$denominator${unit == 'm' ? ' (m)' : ''}';

  Map<String, dynamic> toJson() => {'n': numerator, 'd': denominator, 'u': unit};
  factory ScaleSpec.fromJson(Map<String, dynamic> j) =>
      ScaleSpec(j['n'] as int, j['d'] as int, (j['u'] as String?) ?? 'mm');

  @override
  bool operator ==(Object other) =>
      other is ScaleSpec && other.numerator == numerator && other.denominator == denominator && other.unit == unit;
  @override
  int get hashCode => Object.hash(numerator, denominator, unit);
}

// ---------------------------------------------------------------------------
// Kalem

enum PenType { fountain, ballpoint, pencil, technical, highlighter }

enum LineType { continuous, hidden, center, phantom }

extension PenTypeX on PenType {
  String get label => switch (this) {
        PenType.fountain => 'Dolma kalem',
        PenType.ballpoint => 'Tükenmez',
        PenType.pencil => 'Kurşun kalem',
        PenType.technical => 'Teknik kalem',
        PenType.highlighter => 'Fosforlu',
      };
}

extension LineTypeX on LineType {
  String get label => switch (this) {
        LineType.continuous => 'Sürekli',
        LineType.hidden => 'Gizli (kesik)',
        LineType.center => 'Eksen',
        LineType.phantom => 'Hayali',
      };
}

/// ISO 128 çizgi kalınlıkları (mm)
const isoLineWidths = [0.18, 0.25, 0.35, 0.5, 0.7, 1.0];

class PenStyle {
  final PenType type;
  final int color; // ARGB
  final double width; // mm
  final LineType lineType;

  const PenStyle({
    required this.type,
    required this.color,
    required this.width,
    this.lineType = LineType.continuous,
  });

  PenStyle copyWith({PenType? type, int? color, double? width, LineType? lineType}) => PenStyle(
        type: type ?? this.type,
        color: color ?? this.color,
        width: width ?? this.width,
        lineType: lineType ?? this.lineType,
      );

  Map<String, dynamic> toJson() =>
      {'t': type.index, 'c': color, 'w': width, 'l': lineType.index};
  factory PenStyle.fromJson(Map<String, dynamic> j) => PenStyle(
        type: PenType.values[j['t'] as int],
        color: j['c'] as int,
        width: (j['w'] as num).toDouble(),
        lineType: LineType.values[(j['l'] as int?) ?? 0],
      );

  static PenStyle defaultFor(PenType t) => switch (t) {
        PenType.fountain => const PenStyle(type: PenType.fountain, color: 0xFF1A237E, width: 0.6),
        PenType.ballpoint => const PenStyle(type: PenType.ballpoint, color: 0xFF000000, width: 0.5),
        PenType.pencil => const PenStyle(type: PenType.pencil, color: 0xFF37474F, width: 0.4),
        PenType.technical => const PenStyle(type: PenType.technical, color: 0xFF000000, width: 0.35),
        PenType.highlighter => const PenStyle(type: PenType.highlighter, color: 0xFFFFEB3B, width: 5.0),
      };
}

class InkPoint {
  final double x, y, p; // mm, mm, basınç 0..1
  final int t; // ms (çizgi başından)
  const InkPoint(this.x, this.y, this.p, this.t);
  Offset get o => Offset(x, y);
  InkPoint shifted(double dx, double dy) => InkPoint(x + dx, y + dy, p, t);
}

// ---------------------------------------------------------------------------
// Elemanlar

enum ShapeKind { line, rect, ellipse, triangle, polygon, arrow, centerline, route }

enum DimKind { aligned, horizontal, vertical, radius, diameter, angle }

enum SymbolKind { cone, motorcycle, startGate, finishGate, northArrow, gdtFrame, datum, surface, weld }

extension DimKindX on DimKind {
  String get label => switch (this) {
        DimKind.aligned => 'Hizalı',
        DimKind.horizontal => 'Yatay',
        DimKind.vertical => 'Dikey',
        DimKind.radius => 'Yarıçap R',
        DimKind.diameter => 'Çap Ø',
        DimKind.angle => 'Açı',
      };
}

abstract class NoteElement {
  final String id;
  final int updatedAt;
  final bool deleted;
  final double z; // çizim sırası

  const NoteElement({required this.id, required this.updatedAt, required this.z, this.deleted = false});

  String get type;
  Rect get bounds;

  /// Aynı id ile yeni zaman damgalı kopya
  NoteElement translated(Offset d);
  NoteElement tombstone();

  Map<String, dynamic> bodyJson();

  Map<String, dynamic> toJson() => {
        'id': id,
        'ty': type,
        'u': updatedAt,
        'z': z,
        if (deleted) 'x': 1,
        if (!deleted) ...bodyJson(),
      };

  static NoteElement fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String;
    final u = j['u'] as int;
    final z = (j['z'] as num).toDouble();
    final del = j['x'] == 1;
    final ty = j['ty'] as String;
    if (del) return Tombstone(id: id, updatedAt: u, z: z, originalType: ty);
    return switch (ty) {
      'stroke' => StrokeElement.fromBody(id, u, z, j),
      'shape' => ShapeElement.fromBody(id, u, z, j),
      'dim' => DimensionElement.fromBody(id, u, z, j),
      'text' => TextElement.fromBody(id, u, z, j),
      'sym' => SymbolElement.fromBody(id, u, z, j),
      'lane' => LaneElement.fromBody(id, u, z, j),
      'img' => ImageElement.fromBody(id, u, z, j),
      'audio' => AudioElement.fromBody(id, u, z, j),
      _ => Tombstone(id: id, updatedAt: u, z: z, originalType: ty),
    };
  }
}

double newZ() => nowMs() + math.Random().nextDouble();

Rect _boundsOf(Iterable<Offset> pts, [double pad = 0]) {
  double l = double.infinity, t = double.infinity, r = -double.infinity, b = -double.infinity;
  for (final p in pts) {
    l = math.min(l, p.dx);
    t = math.min(t, p.dy);
    r = math.max(r, p.dx);
    b = math.max(b, p.dy);
  }
  if (l == double.infinity) return Rect.zero;
  return Rect.fromLTRB(l - pad, t - pad, r + pad, b + pad);
}

class Tombstone extends NoteElement {
  final String originalType;
  const Tombstone({required super.id, required super.updatedAt, required super.z, required this.originalType})
      : super(deleted: true);
  @override
  String get type => originalType;
  @override
  Rect get bounds => Rect.zero;
  @override
  NoteElement translated(Offset d) => this;
  @override
  NoteElement tombstone() => this;
  @override
  Map<String, dynamic> bodyJson() => const {};
}

class StrokeElement extends NoteElement {
  final List<InkPoint> points;
  final PenStyle style;
  const StrokeElement({required super.id, required super.updatedAt, required super.z, required this.points, required this.style});

  @override
  String get type => 'stroke';
  @override
  Rect get bounds => _boundsOf(points.map((p) => p.o), style.width);

  @override
  StrokeElement translated(Offset d) => StrokeElement(
      id: id, updatedAt: nowMs(), z: z, style: style, points: [for (final p in points) p.shifted(d.dx, d.dy)]);

  StrokeElement withPoints(List<InkPoint> pts, {bool newIdentity = false}) => StrokeElement(
      id: newIdentity ? newId() : id, updatedAt: nowMs(), z: newIdentity ? newZ() : z, style: style, points: pts);

  StrokeElement withStyle(PenStyle s) =>
      StrokeElement(id: id, updatedAt: nowMs(), z: z, style: s, points: points);

  @override
  NoteElement tombstone() => Tombstone(id: id, updatedAt: nowMs(), z: z, originalType: type);

  @override
  Map<String, dynamic> bodyJson() => {
        's': style.toJson(),
        // düz dizi: x,y,p,t,...
        'p': [
          for (final p in points) ...[_r(p.x), _r(p.y), (p.p * 100).round(), p.t]
        ],
      };

  factory StrokeElement.fromBody(String id, int u, double z, Map<String, dynamic> j) {
    final raw = (j['p'] as List).cast<num>();
    final pts = <InkPoint>[];
    for (var i = 0; i + 3 < raw.length; i += 4) {
      pts.add(InkPoint(raw[i].toDouble(), raw[i + 1].toDouble(), raw[i + 2] / 100.0, raw[i + 3].toInt()));
    }
    return StrokeElement(id: id, updatedAt: u, z: z, points: pts, style: PenStyle.fromJson(j['s']));
  }
}

class ShapeElement extends NoteElement {
  final ShapeKind kind;
  final List<Offset> points; // line/arrow: 2, rect/ellipse: 2 köşe, triangle/polygon/route: n
  final PenStyle style;
  final int? fill; // ARGB
  const ShapeElement(
      {required super.id, required super.updatedAt, required super.z, required this.kind, required this.points, required this.style, this.fill});

  @override
  String get type => 'shape';
  @override
  Rect get bounds => _boundsOf(points, style.width + 1.5);

  @override
  ShapeElement translated(Offset d) => ShapeElement(
      id: id, updatedAt: nowMs(), z: z, kind: kind, style: style, fill: fill, points: [for (final p in points) p + d]);

  ShapeElement withStyle(PenStyle s) =>
      ShapeElement(id: id, updatedAt: nowMs(), z: z, kind: kind, style: s, fill: fill, points: points);

  @override
  NoteElement tombstone() => Tombstone(id: id, updatedAt: nowMs(), z: z, originalType: type);

  /// Kenarlar boyunca "yakalama" noktaları (uç, orta, merkez)
  List<Offset> get snapPoints {
    switch (kind) {
      case ShapeKind.rect:
        final r = Rect.fromPoints(points[0], points[1]);
        return [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight, r.center,
          r.topCenter, r.bottomCenter, r.centerLeft, r.centerRight];
      case ShapeKind.ellipse:
        final r = Rect.fromPoints(points[0], points[1]);
        return [r.center, r.topCenter, r.bottomCenter, r.centerLeft, r.centerRight];
      default:
        final out = <Offset>[...points];
        for (var i = 0; i + 1 < points.length; i++) {
          out.add((points[i] + points[i + 1]) / 2);
        }
        return out;
    }
  }

  @override
  Map<String, dynamic> bodyJson() => {
        'k': kind.index,
        's': style.toJson(),
        'p': [for (final p in points) _o(p)],
        if (fill != null) 'f': fill,
      };

  factory ShapeElement.fromBody(String id, int u, double z, Map<String, dynamic> j) => ShapeElement(
        id: id,
        updatedAt: u,
        z: z,
        kind: ShapeKind.values[j['k'] as int],
        style: PenStyle.fromJson(j['s']),
        points: [for (final p in j['p'] as List) _po(p)],
        fill: j['f'] as int?,
      );
}

class DimTolerance {
  final double? upper; // +0.1
  final double? lower; // -0.05
  final String? fit; // H7, g6
  const DimTolerance({this.upper, this.lower, this.fit});
  bool get isEmpty => upper == null && lower == null && (fit == null || fit!.isEmpty);
  bool get symmetric => upper != null && lower != null && (upper! + lower!).abs() < 1e-9;
  Map<String, dynamic> toJson() => {if (upper != null) 'u': upper, if (lower != null) 'l': lower, if (fit != null) 'f': fit};
  factory DimTolerance.fromJson(Map<String, dynamic>? j) => j == null
      ? const DimTolerance()
      : DimTolerance(upper: (j['u'] as num?)?.toDouble(), lower: (j['l'] as num?)?.toDouble(), fit: j['f'] as String?);
}

class DimensionElement extends NoteElement {
  final DimKind kind;
  /// aligned/horizontal/vertical: [p1, p2, ofsetNoktası]
  /// radius/diameter: [merkez, çember üzerinde nokta, metin noktası]
  /// angle: [tepe, kol1, kol2, yay noktası]
  final List<Offset> points;
  final String? textOverride;
  final DimTolerance tolerance;
  final double textHeight; // mm (2.5 / 3.5)
  final int color;

  const DimensionElement({
    required super.id,
    required super.updatedAt,
    required super.z,
    required this.kind,
    required this.points,
    this.textOverride,
    this.tolerance = const DimTolerance(),
    this.textHeight = 2.5,
    this.color = 0xFF0D47A1,
  });

  @override
  String get type => 'dim';
  @override
  Rect get bounds => _boundsOf(points, textHeight * 2);

  @override
  DimensionElement translated(Offset d) => copyWith(points: [for (final p in points) p + d]);

  DimensionElement copyWith({List<Offset>? points, String? textOverride, bool clearOverride = false, DimTolerance? tolerance, double? textHeight}) =>
      DimensionElement(
        id: id,
        updatedAt: nowMs(),
        z: z,
        kind: kind,
        points: points ?? this.points,
        textOverride: clearOverride ? null : (textOverride ?? this.textOverride),
        tolerance: tolerance ?? this.tolerance,
        textHeight: textHeight ?? this.textHeight,
        color: color,
      );

  @override
  NoteElement tombstone() => Tombstone(id: id, updatedAt: nowMs(), z: z, originalType: type);

  /// Kağıt üzerindeki geometrik büyüklük (mm veya derece)
  double get paperValue {
    final p = points;
    switch (kind) {
      case DimKind.aligned:
        return (p[1] - p[0]).distance;
      case DimKind.horizontal:
        return (p[1].dx - p[0].dx).abs();
      case DimKind.vertical:
        return (p[1].dy - p[0].dy).abs();
      case DimKind.radius:
        return (p[1] - p[0]).distance;
      case DimKind.diameter:
        return 2 * (p[1] - p[0]).distance;
      case DimKind.angle:
        final a = p[1] - p[0], b = p[2] - p[0];
        final ang = math.atan2(a.dx * b.dy - a.dy * b.dx, a.dx * b.dx + a.dy * b.dy).abs();
        return ang * 180 / math.pi;
    }
  }

  @override
  Map<String, dynamic> bodyJson() => {
        'k': kind.index,
        'p': [for (final p in points) _o(p)],
        if (textOverride != null) 'o': textOverride,
        if (!tolerance.isEmpty) 'tol': tolerance.toJson(),
        'h': textHeight,
        'c': color,
      };

  factory DimensionElement.fromBody(String id, int u, double z, Map<String, dynamic> j) => DimensionElement(
        id: id,
        updatedAt: u,
        z: z,
        kind: DimKind.values[j['k'] as int],
        points: [for (final p in j['p'] as List) _po(p)],
        textOverride: j['o'] as String?,
        tolerance: DimTolerance.fromJson(j['tol'] as Map<String, dynamic>?),
        textHeight: (j['h'] as num?)?.toDouble() ?? 2.5,
        color: (j['c'] as int?) ?? 0xFF0D47A1,
      );
}

enum TextKind { plain, box, checklist, bullet }

enum FontKind { sans, serif, mono }

class TextElement extends NoteElement {
  final Offset pos; // sol üst
  final String text; // checklist satırları "[x] " / "[ ] " önekli
  final double size; // mm (yazı yüksekliği)
  final int color;
  final int? background; // ARGB, null = saydam
  final bool bold, italic, underline;
  final FontKind font;
  final TextKind kind;
  final double? boxWidth; // mm, metin kutusu genişliği (null = otomatik)
  final bool fromInk; // el yazısından çevrildi
  const TextElement({
    required super.id,
    required super.updatedAt,
    required super.z,
    required this.pos,
    required this.text,
    this.size = 4,
    this.color = 0xFF000000,
    this.background,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.font = FontKind.sans,
    this.kind = TextKind.plain,
    this.boxWidth,
    this.fromInk = false,
  });

  @override
  String get type => 'text';

  List<String> get lines => text.split('\n');
  double get lineHeight => size * 1.35;
  double get indent => kind == TextKind.checklist || kind == TextKind.bullet ? size * 1.4 : 0;
  double get pad => kind == TextKind.box || background != null ? size * 0.4 : 0;

  @override
  Rect get bounds {
    final w = boxWidth ?? (lines.map((l) => l.length).fold<int>(1, math.max) * size * (bold ? 0.6 : 0.55) + indent);
    return Rect.fromLTWH(pos.dx - pad, pos.dy - pad, w + 2 * pad, lines.length * lineHeight + 2 * pad);
  }

  /// Satır i'nin onay kutusu alanı (checklist)
  Rect checkboxRect(int i) => Rect.fromLTWH(pos.dx, pos.dy + i * lineHeight + size * 0.1, size * 0.95, size * 0.95);

  TextElement copyWith({
    Offset? pos,
    String? text,
    double? size,
    int? color,
    int? background,
    bool clearBackground = false,
    bool? bold,
    bool? italic,
    bool? underline,
    FontKind? font,
    TextKind? kind,
    double? boxWidth,
  }) =>
      TextElement(
        id: id,
        updatedAt: nowMs(),
        z: z,
        pos: pos ?? this.pos,
        text: text ?? this.text,
        size: size ?? this.size,
        color: color ?? this.color,
        background: clearBackground ? null : (background ?? this.background),
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        font: font ?? this.font,
        kind: kind ?? this.kind,
        boxWidth: boxWidth ?? this.boxWidth,
        fromInk: fromInk,
      );

  /// Checklist satırını aç/kapat
  TextElement toggleLine(int i) {
    final ls = lines;
    if (i < 0 || i >= ls.length) return this;
    final l = ls[i];
    if (l.startsWith('[x] ')) {
      ls[i] = '[ ] ${l.substring(4)}';
    } else if (l.startsWith('[ ] ')) {
      ls[i] = '[x] ${l.substring(4)}';
    } else {
      ls[i] = '[x] $l';
    }
    return copyWith(text: ls.join('\n'));
  }

  @override
  TextElement translated(Offset d) => copyWith(pos: pos + d);

  TextElement withText(String t) => copyWith(text: t);

  @override
  NoteElement tombstone() => Tombstone(id: id, updatedAt: nowMs(), z: z, originalType: type);

  @override
  Map<String, dynamic> bodyJson() => {
        'p': _o(pos),
        't': text,
        's': size,
        'c': color,
        if (background != null) 'bg': background,
        if (bold) 'b': 1,
        if (italic) 'it': 1,
        if (underline) 'ul': 1,
        if (font != FontKind.sans) 'f': font.index,
        if (kind != TextKind.plain) 'k': kind.index,
        if (boxWidth != null) 'bw': boxWidth,
        if (fromInk) 'i': 1,
      };

  factory TextElement.fromBody(String id, int u, double z, Map<String, dynamic> j) => TextElement(
        id: id,
        updatedAt: u,
        z: z,
        pos: _po(j['p']),
        text: j['t'] as String,
        size: (j['s'] as num).toDouble(),
        color: j['c'] as int,
        background: j['bg'] as int?,
        bold: j['b'] == 1,
        italic: j['it'] == 1,
        underline: j['ul'] == 1,
        font: FontKind.values[(j['f'] as int?) ?? 0],
        kind: TextKind.values[(j['k'] as int?) ?? 0],
        boxWidth: (j['bw'] as num?)?.toDouble(),
        fromInk: j['i'] == 1,
      );
}

class SymbolElement extends NoteElement {
  final SymbolKind kind;
  final Offset pos;
  final double rotation; // radyan
  final double size; // mm (sembolün ana boyutu)
  final int color;
  /// GD&T: char, tol, dia(1/0), mod(M/L/''), d1,d2,d3 · datum: letter ·
  /// surface: ra, proc(any/remove/keep) · weld: wt(fillet/v/square), a, around(1/0), field(1/0)
  /// gate: w (kağıt mm genişlik), label
  final Map<String, String> params;

  const SymbolElement({
    required super.id,
    required super.updatedAt,
    required super.z,
    required this.kind,
    required this.pos,
    this.rotation = 0,
    this.size = 5,
    this.color = 0xFF000000,
    this.params = const {},
  });

  @override
  String get type => 'sym';

  @override
  Rect get bounds {
    final extent = switch (kind) {
      SymbolKind.gdtFrame => size * 8,
      SymbolKind.startGate || SymbolKind.finishGate => (double.tryParse(params['w'] ?? '') ?? size * 3),
      SymbolKind.weld => size * 6,
      _ => size * 1.5,
    };
    return Rect.fromCircle(center: pos, radius: extent);
  }

  @override
  SymbolElement translated(Offset d) => copyWith(pos: pos + d);

  SymbolElement copyWith({Offset? pos, double? rotation, Map<String, String>? params}) => SymbolElement(
        id: id,
        updatedAt: nowMs(),
        z: z,
        kind: kind,
        pos: pos ?? this.pos,
        rotation: rotation ?? this.rotation,
        size: size,
        color: color,
        params: params ?? this.params,
      );

  @override
  NoteElement tombstone() => Tombstone(id: id, updatedAt: nowMs(), z: z, originalType: type);

  @override
  Map<String, dynamic> bodyJson() =>
      {'k': kind.index, 'p': _o(pos), 'r': rotation, 's': size, 'c': color, if (params.isNotEmpty) 'm': params};

  factory SymbolElement.fromBody(String id, int u, double z, Map<String, dynamic> j) => SymbolElement(
        id: id,
        updatedAt: u,
        z: z,
        kind: SymbolKind.values[j['k'] as int],
        pos: _po(j['p']),
        rotation: (j['r'] as num).toDouble(),
        size: (j['s'] as num).toDouble(),
        color: j['c'] as int,
        params: ((j['m'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, v as String)),
      );
}

/// Şerit / yol: merkez çizgisi + gerçek genişlik (m) — kağıt genişliği sayfa ölçeğinden.
class LaneElement extends NoteElement {
  final List<Offset> centerline;
  final double widthPaper; // mm (yerleştirirken ölçekten hesaplanır)
  final double widthReal; // m, etiket için
  final int lanes; // 1 = tek şerit, 2+ = yol (aralarda kesik çizgi)
  final int color;
  const LaneElement({
    required super.id,
    required super.updatedAt,
    required super.z,
    required this.centerline,
    required this.widthPaper,
    required this.widthReal,
    this.lanes = 1,
    this.color = 0xFF455A64,
  });

  @override
  String get type => 'lane';
  @override
  Rect get bounds => _boundsOf(centerline, widthPaper * lanes / 2 + 1);

  @override
  LaneElement translated(Offset d) => LaneElement(
      id: id,
      updatedAt: nowMs(),
      z: z,
      centerline: [for (final p in centerline) p + d],
      widthPaper: widthPaper,
      widthReal: widthReal,
      lanes: lanes,
      color: color);

  @override
  NoteElement tombstone() => Tombstone(id: id, updatedAt: nowMs(), z: z, originalType: type);

  @override
  Map<String, dynamic> bodyJson() => {
        'p': [for (final p in centerline) _o(p)],
        'w': widthPaper,
        'wr': widthReal,
        'n': lanes,
        'c': color,
      };

  factory LaneElement.fromBody(String id, int u, double z, Map<String, dynamic> j) => LaneElement(
        id: id,
        updatedAt: u,
        z: z,
        centerline: [for (final p in j['p'] as List) _po(p)],
        widthPaper: (j['w'] as num).toDouble(),
        widthReal: (j['wr'] as num).toDouble(),
        lanes: j['n'] as int,
        color: j['c'] as int,
      );
}

/// Görsel (fotoğraf, PDF sayfası arka planı). Dosya yerel "assets/" klasöründe ve Drive'da ayrı durur.
class ImageElement extends NoteElement {
  final String assetId; // dosya adı: <id>.<ext>
  final Rect rect; // mm
  final double rotation; // radyan (merkez etrafında)
  final bool locked; // PDF arka planı: seç/sil ile oynamaz
  const ImageElement({required super.id, required super.updatedAt, required super.z, required this.assetId, required this.rect, this.rotation = 0, this.locked = false});

  @override
  String get type => 'img';
  @override
  Rect get bounds {
    if (rotation == 0) return rect;
    final c = rect.center;
    final pts = [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight].map((p) => rotatePoint(p, c, rotation));
    return _boundsOf(pts);
  }

  ImageElement copyWith({Rect? rect, double? rotation, bool? locked}) => ImageElement(
      id: id, updatedAt: nowMs(), z: z, assetId: assetId, rect: rect ?? this.rect, rotation: rotation ?? this.rotation, locked: locked ?? this.locked);

  @override
  ImageElement translated(Offset d) => copyWith(rect: rect.shift(d));
  @override
  NoteElement tombstone() => Tombstone(id: id, updatedAt: nowMs(), z: z, originalType: type);
  @override
  Map<String, dynamic> bodyJson() => {
        'a': assetId,
        'r': [_r(rect.left), _r(rect.top), _r(rect.width), _r(rect.height)],
        if (rotation != 0) 'rot': rotation,
        if (locked) 'lk': 1,
      };
  factory ImageElement.fromBody(String id, int u, double z, Map<String, dynamic> j) {
    final r = (j['r'] as List).cast<num>();
    return ImageElement(
        id: id,
        updatedAt: u,
        z: z,
        assetId: j['a'] as String,
        rect: Rect.fromLTWH(r[0].toDouble(), r[1].toDouble(), r[2].toDouble(), r[3].toDouble()),
        rotation: (j['rot'] as num?)?.toDouble() ?? 0,
        locked: j['lk'] == 1);
  }
}

/// Ses kaydı: sayfada küçük bir oynat düğmesi
class AudioElement extends NoteElement {
  final String assetId;
  final Offset pos;
  final int durationMs;
  final String label;
  const AudioElement({required super.id, required super.updatedAt, required super.z, required this.assetId, required this.pos, required this.durationMs, this.label = ''});

  @override
  String get type => 'audio';
  @override
  Rect get bounds => Rect.fromLTWH(pos.dx, pos.dy, 36, 9);
  @override
  AudioElement translated(Offset d) =>
      AudioElement(id: id, updatedAt: nowMs(), z: z, assetId: assetId, pos: pos + d, durationMs: durationMs, label: label);
  @override
  NoteElement tombstone() => Tombstone(id: id, updatedAt: nowMs(), z: z, originalType: type);
  @override
  Map<String, dynamic> bodyJson() => {'a': assetId, 'p': _o(pos), 'd': durationMs, if (label.isNotEmpty) 'l': label};
  factory AudioElement.fromBody(String id, int u, double z, Map<String, dynamic> j) => AudioElement(
      id: id, updatedAt: u, z: z, assetId: j['a'] as String, pos: _po(j['p']), durationMs: j['d'] as int, label: (j['l'] as String?) ?? '');
}

Offset rotatePoint(Offset p, Offset c, double a) {
  final v = p - c;
  final cs = math.cos(a), sn = math.sin(a);
  return c + Offset(v.dx * cs - v.dy * sn, v.dx * sn + v.dy * cs);
}

/// Elemanı c etrafında a radyan döndür (aynı id, yeni zaman damgası)
NoteElement rotateElement(NoteElement e, Offset c, double a) {
  Offset r(Offset p) => rotatePoint(p, c, a);
  final u = nowMs();
  switch (e) {
    case StrokeElement s:
      return StrokeElement(id: s.id, updatedAt: u, z: s.z, style: s.style, points: [
        for (final p in s.points)
          () {
            final q = r(p.o);
            return InkPoint(q.dx, q.dy, p.p, p.t);
          }()
      ]);
    case ShapeElement s:
      List<Offset> pts;
      var kind = s.kind;
      if (s.kind == ShapeKind.rect) {
        final rc = Rect.fromPoints(s.points[0], s.points[1]);
        pts = [rc.topLeft, rc.topRight, rc.bottomRight, rc.bottomLeft].map(r).toList();
        kind = ShapeKind.polygon;
      } else if (s.kind == ShapeKind.ellipse) {
        final rc = Rect.fromPoints(s.points[0], s.points[1]);
        if ((rc.width - rc.height).abs() < 1e-6) {
          final nc = r(rc.center);
          pts = [nc - Offset(rc.width / 2, rc.height / 2), nc + Offset(rc.width / 2, rc.height / 2)];
        } else {
          pts = [
            for (var i = 0; i < 64; i++)
              r(rc.center + Offset(math.cos(i / 64 * 2 * math.pi) * rc.width / 2, math.sin(i / 64 * 2 * math.pi) * rc.height / 2))
          ];
          kind = ShapeKind.polygon;
        }
      } else {
        pts = s.points.map(r).toList();
      }
      return ShapeElement(id: s.id, updatedAt: u, z: s.z, kind: kind, style: s.style, fill: s.fill, points: pts);
    case DimensionElement d:
      final rightAngle = ((a / (math.pi / 2)).roundToDouble() * math.pi / 2 - a).abs() < 1e-6;
      return DimensionElement(
        id: d.id,
        updatedAt: u,
        z: d.z,
        kind: (d.kind == DimKind.horizontal || d.kind == DimKind.vertical) && !rightAngle ? DimKind.aligned : d.kind,
        points: d.points.map(r).toList(),
        textOverride: d.textOverride,
        tolerance: d.tolerance,
        textHeight: d.textHeight,
        color: d.color,
      );
    case TextElement t:
      final ctr = t.bounds.center;
      return t.copyWith(pos: r(ctr) - (ctr - t.pos));
    case SymbolElement s:
      return s.copyWith(pos: r(s.pos), rotation: s.rotation + a);
    case LaneElement l:
      return LaneElement(
          id: l.id, updatedAt: u, z: l.z, centerline: l.centerline.map(r).toList(), widthPaper: l.widthPaper, widthReal: l.widthReal, lanes: l.lanes, color: l.color);
    case ImageElement i:
      return i.copyWith(rect: i.rect.shift(r(i.rect.center) - i.rect.center), rotation: i.rotation + a);
    case AudioElement au:
      return au.translated(r(au.pos) - au.pos);
    default:
      return e;
  }
}

// ---------------------------------------------------------------------------
// Sayfa ve defter

class NotePage {
  final String id;
  String notebookId;
  String title;
  PageMode mode;
  String templateId;
  double widthMm;
  double heightMm;
  ScaleSpec scale;
  double order;
  int createdAt;
  int metaUpdatedAt; // başlık/şablon/mod değişiklikleri
  bool deleted;
  bool infinite; // sonsuz tuval (sayfa sınırı yok)
  String recognizedText; // arama dizini (arka plan tanıma)
  final Map<String, NoteElement> elements;

  // --- yalnızca yerel (Drive'a gitmez)
  bool dirty;
  String? syncV; // son birleştirilen/yüklenen uzak sürüm
  String? driveFileId;

  /// Değişiklik sayacı (önbellek geçersizleştirme için), kalıcı değil
  int version = 0;

  NotePage({
    required this.id,
    required this.notebookId,
    required this.title,
    required this.mode,
    required this.templateId,
    this.widthMm = 210,
    this.heightMm = 297,
    this.scale = ScaleSpec.oneToOne,
    this.order = 0,
    int? createdAt,
    int? metaUpdatedAt,
    this.deleted = false,
    this.recognizedText = '',
    this.infinite = false,
    Map<String, NoteElement>? elements,
    this.dirty = true,
    this.syncV,
    this.driveFileId,
  })  : createdAt = createdAt ?? nowMs(),
        metaUpdatedAt = metaUpdatedAt ?? nowMs(),
        elements = elements ?? <String, NoteElement>{};

  List<NoteElement>? _sortedCache;
  int _sortedVersion = -1;

  /// Görünür elemanlar, z sırasına göre
  List<NoteElement> get visible {
    if (_sortedCache == null || _sortedVersion != version) {
      _sortedCache = elements.values.where((e) => !e.deleted).toList()..sort((a, b) => a.z.compareTo(b.z));
      _sortedVersion = version;
    }
    return _sortedCache!;
  }

  int get updatedAt => elements.values.fold<int>(metaUpdatedAt, (m, e) => math.max(m, e.updatedAt));

  void put(NoteElement e) {
    elements[e.id] = e;
    touch();
  }

  void touch() {
    version++;
    dirty = true;
  }

  void touchMeta() {
    metaUpdatedAt = nowMs();
    touch();
  }

  /// Uzak sayfayı bu sayfaya birleştirir. Dönüş: yerelde uzakta olmayan/daha yeni bir şey var mı
  /// (yani birleştirilmiş sonucun yeniden yüklenmesi gerekiyor mu).
  bool mergeFrom(NotePage remote) {
    var localHasNewer = false;
    var changed = false;

    if (remote.metaUpdatedAt > metaUpdatedAt) {
      title = remote.title;
      mode = remote.mode;
      templateId = remote.templateId;
      widthMm = remote.widthMm;
      heightMm = remote.heightMm;
      scale = remote.scale;
      order = remote.order;
      notebookId = remote.notebookId;
      deleted = remote.deleted;
      infinite = remote.infinite;
      metaUpdatedAt = remote.metaUpdatedAt;
      changed = true;
    } else if (metaUpdatedAt > remote.metaUpdatedAt) {
      localHasNewer = true;
    }
    if (remote.recognizedText.isNotEmpty && recognizedText.isEmpty) recognizedText = remote.recognizedText;

    for (final r in remote.elements.values) {
      final l = elements[r.id];
      if (l == null || r.updatedAt > l.updatedAt) {
        elements[r.id] = r;
        changed = true;
      } else if (l.updatedAt > r.updatedAt) {
        localHasNewer = true;
      }
    }
    for (final id in elements.keys) {
      if (!remote.elements.containsKey(id)) localHasNewer = true;
    }
    if (changed) version++;
    return localHasNewer;
  }

  /// 30 günden eski mezar taşlarını temizle
  void purgeTombstones({Duration age = const Duration(days: 30)}) {
    final limit = nowMs() - age.inMilliseconds;
    elements.removeWhere((_, e) => e.deleted && e.updatedAt < limit);
  }

  Map<String, dynamic> toJson({bool includeLocal = false}) => {
        'v': 1,
        'id': id,
        'nb': notebookId,
        'ti': title,
        'mo': mode.index,
        'tp': templateId,
        'w': widthMm,
        'h': heightMm,
        'sc': scale.toJson(),
        'or': order,
        'ca': createdAt,
        'mu': metaUpdatedAt,
        if (deleted) 'del': 1,
        if (recognizedText.isNotEmpty) 'rt': recognizedText,
        if (infinite) 'inf': 1,
        'el': [for (final e in elements.values) e.toJson()],
        if (includeLocal) 'local': {'dirty': dirty, 'syncV': syncV, 'fid': driveFileId},
      };

  factory NotePage.fromJson(Map<String, dynamic> j) {
    final local = j['local'] as Map<String, dynamic>?;
    final els = <String, NoteElement>{};
    for (final e in j['el'] as List) {
      final el = NoteElement.fromJson(e as Map<String, dynamic>);
      els[el.id] = el;
    }
    return NotePage(
      id: j['id'] as String,
      notebookId: j['nb'] as String,
      title: j['ti'] as String,
      mode: PageMode.values[j['mo'] as int],
      templateId: j['tp'] as String,
      widthMm: (j['w'] as num).toDouble(),
      heightMm: (j['h'] as num).toDouble(),
      scale: ScaleSpec.fromJson(j['sc'] as Map<String, dynamic>),
      order: (j['or'] as num).toDouble(),
      createdAt: j['ca'] as int,
      metaUpdatedAt: j['mu'] as int,
      deleted: j['del'] == 1,
      recognizedText: (j['rt'] as String?) ?? '',
      infinite: j['inf'] == 1,
      elements: els,
      dirty: (local?['dirty'] as bool?) ?? false,
      syncV: local?['syncV'] as String?,
      driveFileId: local?['fid'] as String?,
    );
  }
}

class Notebook {
  final String id;
  String title;
  int color;
  int createdAt;
  int updatedAt;
  bool deleted;
  Notebook({required this.id, required this.title, this.color = 0xFF455A64, int? createdAt, int? updatedAt, this.deleted = false})
      : createdAt = createdAt ?? nowMs(),
        updatedAt = updatedAt ?? nowMs();

  Map<String, dynamic> toJson() =>
      {'id': id, 'ti': title, 'c': color, 'ca': createdAt, 'u': updatedAt, if (deleted) 'del': 1};
  factory Notebook.fromJson(Map<String, dynamic> j) => Notebook(
        id: j['id'] as String,
        title: j['ti'] as String,
        color: j['c'] as int,
        createdAt: j['ca'] as int,
        updatedAt: j['u'] as int,
        deleted: j['del'] == 1,
      );
}

/// Defter listelerini birleştir (id başına son yazan kazanır). Dönüş: yerelde daha yeni bir şey var mı.
bool mergeNotebooks(Map<String, Notebook> local, Iterable<Notebook> remote) {
  var localNewer = false;
  final remoteIds = <String>{};
  for (final r in remote) {
    remoteIds.add(r.id);
    final l = local[r.id];
    if (l == null || r.updatedAt > l.updatedAt) {
      local[r.id] = r;
    } else if (l.updatedAt > r.updatedAt) {
      localNewer = true;
    }
  }
  if (local.keys.any((id) => !remoteIds.contains(id))) localNewer = true;
  return localNewer;
}
