// Sayfa şablonları: arka plan deseni, form alanları, varsayılan ölçek ve ızgara.

import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../canvas/element_painter.dart' show drawText;
import '../models/note_models.dart';

typedef TemplatePainter = void Function(Canvas c, NotePage page);

class PageTemplate {
  final String id;
  final String name;
  final String description;
  final Set<PageMode> modes;
  final double widthMm, heightMm;
  final ScaleSpec scale;
  final double? gridMm; // yakalama ızgarası
  final double? ruleMm; // el yazısı hizalama çizgi aralığı
  final double ruleOffsetMm;
  final TemplatePainter painter;
  final bool infinite;

  const PageTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.modes,
    required this.painter,
    this.widthMm = 210,
    this.heightMm = 297,
    this.scale = ScaleSpec.oneToOne,
    this.gridMm,
    this.ruleMm,
    this.ruleOffsetMm = 0,
    this.infinite = false,
  });
}

const _all = {PageMode.engineering, PageMode.moto, PageMode.both};
const _eng = {PageMode.engineering, PageMode.both};
const _moto = {PageMode.moto, PageMode.both};

const _ink = Color(0xFF263238);
const _faint = Color(0x22000000);
const _faint2 = Color(0x44000000);
const _engGreen = Color(0x553C8D5A);

Paint _line(Color c, [double w = 0.15]) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w;

void _grid(Canvas c, Rect r, double step, Paint p, {Paint? major, int majorEvery = 0}) {
  var i = 0;
  for (var x = r.left; x <= r.right + 1e-6; x += step, i++) {
    c.drawLine(Offset(x, r.top), Offset(x, r.bottom), (major != null && majorEvery > 0 && i % majorEvery == 0) ? major : p);
  }
  i = 0;
  for (var y = r.top; y <= r.bottom + 1e-6; y += step, i++) {
    c.drawLine(Offset(r.left, y), Offset(r.right, y), (major != null && majorEvery > 0 && i % majorEvery == 0) ? major : p);
  }
}

void _dots(Canvas c, Rect r, double step, double radius, Color color) {
  final p = Paint()..color = color;
  for (var x = r.left; x <= r.right + 1e-6; x += step) {
    for (var y = r.top; y <= r.bottom + 1e-6; y += step) {
      c.drawCircle(Offset(x, y), radius, p);
    }
  }
}

/// Basit tablo: başlıklar + boş satırlar
void _table(Canvas c, Rect r, List<String> headers, List<double> colFractions, double rowH,
    {double headerH = 8, double textSize = 3}) {
  final p = _line(_ink, 0.25);
  final thin = _line(_faint2, 0.15);
  c.drawRect(r, p);
  var x = r.left;
  for (var i = 0; i < headers.length; i++) {
    final w = r.width * colFractions[i];
    if (i > 0) c.drawLine(Offset(x, r.top), Offset(x, r.bottom), p);
    drawText(c, headers[i], Offset(x + w / 2, r.top + headerH / 2), size: textSize, color: _ink, weight: FontWeight.w600);
    x += w;
  }
  c.drawLine(Offset(r.left, r.top + headerH), Offset(r.right, r.top + headerH), p);
  for (var y = r.top + headerH + rowH; y < r.bottom - 1e-6; y += rowH) {
    c.drawLine(Offset(r.left, y), Offset(r.right, y), thin);
  }
}

void _field(Canvas c, Offset at, String label, double width, {double size = 2.8}) {
  drawText(c, label, at, size: size, color: const Color(0xFF546E7A), anchor: Alignment.bottomLeft);
  final lw = math.min(width, 400.0);
  c.drawLine(at + Offset(0, 1.2), at + Offset(lw, 1.2), _line(_faint2, 0.2));
}

Rect _page(NotePage p) => Rect.fromLTWH(0, 0, p.widthMm, p.heightMm);

// ---------------------------------------------------------------------------
// Ortak

void _blank(Canvas c, NotePage p) {}

