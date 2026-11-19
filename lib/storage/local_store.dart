// Yerel depolama: uygulama destek klasöründe JSON dosyaları.
//   notebooks.json            defter listesi (+ yerel senkron durumu)
//   pages/<id>.json           sayfa başına bir dosya

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/note_models.dart';
import '../templates/templates.dart';

class LocalStore extends ChangeNotifier {
  late Directory _root;
  final Map<String, Notebook> notebooks = {};
  final Map<String, NotePage> pages = {};
  bool notebooksDirty = false;
  String? notebooksSyncV;
  String? notebooksFileId;
  final Map<String, Timer> _saveTimers = {};

  Future<void> init({Directory? root}) async {
    _root = root ?? Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}teknik_defter');
    await Directory('${_root.path}/pages').create(recursive: true);
    await Directory('${_root.path}/assets').create(recursive: true);
    final nbFile = File('${_root.path}/notebooks.json');
    if (await nbFile.exists()) {
      final j = jsonDecode(await nbFile.readAsString()) as Map<String, dynamic>;
      for (final n in j['notebooks'] as List) {
        final nb = Notebook.fromJson(n as Map<String, dynamic>);
        notebooks[nb.id] = nb;
      }
      final local = j['local'] as Map<String, dynamic>?;
      notebooksDirty = (local?['dirty'] as bool?) ?? false;
      notebooksSyncV = local?['syncV'] as String?;
      notebooksFileId = local?['fid'] as String?;
    }
    await for (final f in Directory('${_root.path}/pages').list()) {
      if (f is File && f.path.endsWith('.json')) {
        try {
          final page = NotePage.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
          pages[page.id] = page;
        } catch (e) {
          debugPrint('Sayfa okunamadı ${f.path}: $e');
        }
      }
    }
    if (notebooks.values.where((n) => !n.deleted).isEmpty) {
      final nb = Notebook(id: newId(), title: 'Genel', color: 0xFF37474F);
      notebooks[nb.id] = nb;
      notebooksDirty = true;
      await saveNotebooks();
    }
    notifyListeners();
  }

  List<Notebook> get activeNotebooks =>
      notebooks.values.where((n) => !n.deleted).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  List<NotePage> pagesOf(String notebookId) =>
      pages.values.where((p) => p.notebookId == notebookId && !p.deleted).toList()..sort((a, b) => a.order.compareTo(b.order));

  Iterable<NotePage> get dirtyPages => pages.values.where((p) => p.dirty);

  List<NotePage> search(String q) {
    final s = q.toLowerCase();
    return pages.values
        .where((p) => !p.deleted && (p.title.toLowerCase().contains(s) || p.recognizedText.toLowerCase().contains(s)))
        .toList();
  }

  Notebook createNotebook(String title, int color) {
    final nb = Notebook(id: newId(), title: title, color: color);
    notebooks[nb.id] = nb;
    notebooksDirty = true;
    saveNotebooks();
    notifyListeners();
    return nb;
  }

  void updateNotebook(Notebook nb) {
    nb.updatedAt = nowMs();
    notebooksDirty = true;
    saveNotebooks();
    notifyListeners();
  }

  // --- Ekler (görsel, ses, PDF sayfası): assets/<id>.<ext>, değişmez dosyalar
  Directory get assetsDir => Directory('${_root.path}/assets');
  File assetFile(String assetId) => File('${assetsDir.path}/$assetId');
  bool hasAsset(String assetId) => assetFile(assetId).existsSync();
  List<String> get localAssetIds =>
      assetsDir.listSync().whereType<File>().map((f) => f.uri.pathSegments.last).where((n) => !n.endsWith('.tmp')).toList();

  Future<String> addAssetBytes(List<int> bytes, String ext) async {
    final id = '${newId()}.${ext.replaceAll('.', '').toLowerCase()}';
    await assetFile(id).writeAsBytes(bytes, flush: true);
    return id;
  }

  Future<String> addAssetFile(File src) async {
    final name = src.uri.pathSegments.last;
    final ext = name.contains('.') ? name.split('.').last : 'bin';
    return addAssetBytes(await src.readAsBytes(), ext);
  }

  NotePage createPage({required String notebookId, required PageMode mode, required PageTemplate template, String? title, double? afterOrder}) {
    final siblings = pagesOf(notebookId);
    final page = NotePage(
      id: newId(),
      notebookId: notebookId,
      title: title ?? '${template.name} ${siblings.length + 1}',
      mode: mode,
      templateId: template.id,
      widthMm: template.widthMm,
      heightMm: template.heightMm,
      scale: template.scale,
      order: afterOrder == null
          ? (siblings.isEmpty ? 0 : siblings.last.order + 1)
          : () {
              final next = siblings.where((p) => p.order > afterOrder).map((p) => p.order).fold<double?>(null, (m, o) => m == null || o < m ? o : m);
              return next == null ? afterOrder + 1 : (afterOrder + next) / 2;
            }(),
      infinite: template.infinite,
    );
    pages[page.id] = page;
    savePageNow(page);
    notifyListeners();
    return page;
  }

  void deletePage(NotePage p) {
    p.deleted = true;
    p.touchMeta();
    savePageNow(p);
    notifyListeners();
  }

  File _pageFile(String id) => File('${_root.path}/pages/$id.json');

  /// Çizim sırasında sık çağrılır: 1,5 s toplayıp yazar
  void savePageDebounced(NotePage p) {
    _saveTimers[p.id]?.cancel();
    _saveTimers[p.id] = Timer(const Duration(milliseconds: 1500), () => savePageNow(p));
  }

  final Map<String, Future<void>> _saveChains = {};
  int _tmpSeq = 0;

  /// Aynı sayfanın kayıtları sıraya girer; her yazım ayrı geçici dosya + atomik değiştirme.
  Future<void> savePageNow(NotePage p) {
    _saveTimers.remove(p.id)?.cancel();
    final json = jsonEncode(p.toJson(includeLocal: true)); // anlık görüntü
    final prev = _saveChains[p.id] ?? Future<void>.value();
    final next = prev.catchError((_) {}).then((_) async {
      final f = _pageFile(p.id);
      final tmp = File('${f.path}.${_tmpSeq++}.tmp');
      try {
        await tmp.writeAsString(json, flush: true);
        await tmp.rename(f.path);
      } catch (e) {
        debugPrint('Sayfa kaydedilemedi ${p.id}: $e');
      }
    });
    _saveChains[p.id] = next;
    return next;
  }

  Future<void> _nbChain = Future<void>.value();
  Future<void> saveNotebooks() {
    final data = jsonEncode({
      'notebooks': [for (final n in notebooks.values) n.toJson()],
      'local': {'dirty': notebooksDirty, 'syncV': notebooksSyncV, 'fid': notebooksFileId},
    });
    _nbChain = _nbChain.catchError((_) {}).then((_) async {
      try {
        await File('${_root.path}/notebooks.json').writeAsString(data, flush: true);
      } catch (e) {
        debugPrint('Defterler kaydedilemedi: $e');
      }
    });
    return _nbChain;
  }


  Future<void> flush() async {
    for (final id in _saveTimers.keys.toList()) {
      final p = pages[id];
      if (p != null) await savePageNow(p);
    }
  }

  void notifyExternalChange() => notifyListeners();
}
