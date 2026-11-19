import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:teknik_defter/core/format.dart';
import 'package:teknik_defter/ink/beautify.dart';
import 'package:teknik_defter/models/note_models.dart';

StrokeElement _stroke(List<Offset> pts, {String? id, int? u}) => StrokeElement(
      id: id ?? newId(),
      updatedAt: u ?? nowMs(),
      z: newZ(),
      points: [for (var i = 0; i < pts.length; i++) InkPoint(pts[i].dx, pts[i].dy, 0.5, i * 10)],
      style: PenStyle.defaultFor(PenType.ballpoint),
    );

void main() {
  group('Ölçek ve ölçü metni', () {
    test('2:1 ölçekte 20 mm çizgi 10 yazar', () {
      final d = DimensionElement(id: 'a', updatedAt: 0, z: 0, kind: DimKind.aligned, points: const [Offset(0, 0), Offset(20, 0), Offset(0, -8)]);
      expect(dimensionMainText(d, const ScaleSpec(2, 1)), '10');
    });
    test('1:200 ölçekte 25 mm = 5 m', () {
      final d = DimensionElement(id: 'a', updatedAt: 0, z: 0, kind: DimKind.aligned, points: const [Offset(0, 0), Offset(25, 0), Offset(0, -8)]);
      expect(dimensionMainText(d, ScaleSpec.moto200), '5 m');
    });
    test('Çap ve tolerans', () {
      final d = DimensionElement(
          id: 'a',
          updatedAt: 0,
          z: 0,
          kind: DimKind.diameter,
          points: const [Offset(0, 0), Offset(6.25, 0), Offset(20, -10)],
          tolerance: const DimTolerance(upper: 0.05, lower: -0.05));
      expect(dimensionMainText(d, ScaleSpec.oneToOne), 'Ø12,5');
      expect(dimensionInlineSuffix(d), ' ±0,05');
    });
    test('Açı', () {
      final d = DimensionElement(id: 'a', updatedAt: 0, z: 0, kind: DimKind.angle, points: const [Offset(0, 0), Offset(10, 0), Offset(0, 10), Offset(5, 5)]);
      expect(dimensionMainText(d, ScaleSpec.oneToOne), '90°');
    });
  });

  group('Şekil tanıma', () {
    test('Titrek doğru → çizgi, 0°ye oturur', () {
      final pts = [for (var i = 0; i <= 40; i++) Offset(i * 1.0, 0.3 * math.sin(i.toDouble()) + i * 0.02)];
      final s = recognizeShape(pts);
      expect(s?.kind, ShapeKind.line);
      expect(s!.points.last.dy, closeTo(0, 1e-6));
    });
    test('Daire', () {
      final pts = [for (var i = 0; i <= 64; i++) Offset(50 + 20 * math.cos(i / 64 * 2 * math.pi), 50 + 20 * math.sin(i / 64 * 2 * math.pi))];
      final s = recognizeShape(pts);
      expect(s?.kind, ShapeKind.ellipse);
      final r = Rect.fromPoints(s!.points[0], s.points[1]);
      expect(r.width, closeTo(40, 1));
      expect(r.height, closeTo(40, 1));
    });
    test('Dikdörtgen', () {
      final pts = <Offset>[];
      for (var x = 0.0; x <= 40; x += 2) {
        pts.add(Offset(x, 0));
      }
      for (var y = 0.0; y <= 25; y += 2) {
        pts.add(Offset(40, y));
      }
      for (var x = 40.0; x >= 0; x -= 2) {
        pts.add(Offset(x, 25));
      }
      for (var y = 25.0; y >= 0; y -= 2) {
        pts.add(Offset(0.3, y));
      }
      expect(recognizeShape(pts)?.kind, ShapeKind.rect);
    });
    test('Üçgen', () {
      final a = const Offset(0, 40), b = const Offset(40, 40), c = const Offset(20, 5);
      final pts = <Offset>[];
      for (final (p, q) in [(a, b), (b, c), (c, a)]) {
        for (var t = 0.0; t < 1; t += 0.05) {
          pts.add(Offset.lerp(p, q, t)!);
        }
      }
      pts.add(a);
      expect(recognizeShape(pts)?.kind, ShapeKind.triangle);
    });
    test('Karalama → null', () {
      final rnd = math.Random(3);
      final pts = [for (var i = 0; i < 60; i++) Offset(rnd.nextDouble() * 30, rnd.nextDouble() * 30)];
      expect(recognizeShape(pts), isNull);
    });
  });

  group('El yazısı hizalama', () {
    test('Kayık kelimeler ortak tabana iner', () {
      // 3 "kelime", taban y = 50, 53, 47
      final words = [
        _stroke([const Offset(0, 45), const Offset(5, 50), const Offset(10, 45)]),
        _stroke([const Offset(20, 48), const Offset(25, 53), const Offset(30, 48)]),
        _stroke([const Offset(45, 42), const Offset(50, 47), const Offset(55, 42)]),
      ];
      final out = alignHandwriting(words);
      final bases = [for (final s in out) s.points.map((p) => p.y).reduce(math.max)];
      expect(bases[0], closeTo(bases[1], 0.01));
      expect(bases[1], closeTo(bases[2], 0.01));
      expect(out.map((e) => e.id).toSet(), words.map((e) => e.id).toSet());
    });
  });

  group('Senkron birleştirme', () {
    test('İki cihazın çizgileri birleşir, silme yayılır', () {
      final base = NotePage(id: 'p', notebookId: 'n', title: 't', mode: PageMode.engineering, templateId: 'blank', metaUpdatedAt: 1);
      final shared = _stroke([const Offset(0, 0), const Offset(5, 5)], id: 'shared', u: 100);
      base.put(shared);

      final tablet = NotePage.fromJson(base.toJson());
      final phone = NotePage.fromJson(base.toJson());
      tablet.put(_stroke([const Offset(1, 1), const Offset(2, 2)], id: 'tab', u: 200));
      phone.put(_stroke([const Offset(3, 3), const Offset(4, 4)], id: 'tel', u: 210));
      phone.put(Tombstone(id: 'shared', updatedAt: 220, z: shared.z, originalType: 'stroke'));

      final localNewer = tablet.mergeFrom(NotePage.fromJson(phone.toJson()));
      expect(localNewer, isTrue); // tabletin 'tab' çizgisi uzakta yok → yeniden yüklenmeli
      expect(tablet.visible.map((e) => e.id).toSet(), {'tab', 'tel'});
      expect(tablet.elements['shared']!.deleted, isTrue);
    });

    test('JSON gidiş-dönüş tüm eleman türleri', () {
      final p = NotePage(id: 'p', notebookId: 'n', title: 't', mode: PageMode.both, templateId: 'grid5');
      p.put(_stroke([const Offset(0, 0), const Offset(1, 1)]));
      p.put(ShapeElement(id: newId(), updatedAt: 1, z: 1, kind: ShapeKind.rect, points: const [Offset(0, 0), Offset(10, 5)], style: PenStyle.defaultFor(PenType.technical)));
      p.put(DimensionElement(id: newId(), updatedAt: 1, z: 2, kind: DimKind.radius, points: const [Offset(0, 0), Offset(3, 0), Offset(9, -4)], tolerance: const DimTolerance(fit: 'H7')));
      p.put(TextElement(id: newId(), updatedAt: 1, z: 3, pos: const Offset(4, 4), text: 'Ölçü kontrol', fromInk: true));
      p.put(SymbolElement(id: newId(), updatedAt: 1, z: 4, kind: SymbolKind.gdtFrame, pos: const Offset(50, 50), params: const {'char': 'flatness', 'tol': '0,05'}));
      p.put(LaneElement(id: newId(), updatedAt: 1, z: 5, centerline: const [Offset(0, 0), Offset(50, 10)], widthPaper: 12.5, widthReal: 2.5));
      final back = NotePage.fromJson(p.toJson());
      expect(back.visible.length, 6);
      expect(back.toJson()['el'], p.toJson()['el']);
    });
  });
}