void _lined(Canvas c, NotePage p) {
  final r = _page(p);
  for (var y = 20.0; y < r.bottom - 10; y += 8) {
    c.drawLine(Offset(10, y), Offset(r.right - 10, y), _line(const Color(0x332196F3), 0.2));
  }
  c.drawLine(const Offset(28, 0), Offset(28, r.bottom), _line(const Color(0x55E53935), 0.25));
}

void _grid5(Canvas c, NotePage p) =>
    _grid(c, _page(p), 5, _line(_faint), major: _line(_faint2, 0.2), majorEvery: 4);

void _dot5(Canvas c, NotePage p) => _dots(c, _page(p), 5, 0.22, const Color(0x66000000));

// ---------------------------------------------------------------------------
// Mühendislik

void _engPad(Canvas c, NotePage p) {
  final r = _page(p);
  _grid(c, Rect.fromLTRB(20, 25, r.right - 8, r.bottom - 8), 5, _line(_engGreen, 0.12),
      major: _line(const Color(0x993C8D5A), 0.2), majorEvery: 5);
  // başlık şeridi
  final h = Rect.fromLTWH(20, 6, r.width - 28, 15);
  c.drawRect(h, _line(_ink, 0.3));
  final cols = [0.38, 0.24, 0.14, 0.24];
  final labels = ['PROJE', 'PARÇA NO', 'REV', 'TARİH'];
  var x = h.left;
  for (var i = 0; i < cols.length; i++) {
    final w = h.width * cols[i];
    if (i > 0) c.drawLine(Offset(x, h.top), Offset(x, h.bottom), _line(_ink, 0.3));
    drawText(c, labels[i], Offset(x + 1.2, h.top + 1.2), size: 2, color: const Color(0xFF546E7A), anchor: Alignment.topLeft);
    x += w;
  }
}

void _iso(Canvas c, NotePage p) {
  final r = _page(p);
  final paint = _line(_faint, 0.15);
  const step = 5.0; // kafes kenarı
  final dx = step * math.cos(math.pi / 6);
  for (var x = 0.0; x <= r.right; x += dx) {
    c.drawLine(Offset(x, 0), Offset(x, r.bottom), paint);
  }
  final span = r.right * math.tan(math.pi / 6);
  for (var y = -span; y <= r.bottom + span; y += step) {
    c.drawLine(Offset(0, y), Offset(r.right, y + span), paint);
    c.drawLine(Offset(0, y + span), Offset(r.right, y), paint);
  }
}

/// ISO 7200 başlık bloğu (180 mm genişlik), ISO 5457 çerçeve
void _drawingSheet(Canvas c, NotePage p) {
  final r = _page(p);
  final frame = Rect.fromLTRB(20, 10, r.right - 10, r.bottom - 10);
  c.drawRect(frame, _line(_ink, 0.7));
  // merkezleme işaretleri
  for (final m in [
    (Offset(r.width / 2, 0), Offset(r.width / 2, 15)),
    (Offset(r.width / 2, r.bottom), Offset(r.width / 2, r.bottom - 15)),
    (Offset(0, r.height / 2), Offset(25, r.height / 2)),
    (Offset(r.right, r.height / 2), Offset(r.right - 15, r.height / 2)),
  ]) {
    c.drawLine(m.$1, m.$2, _line(_ink, 0.7));
  }
  const tbW = 180.0, tbH = 36.0;
  final tb = Rect.fromLTWH(frame.right - tbW, frame.bottom - tbH, tbW, tbH);
  c.drawRect(tb, _line(_ink, 0.5));
  final thin = _line(_ink, 0.25);
  // satırlar
  c.drawLine(Offset(tb.left, tb.top + 9), Offset(tb.right, tb.top + 9), thin);
  c.drawLine(Offset(tb.left, tb.top + 18), Offset(tb.left + 110, tb.top + 18), thin);
  c.drawLine(Offset(tb.left, tb.top + 27), Offset(tb.left + 110, tb.top + 27), thin);
  for (final x in [35.0, 70.0, 110.0, 145.0]) {
    c.drawLine(Offset(tb.left + x, tb.top + (x == 110 ? 0 : 9)), Offset(tb.left + x, tb.bottom), thin);
  }
  void lbl(double x, double y, String s) =>
      drawText(c, s, Offset(tb.left + x + 1, tb.top + y + 1), size: 1.8, color: const Color(0xFF546E7A), anchor: Alignment.topLeft);
  lbl(0, 0, 'BAŞLIK / PARÇA ADI');
  lbl(110, 0, 'FİRMA');
  lbl(0, 9, 'ÇİZEN');
  lbl(35, 9, 'KONTROL');
  lbl(70, 9, 'ONAY');
  lbl(110, 9, 'MALZEME');
  lbl(145, 9, 'ÖLÇEK');
  lbl(0, 18, 'TARİH');
  lbl(35, 18, 'GENEL TOL. (ISO 2768)');
  lbl(70, 18, 'YÜZEY');
  lbl(110, 22.5, 'PARÇA NO / RESİM NO');
  lbl(145, 22.5, 'REV');
  lbl(0, 27, 'KÜTLE');
  lbl(35, 27, 'BOYUT');
  lbl(70, 27, 'SAYFA');
  c.drawLine(Offset(tb.left + 110, tb.top + 22.5), Offset(tb.right, tb.top + 22.5), thin);
  drawText(c, p.scale.label, Offset(tb.left + 162.5, tb.top + 15.5), size: 3.5, color: _ink);
}

