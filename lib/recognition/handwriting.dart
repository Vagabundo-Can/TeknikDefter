// El yazısı -> metin.
// Android: Google ML Kit Digital Ink (cihaz üstü, 'tr' modeli ilk kullanımda ~20 MB indirilir).
// Windows: Faz 2 — Windows.UI.Input.Inking.InkRecognizerContainer için C++/WinRT eklentisi (kanal: teknik_defter/ink).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart' as mlkit;

import '../models/note_models.dart';

abstract class HandwritingRecognizer {
  /// Model hazır değilse indirir. İlerleme/sonuç metni döner.
  Future<void> prepare(String lang);
  Future<bool> isReady(String lang);

  /// En iyi adaylar (en olası ilk)
  Future<List<String>> recognize(List<StrokeElement> strokes, {String lang = 'tr'});

  static HandwritingRecognizer create() {
    if (Platform.isAndroid || Platform.isIOS) return MlKitRecognizer();
    if (Platform.isWindows) return WindowsInkRecognizer();
    return UnsupportedRecognizer();
  }
}

List<StrokeElement> _readingOrder(List<StrokeElement> strokes) {
  final s = List.of(strokes);
  // satırları kabaca ayırıp soldan sağa sırala
  s.sort((a, b) {
    final ay = a.bounds.center.dy, by = b.bounds.center.dy;
    final h = (a.bounds.height + b.bounds.height) / 2;
    if ((ay - by).abs() > h * 0.8) return ay.compareTo(by);
    return a.bounds.left.compareTo(b.bounds.left);
  });
  return s;
}

class MlKitRecognizer implements HandwritingRecognizer {
  final _models = mlkit.DigitalInkRecognizerModelManager();
  final Map<String, mlkit.DigitalInkRecognizer> _recognizers = {};

  @override
  Future<bool> isReady(String lang) => _models.isModelDownloaded(lang);

  @override
  Future<void> prepare(String lang) async {
    if (!await _models.isModelDownloaded(lang)) {
      await _models.downloadModel(lang, isWifiRequired: false);
    }
  }

  @override
  Future<List<String>> recognize(List<StrokeElement> strokes, {String lang = 'tr'}) async {
    await prepare(lang);
    final r = _recognizers.putIfAbsent(lang, () => mlkit.DigitalInkRecognizer(languageCode: lang));
    final ink = mlkit.Ink();
    var tBase = 0;
    for (final s in _readingOrder(strokes)) {
      final st = mlkit.Stroke();
      st.points = [
        // mm -> ~piksel (ML Kit göreli ölçekle çalışır; 10x hassasiyet için yeterli)
        for (final p in s.points) mlkit.StrokePoint(x: p.x * 10, y: p.y * 10, t: tBase + p.t)
      ];
      tBase += (s.points.isEmpty ? 0 : s.points.last.t) + 50;
      ink.strokes.add(st);
    }
    final candidates = await r.recognize(ink);
    return [for (final c in candidates.take(3)) c.text];
  }
}

class WindowsInkRecognizer implements HandwritingRecognizer {
  static const _ch = MethodChannel('teknik_defter/ink');

  @override
  Future<bool> isReady(String lang) async {
    try {
      return (await _ch.invokeMethod<bool>('isReady', {'lang': lang})) ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> prepare(String lang) async {}

  @override
  Future<List<String>> recognize(List<StrokeElement> strokes, {String lang = 'tr'}) async {
    try {
      final data = [
        for (final s in _readingOrder(strokes)) [for (final p in s.points) ...[p.x, p.y]]
      ];
      final res = await _ch.invokeListMethod<String>('recognize', {'lang': lang, 'strokes': data});
      return res ?? const [];
    } on MissingPluginException {
      throw UnsupportedError('Windows el yazısı tanıma Faz 2\'de geliyor. Sayfa Android\'de tanınıp senkronla gelebilir.');
    }
  }
}

class UnsupportedRecognizer implements HandwritingRecognizer {
  @override
  Future<bool> isReady(String lang) async => false;
  @override
  Future<void> prepare(String lang) async {}
  @override
  Future<List<String>> recognize(List<StrokeElement> strokes, {String lang = 'tr'}) =>
      throw UnsupportedError('Bu platformda el yazısı tanıma yok.');
}
