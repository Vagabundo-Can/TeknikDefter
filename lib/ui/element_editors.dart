// Seçili elemanı düzenleme pencereleri: ölçü (değer/tolerans, parametrik), şekil (parametreler),
// semboller (GD&T, datum, yüzey, kaynak, döndürme), metin (font, punto, renk, arka plan, liste türü).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../canvas/editor_controller.dart';
import '../canvas/element_painter.dart' show gdtCharacteristics;
import '../canvas/tools.dart';
import '../core/format.dart';
import '../models/note_models.dart';

double? parseNum(String s) => double.tryParse(s.replaceAll(',', '.').replaceAll('+', '').trim());
String fmt(double v, [int d = 3]) => formatNumber(v, maxDecimals: d);

String unitOf(ScaleSpec s) => s.isFree ? '' : (s.unit == 'm' ? 'm' : 'mm');

Widget _swatches(List<int?> colors, int? selected, ValueChanged<int?> onPick) => Wrap(spacing: 6, runSpacing: 6, children: [
      for (final c in colors)
        InkResponse(
          onTap: () => onPick(c),
          radius: 18,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: c == null ? Colors.white : Color(c),
              shape: BoxShape.circle,
              border: Border.all(color: c == selected ? Colors.blueAccent : Colors.black26, width: c == selected ? 3 : 1),
            ),
            child: c == null ? const Icon(Icons.format_color_reset, size: 16) : null,
          ),
        ),
    ]);

const textColors = <int>[0xFF000000, 0xFF1A237E, 0xFF0D47A1, 0xFFC62828, 0xFF2E7D32, 0xFFEF6C00, 0xFF6A1B9A, 0xFF546E7A, 0xFFFFFFFF];
const bgColors = <int?>[null, 0xFFFFF59D, 0xFFC8E6C9, 0xFFBBDEFB, 0xFFFFCDD2, 0xFFE1BEE7, 0xFFFFE0B2, 0xFFECEFF1, 0xFF263238];

// ---------------------------------------------------------------------------
// Metin düzenleyici

Future<TextElement?> showTextEditor(BuildContext context, TextElement t, {required bool isNew}) {
  return showDialog<TextElement>(context: context, builder: (_) => _TextEditor(initial: t, isNew: isNew));
}

class _TextEditor extends StatefulWidget {
  final TextElement initial;
  final bool isNew;
  const _TextEditor({required this.initial, required this.isNew});
  @override
  State<_TextEditor> createState() => _TextEditorState();
}

class _TextEditorState extends State<_TextEditor> {
  late TextElement t = widget.initial;
  late final TextEditingController ctrl;
  late List<bool> checks;

  @override
  void initState() {
    super.initState();
    final ls = t.lines;
    checks = [for (final l in ls) l.startsWith('[x] ')];
    ctrl = TextEditingController(text: ls.map((l) => (l.startsWith('[x] ') || l.startsWith('[ ] ')) ? l.substring(4) : l).join('\n'));
  }

  TextElement _result() {
    final ls = ctrl.text.split('\n');
    final text = t.kind == TextKind.checklist
        ? [for (var i = 0; i < ls.length; i++) '${i < checks.length && checks[i] ? '[x]' : '[ ]'} ${ls[i]}'].join('\n')
        : ctrl.text;
    return t.copyWith(text: text);
  }