void _review(Canvas c, NotePage p) {
  final r = _page(p);
  drawText(c, 'TASARIM GÖZDEN GEÇİRME', const Offset(15, 14), size: 5, color: _ink, weight: FontWeight.w700, anchor: Alignment.centerLeft);
  _field(c, const Offset(15, 28), 'Proje / Parça', 85);
  _field(c, const Offset(110, 28), 'Tarih', 85);
  _field(c, const Offset(15, 40), 'Katılımcılar', 180);
  drawText(c, 'Eskiz', const Offset(15, 50), size: 3, color: const Color(0xFF546E7A), anchor: Alignment.centerLeft);
  _grid(c, const Rect.fromLTRB(15, 53, 195, 160), 5, _line(_faint));
  c.drawRect(const Rect.fromLTRB(15, 53, 195, 160), _line(_faint2, 0.25));
  drawText(c, 'Kararlar', const Offset(15, 168), size: 3, color: const Color(0xFF546E7A), anchor: Alignment.centerLeft);
  for (var y = 178.0; y < 214; y += 8) {
    c.drawLine(Offset(15, y), Offset(195, y), _line(_faint2, 0.15));
  }
  _table(c, Rect.fromLTRB(15, 220, 195, r.bottom - 12), ['#', 'Aksiyon', 'Sorumlu', 'Termin', 'Durum'],
      [0.06, 0.5, 0.16, 0.14, 0.14], 9);
}

void _inspection(Canvas c, NotePage p) {
  final r = _page(p);
  drawText(c, 'ÖLÇÜM / MUAYENE KAYDI', const Offset(15, 14), size: 5, color: _ink, weight: FontWeight.w700, anchor: Alignment.centerLeft);
  _field(c, const Offset(15, 28), 'Parça no / Rev', 85);
  _field(c, const Offset(110, 28), 'Lot / Seri no', 85);
  _field(c, const Offset(15, 40), 'Ölçüm aleti / Kalibrasyon', 85);
  _field(c, const Offset(110, 40), 'Muayene eden / Tarih', 85);
  _table(c, Rect.fromLTRB(15, 50, 195, r.bottom - 15), ['No', 'Özellik', 'Nominal', 'Tolerans', 'Ölçülen', 'OK/RED'],
      [0.07, 0.3, 0.15, 0.17, 0.17, 0.14], 9);
}

// ---------------------------------------------------------------------------
// Motosiklet eğitim (ölçek 1:200 → 1 m = 5 mm)

