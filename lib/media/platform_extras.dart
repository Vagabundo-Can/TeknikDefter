// Takvim, arama notları, ana ekran widget'ı ve hızlı not oluşturma.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/note_models.dart';
import '../storage/local_store.dart';
import '../templates/templates.dart';

const _ch = MethodChannel('teknik_defter/intent');

String _two(int v) => v.toString().padLeft(2, '0');
String trDate(DateTime d) => '${_two(d.day)}.${_two(d.month)}.${d.year} ${_two(d.hour)}:${_two(d.minute)}';

/// Takvime etkinlik: Android'de takvim uygulaması açılır; Windows'ta .ics dosyası (Outlook / Takvim) açılır.
Future<void> addToCalendar(NotePage page, String title, DateTime start, Duration duration, String notebookTitle) async {
  final link = 'teknikdefter://page/${page.id}';
  final desc = 'Teknik Defter notu: $notebookTitle › ${page.title}\n$link';
  final end = start.add(duration);
  if (Platform.isAndroid) {
    await _ch.invokeMethod('addCalendarEvent', {
      'title': title,
      'description': desc,
      'begin': start.millisecondsSinceEpoch,
      'end': end.millisecondsSinceEpoch,
    });
    return;
  }
  String utc(DateTime d) {
    final u = d.toUtc();
    return '${u.year}${_two(u.month)}${_two(u.day)}T${_two(u.hour)}${_two(u.minute)}${_two(u.second)}Z';
  }

  String esc(String s) => s.replaceAll('\\', '\\\\').replaceAll(',', '\\,').replaceAll(';', '\;').replaceAll('\n', '\\n');
  final ics = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Vagabundo Apps//Teknik Defter//TR',
    'BEGIN:VEVENT',
    'UID:${page.id}-${start.millisecondsSinceEpoch}@teknikdefter',
    'DTSTAMP:${utc(DateTime.now())}',
    'DTSTART:${utc(start)}',
    'DTEND:${utc(end)}',
    'SUMMARY:${esc(title)}',
    'DESCRIPTION:${esc(desc)}',
    'END:VEVENT',
    'END:VCALENDAR',
  ].join('\r\n');
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/etkinlik_${start.millisecondsSinceEpoch}.ics');
  await f.writeAsString(ics);
  await launchUrl(Uri.file(f.path));
}

Future<bool> getCallNotes() async {
  if (!Platform.isAndroid) return false;
  return (await _ch.invokeMethod<bool>('getCallNotes')) ?? false;
}

Future<void> setCallNotes(bool on) async {
  if (Platform.isAndroid) await _ch.invokeMethod('setCallNotes', {'enabled': on});
}

/// Son açılan sayfa (widget'taki "Son sayfa" düğmesi için)
Future<void> rememberLastPage(NotePage p) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('lastPageId', p.id);
  await prefs.setString('lastPageTitle', p.title);
  if (Platform.isAndroid) {
    try {
      await _ch.invokeMethod('refreshWidget');
    } catch (_) {}
  }
}

/// Hızlı not (widget "Yeni not") ya da arama notu (görüşme sonrası bildirim)
Future<NotePage> createQuickNote(LocalStore store, {required bool call}) async {
  final now = DateTime.now();
  Notebook nb;
  if (call) {
    nb = store.activeNotebooks.where((n) => n.title == 'Arama notları').firstOrNull ?? store.createNotebook('Arama notları', 0xFF2E7D32);
  } else {
    final prefs = await SharedPreferences.getInstance();
    final last = store.pages[prefs.getString('lastPageId') ?? ''];
    nb = (last != null ? store.notebooks[last.notebookId] : null) ?? store.activeNotebooks.first;
  }
  final page = store.createPage(
      notebookId: nb.id,
      mode: PageMode.both,
      template: templateById('lined'),
      title: call ? 'Arama notu · ${trDate(now)}' : 'Hızlı not · ${trDate(now)}');
  if (call) {
    page.put(TextElement(id: newId(), updatedAt: nowMs(), z: newZ(), pos: const Offset(30, 14), text: 'Kişi / firma:\nKonu:', size: 4.5, bold: true, color: 0xFF263238));
    page.put(TextElement(
        id: newId(), updatedAt: nowMs(), z: newZ(), pos: const Offset(30, 34), text: '[ ] \n[ ] \n[ ] ', size: 4.5, kind: TextKind.checklist, color: 0xFF263238));
  }
  await store.savePageNow(page);
  return page;
}
