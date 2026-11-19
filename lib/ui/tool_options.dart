import 'package:flutter/material.dart';

import '../canvas/editor_controller.dart';
import '../canvas/element_painter.dart' show gdtCharacteristics;
import '../canvas/tools.dart';
import '../core/format.dart';
import '../models/note_models.dart';


/// Tablet/Windows: araç çubuğunun altında yatay ayar şeridi
class ToolOptionsBar extends StatelessWidget {
  final EditorController ctrl;
  const ToolOptionsBar({super.key, required this.ctrl});
  @override
  Widget build(BuildContext context) {
    final items = buildToolOptions(context, ctrl);
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (_, i) => Center(child: items[i]),
    );
  }
}

/// Telefon: alt sayfada dikey ayar paneli
class ToolOptionsPanel extends StatelessWidget {
  final EditorController ctrl;
  const ToolOptionsPanel({super.key, required this.ctrl});
  @override
  Widget build(BuildContext context) => Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: buildToolOptions(context, ctrl));
}

Widget _colorDots(List<int> colors, int selected, ValueChanged<int> onPick) => Row(mainAxisSize: MainAxisSize.min, children: [
      for (final c in colors)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: InkResponse(
            onTap: () => onPick(c),
            radius: 16,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(color: c == selected ? Colors.blueAccent : Colors.black26, width: c == selected ? 3 : 1),
              ),
            ),
          ),
        ),
    ]);

Widget _chips<T>(List<T> values, T selected, String Function(T) label, ValueChanged<T> onPick) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final v in values)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: ChoiceChip(label: Text(label(v)), selected: v == selected, onSelected: (_) => onPick(v), visualDensity: VisualDensity.compact),
          ),
      ],
    );

Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) =>
    FilterChip(label: Text(label), selected: value, onSelected: onChanged, visualDensity: VisualDensity.compact);

Widget _miniField(String label, String value, ValueChanged<String> onChanged, {double width = 70}) => SizedBox(
      width: width,
      child: TextFormField(
        key: ValueKey('field-$label'),
        initialValue: value,
        decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
        onChanged: onChanged,
      ),
    );

double? _parse(String s) => double.tryParse(s.replaceAll(',', '.').replaceAll('+', '').trim());

