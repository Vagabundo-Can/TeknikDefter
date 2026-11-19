import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../canvas/element_painter.dart';
import '../models/note_models.dart';
import '../storage/local_store.dart';
import '../templates/templates.dart';
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

  Future<void> _newNotebook(LocalStore store) async {
    final ctrl = TextEditingController();
    var color = _nbColors[1];
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Yeni defter'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'Ad')),
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
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Oluştur')),
          ],
        ),
      ),
    );
    if (title != null && title.isNotEmpty) {
      final nb = store.createNotebook(title, color);
      setState(() => notebookId = nb.id);
    }
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
        ListTile(
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
        ),
      ListTile(leading: const Icon(Icons.add), title: const Text('Yeni defter'), onTap: () => _newNotebook(store)),
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
                itemBuilder: (_, i) => _PageCard(page: pages[i], onOpen: () => _open(pages[i]), onDelete: () => store.deletePage(pages[i])),
              ),
      ),
    ]);

    final appBar = AppBar(
      title: Row(children: [const AppLogo(size: 34), const SizedBox(width: 10), Flexible(child: Text(nb?.title ?? 'Teknik Defter', overflow: TextOverflow.ellipsis))]),
      actions: const [SyncButton(), SizedBox(width: 4), AccountButton(), SizedBox(width: 8)],
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
  final VoidCallback onOpen, onDelete;
  const _PageCard({required this.page, required this.onOpen, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return InkWell(
      onTap: onOpen,
      onLongPress: () async {
        final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
                  title: Text('"${page.title}" silinsin mi?'),
                  content: const Text('Sayfa tüm cihazlardan kaldırılır.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sil')),
                  ],
                ));
        if (ok == true) onDelete();
      },
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
