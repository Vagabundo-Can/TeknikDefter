import '../models/note_models.dart';

/// Ölçü değerini teknik resim kuralıyla yazar: gereksiz sıfır yok, ondalık ayırıcı virgül (TS/ISO).
String formatNumber(double v, {int maxDecimals = 2, String decimalSep = ','}) {
  var s = v.toStringAsFixed(maxDecimals);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
  }
  if (s == '-0') s = '0';
  return s.replaceAll('.', decimalSep);
}

String formatTolValue(double v) => '${v >= 0 ? '+' : '−'}${formatNumber(v.abs(), maxDecimals: 3)}';

/// Ölçü metninin ana kısmı (tolerans hariç)
String dimensionMainText(DimensionElement d, ScaleSpec scale) {
  if (d.textOverride != null && d.textOverride!.isNotEmpty) return d.textOverride!;
  if (d.kind == DimKind.angle) return '${formatNumber(d.paperValue, maxDecimals: 1)}°';
  final real = scale.realFromPaper(d.paperValue);
  final decimals = scale.unit == 'm' ? 2 : 2;
  final n = formatNumber(real, maxDecimals: decimals);
  final unitSuffix = scale.unit == 'm' ? ' m' : '';
  return switch (d.kind) {
    DimKind.radius => 'R$n$unitSuffix',
    DimKind.diameter => 'Ø$n$unitSuffix',
    _ => '$n$unitSuffix',
  };
}

/// Simetrik tolerans / geçme eki (tek satır). Asimetrik tolerans ayrıca yığın olarak çizilir.
String dimensionInlineSuffix(DimensionElement d) {
  final t = d.tolerance;
  final parts = <String>[];
  if (t.fit != null && t.fit!.isNotEmpty) parts.add(t.fit!);
  if (t.symmetric) parts.add('±${formatNumber(t.upper!.abs(), maxDecimals: 3)}');
  return parts.isEmpty ? '' : ' ${parts.join(' ')}';
}
