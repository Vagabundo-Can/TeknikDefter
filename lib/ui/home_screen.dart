import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../canvas/element_painter.dart';
import '../media/platform_extras.dart';
import '../models/note_models.dart';
import '../storage/local_store.dart';
import '../templates/templates.dart';
import 'context_menu.dart';
import 'editor_screen.dart';
import 'layout.dart';
import 'new_page_wizard.dart';
import 'pen_glyph.dart' show AppLogo;
import 'sync_button.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? notebookId;
  String query = '';
  PageMode? lastMode;

  static const _nbColors = [0xFF37474F, 0xFF1565C0, 0xFF2E7D32, 0xFFEF6C00, 0xFFC62828, 0xFF6A1B9A];

  Future<void> _settings() async {
    var callNotes = await getCallNotes();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Ayarlar'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (Platform.isAndroid)
                SwitchListTile(
                  value: callNotes,
                  title: const Text('Görüşme bitince not hatırlatması'),
                  subtitle: const Text('Telefon görüşmesi bitince "Arama notu al" bildirimi gelir; dokununca tarihli bir arama notu açılır. Telefon durumu ve bildirim izni istenir.'),
                  onChanged: (v) async {
                    await setCallNotes(v);
                    setD(() => callNotes = v);
                  },
                ),
              if (Platform.isAndroid)
                const ListTile(
                  leading: Icon(Icons.widgets_outlined),
                  title: Text('Ana ekran widget\'ı'),
                  subtitle: Text('Ana ekrana uzun bas → Widget\'lar → Teknik Defter: Yeni not · Arama notu · Son sayfa'),
                ),
              const ListTile(
                leading: Icon(Icons.event_outlined),
                title: Text('Takvim'),
                subtitle: Text('Sayfada sağ tık / uzun bas ya da ⋮ menü → Takvime ekle. Etkinlikte nota giden bağlantı bulunur.'),
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat'))],
        ),
      ),
    );
  }

  /// Yeni defter ya da mevcut defteri düzenle (ad + renk)
  Future<void> _editNotebook(LocalStore store, [Notebook? existing]) async {
    final ctrl = TextEditingController(text: existing?.title ?? '');
    var color = existing?.color ?? _nbColors[1];
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(existing == null ? 'Yeni defter' : 'Defteri düzenle'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Ad'),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              for (final c in _nbColors)
                GestureDetector(
                  onTap: () => setD(() => color = c),
                  child: CircleAvatar(
                      radius: 14, backgroundColor: Color(c), child: color == c ? const Icon(Icons.check, size: 16, color: Colors.white) : null),
                ),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(existing == null ? 'Oluştur' : 'Kaydet')),
          ],
        ),
      ),
    );
    if (title == null || title.isEmpty) return;
    if (existing == null) {
      final nb = store.createNotebook(title, color);
      setState(() => notebookId = nb.id);
    } else {
      existing
        ..title = title
        ..color = color;
      store.updateNotebook(existing);
    }
  }

  Future<void> _deleteNotebook(LocalStore store, Notebook nb) async {
    final n = store.pagesOf(nb.id).length;
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text('"${nb.title}" silinsin mi?'),
              content: Text(n == 0 ? 'Defter boş.' : 'İçindeki $n sayfa da tüm cihazlardan silinir.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sil')),
              ],
            ));
    if (ok != true) return;
    for (final p in store.pagesOf(nb.id)) {
      store.deletePage(p);
    }
    nb.deleted = true;
    store.updateNotebook(nb);
  }

  Future<void> _renamePage(LocalStore store, NotePage p) async {
    final c = TextEditingController(text: p.title);
    final t = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Sayfa adı'),
              content: TextField(controller: c, autofocus: true, onSubmitted: (v) => Navigator.pop(ctx, v)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
                FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Kaydet')),
              ],
            ));
    if (t == null || t.trim().isEmpty) return;
    p.title = t.trim();
    p.touchMeta();
    await store.savePageNow(p);
    store.notifyExternalChange();
  }

  Future<void> _movePage(LocalStore store, NotePage p) async {
    final target = await showDialog<Notebook>(
        context: context,
        builder: (ctx) => SimpleDialog(title: const Text('Hangi deftere?'), children: [
              for (final n in store.activeNotebooks.where((n) => n.id != p.notebookId))
                SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, n),
                    child: Row(children: [Icon(Icons.book, color: Color(n.color)), const SizedBox(width: 10), Text(n.title)])),
            ]));
    if (target == null) return;
    final sib = store.pagesOf(target.id);
    p.notebookId = target.id;
    p.order = sib.isEmpty ? 0 : sib.last.order + 1;
    p.touchMeta();
    await store.savePageNow(p);
    store.notifyExternalChange();
  }

  Future<void> _duplicatePage(LocalStore store, NotePage p) async {
    final j = p.toJson();
    j['id'] = newId();
    j['ti'] = '${p.title} (kopya)';
    j['or'] = p.order + 0.5;
    j['mu'] = nowMs();
    final copy = NotePage.fromJson(j)..dirty = true;
    store.pages[copy.id] = copy;
    await store.savePageNow(copy);
    store.notifyExternalChange();
  }

  Future<void> _newPage(LocalStore store, String nbId) async {
    final r = await showNewPageWizard(context, lastMode: lastMode);
    if (r == null || !mounted) return;
    lastMode = r.mode;
    final page = store.createPage(notebookId: nbId, mode: r.mode, template: r.template);
    _open(page);
  }

  void _open(NotePage page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditorScreen(pageId: page.id)));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LocalStore>();
    final nbs = store.activeNotebooks;
    if (notebookId == null || !nbs.any((n) => n.id == notebookId)) {
      notebookId = nbs.isEmpty ? null : nbs.first.id;
    }
    final ff = formFactorOf(context);
    final nb = nbs.where((n) => n.id == notebookId).firstOrNull;
    final pages = query.isEmpty ? (nb == null ? <NotePage>[] : store.pagesOf(nb.id)) : store.search(query);

    final notebookList = ListView(children: [
      const SizedBox(height: 8),
      for (final n in nbs)
        ContextMenuRegion(
          actions: () => [
            MenuAction('Yeniden adlandır / renk', Icons.edit_outlined, () => _editNotebook(store, n)),
            MenuAction('Yeni sayfa', Icons.note_add_outlined, () => _newPage(store, n.id)),
            menuDivider,
            MenuAction('Defteri sil', Icons.delete_outline, () => _deleteNotebook(store, n), destructive: true),
          ],
          child: ListTile(
          leading: Icon(Icons.book, color: Color(n.color)),
          title: Text(n.title),
          trailing: Text('${store.pagesOf(n.id).length}'),
          selected: n.id == notebookId,
          onTap: () {
            setState(() {
              notebookId = n.id;
              query = '';
            });
            if (ff == FormFactor.phone) Navigator.of(context).maybePop();
          },
        )),
      ListTile(leading: const Icon(Icons.add), title: const Text('Yeni defter'), onTap: () => _editNotebook(store)),
    ]);

    final body = Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: SearchBar(
          hintText: 'Başlık veya tanınan el yazısında ara',
          leading: const Icon(Icons.search),
          onChanged: (v) => setState(() => query = v.trim()),
        ),
      ),
      Expanded(
        child: pages.isEmpty
            ? Center(child: Text(query.isEmpty ? 'Bu defterde sayfa yok. + ile başla.' : 'Sonuç yok'))
            : GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: ff == FormFactor.phone ? 180 : 220, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 0.66),
                itemCount: pages.length,
                itemBuilder: (_, i) => ContextMenuRegion(
                  actions: () => [
                    MenuAction('Aç', Icons.open_in_new, () => _open(pages[i])),
                    MenuAction('Yeniden adlandır', Icons.edit_outlined, () => _renamePage(store, pages[i])),
                    MenuAction('Çoğalt', Icons.copy, () => _duplicatePage(store, pages[i])),
                    MenuAction('Başka deftere taşı', Icons.drive_file_move_outline, () => _movePage(store, pages[i])),
                    menuDivider,
                    MenuAction('Sil', Icons.delete_outline, () => store.deletePage(pages[i]), destructive: true),
                  ],
                  child: _PageCard(page: pages[i], onOpen: () => _open(pages[i])),
                ),
              ),
      ),
    ]);

    final appBar = AppBar(
      title: Row(children: [
        const AppLogo(size: 34),
        const SizedBox(width: 10),
        Flexible(
          child: InkWell(
            onTap: nb == null ? null : () => _editNotebook(store, nb),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text(nb?.title ?? 'Teknik Defter', overflow: TextOverflow.ellipsis)),
              if (nb != null) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.edit_outlined, size: 18)),
            ]),
          ),
        ),
      ]),
      actions: [IconButton(tooltip: 'Ayarlar', onPressed: _settings, icon: const Icon(Icons.settings_outlined)), const SyncButton(), const SizedBox(width: 4), const AccountButton(), const SizedBox(width: 8)],
    );
    final fab = nb == null
        ? null
        : FloatingActionButton.extended(onPressed: () => _newPage(store, nb.id), icon: const Icon(Icons.add), label: const Text('Yeni sayfa'));

    if (ff == FormFactor.phone) {
      return Scaffold(appBar: appBar, drawer: Drawer(child: SafeArea(child: notebookList)), body: body, floatingActionButton: fab);
    }
    return Scaffold(
      appBar: appBar,
      floatingActionButton: fab,
      body: Row(children: [
        SizedBox(width: 260, child: Material(color: Theme.of(context).colorScheme.surfaceContainerLow, child: notebookList)),
        const VerticalDivider(width: 1),
        Expanded(child: body),
      ]),
    );
  }
}

