// "Ekle" menüsü (görsel, kamera, ses, PDF) ve "Dışa aktar / Paylaş" penceresi.

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../canvas/editor_controller.dart';
import '../canvas/element_painter.dart' show formatDuration;
import '../media/audio.dart';
import '../media/export_import.dart';
import '../media/office_export.dart';
import '../models/note_models.dart';
import '../storage/local_store.dart';

Future<void> showInsertMenu(BuildContext context, EditorController ctrl, Offset viewCenter, {required void Function(NotePage) openPage}) async {
  final mobile = Platform.isAndroid || Platform.isIOS;
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Wrap(children: [
        ListTile(leading: const Icon(Icons.image_outlined), title: const Text('Görsel (galeri / dosya)'), onTap: () => Navigator.pop(ctx, 'image')),
        if (mobile) ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Kamera'), onTap: () => Navigator.pop(ctx, 'camera')),
        ListTile(leading: const Icon(Icons.mic_none), title: const Text('Ses kaydı'), onTap: () => Navigator.pop(ctx, 'audio')),
        ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('PDF içe aktar (sayfa sayfa, üstüne yazılabilir)'),
            onTap: () => Navigator.pop(ctx, 'pdf')),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return;
  final store = ctrl.store;
  final messenger = ScaffoldMessenger.of(context);
  try {
    switch (choice) {
      case 'image':
        final r = await FilePicker.platform.pickFiles(type: FileType.image);
        final path = r?.files.single.path;
        if (path == null) return;
        final (id, w, h) = await importImageFile(store, File(path));
        ctrl.addImage(id, w, h, viewCenter);
      case 'camera':
        final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2400);
        if (x == null) return;
        final (id, w, h) = await importImageFile(store, File(x.path));
        ctrl.addImage(id, w, h, viewCenter);
      case 'audio':
        if (!context.mounted) return;
        final res = await recordAudio(context, store);
        if (res != null) ctrl.addAudio(res.$1, res.$2, viewCenter);
      case 'pdf':
        final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
        final path = r?.files.single.path;
        if (path == null) return;
        messenger.showSnackBar(const SnackBar(content: Text('PDF sayfaları aktarılıyor…')));
        final pages = await importPdf(store, path, ctrl.page.notebookId, afterOrder: ctrl.page.order);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(content: Text('${pages.length} sayfa eklendi')));
        if (pages.isNotEmpty) openPage(pages.first);
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Eklenemedi: $e')));
  }
}

/// Dönüş: (assetId, süre ms)
Future<(String, int)?> recordAudio(BuildContext context, LocalStore store) async {
  final tmp = await getTemporaryDirectory();
  final path = '${tmp.path}/kayit_${DateTime.now().millisecondsSinceEpoch}.${AudioService.instance.extension}';
  if (!await AudioService.instance.start(path)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mikrofon izni verilmedi')));
    }
    return null;
  }
  final started = DateTime.now();
  if (!context.mounted) return null;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _RecordingDialog(started: started),
  );
  final ms = DateTime.now().difference(started).inMilliseconds;
  if (ok != true) {
    await AudioService.instance.cancel();
    return null;
  }
  final out = await AudioService.instance.stop();
  if (out == null) return null;
  final id = await store.addAssetFile(File(out));
  return (id, ms);
}

class _RecordingDialog extends StatefulWidget {
  final DateTime started;
  const _RecordingDialog({required this.started});
  @override
  State<_RecordingDialog> createState() => _RecordingDialogState();
}

