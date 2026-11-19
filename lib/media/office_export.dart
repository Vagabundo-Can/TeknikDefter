// Word (.docx) ve PowerPoint (.pptx) dışa aktarma. Her sayfa yüksek çözünürlüklü görsel olarak eklenir;
// sayfadaki metin, onay listesi ve madde öğeleri Word'de ayrıca düzenlenebilir paragraf olarak yer alır.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

import '../models/note_models.dart';
import 'export_import.dart';

part 'office_templates.dart';

String _x(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

const _emuPerMm = 36000;

Future<List<int>> _pagePng(NotePage p) async {
  final img = await renderPageRegion(p, exportRegion(p), pxPerMm: 6);
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return bd!.buffer.asUint8List();
}

void _add(Archive a, String name, List<int> bytes) => a.addFile(ArchiveFile(name, bytes.length, bytes));
void _addStr(Archive a, String name, String s) => _add(a, name, utf8.encode(s));

Future<File> _write(Archive a, String title, String ext) async {
  // ignore: unnecessary_nullable_for_final_variable_declarations
  final List<int>? bytes = ZipEncoder().encode(a);
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/${safeName(title)}.$ext');
  await f.writeAsBytes(bytes!);
  return f;
}

Future<File> exportDocx(List<NotePage> pages, String title) async {
  final a = Archive();
  _addStr(a, '[Content_Types].xml', _ct_docx);
  _addStr(a, '_rels/.rels', _rels_root_docx);
  _addStr(a, 'docProps/core.xml', _core.replaceAll('__TITLE__', _x(title)));
  _addStr(a, 'word/styles.xml', _styles);
  final rels = StringBuffer(_doc_rels_head);
  final body = StringBuffer(_doc_head);
  for (var i = 0; i < pages.length; i++) {
    final p = pages[i];
    final n = i + 1;
    final png = await _pagePng(p);
    _add(a, 'word/media/p$n.png', png);
    rels.write(_doc_rel_img.replaceAll('__RID__', 'rIdImg$n').replaceAll('__FILE__', 'p$n.png'));
    if (i > 0) body.write(_doc_break);
    body.write(_doc_heading.replaceAll('__TEXT__', _x(p.title)));
    final r = exportRegion(p);
    var cx = 190 * _emuPerMm;
    var cy = (cx * r.height / r.width).round();
    if (cy > 255 * _emuPerMm) {
      cy = 255 * _emuPerMm;
      cx = (cy * r.width / r.height).round();
    }
    body.write(_doc_img.replaceAll('__CX__', '$cx').replaceAll('__CY__', '$cy').replaceAll('__ID__', '$n').replaceAll('__RID__', 'rIdImg$n'));
    // sayfadaki metinler (yukarıdan aşağı)
    final texts = p.visible.whereType<TextElement>().toList()..sort((a, b) => a.pos.dy.compareTo(b.pos.dy));
    for (final t in texts) {
      for (final line in t.lines) {
        if (line.trim().isEmpty) continue;
        if (t.kind == TextKind.checklist && (line.startsWith('[x] ') || line.startsWith('[ ] '))) {
          body.write(_doc_check.replaceAll('__BOX__', line.startsWith('[x]') ? '☑' : '☐').replaceAll('__TEXT__', _x(line.substring(4))));
        } else if (t.kind == TextKind.bullet) {
          body.write(_doc_para.replaceAll('__TEXT__', '• ${_x(line)}'));
        } else {
          body.write(_doc_para.replaceAll('__TEXT__', _x(line)));
        }
      }
    }
  }
  rels.write(_rels_tail);
  body.write(_doc_tail);
  _addStr(a, 'word/_rels/document.xml.rels', rels.toString());
  _addStr(a, 'word/document.xml', body.toString());
  return _write(a, title, 'docx');
}

Future<File> exportPptx(List<NotePage> pages, String title) async {
  final a = Archive();
  // slayt boyutu ilk sayfanın yönüne göre: A4 yatay ya da dikey
  final first = exportRegion(pages.first);
  final landscape = first.width >= first.height;
  final sw = (landscape ? 297 : 210) * _emuPerMm, sh = (landscape ? 210 : 297) * _emuPerMm;
  final ct = StringBuffer(_ct_pptx_head);
  final pres = StringBuffer(_pres_head);
  final prels = StringBuffer(_pres_rels_head);
  for (var i = 0; i < pages.length; i++) {
    final n = i + 1;
    final p = pages[i];
    ct.write(_ct_pptx_slide.replaceAll('__N__', '$n'));
    pres.write(_pres_sld.replaceAll('__SID__', '${255 + n}').replaceAll('__N__', '$n'));
    prels.write(_pres_rel_slide.replaceAll('__N__', '$n'));
    final r = exportRegion(p);
    final s = math.min(sw / r.width, sh / r.height);
    final cx = (r.width * s).round(), cy = (r.height * s).round();
    _add(a, 'ppt/media/slide$n.png', await _pagePng(p));
    _addStr(
        a,
        'ppt/slides/slide$n.xml',
        _slide
            .replaceAll('__NAME__', _x(p.title))
            .replaceAll('__X__', '${(sw - cx) ~/ 2}')
            .replaceAll('__Y__', '${(sh - cy) ~/ 2}')
            .replaceAll('__CX__', '$cx')
            .replaceAll('__CY__', '$cy'));
    _addStr(a, 'ppt/slides/_rels/slide$n.xml.rels', _slide_rels.replaceAll('__N__', '$n'));
  }
  ct.write(_ct_tail);
  pres.write(_pres_tail.replaceAll('__CX__', '$sw').replaceAll('__CY__', '$sh'));
  prels.write(_rels_tail);
  _addStr(a, '[Content_Types].xml', ct.toString());
  _addStr(a, '_rels/.rels', _rels_root_pptx);
  _addStr(a, 'docProps/core.xml', _core.replaceAll('__TITLE__', _x(title)));
  _addStr(a, 'ppt/presentation.xml', pres.toString());
  _addStr(a, 'ppt/_rels/presentation.xml.rels', prels.toString());
  _addStr(a, 'ppt/slideMasters/slideMaster1.xml', _master);
  _addStr(a, 'ppt/slideMasters/_rels/slideMaster1.xml.rels', _master_rels);
  _addStr(a, 'ppt/slideLayouts/slideLayout1.xml', _layout);
  _addStr(a, 'ppt/slideLayouts/_rels/slideLayout1.xml.rels', _layout_rels);
  _addStr(a, 'ppt/theme/theme1.xml', _theme);
  return _write(a, title, 'pptx');
}