class _PageCard extends StatelessWidget {
  final NotePage page;
  final VoidCallback onOpen;
  const _PageCard({required this.page, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return InkWell(
      onTap: onOpen,
      child: Column(children: [
        Expanded(child: Center(child: PageThumbnail(page: page))),
        const SizedBox(height: 6),
        Text(page.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.labelLarge),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(
              switch (page.mode) {
                PageMode.engineering => Icons.architecture,
                PageMode.moto => Icons.two_wheeler,
                PageMode.both => Icons.dashboard_customize_outlined,
              },
              size: 14),
          const SizedBox(width: 4),
          if (page.dirty) const Icon(Icons.cloud_upload_outlined, size: 14),
        ]),
      ]),
    );
  }
}

class PageThumbnail extends StatelessWidget {
  final NotePage page;
  const PageThumbnail({super.key, required this.page});
  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: page.widthMm / page.heightMm,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black26),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: ClipRect(child: CustomPaint(painter: _ThumbPainter(page, page.version))),
      ),
    );
  }
}

class _ThumbPainter extends CustomPainter {
  final NotePage page;
  final int version;
  _ThumbPainter(this.page, this.version);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / page.widthMm);
    templateById(page.templateId).painter(canvas, page);
    for (final e in page.visible) {
      paintElement(canvas, e, page.scale);
    }
  }

  @override
  bool shouldRepaint(covariant _ThumbPainter old) => old.version != version || old.page != page;
}