void _metreGrid(Canvas c, NotePage p, {bool dots = false}) {
  final r = Rect.fromLTRB(10, 22, p.widthMm - 10, p.heightMm - 10);
  final oneM = p.scale.paperFromReal(1); // kağıt mm
  if (dots) {
    _dots(c, r, oneM, 0.25, const Color(0x55000000));
  } else {
    _grid(c, r, oneM, _line(_faint, 0.1), major: _line(_faint2, 0.2), majorEvery: 5);
  }
  c.drawRect(r, _line(_faint2, 0.3));
  // ölçek çubuğu: 10 m
  final bar = p.scale.paperFromReal(10);
  final y = 16.0;
  final x0 = p.widthMm - 12 - bar;
  for (var i = 0; i < 10; i++) {
    final w = bar / 10;
    c.drawRect(Rect.fromLTWH(x0 + i * w, y - 1, w, 2), Paint()..color = i.isEven ? _ink : const Color(0xFFFFFFFF));
  }
  c.drawRect(Rect.fromLTWH(x0, y - 1, bar, 2), _line(_ink, 0.2));
  drawText(c, '0', Offset(x0, y - 2.5), size: 2.2, color: _ink);
  drawText(c, '10 m', Offset(x0 + bar, y - 2.5), size: 2.2, color: _ink);
  drawText(c, 'Ölçek ${p.scale.numerator}:${p.scale.denominator}', Offset(x0 - 3, y), size: 2.2, color: _ink, anchor: Alignment.centerRight);
}

void _track(Canvas c, NotePage p) {
  drawText(c, 'PARKUR PLANI', const Offset(10, 12), size: 5, color: _ink, weight: FontWeight.w700, anchor: Alignment.centerLeft);
  _metreGrid(c, p);
}

void _gymkhana(Canvas c, NotePage p) {
  drawText(c, 'GYMKHANA PARKURU', const Offset(10, 12), size: 5, color: _ink, weight: FontWeight.w700, anchor: Alignment.centerLeft);
  _metreGrid(c, p, dots: true);
}

void _roadCurve(Canvas c, NotePage p) {
  drawText(c, 'YOL VE VİRAJ ANALİZİ', const Offset(10, 12), size: 5, color: _ink, weight: FontWeight.w700, anchor: Alignment.centerLeft);
  // Ölçek 1:500 → 3,5 m şerit = 7 mm. Düz yol + 90° sağ viraj.
  final lane = p.scale.paperFromReal(3.5);
  final cx = 60.0, cy = 120.0, rMid = 70.0;
  final asphalt = Paint()..color = const Color(0x22455A64);
  final edge = _line(const Color(0xFF455A64), 0.45);
  final dashP = _line(const Color(0xFF455A64), 0.3);
  // düz kısım (aşağıdan yukarı)
  final straight = Rect.fromLTRB(cx + rMid - lane, cy, cx + rMid + lane, p.heightMm - 20);
  c.drawRect(straight, asphalt);
  c.drawLine(straight.topLeft, straight.bottomLeft, edge);
  c.drawLine(straight.topRight, straight.bottomRight, edge);
  for (var y = straight.top; y < straight.bottom; y += 6) {
    c.drawLine(Offset(cx + rMid, y), Offset(cx + rMid, math.min(y + 3, straight.bottom)), dashP);
  }
  // viraj: merkezi (cx, cy), 0 → -90° (sağdan yukarıya, sola dönüş)
  final outer = Rect.fromCircle(center: Offset(cx, cy), radius: rMid + lane);
  final inner = Rect.fromCircle(center: Offset(cx, cy), radius: rMid - lane);
  final ring = Path()
    ..addArc(outer, 0, -math.pi / 2)
    ..arcTo(inner, -math.pi / 2, math.pi / 2, false)
    ..close();
  c.drawPath(ring, asphalt);
  c.drawArc(outer, 0, -math.pi / 2, false, edge);
  c.drawArc(inner, 0, -math.pi / 2, false, edge);
  final mid = Rect.fromCircle(center: Offset(cx, cy), radius: rMid);
  for (var a = 0.0; a > -math.pi / 2; a -= 0.09) {
    c.drawArc(mid, a, -0.045, false, dashP);
  }
  // işaretler (Roadcraft): giriş, apeks, çıkış, limit noktası
  void mark(Offset at, String s, Color col) {
    c.drawCircle(at, 1.2, Paint()..color = col);
    drawText(c, s, at + const Offset(2.5, 0), size: 2.6, color: col, anchor: Alignment.centerLeft, weight: FontWeight.w600);
  }

  final rOut = rMid + lane * 0.6;
  mark(Offset(cx + rOut, cy + 15), 'Giriş', const Color(0xFF1565C0));
  final ap = -math.pi / 4;
  mark(Offset(cx + (rMid - lane * 0.6) * math.cos(ap), cy + (rMid - lane * 0.6) * math.sin(ap)), 'Apeks', const Color(0xFFC62828));
  mark(Offset(cx + 5, cy - rOut), 'Çıkış', const Color(0xFF2E7D32));
  mark(Offset(cx + (rMid + lane) * math.cos(-1.0), cy + (rMid + lane) * math.sin(-1.0)), 'Limit noktası', const Color(0xFF6A1B9A));
  // şerit içi pozisyonlar 1-2-3
  final py = straight.bottom - 25;
  for (final (i, f) in [(1, 0.2), (2, 0.5), (3, 0.8)]) {
    final x = cx + rMid + lane * (f * 2 - 1) * 0.5 + lane * 0.5;
    drawText(c, '$i', Offset(x, py), size: 3, color: _ink, weight: FontWeight.w700);
  }
  _field(c, Offset(15, p.heightMm - 40), 'Hız / vites', 50);
  _field(c, Offset(15, p.heightMm - 28), 'Not', 50);
  drawText(c, 'Ölçek ${p.scale.numerator}:${p.scale.denominator}', Offset(p.widthMm - 12, 12), size: 2.4, color: _ink, anchor: Alignment.centerRight);
}

