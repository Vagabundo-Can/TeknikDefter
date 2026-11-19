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

  NotePage createPage({required String notebookId, required PageMode mode, required PageTemplate template, String? title}) {
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
      order: siblings.isEmpty ? 0 : siblings.last.order + 1,
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

  Future<void> savePageNow(NotePage p) async {
    _saveTimers.remove(p.id)?.cancel();
    final f = _pageFile(p.id);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(p.toJson(includeLocal: true)), flush: true);
    await tmp.rename(f.path); // atomik değiştir
  }

  Future<void> saveNotebooks() async {
    final f = File('${_root.path}/notebooks.json');
    await f.writeAsString(jsonEncode({
      'notebooks': [for (final n in notebooks.values) n.toJson()],
      'local': {'dirty': notebooksDirty, 'syncV': notebooksSyncV, 'fid': notebooksFileId},
    }));
  }

  Future<void> flush() async {
    for (final id in _saveTimers.keys.toList()) {
      final p = pages[id];
      if (p != null) await savePageNow(p);
    }
  }

  void notifyExternalChange() => notifyListeners();
}
