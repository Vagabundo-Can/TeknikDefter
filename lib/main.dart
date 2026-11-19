import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'recognition/handwriting.dart';
import 'storage/local_store.dart';
import 'sync/drive_sync.dart';
import 'sync/google_auth.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = LocalStore();
  await store.init();
  final sync = SyncController(store, GoogleAuth.create());
  runApp(TeknikDefterApp(store: store, sync: sync, recognizer: HandwritingRecognizer.create()));
  // giriş + ilk senkron arka planda
  sync.start();
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
        title: 'Teknik Defter',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true, brightness: Brightness.light),
        darkTheme: ThemeData(colorSchemeSeed: seed, useMaterial3: true, brightness: Brightness.dark),
        home: const HomeScreen(),
      ),
    );
  }
}
