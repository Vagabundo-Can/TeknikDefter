// Google Drive appDataFolder senkronu.
// Her dosyanın appProperties.v alanı içerik sürümüdür (yükleme başına rastgele).
// Yerelde son birleştirilen sürüm (syncV) farklıysa uzak dosya indirilir ve eleman düzeyinde birleştirilir;
// yerel değişiklik varsa (dirty) birleşik sonuç yeni sürümle yüklenir. Saat farkından bağımsızdır.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../models/note_models.dart';
import '../storage/local_store.dart';
import 'google_auth.dart';

const _space = 'appDataFolder';
const _notebooksName = 'notebooks.json';
String _pageName(String id) => 'page_$id.json';

class SyncReport {
  int downloaded = 0, uploaded = 0, merged = 0;
  @override
  String toString() => '$downloaded indirildi · $uploaded yüklendi · $merged birleştirildi';
}

enum SyncState { signedOut, idle, syncing, error }

class SyncController extends ChangeNotifier with WidgetsBindingObserver {
  final LocalStore store;
  final GoogleAuth auth;
  http.Client? _client;
  SyncState state = SyncState.signedOut;
  String? lastError;
  DateTime? lastSync;
  SyncReport? lastReport;
  Timer? _periodic;
  Timer? _debounce;
  bool _running = false;
  bool _again = false;

  SyncController(this.store, this.auth);

  String? get email => auth.email;
  bool get signedIn => _client != null;

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      _client = await auth.signInSilently();
    } catch (_) {}
    if (_client != null) {
      state = SyncState.idle;
      notifyListeners();
      _periodic = Timer.periodic(const Duration(minutes: 5), (_) => syncAll());
      unawaited(syncAll());
    }
  }

  Future<void> signIn() async {
    try {
      _client = await auth.signIn();
      if (_client == null) return;
      state = SyncState.idle;
      lastError = null;
      notifyListeners();
      _periodic ??= Timer.periodic(const Duration(minutes: 5), (_) => syncAll());
      await syncAll();
    } catch (e) {
      state = SyncState.error;
      lastError = '$e';
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await auth.signOut();
    _client = null;
    _periodic?.cancel();
    _periodic = null;
    state = SyncState.signedOut;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(syncAll());
    if (state == AppLifecycleState.paused) unawaited(store.flush().then((_) => syncAll()));
  }

  /// Çizim durduktan 20 s sonra
  void pageChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 20), () => syncAll());
  }

  Future<SyncReport?> syncAll() async {
    final client = _client;
    if (client == null) return null;
    if (_running) {
      _again = true;
      return null;
    }
    _running = true;
    state = SyncState.syncing;
    notifyListeners();
    final report = SyncReport();
    try {
      await store.flush();
      final api = drive.DriveApi(client);
      final remote = await _listAll(api);
      await _syncNotebooks(api, remote[_notebooksName], report);
      await _syncPages(api, remote, report);
      lastSync = DateTime.now();
      lastReport = report;
      lastError = null;
      state = SyncState.idle;
      store.notifyExternalChange();
    } catch (e, st) {
      debugPrint('Senkron hatası: $e\n$st');
      lastError = '$e';
      state = SyncState.error;
    } finally {
      _running = false;
      notifyListeners();
    }
    if (_again) {
      _again = false;
      unawaited(syncAll());
    }
    return report;
  }

  Future<Map<String, drive.File>> _listAll(drive.DriveApi api) async {
    final out = <String, drive.File>{};
    String? token;
    do {
      final list = await api.files.list(
        spaces: _space,
        pageSize: 1000,
        pageToken: token,
        $fields: 'nextPageToken, files(id, name, appProperties)',
      );
      for (final f in list.files ?? const <drive.File>[]) {
        if (f.name != null) out[f.name!] = f;
      }
      token = list.nextPageToken;
    } while (token != null);
    return out;
  }

  Future<Map<String, dynamic>> _download(drive.DriveApi api, String fileId) async {
    final media = await api.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    final bytes = <int>[];
    await for (final chunk in media.stream) {
      bytes.addAll(chunk);
    }
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  /// Yükle; dönüş: (fileId, yeni sürüm)
  Future<(String, String)> _upload(drive.DriveApi api, String name, String? fileId, Map<String, dynamic> json) async {
    final bytes = utf8.encode(jsonEncode(json));
    final v = newId();
    final media = drive.Media(Stream<List<int>>.value(bytes), bytes.length, contentType: 'application/json');
    final meta = drive.File()..appProperties = {'v': v};
    if (fileId == null) {
      meta
        ..name = name
        ..parents = [_space];
      final created = await api.files.create(meta, uploadMedia: media, $fields: 'id');
      return (created.id!, v);
    }
    await api.files.update(meta, fileId, uploadMedia: media, $fields: 'id');
    return (fileId, v);
  }

  Future<void> _syncNotebooks(drive.DriveApi api, drive.File? remote, SyncReport r) async {
    var needUpload = store.notebooksDirty || remote == null;
    if (remote != null) {
      store.notebooksFileId = remote.id;
      final v = remote.appProperties?['v'];
      if (v != store.notebooksSyncV) {
        final j = await _download(api, remote.id!);
        final list = [for (final n in j['notebooks'] as List) Notebook.fromJson(n as Map<String, dynamic>)];
        final localNewer = mergeNotebooks(store.notebooks, list);
        store.notebooksSyncV = v;
        r.downloaded++;
        if (localNewer) {
          needUpload = true;
          r.merged++;
        }
      }
    }
    if (needUpload) {
      final (fid, v) = await _upload(api, _notebooksName, store.notebooksFileId,
          {'notebooks': [for (final n in store.notebooks.values) n.toJson()]});
      store.notebooksFileId = fid;
      store.notebooksSyncV = v;
      r.uploaded++;
    }
    store.notebooksDirty = false;
    await store.saveNotebooks();
  }

  Future<void> _syncPages(drive.DriveApi api, Map<String, drive.File> remote, SyncReport r) async {
    // 1) Uzakta değişenleri indir + birleştir
    for (final entry in remote.entries) {
      if (!entry.key.startsWith('page_')) continue;
      final id = entry.key.substring(5, entry.key.length - 5);
      final f = entry.value;
      final v = f.appProperties?['v'];
      final local = store.pages[id];
      if (local != null && local.syncV == v) {
        local.driveFileId ??= f.id;
        continue;
      }
      final remotePage = NotePage.fromJson(await _download(api, f.id!));
      r.downloaded++;
      if (local == null) {
        remotePage
          ..dirty = false
          ..syncV = v
          ..driveFileId = f.id;
        store.pages[id] = remotePage;
      } else {
        final localNewer = local.mergeFrom(remotePage);
        local
          ..syncV = v
          ..driveFileId = f.id;
        if (localNewer) {
          local.dirty = true;
          r.merged++;
        } else {
          local.dirty = false;
        }
      }
      await store.savePageNow(store.pages[id]!);
    }
    // 2) Yerel değişiklikleri yükle
    for (final p in store.pages.values.toList()) {
      final remoteFile = remote[_pageName(p.id)];
      if (!p.dirty && remoteFile != null) continue;
      p.purgeTombstones();
      final versionAtUpload = p.version;
      final (fid, v) = await _upload(api, _pageName(p.id), p.driveFileId ?? remoteFile?.id, p.toJson());
      p
        ..driveFileId = fid
        ..syncV = v
        ..dirty = p.version != versionAtUpload; // yükleme sırasında çizildiyse tekrar gönderilecek
      r.uploaded++;
      await store.savePageNow(p);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _periodic?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}