class _RecordingDialogState extends State<_RecordingDialog> {
  late final Timer _t = Timer.periodic(const Duration(milliseconds: 250), (_) => setState(() {}));
  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ms = DateTime.now().difference(widget.started).inMilliseconds;
    return AlertDialog(
      title: const Text('Ses kaydı'),
      content: Row(children: [
        const Icon(Icons.fiber_manual_record, color: Colors.red),
        const SizedBox(width: 12),
        Text(formatDuration(ms), style: Theme.of(context).textTheme.headlineMedium),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        FilledButton.icon(onPressed: () => Navigator.pop(context, true), icon: const Icon(Icons.stop), label: const Text('Durdur ve ekle')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

enum _Fmt { pdf, png, docx, pptx }

Future<void> showExportDialog(BuildContext context, EditorController ctrl) async {
  var allPages = true;
  var fmt = _Fmt.pdf;
  var fit = ctrl.page.infinite ? PaperFit.a4 : PaperFit.original;
  final mobile = Platform.isAndroid || Platform.isIOS;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: const Text('Dışa aktar / Paylaş'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          SegmentedButton<bool>(
            segments: const [ButtonSegment(value: false, label: Text('Bu sayfa')), ButtonSegment(value: true, label: Text('Tüm defter'))],
            selected: {allPages},
            onSelectionChanged: (v) => setD(() {
              allPages = v.first;
              if (allPages && fmt == _Fmt.png) fmt = _Fmt.pdf;
            }),
          ),
          const SizedBox(height: 12),
          SegmentedButton<_Fmt>(
            segments: [
              const ButtonSegment(value: _Fmt.pdf, label: Text('PDF'), icon: Icon(Icons.picture_as_pdf_outlined)),
              ButtonSegment(value: _Fmt.png, label: const Text('PNG'), icon: const Icon(Icons.image_outlined), enabled: !allPages),
              const ButtonSegment(value: _Fmt.docx, label: Text('Word'), icon: Icon(Icons.description_outlined)),
              const ButtonSegment(value: _Fmt.pptx, label: Text('PowerPoint'), icon: Icon(Icons.slideshow_outlined)),
            ],
            selected: {fmt},
            onSelectionChanged: (v) => setD(() => fmt = v.first),
          ),
          if (fmt == _Fmt.pdf) ...[
            const SizedBox(height: 12),
            const Text('Kağıt'),
            const SizedBox(height: 6),
            SegmentedButton<PaperFit>(
              segments: const [
                ButtonSegment(value: PaperFit.original, label: Text('Orijinal')),
                ButtonSegment(value: PaperFit.a4, label: Text('A4')),
                ButtonSegment(value: PaperFit.a3, label: Text('A3')),
              ],
              selected: {fit},
              onSelectionChanged: (v) => setD(() => fit = v.first),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            switch (fmt) {
              _Fmt.docx => 'Her sayfa görsel olarak, sayfadaki metinler ve listeler düzenlenebilir paragraf olarak eklenir.',
              _Fmt.pptx => 'Her sayfa bir slayt (A4 oranında).',
              _ => ctrl.page.infinite ? 'Sonsuz tuval: tüm içerik seçilen kağıda sığdırılır.' : '',
            },
            style: const TextStyle(fontSize: 12),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: Icon(mobile ? Icons.share : Icons.save_alt),
            label: Text(mobile ? 'Paylaş (WhatsApp, Mail…)' : 'Kaydet'),
          ),
        ],
      ),
    ),
  );
  if (go != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Hazırlanıyor…')));
  try {
    final store = ctrl.store;
    final pages = allPages ? store.pagesOf(ctrl.page.notebookId) : [ctrl.page];
    final title = allPages ? (store.notebooks[ctrl.page.notebookId]?.title ?? 'Defter') : ctrl.page.title;
    final f = switch (fmt) {
      _Fmt.png => await exportPng(ctrl.page),
      _Fmt.pdf => await exportPdf(pages, title, fit: fit),
      _Fmt.docx => await exportDocx(pages, title),
      _Fmt.pptx => await exportPptx(pages, title),
    };
    messenger.hideCurrentSnackBar();
    final saved = await shareOrSave(f, title);
    if (saved != null) messenger.showSnackBar(SnackBar(content: Text('Kaydedildi: $saved')));
  } catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text('Dışa aktarılamadı: $e')));
  }
}
