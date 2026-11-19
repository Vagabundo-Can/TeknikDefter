// Dışa aktarma (PDF / PNG), paylaşma, PDF ve görsel içe aktarma.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';

import '../canvas/element_painter.dart';
import '../models/note_models.dart';
import '../storage/local_store.dart';
import '../templates/templates.dart';
import 'asset_images.dart';

enum PaperFit { original, a4, a3 }

/// Sayfanın bir bölgesini (mm) görüntüye çiz
Future<ui.Image> renderPageRegion(NotePage page, Rect region, {double pxPerMm = 6}) async {
  await AssetImages.instance.preload(page.visible.whereType<ImageElement>().map((e) => e.assetId));
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.scale(pxPerMm);
  c.translate(-region.left, -region.top);
  c.drawRect(region, Paint()..color = Colors.white);
  if (!page.infinite) {
    c.save();
    c.clipRect(Rect.fromLTWH(0, 0, page.widthMm, page.heightMm));
    templateById(page.templateId).painter(c, page);
    c.restore();
  }
  for (final e in page.visible) {
    paintElement(c, e, page.scale);
  }
  final pic = rec.endRecording();
  final img = await pic.toImage((region.width * pxPerMm).round(), (region.height * pxPerMm).round());
  pic.dispose();
  return img;
}

Rect exportRegion(NotePage page) {
  if (!page.infinite) return Rect.fromLTWH(0, 0, page.widthMm, page.heightMm);
  final v = page.visible;
  if (v.isEmpty) return const Rect.fromLTWH(0, 0, 210, 297);
  return v.map((e) => e.bounds).reduce((a, b) => a.expandToInclude(b)).inflate(10);
}

Future<List<int>> _png(ui.Image img) async => (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();

String safeName(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

Future<File> exportPdf(List<NotePage> pages, String title, {PaperFit fit = PaperFit.original}) async {
  final doc = pw.Document(title: title, creator: 'Teknik Defter');
  for (final p in pages) {
    final region = exportRegion(p);
    final img = await renderPageRegion(p, region, pxPerMm: 7); // ~180 dpi
    final bytes = await _png(img);
    img.dispose();
    final landscape = region.width > region.height;
    final format = switch (fit) {
      PaperFit.original => pdf.PdfPageFormat(region.width * pdf.PdfPageFormat.mm, region.height * pdf.PdfPageFormat.mm),
      PaperFit.a4 => landscape ? pdf.PdfPageFormat.a4.landscape : pdf.PdfPageFormat.a4,
      PaperFit.a3 => landscape ? pdf.PdfPageFormat.a3.landscape : pdf.PdfPageFormat.a3,
    };
    final image = pw.MemoryImage(_u8(bytes));
    doc.addPage(pw.Page(
      pageFormat: format,
      margin: fit == PaperFit.original ? pw.EdgeInsets.zero : const pw.EdgeInsets.all(8 * pdf.PdfPageFormat.mm),
      build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
    ));
  }
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/${safeName(title)}.pdf');
  await f.writeAsBytes(await doc.save());
  return f;
}

Future<File> exportPng(NotePage page) async {
  final img = await renderPageRegion(page, exportRegion(page), pxPerMm: 8);
  final bytes = await _png(img);
  img.dispose();
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/${safeName(page.title)}.png');
  await f.writeAsBytes(bytes);
  return f;
}

/// Android: paylaşım menüsü (WhatsApp, Gmail…). Windows: "Farklı kaydet".
Future<String?> shareOrSave(File f, String subject) async {
  if (Platform.isAndroid || Platform.isIOS) {
    await Share.shareXFiles([XFile(f.path)], subject: subject, text: subject);
    return null;
  }
  final name = f.uri.pathSegments.last;
  final target = await FilePicker.platform.saveFile(dialogTitle: 'Kaydet', fileName: name);
  if (target == null) return null;
  await f.copy(target);
  return target;
}

Uint8List _u8(List<int> b) => b is Uint8List ? b : Uint8List.fromList(b);

// ---------------------------------------------------------------------------
// İçe aktarma

const _mm = 25.4 / 72; // pt → mm

/// PDF'nin her sayfasını not sayfasına çevirir (arka plan görseli kilitli). Dönüş: oluşan sayfalar.
Future<List<NotePage>> importPdf(LocalStore store, String path, String notebookId, {double? afterOrder, void Function(int done, int total)? progress}) async {
  await pdfrxFlutterInitialize();
  final doc = await PdfDocument.openFile(path);
  final out = <NotePage>[];
  final base = File(path).uri.pathSegments.last.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
  var order = afterOrder;
  try {
    final total = doc.pages.length;
    for (var i = 0; i < total; i++) {
      final pg = doc.pages[i];
      final wMm = pg.width * _mm, hMm = pg.height * _mm;
      const scale = 200 / 72; // 200 dpi
      final w = (pg.width * scale).round(), h = (pg.height * scale).round();
      final rendered = await pg.render(fullWidth: w.toDouble(), fullHeight: h.toDouble(), width: w, height: h, backgroundColor: 0xFFFFFFFF);
      if (rendered == null) continue;
      final img = await rendered.createImage();
      final bytes = await _png(img);
      img.dispose();
      rendered.dispose();
      final assetId = await store.addAssetBytes(bytes, 'png');
      final page = store.createPage(
          notebookId: notebookId,
          mode: PageMode.both,
          template: templateById('blank'),
          title: total > 1 ? '$base · ${i + 1}' : base,
          afterOrder: order);
      order = page.order;
      page.widthMm = wMm;
      page.heightMm = hMm;
      page.put(ImageElement(id: newId(), updatedAt: nowMs(), z: -1e12, assetId: assetId, rect: Rect.fromLTWH(0, 0, wMm, hMm), locked: true));
      await store.savePageNow(page);
      out.add(page);
      progress?.call(i + 1, total);
    }
  } finally {
    await doc.dispose();
  }
  store.notifyExternalChange();
  return out;
}

/// Görsel dosyasını eke çevir; dönüş: (assetId, genişlik px, yükseklik px)
Future<(String, int, int)> importImageFile(LocalStore store, File f) async {
  final id = await store.addAssetFile(f);
  final img = await AssetImages.instance.load(id);
  return (id, img?.width ?? 1000, img?.height ?? 750);
}

/// Dışarıdan gelen dosya ("Birlikte aç" / "Paylaş"): PDF → sayfalar, görsel → yeni sayfa. Dönüş: açılacak sayfa.
Future<NotePage?> importIncoming(LocalStore store, String path) async {
  final lower = path.toLowerCase();
  var nb = store.activeNotebooks.where((n) => n.title == 'Gelenler').firstOrNull;
  nb ??= store.createNotebook('Gelenler', 0xFF00897B);
  if (lower.endsWith('.pdf')) {
    final pages = await importPdf(store, path, nb.id);
    return pages.firstOrNull;
  }
  if (RegExp(r'\.(png|jpe?g|webp|gif|bmp|heic)$').hasMatch(lower)) {
    final (id, w, h) = await importImageFile(store, File(path));
    final page = store.createPage(notebookId: nb.id, mode: PageMode.both, template: templateById('blank'), title: File(path).uri.pathSegments.last);
    const wMm = 190.0;
    final hMm = wMm * h / math.max(1, w);
    page.put(ImageElement(id: newId(), updatedAt: nowMs(), z: newZ(), assetId: id, rect: Rect.fromLTWH(10, 10, wMm, hMm)));
    await store.savePageNow(page);
    return page;
  }
  return null;
}
