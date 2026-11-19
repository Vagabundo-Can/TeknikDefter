import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'media/asset_images.dart';
import 'models/note_models.dart';
import 'media/export_import.dart';
import 'media/platform_extras.dart';
import 'recognition/handwriting.dart';
import 'storage/local_store.dart';
import 'sync/drive_sync.dart';
import 'sync/google_auth.dart';
import 'ui/editor_screen.dart';
import 'ui/home_screen.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = LocalStore();
  await store.init();
  AssetImages.instance.store = store;
  final sync = SyncController(store, GoogleAuth.create());
  runApp(TeknikDefterApp(store: store, sync: sync, recognizer: HandwritingRecognizer.create()));
  // giriş + ilk senkron arka planda
  sync.start();
  IncomingFiles(store).start(args);
}

/// "Birlikte aç" / "Paylaş" ile gelen dosyalar (Android intent, Windows komut satırı)
class IncomingFiles {
  final LocalStore store;
  IncomingFiles(this.store);
  static const _ch = MethodChannel('teknik_defter/intent');

  Future<void> start(List<String> args) async {
    if (Platform.isAndroid) {
      _ch.setMethodCallHandler((call) async {
        if (call.method == 'filesReceived') await _handle((call.arguments as List).cast<String>());
      });
      try {
        final initial = await _ch.invokeListMethod<String>('initialFiles');
        if (initial != null && initial.isNotEmpty) await _handle(initial);
      } catch (_) {}
    } else if (args.isNotEmpty) {
      await _handle(args.where((a) => File(a).existsSync()).toList());
    }
  }

  Future<void> _handle(List<String> paths) async {
    for (final p in paths) {
      try {
        NotePage? page;
        if (p.startsWith('page:')) {
          page = store.pages[p.substring(5)];
        } else if (p == 'action:new' || p == 'action:call') {
          page = await createQuickNote(store, call: p == 'action:call');
        } else {
          page = await importIncoming(store, p);
        }
        if (page != null) {
          // ilk kare çizilene kadar bekle
          await WidgetsBinding.instance.endOfFrame;
          navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => EditorScreen(pageId: page.id)));
        }
      } catch (e) {
        debugPrint('Gelen dosya açılamadı $p: $e');
      }
    }
  }
}

class TeknikDefterApp extends StatelessWidget {
  final LocalStore store;
  final SyncController sync;
  final HandwritingRecognizer recognizer;
  const TeknikDefterApp({super.key, required this.store, required this.sync, required this.recognizer});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF37474F);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: store),
        ChangeNotifierProvider.value(value: sync),
        Provider.value(value: recognizer),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Teknik Defter',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true, brightness: Brightness.light),
        darkTheme: ThemeData(colorSchemeSeed: seed, useMaterial3: true, brightness: Brightness.dark),
        home: const HomeScreen(),
      ),
    );
  }
}