List<Widget> buildToolOptions(BuildContext context, EditorController c) {
  switch (c.tool) {
    case ToolKind.pen:
      final pen = c.pens[c.penType]!;
      return [
        _chips([PenType.fountain, PenType.ballpoint, PenType.pencil, PenType.technical], c.penType, (t) => t.label, c.setPenType),
        _colorDots(penPalette, pen.color, (v) => c.updatePen(c.penType, pen.copyWith(color: v))),
        if (c.penType == PenType.technical) ...[
          _chips(isoLineWidths, pen.width, (w) => formatNumber(w), (w) => c.updatePen(c.penType, pen.copyWith(width: w))),
          _chips(LineType.values, pen.lineType, (l) => l.label, (l) => c.updatePen(c.penType, pen.copyWith(lineType: l))),
        ] else
          SizedBox(
            width: 160,
            child: Slider(
              value: pen.width.clamp(0.2, 2.0),
              min: 0.2,
              max: 2.0,
              divisions: 18,
              label: '${formatNumber(pen.width)} mm',
              onChanged: (v) => c.updatePen(c.penType, pen.copyWith(width: v)),
            ),
          ),
        _chips([0, 1, 2, 3], c.smoothing, (v) => 'Yumuşatma $v', (v) => c.update(() => c.smoothing = v)),
        _toggle('Basılı tut → şekil', c.shapeHold, (v) => c.update(() => c.shapeHold = v)),
        _toggle('Yalnızca kalem', c.stylusOnly, (v) => c.update(() => c.stylusOnly = v)),
        if (c.stylusOnly) _toggle('Tek parmakla kaydır', c.fingerScroll, (v) => c.update(() => c.fingerScroll = v)),
      ];
    case ToolKind.highlighter:
      final hl = c.pens[PenType.highlighter]!;
      return [
        _colorDots(highlighterPalette, hl.color, (v) => c.updatePen(PenType.highlighter, hl.copyWith(color: v))),
        _chips([3.0, 5.0, 8.0], hl.width, (w) => '${formatNumber(w)} mm', (w) => c.updatePen(PenType.highlighter, hl.copyWith(width: w))),
      ];
    case ToolKind.eraser:
      return [
        _chips(EraserMode.values, c.eraserMode, (m) => m == EraserMode.stroke ? 'Çizgi silgisi' : 'Kısmi silgi', (m) => c.update(() => c.eraserMode = m)),
        _chips([1.0, 2.0, 5.0], c.eraserRadius, (r) => '${formatNumber(r)} mm', (r) => c.update(() => c.eraserRadius = r)),
      ];
    case ToolKind.select:
      return [const Text('Dokun: seç · sürükle: taşı · çift dokun: düzenle (ölçü değeri, tolerans, GD&T, metin…). Ölçünün mavi tutamacını sürükle: ölçü çizgisini kaydır.')];
    case ToolKind.lasso:
      return [const Text('Çevresini çiz → seç (dokunarak da seçilir). Seçimi sürükle → taşı. Seçim çubuğunda: Metne çevir, Hizala, Şekle oturt.')];
    case ToolKind.text:
      final d = c.textDefaults;
      return [
        _chips(TextKind.values, d.kind,
            (k) => switch (k) { TextKind.plain => 'Metin', TextKind.box => 'Metin kutusu', TextKind.checklist => 'Onay listesi', TextKind.bullet => 'Madde listesi' },
            (k) => c.update(() => c.textDefaults = d.copyWith(kind: k))),
        _chips([3.0, 4.0, 5.0, 6.0, 8.0], d.size, (v) => '${(v * 2.835).round()} pt', (v) => c.update(() => c.textDefaults = d.copyWith(size: v))),
        _toggle('Kalın', d.bold, (v) => c.update(() => c.textDefaults = d.copyWith(bold: v))),
        _colorDots(penPalette, d.color, (v) => c.update(() => c.textDefaults = d.copyWith(color: v))),
        Text('Boş yere dokun → yeni metin · metne dokun → düzenle', style: Theme.of(context).textTheme.bodySmall),
      ];
    case ToolKind.shape:
      final tech = c.pens[PenType.technical]!;
      return [
        _chips([ShapeKind.line, ShapeKind.rect, ShapeKind.ellipse, ShapeKind.arrow, ShapeKind.centerline], c.shapeKind,
            (k) => switch (k) {
                  ShapeKind.line => 'Çizgi',
                  ShapeKind.rect => 'Dikdörtgen',
                  ShapeKind.ellipse => 'Daire/elips',
                  ShapeKind.arrow => 'Ok',
                  ShapeKind.centerline => 'Eksen',
                  _ => k.name,
                },
            (k) => c.update(() => c.shapeKind = k)),
        _chips(isoLineWidths, tech.width, (w) => formatNumber(w), (w) => c.updatePen(PenType.technical, tech.copyWith(width: w))),
        _chips(LineType.values, tech.lineType, (l) => l.label, (l) => c.updatePen(PenType.technical, tech.copyWith(lineType: l))),
        _toggle('Parametrik (dokun → ölçü yaz)', c.parametric, (v) => c.update(() => c.parametric = v)),
        _toggle('Ortho 15° (Shift)', c.ortho, (v) => c.update(() => c.ortho = v)),
        _toggle('Izgara', c.gridSnap, (v) => c.update(() => c.gridSnap = v)),
        _toggle('Nesne yakala', c.objectSnap, (v) => c.update(() => c.objectSnap = v)),
      ];
    case ToolKind.dimension:
      final t = c.nextTolerance;
      return [
        _chips(DimKind.values, c.dimKind, (k) => k.label, (k) => c.update(() => c.dimKind = k)),
        _chips([2.5, 3.5], c.dimTextHeight, (h) => 'h ${formatNumber(h)}', (h) => c.update(() => c.dimTextHeight = h)),
        _miniField('Üst sapma', t.upper == null ? '' : formatNumber(t.upper!, maxDecimals: 3),
            (s) => c.nextTolerance = DimTolerance(upper: _parse(s), lower: c.nextTolerance.lower, fit: c.nextTolerance.fit)),
        _miniField('Alt sapma', t.lower == null ? '' : formatNumber(t.lower!, maxDecimals: 3),
            (s) => c.nextTolerance = DimTolerance(upper: c.nextTolerance.upper, lower: _parse(s), fit: c.nextTolerance.fit)),
        _miniField('Geçme', t.fit ?? '', (s) => c.nextTolerance = DimTolerance(upper: c.nextTolerance.upper, lower: c.nextTolerance.lower, fit: s.trim().isEmpty ? null : s.trim())),
        Text(c.dimKind == DimKind.angle ? 'Tepe → kol 1 (sürükle) → kol 2 → yay' : 'Nokta 1 → nokta 2 (sürükle) → ölçü çizgisi yeri', style: Theme.of(context).textTheme.bodySmall),
      ];
    case ToolKind.distance:
      return [Text('Mesafe: iki nokta + ölçü çizgisi yeri. Birim sayfa ölçeğinden (${c.page.scale.label}).', style: Theme.of(context).textTheme.bodySmall)];
    case ToolKind.gdt:
      final p = c.gdtParams;
      void put(String k, String v) => c.update(() => c.gdtParams = {...c.gdtParams, k: v});
      return [
        DropdownButton<String>(
          value: p['char'],
          items: [for (final e in gdtCharacteristics.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => put('char', v!),
        ),
        _toggle('Ø', p['dia'] == '1', (v) => put('dia', v ? '1' : '0')),
        _miniField('Tolerans', p['tol'] ?? '', (v) => put('tol', v)),
        _chips(['', 'M', 'L'], p['mod'] ?? '', (m) => m.isEmpty ? 'Değiştirici yok' : m, (m) => put('mod', m)),
        _miniField('Datum 1', p['d1'] ?? '', (v) => put('d1', v.toUpperCase()), width: 64),
        _miniField('Datum 2', p['d2'] ?? '', (v) => put('d2', v.toUpperCase()), width: 64),
        _miniField('Datum 3', p['d3'] ?? '', (v) => put('d3', v.toUpperCase()), width: 64),
      ];
    case ToolKind.datum:
      return [_miniField('Harf', c.datumLetter, (v) => c.datumLetter = v.isEmpty ? 'A' : v.toUpperCase().substring(0, 1), width: 60)];
    case ToolKind.surface:
      final p = c.surfaceParams;
      return [
        _chips(['any', 'remove', 'keep'], p['proc'] ?? 'remove',
            (v) => switch (v) { 'any' => 'Serbest', 'remove' => 'Talaşlı', _ => 'Talaşsız' },
            (v) => c.update(() => c.surfaceParams = {...p, 'proc': v})),
        _chips(['0,4', '0,8', '1,6', '3,2', '6,3', '12,5'], p['ra'] ?? '3,2', (v) => 'Ra $v', (v) => c.update(() => c.surfaceParams = {...p, 'ra': v})),
      ];
    case ToolKind.weld:
      final p = c.weldParams;
      return [
        _chips(['fillet', 'v', 'square'], p['wt'] ?? 'fillet',
            (v) => switch (v) { 'fillet' => 'Köşe', 'v' => 'V', _ => 'I (alın)' },
            (v) => c.update(() => c.weldParams = {...p, 'wt': v})),
        _miniField('a / s', p['a'] ?? '', (v) => c.weldParams = {...c.weldParams, 'a': v}),
        _toggle('Çevre kaynağı', p['around'] == '1', (v) => c.update(() => c.weldParams = {...p, 'around': v ? '1' : '0'})),
        _toggle('Saha kaynağı', p['field'] == '1', (v) => c.update(() => c.weldParams = {...p, 'field': v ? '1' : '0'})),
      ];
    case ToolKind.cone:
      return [
        _colorDots([0xFFFF6D00, 0xFFFFD600, 0xFF2962FF, 0xFFD50000, 0xFF00C853], c.coneColor, (v) => c.update(() => c.coneColor = v)),
        _chips([0.0, 2.0, 3.0, 4.0, 5.0, 6.0], c.coneSpacingM, (v) => v == 0 ? 'Tek koni' : 'Dizi ${formatNumber(v)} m', (v) => c.update(() => c.coneSpacingM = v)),
        Text('${c.coneCount} koni', style: Theme.of(context).textTheme.labelLarge),
      ];
    case ToolKind.lane:
      return [
        _chips([1.5, 2.5, 3.5], c.laneWidthM, (v) => '${formatNumber(v)} m', (v) => c.update(() => c.laneWidthM = v)),
        Text('Merkez çizgisini çiz', style: Theme.of(context).textTheme.bodySmall),
      ];
    case ToolKind.road:
      return [
        _chips([1, 2, 3, 4], c.roadLanes, (v) => '$v şerit', (v) => c.update(() => c.roadLanes = v)),
        Text('3,5 m şerit · merkez çizgisini çiz', style: Theme.of(context).textTheme.bodySmall),
      ];
    case ToolKind.route:
      return [Text('Sürüş hattını çiz; uca ok eklenir', style: Theme.of(context).textTheme.bodySmall)];
    case ToolKind.motorcycle:
      return [Text('Dokun ve yön ver (sürükle)', style: Theme.of(context).textTheme.bodySmall)];
    case ToolKind.gate:
      return [
        _chips([true, false], c.gateIsStart, (v) => v ? 'START' : 'FİNİŞ', (v) => c.update(() => c.gateIsStart = v)),
        Text('Kapı genişliği kadar sürükle', style: Theme.of(context).textTheme.bodySmall),
      ];
    case ToolKind.north:
    case ToolKind.pan:
      return const [];
  }
}