void _lessonPlan(Canvas c, NotePage p) {
  final r = _page(p);
  drawText(c, 'DERS PLANI', const Offset(15, 14), size: 5, color: _ink, weight: FontWeight.w700, anchor: Alignment.centerLeft);
  _field(c, const Offset(15, 28), 'Tarih / Alan', 85);
  _field(c, const Offset(110, 28), 'Seviye / Grup', 85);
  _field(c, const Offset(15, 40), 'Hedef', 180);
  var y = 52.0;
  for (final s in ['Güvenlik brifingi', 'Isınma', 'Egzersiz 1', 'Egzersiz 2', 'Egzersiz 3', 'Değerlendirme / kapanış']) {
    drawText(c, s, Offset(15, y), size: 3, color: _ink, weight: FontWeight.w600, anchor: Alignment.centerLeft);
    for (var k = 1; k <= 3; k++) {
      c.drawLine(Offset(15, y + k * 7 + 1), Offset(195, y + k * 7 + 1), _line(_faint2, 0.15));
    }
    y += 30;
  }
  drawText(c, 'Ekipman kontrolü', Offset(15, y), size: 3, color: _ink, weight: FontWeight.w600, anchor: Alignment.centerLeft);
  final items = ['Kask', 'Eldiven', 'Mont/koruma', 'Bot', 'Lastik/basınç', 'Fren', 'Işıklar', 'Zincir', 'Koni seti', 'İlk yardım'];
  for (var i = 0; i < items.length; i++) {
    final cx = 15.0 + (i % 5) * 37, cy = y + 8 + (i ~/ 5) * 8;
    if (cy > r.bottom - 10) break;
    c.drawRect(Rect.fromLTWH(cx, cy - 1.8, 3.6, 3.6), _line(_ink, 0.25));
    drawText(c, items[i], Offset(cx + 5, cy), size: 2.6, color: _ink, anchor: Alignment.centerLeft);
  }
}

