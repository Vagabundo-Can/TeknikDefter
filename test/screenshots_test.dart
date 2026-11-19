// Kılavuz ekran görüntüleri. Yalnızca SCREENSHOTS=1 ile çalışır:
//   SCREENSHOTS=1 flutter test test/screenshots_test.dart
// Çıktı: screenshots/*.png

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:teknik_defter/canvas/tools.dart';
import 'package:teknik_defter/recognition/handwriting.dart';
import 'package:teknik_defter/storage/local_store.dart';
import 'package:teknik_defter/sync/drive_sync.dart';
import 'package:teknik_defter/sync/google_auth.dart';
import 'package:teknik_defter/ui/editor_screen.dart';
import 'package:teknik_defter/ui/home_screen.dart';
import 'package:teknik_defter/ui/layout.dart';

import 'sample_data.dart';

class _FakeAuth implements GoogleAuth {
  @override
  bool get configured => true;
  @override
  String? get email => 'umut@gmail.com';
  @override
  Future<http.Client?> signIn() async => null;
  @override
  Future<http.Client?> signInSilently() async => null;
  @override
  Future<void> signOut() async {}
}

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  final roboto = FontLoader('Roboto');
  for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Italic.ttf', 'Roboto-Light.ttf']) {
    final file = File('${dir.path}/$f');
    if (file.existsSync()) roboto.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons');
  icons.addFont(Future.value(ByteData.sublistView(File('${dir.path}/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
}

void main() {
  final enabled = Platform.environment['SCREENSHOTS'] == '1';
  late LocalStore store;
  late SyncController sync;
  late SampleIds ids;
  final rootKey = GlobalKey();

  setUpAll(() async {
    if (!enabled) return;
    await _loadFonts();
    store = LocalStore();
    await store.init(root: await Directory.systemTemp.createTemp('td'));
    ids = seedSamples(store);
    sync = SyncController(store, _FakeAuth());
    Directory('screenshots').createSync();
  });

  Widget app(Widget home) => RepaintBoundary(
        key: rootKey,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: store),
            ChangeNotifierProvider.value(value: sync),
            Provider<HandwritingRecognizer>.value(value: UnsupportedRecognizer()),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(colorSchemeSeed: const Color(0xFF37474F), useMaterial3: true, fontFamily: 'Roboto'),
            home: home,
          ),
        ),
      );

  Future<void> setSize(WidgetTester t, Size logical, double dpr, FormFactor ff) async {
    t.view.physicalSize = logical * dpr;
    t.view.devicePixelRatio = dpr;
    debugFormFactorOverride = ff;
  }

  Future<void> shot(WidgetTester t, String name, double dpr) async {
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(rootKey));
    await t.runAsync(() async {
      final img = await boundary.toImage(pixelRatio: dpr);
      final bd = await img.toByteData(format: ui.ImageByteFormat.png);
      File('screenshots/$name.png').writeAsBytesSync(bd!.buffer.asUint8List());
    });
  }

  const tablet = Size(1280, 800);
  const phone = Size(412, 915);
  const desktop = Size(1440, 900);

  testWidgets('ekran görüntüleri', (t) async {
    debugDisableShadows = false;
    // --- Tablet ana ekran
    await setSize(t, tablet, 1.5, FormFactor.tablet);
    await t.pumpWidget(app(const HomeScreen()));
    await shot(t, '01_tablet_ana_ekran', 1.5);

    // --- Yeni sayfa sihirbazı
    await t.tap(find.text('Yeni sayfa'));
    await t.pump(const Duration(milliseconds: 400));
    await shot(t, '02_yeni_sayfa_kullanim', 1.5);
    await t.tap(find.text('Motosiklet eğitim').first);
    await t.pump(const Duration(milliseconds: 400));
    await shot(t, '03_yeni_sayfa_sablon_moto', 1.5);
    await t.tap(find.byIcon(Icons.arrow_back));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Mühendislik').last);
    await t.pump(const Duration(milliseconds: 400));
    await shot(t, '04_yeni_sayfa_sablon_muhendislik', 1.5);

    // --- Mühendislik editörü
    Future<void> editor(String name, String pageId, ToolKind tool, Rect view, {Set<String>? sel, Size size = tablet, double dpr = 1.5, FormFactor ff = FormFactor.tablet}) async {
      await setSize(t, size, dpr, ff);
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(app(EditorScreen(key: UniqueKey(), pageId: pageId, initialTool: tool, debugSelection: sel, debugView: view)));
      await shot(t, name, dpr);
    }

    await editor('05_muhendislik_olcu', ids.bracketPage, ToolKind.dimension, const Rect.fromLTWH(15, 40, 180, 135));
    await editor('06_muhendislik_kalem', ids.bracketPage, ToolKind.pen, const Rect.fromLTWH(10, 150, 190, 80));
    await editor('07_secim_metne_cevir', ids.bracketPage, ToolKind.lasso, const Rect.fromLTWH(10, 150, 190, 80), sel: ids.handwriting);
    await editor('08_gdt_araci', ids.bracketPage, ToolKind.gdt, const Rect.fromLTWH(30, 40, 140, 125));
    await editor('09_gymkhana_koni', ids.gymkhanaPage, ToolKind.cone, const Rect.fromLTWH(0, 0, 297, 210));
    await editor('10_gymkhana_serit', ids.gymkhanaPage, ToolKind.lane, const Rect.fromLTWH(0, 0, 297, 210));
    await editor('11_yol_viraj', ids.roadPage, ToolKind.route, const Rect.fromLTWH(0, 0, 210, 297));
    await editor('12_ogrenci_degerlendirme', ids.evalPage, ToolKind.pen, const Rect.fromLTWH(0, 0, 210, 297));

    // --- Telefon
    await setSize(t, phone, 2.625, FormFactor.phone);
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(app(const HomeScreen()));
    await shot(t, '13_telefon_ana_ekran', 2.625);
    await editor('14_telefon_gymkhana', ids.gymkhanaPage, ToolKind.cone, const Rect.fromLTWH(0, 0, 297, 210),
        size: phone, dpr: 2.625, ff: FormFactor.phone);
    await editor('15_telefon_muhendislik', ids.bracketPage, ToolKind.pen, const Rect.fromLTWH(15, 40, 180, 160),
        size: phone, dpr: 2.625, ff: FormFactor.phone);

    // --- Windows
    await editor('16_windows_muhendislik', ids.bracketPage, ToolKind.shape, const Rect.fromLTWH(10, 0, 190, 230),
        size: desktop, dpr: 1.25, ff: FormFactor.desktop);
    await editor('17_windows_gymkhana', ids.gymkhanaPage, ToolKind.route, const Rect.fromLTWH(0, 0, 297, 210),
        size: desktop, dpr: 1.25, ff: FormFactor.desktop);
    await setSize(t, desktop, 1.25, FormFactor.desktop);
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(app(const HomeScreen()));
    await t.tap(find.text('Akıncı Eğitim'));
    await shot(t, '18_windows_ana_ekran', 1.25);

    await t.pumpWidget(const SizedBox());
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
    debugDisableShadows = true;
  }, skip: !enabled);
}