  @override
  Widget build(BuildContext context) {
    final preview = TextStyle(
      fontFamily: switch (t.font) { FontKind.sans => null, FontKind.serif => 'serif', FontKind.mono => 'monospace' },
      fontSize: 16,
      fontWeight: t.bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: t.italic ? FontStyle.italic : FontStyle.normal,
      decoration: t.underline ? TextDecoration.underline : null,
      color: Color(t.color) == Colors.white ? Colors.black : Color(t.color),
    );
    return AlertDialog(
      title: Text(widget.isNew ? 'Metin ekle' : 'Metni düzenle'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SegmentedButton<TextKind>(
              segments: const [
                ButtonSegment(value: TextKind.plain, icon: Icon(Icons.notes), label: Text('Metin')),
                ButtonSegment(value: TextKind.box, icon: Icon(Icons.crop_square), label: Text('Kutu')),
                ButtonSegment(value: TextKind.checklist, icon: Icon(Icons.check_box_outlined), label: Text('Onay')),
                ButtonSegment(value: TextKind.bullet, icon: Icon(Icons.format_list_bulleted), label: Text('Liste')),
              ],
              selected: {t.kind},
              onSelectionChanged: (v) => setState(() => t = t.copyWith(kind: v.first)),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: t.background == null ? null : Color(t.background!),
                borderRadius: BorderRadius.circular(6),
              ),
              child: TextField(
                controller: ctrl,
                autofocus: true,
                minLines: 3,
                maxLines: 10,
                style: preview,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: t.kind == TextKind.checklist || t.kind == TextKind.bullet ? 'Her satır bir madde' : 'Metin',
                ),
              ),
            ),
            if (t.kind == TextKind.checklist)
              ListenableBuilder(
                listenable: ctrl,
                builder: (_, __) {
                  final ls = ctrl.text.split('\n');
                  while (checks.length < ls.length) {
                    checks.add(false);
                  }
                  return Column(children: [
                    for (var i = 0; i < ls.length; i++)
                      if (ls[i].trim().isNotEmpty)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: checks[i],
                          title: Text(ls[i]),
                          onChanged: (v) => setState(() => checks[i] = v ?? false),
                        ),
                  ]);
                },
              ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              DropdownButton<FontKind>(
                value: t.font,
                items: const [
                  DropdownMenuItem(value: FontKind.sans, child: Text('Varsayılan')),
                  DropdownMenuItem(value: FontKind.serif, child: Text('Serif', style: TextStyle(fontFamily: 'serif'))),
                  DropdownMenuItem(value: FontKind.mono, child: Text('Mono', style: TextStyle(fontFamily: 'monospace'))),
                ],
                onChanged: (v) => setState(() => t = t.copyWith(font: v)),
              ),
              DropdownButton<double>(
                value: t.size,
                items: [
                  for (final s in {2.5, 3.0, 3.5, 4.0, 5.0, 6.0, 8.0, 10.0, 14.0, t.size}.toList()..sort())
                    DropdownMenuItem(value: s, child: Text('${(s * 2.835).round()} pt')),
                ],
                onChanged: (v) => setState(() => t = t.copyWith(size: v)),
              ),
              IconButton.outlined(
                  isSelected: t.bold, onPressed: () => setState(() => t = t.copyWith(bold: !t.bold)), icon: const Icon(Icons.format_bold)),
              IconButton.outlined(
                  isSelected: t.italic,
                  onPressed: () => setState(() => t = t.copyWith(italic: !t.italic)),
                  icon: const Icon(Icons.format_italic)),
              IconButton.outlined(
                  isSelected: t.underline,
                  onPressed: () => setState(() => t = t.copyWith(underline: !t.underline)),
                  icon: const Icon(Icons.format_underline)),
            ]),
            const SizedBox(height: 12),
            const Text('Metin rengi'),
            const SizedBox(height: 6),
            _swatches(textColors, t.color, (c) => setState(() => t = t.copyWith(color: c))),
            const SizedBox(height: 12),
            const Text('Arka plan'),
            const SizedBox(height: 6),
            _swatches(bgColors, t.background, (c) => setState(() => t = c == null ? t.copyWith(clearBackground: true) : t.copyWith(background: c))),
          ]),
        ),
      ),
      actions: [
        if (!widget.isNew)
          TextButton(
              onPressed: () => Navigator.pop(context, t.copyWith(text: '')),
              child: Text('Sil', style: TextStyle(color: Theme.of(context).colorScheme.error))),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(context, _result()), child: const Text('Tamam')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Parametre girişi (şekil çizerken / düzenlerken)

Future<Map<String, double>?> showParamsDialog(BuildContext context, String title, Map<String, double> values, String unit) {
  final ctrls = {for (final e in values.entries) e.key: TextEditingController(text: fmt(e.value))};
  return showDialog<Map<String, double>>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final e in ctrls.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              controller: e.value,
              autofocus: e.key == ctrls.keys.first,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(
                labelText: e.key,
                suffixText: e.key.contains('°') ? '°' : unit,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        if (ctrls.keys.any((k) => k.contains('Açı')))
          const Text('Açı: 0° = sağa, 90° = yukarı (saat yönü tersi)', style: TextStyle(fontSize: 12)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: () {
            final out = <String, double>{};
            for (final e in ctrls.entries) {
              final v = parseNum(e.value.text);
              if (v != null) out[e.key] = v;
            }
            Navigator.pop(ctx, out);
          },
          child: const Text('Uygula'),
        ),
      ],
    ),
  );
}

