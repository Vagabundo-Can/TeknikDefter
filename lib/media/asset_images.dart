// Görsel eklerin çözülmüş hali (ui.Image) için önbellek. Tuval yüklenince yeniden çizilir.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../storage/local_store.dart';

class AssetImages extends ChangeNotifier {
  AssetImages._();
  static final instance = AssetImages._();

  LocalStore? store;
  final Map<String, ui.Image> _images = {};
  final Set<String> _loading = {};
  int version = 0;

  ui.Image? get(String assetId) {
    final img = _images[assetId];
    if (img == null) load(assetId);
    return img;
  }

  Future<ui.Image?> load(String assetId) async {
    if (_images.containsKey(assetId)) return _images[assetId];
    final s = store;
    if (s == null || _loading.contains(assetId) || !s.hasAsset(assetId)) return null;
    _loading.add(assetId);
    try {
      final bytes = await s.assetFile(assetId).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      _images[assetId] = frame.image;
      version++;
      notifyListeners();
      return frame.image;
    } catch (e) {
      debugPrint('Görsel açılamadı $assetId: $e');
      return null;
    } finally {
      _loading.remove(assetId);
    }
  }

  Future<void> preload(Iterable<String> ids) async {
    for (final id in ids) {
      await load(id);
    }
  }
}