void _studentEval(Canvas c, NotePage p) {
  final r = _page(p);
  drawText(c, 'ÖĞRENCİ DEĞERLENDİRME', const Offset(15, 14), size: 5, color: _ink, weight: FontWeight.w700, anchor: Alignment.centerLeft);
  _field(c, const Offset(15, 28), 'Öğrenci', 85);
  _field(c, const Offset(110, 28), 'Tarih / Motosiklet', 85);
  _table(c, Rect.fromLTRB(15, 38, 195, 190), ['Egzersiz', '1', '2', '3', '4', '5', 'Not'],
      [0.34, 0.07, 0.07, 0.07, 0.07, 0.07, 0.31], 10);
  const rows = ['Bakış / göz yönü', 'Gaz–debriyaj kontrolü', 'Düşük hız denge', 'Slalom', 'Ani fren', 'Kaçınma manevrası', 'Viraj hattı', 'Vücut pozisyonu', 'Gözlem / Roadcraft', 'Genel güven'];
  for (var i = 0; i < rows.length; i++) {
    final y = 38 + 8 + 10 * i + 5.0;
    if (y > 188) break;
    drawText(c, rows[i], Offset(17, y), size: 2.6, color: _ink, anchor: Alignment.centerLeft);
  }
  drawText(c, 'Gözlemler ve sonraki ders hedefi', const Offset(15, 200), size: 3, color: const Color(0xFF546E7A), anchor: Alignment.centerLeft);
  for (var y = 210.0; y < r.bottom - 10; y += 8) {
    c.drawLine(Offset(15, y), Offset(195, y), _line(_faint2, 0.15));
  }
}

// ---------------------------------------------------------------------------

final templates = <PageTemplate>[
  PageTemplate(id: 'blank', name: 'Boş', description: 'Düz kağıt', modes: _all, painter: _blank),
  PageTemplate(id: 'infinite', name: 'Sonsuz tuval', description: 'Sınırsız alan, sonra A4/A3 dışa aktar', modes: _all, painter: _blank, infinite: true, gridMm: 5),
  PageTemplate(id: 'lined', name: 'Çizgili', description: '8 mm satır', modes: _all, painter: _lined, ruleMm: 8, ruleOffsetMm: 20),
  PageTemplate(id: 'grid5', name: '5 mm kareli', description: '20 mm ana çizgi', modes: _all, painter: _grid5, gridMm: 5),
  PageTemplate(id: 'dot5', name: '5 mm noktalı', description: 'Nokta ızgara', modes: _all, painter: _dot5, gridMm: 5),
  PageTemplate(id: 'engpad', name: 'Mühendislik pedi', description: 'Yeşil kareli + başlık şeridi', modes: _eng, painter: _engPad, gridMm: 5),
  PageTemplate(id: 'iso', name: 'İzometrik', description: '30° ızgara', modes: _eng, painter: _iso),
  PageTemplate(id: 'drawA4', name: 'Teknik resim A4', description: 'ISO 7200 başlık bloğu', modes: _eng, painter: _drawingSheet, gridMm: 5),
  PageTemplate(id: 'drawA3', name: 'Teknik resim A3', description: 'A3 yatay, ISO 7200', modes: _eng, painter: _drawingSheet, widthMm: 420, heightMm: 297, gridMm: 5),
  PageTemplate(id: 'review', name: 'Tasarım gözden geçirme', description: 'Kararlar + aksiyon tablosu', modes: _eng, painter: _review, gridMm: 5),
  PageTemplate(id: 'inspection', name: 'Ölçüm / muayene', description: 'Nominal, tolerans, ölçülen', modes: _eng, painter: _inspection),
  PageTemplate(id: 'track', name: 'Parkur planı', description: '1 m ızgara, 1:200', modes: _moto, painter: _track, widthMm: 297, heightMm: 210, scale: ScaleSpec.moto200, gridMm: 5),
  PageTemplate(id: 'gymkhana', name: 'Gymkhana parkuru', description: '1 m nokta, start/finiş', modes: _moto, painter: _gymkhana, widthMm: 297, heightMm: 210, scale: ScaleSpec.moto200, gridMm: 5),
  PageTemplate(id: 'road', name: 'Yol ve viraj', description: 'Giriş–apeks–çıkış, limit noktası', modes: _moto, painter: _roadCurve, scale: ScaleSpec(1, 500, 'm')),
  PageTemplate(id: 'lesson', name: 'Ders planı', description: 'Brifing, egzersizler, ekipman', modes: _moto, painter: _lessonPlan),
  PageTemplate(id: 'eval', name: 'Öğrenci değerlendirme', description: 'Egzersiz × 1–5 puan', modes: _moto, painter: _studentEval),
];

PageTemplate templateById(String id) => templates.firstWhere((t) => t.id == id, orElse: () => templates.first);

List<PageTemplate> templatesFor(PageMode mode) => templates.where((t) => t.modes.contains(mode)).toList();