Future<String?> askDimensionText(BuildContext context, DimensionElement d) {
  final c = TextEditingController(text: d.textOverride ?? '');
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Ölçü değeri'),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          hintText: switch (d.kind) { DimKind.radius => 'R12', DimKind.diameter => 'Ø20', _ => '85' },
          helperText: 'Ölçeksiz sayfa: değer elle yazılır',
        ),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Boş bırak')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Tamam')),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Eleman düzenleyici (seç → çift dokun)

Future<void> showElementEditor(BuildContext context, EditorController ctrl, NoteElement e) async {
  switch (e) {
    case TextElement t:
      final r = await showTextEditor(context, t, isNew: false);
      if (r != null) r.text.trim().isEmpty ? ctrl.deleteIds([t.id]) : ctrl.replace(r);
    case DimensionElement d:
      await showDialog<void>(context: context, builder: (_) => _DimensionEditor(ctrl: ctrl, dim: d));
    case ShapeElement s:
      final unit = unitOf(ctrl.page.scale);
      final v = await showParamsDialog(context, 'Şekil ölçüleri', ctrl.shapeParams(s), unit);
      if (v != null && v.isNotEmpty) ctrl.applyShapeParams(s, v);
    case SymbolElement s:
      await showDialog<void>(context: context, builder: (_) => _SymbolEditor(ctrl: ctrl, sym: s));
    case LaneElement l:
      final v = await showParamsDialog(context, 'Şerit', {'Genişlik': l.widthReal, 'Şerit sayısı': l.lanes.toDouble()}, 'm');
      if (v != null) {
        final w = v['Genişlik'] ?? l.widthReal;
        ctrl.replace(LaneElement(
            id: l.id,
            updatedAt: nowMs(),
            z: l.z,
            centerline: l.centerline,
            widthPaper: ctrl.paperFromMeters(w),
            widthReal: w,
            lanes: math.max(1, (v['Şerit sayısı'] ?? l.lanes.toDouble()).round()),
            color: l.color));
      }
    case StrokeElement s:
      final c = await showDialog<int>(
          context: context,
          builder: (ctx) => AlertDialog(
                title: const Text('Çizgi rengi'),
                content: _swatches(penPalette, s.style.color, (c) => Navigator.pop(ctx, c)),
              ));
      if (c != null) ctrl.replace(s.withStyle(s.style.copyWith(color: c)));
    default:
      break;
  }
}

class _DimensionEditor extends StatefulWidget {
  final EditorController ctrl;
  final DimensionElement dim;
  const _DimensionEditor({required this.ctrl, required this.dim});
  @override
  State<_DimensionEditor> createState() => _DimensionEditorState();
}

class _DimensionEditorState extends State<_DimensionEditor> {
  late final DimensionElement d = widget.dim;
  late final scale = widget.ctrl.page.scale;
  late final linked = widget.ctrl.linkedShape(d);
  late final double current = d.kind == DimKind.angle ? d.paperValue : (scale.isFree ? 0 : scale.realFromPaper(d.paperValue));
  late final valueC = TextEditingController(text: scale.isFree ? '' : fmt(current));
  late final overrideC = TextEditingController(text: d.textOverride ?? '');
  late final upC = TextEditingController(text: d.tolerance.upper == null ? '' : fmt(d.tolerance.upper!));
  late final loC = TextEditingController(text: d.tolerance.lower == null ? '' : fmt(d.tolerance.lower!));
  late final fitC = TextEditingController(text: d.tolerance.fit ?? '');
  late double h = d.textHeight;

  void _save() {
    final ctrl = widget.ctrl;
    var dim = d.copyWith(
      tolerance: DimTolerance(upper: parseNum(upC.text), lower: parseNum(loC.text), fit: fitC.text.trim().isEmpty ? null : fitC.text.trim()),
      textHeight: h,
      textOverride: overrideC.text.trim(),
      clearOverride: overrideC.text.trim().isEmpty,
    );
    ctrl.replace(dim);
    final v = parseNum(valueC.text);
    if (v != null && !scale.isFree && overrideC.text.trim().isEmpty && (v - current).abs() > 1e-9) {
      final cur = ctrl.page.elements[d.id] as DimensionElement;
      ctrl.applyDimensionValue(cur, v);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final unit = d.kind == DimKind.angle ? '°' : unitOf(scale);
    return AlertDialog(
      title: Text('Ölçü — ${d.kind.label}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!scale.isFree) ...[
              TextField(
                controller: valueC,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Değer',
                  suffixText: unit,
                  border: const OutlineInputBorder(),
                  helperText: linked != null ? 'Bağlı şekil bu ölçüye göre yeniden boyutlanır (parametrik)' : 'Bağlı şekil yok: değer ölçü metni olarak yazılır',
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: overrideC,
              decoration: InputDecoration(
                labelText: scale.isFree ? 'Ölçü metni' : 'Metni elle yaz (boş = otomatik)',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: upC, decoration: const InputDecoration(labelText: 'Üst sapma', border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: loC, decoration: const InputDecoration(labelText: 'Alt sapma', border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: fitC, decoration: const InputDecoration(labelText: 'Geçme (H7)', border: OutlineInputBorder()))),
            ]),
            const SizedBox(height: 12),
            SegmentedButton<double>(
              segments: const [ButtonSegment(value: 2.5, label: Text('h 2,5')), ButtonSegment(value: 3.5, label: Text('h 3,5')), ButtonSegment(value: 5, label: Text('h 5'))],
              selected: {h},
              onSelectionChanged: (v) => setState(() => h = v.first),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () {
              widget.ctrl.deleteIds([d.id]);
              Navigator.pop(context);
            },
            child: Text('Sil', style: TextStyle(color: Theme.of(context).colorScheme.error))),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: _save, child: const Text('Uygula')),
      ],
    );
  }
}

class _SymbolEditor extends StatefulWidget {
  final EditorController ctrl;
  final SymbolElement sym;
  const _SymbolEditor({required this.ctrl, required this.sym});
  @override
  State<_SymbolEditor> createState() => _SymbolEditorState();
}

class _SymbolEditorState extends State<_SymbolEditor> {
  late Map<String, String> p = Map.of(widget.sym.params);
  late double rotDeg = (widget.sym.rotation * 180 / math.pi) % 360;

  Widget _field(String key, String label, {double width = 110}) => SizedBox(
        width: width,
        child: TextFormField(
          initialValue: p[key] ?? '',
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
          onChanged: (v) => p[key] = v,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.sym;
    final title = switch (s.kind) {
      SymbolKind.gdtFrame => 'GD&T çerçevesi',
      SymbolKind.datum => 'Datum',
      SymbolKind.surface => 'Yüzey işareti',
      SymbolKind.weld => 'Kaynak sembolü',
      SymbolKind.cone => 'Koni',
      SymbolKind.motorcycle => 'Motosiklet',
      SymbolKind.startGate || SymbolKind.finishGate => 'Kapı',
      SymbolKind.northArrow => 'Kuzey oku',
    };
    final fields = <Widget>[
      if (s.kind == SymbolKind.gdtFrame) ...[
        DropdownButton<String>(
          value: p['char'],
          items: [for (final e in gdtCharacteristics.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() => p['char'] = v!),
        ),
        FilterChip(label: const Text('Ø'), selected: p['dia'] == '1', onSelected: (v) => setState(() => p['dia'] = v ? '1' : '0')),
        _field('tol', 'Tolerans'),
        DropdownButton<String>(
          value: p['mod'] ?? '',
          items: const [
            DropdownMenuItem(value: '', child: Text('Değiştirici yok')),
            DropdownMenuItem(value: 'M', child: Text('(M) MMC')),
            DropdownMenuItem(value: 'L', child: Text('(L) LMC')),
          ],
          onChanged: (v) => setState(() => p['mod'] = v!),
        ),
        _field('d1', 'Datum 1', width: 80),
        _field('d2', 'Datum 2', width: 80),
        _field('d3', 'Datum 3', width: 80),
      ],
      if (s.kind == SymbolKind.datum) _field('letter', 'Harf', width: 80),
      if (s.kind == SymbolKind.surface) ...[
        DropdownButton<String>(
          value: p['proc'] ?? 'remove',
          items: const [
            DropdownMenuItem(value: 'any', child: Text('Serbest')),
            DropdownMenuItem(value: 'remove', child: Text('Talaşlı')),
            DropdownMenuItem(value: 'keep', child: Text('Talaşsız')),
          ],
          onChanged: (v) => setState(() => p['proc'] = v!),
        ),
        _field('ra', 'Ra (µm)'),
      ],
      if (s.kind == SymbolKind.weld) ...[
        DropdownButton<String>(
          value: p['wt'] ?? 'fillet',
          items: const [
            DropdownMenuItem(value: 'fillet', child: Text('Köşe')),
            DropdownMenuItem(value: 'v', child: Text('V')),
            DropdownMenuItem(value: 'square', child: Text('I (alın)')),
          ],
          onChanged: (v) => setState(() => p['wt'] = v!),
        ),
        _field('a', 'a / s'),
        FilterChip(label: const Text('Çevre'), selected: p['around'] == '1', onSelected: (v) => setState(() => p['around'] = v ? '1' : '0')),
        FilterChip(label: const Text('Saha'), selected: p['field'] == '1', onSelected: (v) => setState(() => p['field'] = v ? '1' : '0')),
      ],
      if (s.kind == SymbolKind.startGate || s.kind == SymbolKind.finishGate) _field('label', 'Etiket'),
    ];
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: fields),
          const SizedBox(height: 12),
          Text('Döndür: ${rotDeg.round()}°'),
          Slider(value: rotDeg, min: 0, max: 359, divisions: 72, onChanged: (v) => setState(() => rotDeg = v)),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () {
              widget.ctrl.deleteIds([s.id]);
              Navigator.pop(context);
            },
            child: Text('Sil', style: TextStyle(color: Theme.of(context).colorScheme.error))),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: () {
            widget.ctrl.replace(s.copyWith(params: p, rotation: rotDeg * math.pi / 180));
            Navigator.pop(context);
          },
          child: const Text('Uygula'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Ölçü tuş takımı: ölçü konunca açılır; değer yaz → bağlı şekil boyutlanır, ya da ölçülen değerle devam et.

Future<String?> showDimNumpad(BuildContext context, DimensionElement d, ScaleSpec scale) {
  final measured = d.kind == DimKind.angle ? d.paperValue : (scale.isFree ? null : scale.realFromPaper(d.paperValue));
  return showDialog<String>(context: context, builder: (_) => _Numpad(dim: d, measured: measured, scale: scale));
}

class _Numpad extends StatefulWidget {
  final DimensionElement dim;
  final double? measured;
  final ScaleSpec scale;
  const _Numpad({required this.dim, required this.measured, required this.scale});
  @override
  State<_Numpad> createState() => _NumpadState();
}

class _NumpadState extends State<_Numpad> {
  late final TextEditingController c = TextEditingController(text: widget.measured == null ? '' : fmt(widget.measured!, 2));
  bool fresh = true; // ilk tuş eski değeri siler

  void _key(String k) {
    setState(() {
      var t = fresh ? '' : c.text;
      fresh = false;
      switch (k) {
        case '⌫':
          if (t.isNotEmpty) t = t.substring(0, t.length - 1);
        case 'C':
          t = '';
        case ',':
          if (!t.contains(',')) t = t.isEmpty ? '0,' : '$t,';
        default:
          t += k;
      }
      c.text = t;
      c.selection = TextSelection.collapsed(offset: t.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.dim;
    final unit = d.kind == DimKind.angle ? '°' : unitOf(widget.scale);
    final prefix = switch (d.kind) { DimKind.radius => 'R', DimKind.diameter => 'Ø', _ => '' };
    Widget key(String k, {Color? color, int flex = 1}) => Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: SizedBox(
              height: 52,
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(backgroundColor: color, padding: EdgeInsets.zero),
                onPressed: () => _key(k),
                child: k == '⌫' ? const Icon(Icons.backspace_outlined) : Text(k, style: const TextStyle(fontSize: 22)),
              ),
            ),
          ),
        );
    final keyboard = Theme.of(context).platform == TargetPlatform.windows;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      title: Text('${d.kind.label} ölçüsü'),
      content: SizedBox(
        width: 300,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: c,
            autofocus: keyboard,
            readOnly: !keyboard,
            showCursor: true,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              prefixText: prefix,
              suffixText: unit,
              border: const OutlineInputBorder(),
              helperText: widget.measured == null ? 'Ölçeksiz: değeri yaz' : 'Çizimden ölçülen: $prefix${fmt(widget.measured!, 2)} $unit',
            ),
            onTap: () => fresh = false,
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
          const SizedBox(height: 8),
          for (final row in const [
            ['7', '8', '9'],
            ['4', '5', '6'],
            ['1', '2', '3'],
          ])
            Row(children: [for (final k in row) key(k)]),
          Row(children: [key(','), key('0'), key('⌫')]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(widget.measured == null ? 'Boş bırak' : 'Ölçülenle devam')),
        FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Uygula')),
      ],
    );
  }
}
