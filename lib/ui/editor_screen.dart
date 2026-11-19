import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../canvas/editor_controller.dart';
import '../canvas/note_canvas.dart';
import '../canvas/tools.dart';
import '../models/note_models.dart';
import '../recognition/handwriting.dart';
import '../storage/local_store.dart';
import '../sync/drive_sync.dart';
import '../media/audio.dart';
import '../templates/templates.dart';
import 'context_menu.dart';
import 'element_editors.dart';
import 'insert_export.dart';
import '../media/platform_extras.dart';
import 'new_page_wizard.dart';
import 'layout.dart';
import 'pen_glyph.dart';
import 'presentation.dart';
import 'sync_button.dart';
import 'tool_options.dart';

class EditorScreen extends StatefulWidget {
  final String pageId;
  final ToolKind? initialTool;
  final Set<String>? debugSelection;
  final Rect? debugView;
  const EditorScreen({super.key, required this.pageId, this.initialTool, this.debugSelection, this.debugView});
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final EditorController ctrl;
  late final LocalStore store;
  final _canvasKey = GlobalKey<NoteCanvasState>();
  final _focus = FocusNode();
  int _lastVersion = -1;

  @override
  void initState() {
    super.initState();
    store = context.read<LocalStore>();
    final sync = context.read<SyncController>();
    final page = store.pages[widget.pageId]!;
    ctrl = EditorController(
      page: page,
      store: store,
      recognizer: context.read<HandwritingRecognizer>(),
      onPageChanged: sync.pageChanged,
    );
    if (widget.initialTool != null) ctrl.tool = widget.initialTool!;
    if (widget.debugSelection != null) ctrl.selection.addAll(widget.debugSelection!);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (formFactorOf(context) == FormFactor.phone) ctrl.update(() => ctrl.stylusOnly = false);
      if (page.mode == PageMode.moto && widget.initialTool == null) ctrl.update(() => ctrl.penType = PenType.ballpoint);
      if (widget.debugView != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _canvasKey.currentState?.zoomToRect(widget.debugView!));
      }
    });
    store.addListener(_onStore);
    _lastVersion = page.version;
    rememberLastPage(page);
  }

  void _onStore() {
    // senkron sayfayı değiştirdiyse tuvali yenile
    if (ctrl.page.version != _lastVersion) {
      _lastVersion = ctrl.page.version;
      ctrl.externalRefresh();
    }
  }

  @override
  void dispose() {
    store.removeListener(_onStore);
    store.savePageNow(ctrl.page);
    ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<String?> _askText(String initial, {String title = 'Metin'}) {
    final t = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: t, autofocus: true, maxLines: null, minLines: 1),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, t.text), child: const Text('Tamam')),
        ],
      ),
    );
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrlDown = HardwareKeyboard.instance.isControlPressed;
    final k = e.logicalKey;
    if (ctrlDown) {
      if (k == LogicalKeyboardKey.keyZ) {
        HardwareKeyboard.instance.isShiftPressed ? ctrl.redo() : ctrl.undo();
      } else if (k == LogicalKeyboardKey.keyY) {
        ctrl.redo();
      } else if (k == LogicalKeyboardKey.keyS) {
        context.read<SyncController>().syncAll();
      } else if (k == LogicalKeyboardKey.digit0) {
        _canvasKey.currentState?.fitPage();
      } else if (k == LogicalKeyboardKey.keyD) {
        ctrl.duplicateSelection();
      } else if (k == LogicalKeyboardKey.keyC) {
        ctrl.copySelection();
      } else if (k == LogicalKeyboardKey.keyX) {
        ctrl.cutSelection();
      } else if (k == LogicalKeyboardKey.keyV) {
        ctrl.paste(at: _viewCenter);
      } else if (k == LogicalKeyboardKey.keyA) {
        ctrl.selectAll();
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    final map = <LogicalKeyboardKey, ToolKind>{
      LogicalKeyboardKey.keyV: ToolKind.select,
      LogicalKeyboardKey.keyP: ToolKind.pen,
      LogicalKeyboardKey.keyH: ToolKind.highlighter,
      LogicalKeyboardKey.keyE: ToolKind.eraser,
      LogicalKeyboardKey.keyL: ToolKind.lasso,
      LogicalKeyboardKey.keyS: ToolKind.shape,
      LogicalKeyboardKey.keyD: ToolKind.dimension,
      LogicalKeyboardKey.keyT: ToolKind.text,
      LogicalKeyboardKey.keyC: ToolKind.cone,
    };
    final tool = map[k];
    if (tool != null && toolsFor(ctrl.page.mode).contains(tool)) {
      ctrl.setTool(tool);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      ctrl.deleteSelection();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      _canvasKey.currentState?.cancelPending();
      ctrl.clearSelection();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _rename() async {
    final t = await _askText(ctrl.page.title, title: 'Sayfa adı');
    if (t != null && t.trim().isNotEmpty) ctrl.rename(t.trim());
  }

  Future<void> _convertToText() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      messenger.showSnackBar(const SnackBar(content: Text('El yazısı tanınıyor… (ilk seferde Türkçe modeli indirilir)')));
      final cands = await ctrl.recognizeSelection();
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      if (cands.isEmpty) {
        messenger.showSnackBar(const SnackBar(content: Text('Metin bulunamadı')));
        return;
      }
      var keepInk = false;
      final chosen = await showDialog<String>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            title: const Text('Metne çevir'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final c in cands)
                ListTile(title: Text(c), onTap: () => Navigator.pop(ctx, c)),
              CheckboxListTile(
                value: keepInk,
                onChanged: (v) => setD(() => keepInk = v ?? false),
                title: const Text('El yazısını da sakla'),
              ),
            ]),
            actions: [
              TextButton(
                  onPressed: () async {
                    final edited = await _askText(cands.first, title: 'Düzenle');
                    if (ctx.mounted) Navigator.pop(ctx, edited);
                  },
                  child: const Text('Düzenle')),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
            ],
          ),
        ),
      );
      if (chosen != null && chosen.isNotEmpty) ctrl.replaceSelectionWithText(chosen, keepInk: keepInk);
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  NoteCanvas _canvas() => NoteCanvas(
        key: _canvasKey,
        controller: ctrl,
        onRequestText: (t, isNew) => showTextEditor(context, t, isNew: isNew),
        onEditElement: (e) => showElementEditor(context, ctrl, e),
        onRequestShapeParams: (k, d) => showParamsDialog(
            context,
            switch (k) { ShapeKind.rect => 'Dikdörtgen', ShapeKind.ellipse => 'Daire', _ => 'Çizgi' },
            d,
            unitOf(ctrl.page.scale)),
        onRequestDimValue: (d) => showDimNumpad(context, d, ctrl.page.scale),
        onContextMenu: _contextMenu,
        onPlayAudio: (a) => AudioService.instance.toggle(a.assetId, store.assetFile(a.assetId).path),
      );

  void _contextMenu(Offset global, Offset p, NoteElement? hit) {
    final inSelection = hit != null && ctrl.selection.contains(hit.id);
    if (hit != null && !inSelection) ctrl.selectOnly(hit.id);
    final hasSel = ctrl.selection.isNotEmpty && (hit != null);
    final single = ctrl.singleSelected;
    final List<MenuAction> actions;
    if (hasSel) {
      final strokes = ctrl.selected.any((e) => e is StrokeElement);
      actions = [
        if (single != null && single is! StrokeElement)
          MenuAction('Düzenle…', Icons.tune, () => showElementEditor(context, ctrl, single)),
        if (single is AudioElement)
          MenuAction('Çal / durdur', Icons.play_arrow, () => AudioService.instance.toggle(single.assetId, store.assetFile(single.assetId).path)),
        if (strokes) MenuAction('Metne çevir', Icons.text_fields, _convertToText),
        if (strokes) MenuAction('Şekle oturt', Icons.auto_fix_high, () => ctrl.beautifySelection()),
        menuDivider,
        MenuAction('Kes', Icons.content_cut, ctrl.cutSelection, shortcut: 'Ctrl+X'),
        MenuAction('Kopyala', Icons.content_copy, ctrl.copySelection, shortcut: 'Ctrl+C'),
        MenuAction('Çoğalt', Icons.copy_all, ctrl.duplicateSelection, shortcut: 'Ctrl+D'),
        menuDivider,
        MenuAction('90° sağa döndür', Icons.rotate_right, () => ctrl.rotateSelection(math.pi / 2)),
        MenuAction('90° sola döndür', Icons.rotate_left, () => ctrl.rotateSelection(-math.pi / 2)),
        MenuAction('Öne getir', Icons.flip_to_front, () => ctrl.bringSelection(front: true)),
        MenuAction('Arkaya gönder', Icons.flip_to_back, () => ctrl.bringSelection(front: false)),
        if (single is ImageElement) MenuAction('Arka plan olarak kilitle', Icons.lock_outline, () => ctrl.toggleImageLock(single)),
        menuDivider,
        MenuAction('Sil', Icons.delete_outline, ctrl.deleteSelection, destructive: true, shortcut: 'Del'),
      ];
    } else {
      ctrl.selectOnly(null);
      final locked = ctrl.page.visible.whereType<ImageElement>().where((i) => i.locked).toList();
      actions = [
        MenuAction('Yapıştır', Icons.content_paste, EditorController.clipboard.isEmpty ? null : () => ctrl.paste(at: p), shortcut: 'Ctrl+V'),
        MenuAction('Tümünü seç', Icons.select_all, ctrl.selectAll, shortcut: 'Ctrl+A'),
        menuDivider,
        MenuAction('Buraya metin', Icons.text_fields, () async {
          final d = ctrl.textDefaults;
          final t = await showTextEditor(
              context,
              TextElement(id: newId(), updatedAt: nowMs(), z: newZ(), pos: p, text: d.kind == TextKind.checklist ? '[ ] ' : '', size: d.size, color: d.color, kind: d.kind),
              isNew: true);
          if (t != null && t.text.replaceAll('[ ]', '').trim().isNotEmpty) ctrl.add(t);
        }),
        MenuAction('Görsel / kamera / ses / PDF ekle…', Icons.add_photo_alternate_outlined,
            () => showInsertMenu(context, ctrl, p, openPage: _openPage)),
        MenuAction('Sayfa ekle', Icons.note_add_outlined, () => _addPage()),
        if (locked.isNotEmpty) menuDivider,
        if (locked.isNotEmpty)
          MenuAction('Arka plan kilidini aç', Icons.lock_open, () {
            for (final i in locked) {
              ctrl.toggleImageLock(i);
            }
          }),
        menuDivider,
        MenuAction('Seç aracı', Icons.near_me_outlined, () => ctrl.setTool(ToolKind.select), shortcut: 'V'),
        MenuAction('Sunum modu', Icons.slideshow_outlined, _present),
        MenuAction('Takvime ekle…', Icons.event_outlined, _addToCalendar),
      ];
    }
    showContextMenuAt(context, global, actions);
  }

  Future<void> _addToCalendar() async {
    final now = DateTime.now();
    final date = await showDatePicker(context: context, initialDate: now, firstDate: now.subtract(const Duration(days: 365)), lastDate: now.add(const Duration(days: 3650)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))));
    if (time == null || !mounted) return;
    final start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    try {
      await addToCalendar(ctrl.page, ctrl.page.title, start, const Duration(hours: 1), store.notebooks[ctrl.page.notebookId]?.title ?? '');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Takvime eklenemedi: $e')));
    }
  }

  void _present() {
    final pages = store.pagesOf(ctrl.page.notebookId);
    final i = pages.indexWhere((p) => p.id == ctrl.page.id);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PresentationScreen(pages: pages, initialIndex: i < 0 ? 0 : i)));
  }

  void _openPage(NotePage p) {
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, __, ___) => EditorScreen(pageId: p.id),
      transitionDuration: const Duration(milliseconds: 150),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  Future<void> _addPage({bool choose = false}) async {
    final page = ctrl.page;
    var mode = page.mode;
    var template = templateById(page.templateId);
    if (choose) {
      final r = await showNewPageWizard(context, lastMode: page.mode);
      if (r == null) return;
      mode = r.mode;
      template = r.template;
    }
    final np = store.createPage(notebookId: page.notebookId, mode: mode, template: template, afterOrder: page.order);
    _openPage(np);
  }

  Offset get _viewCenter => _canvasKey.currentState?.viewCenterMm ?? Offset(ctrl.page.widthMm / 2, ctrl.page.heightMm / 3);

  /// Araç seçimi: aynı araca ikinci dokunuş ayar panelini açar (Samsung Notes gibi)
  void _pickTool(BuildContext anchor, ToolKind t, {PenType? pen}) {
    final same = ctrl.tool == t && (pen == null || ctrl.penType == pen);
    if (pen != null) {
      ctrl.setPenType(pen);
    } else {
      ctrl.setTool(t);
    }
    if (same) _openPanel(anchor, (_) => ToolOptionsPanel(ctrl: ctrl));
  }

  void _openGroup(BuildContext anchor, String title, List<ToolKind> group) {
    _openPanel(anchor, (ctx) {
      final inGroup = group.contains(ctrl.tool);
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(ctx).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final t in group)
            _GroupTile(
              info: toolInfos[t]!,
              selected: ctrl.tool == t,
              onTap: () => ctrl.setTool(t),
            ),
        ]),
        if (inGroup) ...[
          const Divider(height: 24),
          ToolOptionsPanel(ctrl: ctrl),
        ],
      ]);
    });
  }

  void _openPanel(BuildContext anchor, WidgetBuilder builder) {
    if (formFactorOf(context) == FormFactor.phone) {
      showModalBottomSheet(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => ListenableBuilder(
          listenable: ctrl,
          builder: (ctx, _) => SafeArea(
            child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: builder(ctx)),
          ),
        ),
      );
      return;
    }
    final box = anchor.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final rect = box == null ? Rect.zero : box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    final screen = overlay.size;
    const width = 440.0;
    final left = (rect.center.dx - width / 2).clamp(8.0, screen.width - width - 8);
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Kapat',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (ctx, _, __) => Stack(children: [
        Positioned(
          left: left,
          top: rect.bottom + 6,
          width: width,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: screen.height - rect.bottom - 24),
              child: ListenableBuilder(
                listenable: ctrl,
                builder: (ctx, _) => SingleChildScrollView(padding: const EdgeInsets.all(14), child: builder(ctx)),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ff = formFactorOf(context);
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final page = ctrl.page;
        final selectionBar = ctrl.selection.isEmpty ? null : _SelectionBar(ctrl: ctrl, onConvert: _convertToText, onEdit: () {
          final e = ctrl.singleSelected;
          if (e != null) showElementEditor(context, ctrl, e);
        });

        final appBar = AppBar(
          title: InkWell(
            onTap: _rename,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(page.title, overflow: TextOverflow.ellipsis),
              Text(
                [
                  store.notebooks[page.notebookId]?.title ?? '',
                  page.mode.label,
                  'Ölçek ${page.scale.label}',
                  if (page.mode != PageMode.engineering && ctrl.coneCount > 0) '${ctrl.coneCount} koni',
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ]),
          ),
          actions: [
            IconButton(tooltip: 'Geri al (Ctrl+Z)', onPressed: ctrl.canUndo ? ctrl.undo : null, icon: const Icon(Icons.undo)),
            IconButton(tooltip: 'Yinele (Ctrl+Y)', onPressed: ctrl.canRedo ? ctrl.redo : null, icon: const Icon(Icons.redo)),
            IconButton(
              tooltip: ctrl.canvasLocked ? 'Sayfa kilitli: kaydırma/zoom kapalı' : 'Sayfayı kilitle (el ekranı oynatmasın)',
              isSelected: ctrl.canvasLocked,
              onPressed: () => ctrl.update(() => ctrl.canvasLocked = !ctrl.canvasLocked),
              icon: Icon(ctrl.canvasLocked ? Icons.lock : Icons.lock_open_outlined),
            ),
            if (ff != FormFactor.phone)
              IconButton(tooltip: 'Sayfaya sığdır (Ctrl+0)', onPressed: () => _canvasKey.currentState?.fitPage(), icon: const Icon(Icons.fit_screen)),
            IconButton(
                tooltip: 'Ekle: görsel, kamera, ses, PDF',
                onPressed: () => showInsertMenu(context, ctrl, _viewCenter, openPage: _openPage),
                icon: const Icon(Icons.add_photo_alternate_outlined)),
            IconButton(tooltip: 'Dışa aktar / Paylaş', onPressed: () => showExportDialog(context, ctrl), icon: const Icon(Icons.ios_share)),
            if (ff != FormFactor.phone) IconButton(tooltip: 'Sunum modu', onPressed: _present, icon: const Icon(Icons.slideshow_outlined)),
            if (ff != FormFactor.phone) const SyncButton(),
            PageMenu(ctrl: ctrl, onCalendar: _addToCalendar, onPresent: _present),
          ],
        );
        final siblings = store.pagesOf(page.notebookId);
        final idx = siblings.indexWhere((p) => p.id == page.id);
        final pageNav = Material(
          elevation: 3,
          borderRadius: BorderRadius.circular(24),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
                tooltip: 'Önceki sayfa',
                onPressed: idx > 0 ? () => _openPage(siblings[idx - 1]) : null,
                icon: const Icon(Icons.chevron_left)),
            Text('${idx + 1} / ${siblings.length}'),
            IconButton(
                tooltip: 'Sonraki sayfa',
                onPressed: idx >= 0 && idx < siblings.length - 1 ? () => _openPage(siblings[idx + 1]) : null,
                icon: const Icon(Icons.chevron_right)),
            GestureDetector(
              onLongPress: () => _addPage(choose: true),
              child: IconButton(
                  tooltip: 'Sayfa ekle (uzun bas: şablon seç)', onPressed: () => _addPage(), icon: const Icon(Icons.note_add_outlined)),
            ),
          ]),
        );

        final body = Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Stack(children: [
            Positioned.fill(child: _canvas()),
            if (ff != FormFactor.phone) Positioned(left: 0, right: 0, top: 10, child: Center(child: _Toolbar(state: this))),
            if (selectionBar != null) Positioned(left: 8, right: 8, bottom: 68, child: Center(child: selectionBar)),
            Positioned(right: 12, bottom: 12, child: pageNav),
          ]),
        );

        if (ff == FormFactor.phone) {
          return Scaffold(
            appBar: appBar,
            body: body,
            bottomNavigationBar: SafeArea(
              child: Material(elevation: 6, child: SizedBox(height: 62, child: _PhoneBar(state: this))),
            ),
          );
        }
        return Scaffold(appBar: appBar, body: body);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Araç çubuğu (tablet / Windows): Samsung Notes tarzı yüzen çubuk

class _Toolbar extends StatelessWidget {
  final _EditorScreenState state;
  const _Toolbar({required this.state});

  @override
  Widget build(BuildContext context) {
    final ctrl = state.ctrl;
    final mode = ctrl.page.mode;
    final scheme = Theme.of(context).colorScheme;
    Widget tool(ToolKind t) => Builder(
          builder: (b) => _IconTool(
            info: toolInfos[t]!,
            selected: ctrl.tool == t,
            onTap: () => state._pickTool(b, t),
          ),
        );
    Widget pen(PenType p) => Builder(
          builder: (b) {
            final isHl = p == PenType.highlighter;
            final selected = isHl ? ctrl.tool == ToolKind.highlighter : (ctrl.tool == ToolKind.pen && ctrl.penType == p);
            return Tooltip(
              message: p.label,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => isHl ? state._pickTool(b, ToolKind.highlighter) : state._pickTool(b, ToolKind.pen, pen: p),
                child: Container(
                  width: 42,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? scheme.primaryContainer : null,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: PenGlyph(type: p, color: Color(ctrl.pens[p]!.color), selected: selected),
                ),
              ),
            );
          },
        );
    Widget group(String label, IconData icon, List<ToolKind> tools) => Builder(
          builder: (b) {
            final active = tools.contains(ctrl.tool);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: active ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: () => state._openGroup(b, label, tools),
                icon: Icon(active ? toolInfos[ctrl.tool]!.icon : icon, size: 20),
                label: Text(label),
              ),
            );
          },
        );
    return Material(
      elevation: 3,
      color: scheme.surface,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            tool(ToolKind.select),
            const SizedBox(width: 4),
            pen(PenType.fountain),
            pen(PenType.ballpoint),
            pen(PenType.pencil),
            pen(PenType.technical),
            pen(PenType.highlighter),
            const SizedBox(width: 4),
            tool(ToolKind.eraser),
            tool(ToolKind.lasso),
            tool(ToolKind.text),
            tool(ToolKind.shape),
            const SizedBox(height: 32, child: VerticalDivider(width: 16)),
            if (showsEngineering(mode)) group('Mühendislik', Icons.architecture, engineeringTools),
            if (showsMoto(mode)) group('Motosiklet', Icons.two_wheeler, motoTools),
          ]),
        ),
      ),
    );
  }
}

class _PhoneBar extends StatelessWidget {
  final _EditorScreenState state;
  const _PhoneBar({required this.state});
  @override
  Widget build(BuildContext context) {
    final ctrl = state.ctrl;
    final mode = ctrl.page.mode;
    final scheme = Theme.of(context).colorScheme;
    final penSel = ctrl.tool == ToolKind.pen || ctrl.tool == ToolKind.highlighter;
    final penType = ctrl.tool == ToolKind.highlighter ? PenType.highlighter : ctrl.penType;
    Widget tool(ToolKind t) => Builder(
        builder: (b) => _IconTool(info: toolInfos[t]!, selected: ctrl.tool == t, onTap: () => state._pickTool(b, t)));
    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      tool(ToolKind.select),
      Builder(
        builder: (b) => InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (!penSel) {
              ctrl.setTool(ToolKind.pen);
            } else {
              state._openPanel(b, (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 8, children: [
                      for (final p in PenType.values)
                        InkWell(
                          onTap: () => p == PenType.highlighter ? ctrl.setTool(ToolKind.highlighter) : ctrl.setPenType(p),
                          child: Padding(padding: const EdgeInsets.all(4), child: PenGlyph(type: p, color: Color(ctrl.pens[p]!.color), size: 40)),
                        ),
                    ]),
                    const Divider(),
                    ToolOptionsPanel(ctrl: ctrl),
                  ]));
            }
          },
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: penSel ? scheme.primaryContainer : null, borderRadius: BorderRadius.circular(10)),
            child: PenGlyph(type: penType, color: Color(ctrl.pens[penType]!.color), selected: penSel),
          ),
        ),
      ),
      tool(ToolKind.eraser),
      tool(ToolKind.lasso),
      tool(ToolKind.text),
      tool(ToolKind.shape),
      if (showsEngineering(mode))
        Builder(
            builder: (b) => IconButton(
                  tooltip: 'Mühendislik',
                  isSelected: engineeringTools.contains(ctrl.tool),
                  icon: Icon(engineeringTools.contains(ctrl.tool) ? toolInfos[ctrl.tool]!.icon : Icons.architecture),
                  onPressed: () => state._openGroup(b, 'Mühendislik', engineeringTools),
                )),
      if (showsMoto(mode))
        Builder(
            builder: (b) => IconButton(
                  tooltip: 'Motosiklet',
                  isSelected: motoTools.contains(ctrl.tool),
                  icon: Icon(motoTools.contains(ctrl.tool) ? toolInfos[ctrl.tool]!.icon : Icons.two_wheeler),
                  onPressed: () => state._openGroup(b, 'Motosiklet', motoTools),
                )),
    ]);
  }
}

class _IconTool extends StatelessWidget {
  final ToolInfo info;
  final bool selected;
  final VoidCallback onTap;
  const _IconTool({required this.info, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Tooltip(
        message: info.shortcut != null ? '${info.label} (${info.shortcut})' : info.label,
        child: IconButton(
          isSelected: selected,
          style: IconButton.styleFrom(backgroundColor: selected ? Theme.of(context).colorScheme.primaryContainer : null),
          icon: Icon(info.icon),
          onPressed: onTap,
        ),
      );
}

class _GroupTile extends StatelessWidget {
  final ToolInfo info;
  final bool selected;
  final VoidCallback onTap;
  const _GroupTile({required this.info, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 92,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: [
          Icon(info.icon, color: selected ? scheme.onPrimaryContainer : null),
          const SizedBox(height: 4),
          Text(info.label, style: Theme.of(context).textTheme.labelSmall, textAlign: TextAlign.center, maxLines: 2),
        ]),
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  final EditorController ctrl;
  final VoidCallback onConvert;
  final VoidCallback onEdit;
  const _SelectionBar({required this.ctrl, required this.onConvert, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final hasStrokes = ctrl.selected.any((e) => e is StrokeElement);
    final single = ctrl.singleSelected;
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('${ctrl.selection.length} seçili')),
            if (single != null && single is! StrokeElement)
              TextButton.icon(onPressed: onEdit, icon: const Icon(Icons.tune), label: const Text('Düzenle')),
            if (hasStrokes) ...[
              TextButton.icon(onPressed: onConvert, icon: const Icon(Icons.text_fields), label: const Text('Metne çevir')),
              TextButton.icon(onPressed: ctrl.alignSelection, icon: const Icon(Icons.format_align_left), label: const Text('Hizala')),
              TextButton.icon(
                  onPressed: () {
                    final n = ctrl.beautifySelection();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(n == 0 ? 'Tanınan şekil yok' : '$n şekil düzeltildi')));
                  },
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('Şekle oturt')),
            ],
            PopupMenuButton<int>(
              tooltip: 'Renk',
              icon: const Icon(Icons.palette_outlined),
              itemBuilder: (_) => [
                for (final c in penPalette)
                  PopupMenuItem(value: c, child: Row(children: [CircleAvatar(radius: 10, backgroundColor: Color(c)), const SizedBox(width: 8), Text('#${c.toRadixString(16).substring(2).toUpperCase()}')])),
              ],
              onSelected: ctrl.recolorSelection,
            ),
            IconButton(tooltip: 'Öne getir', onPressed: () => ctrl.bringSelection(front: true), icon: const Icon(Icons.flip_to_front)),
            IconButton(tooltip: 'Arkaya gönder', onPressed: () => ctrl.bringSelection(front: false), icon: const Icon(Icons.flip_to_back)),
            IconButton(tooltip: 'Çoğalt (Ctrl+D)', onPressed: ctrl.duplicateSelection, icon: const Icon(Icons.copy)),
            IconButton(tooltip: 'Sil', onPressed: ctrl.deleteSelection, icon: const Icon(Icons.delete_outline)),
            IconButton(tooltip: 'Kapat', onPressed: ctrl.clearSelection, icon: const Icon(Icons.close)),
          ]),
        ),
      ),
    );
  }
}

class PageMenu extends StatelessWidget {
  final EditorController ctrl;
  final VoidCallback onCalendar;
  final VoidCallback onPresent;
  const PageMenu({super.key, required this.ctrl, required this.onCalendar, required this.onPresent});

  static const engScales = [ScaleSpec.free, ScaleSpec(5, 1), ScaleSpec(2, 1), ScaleSpec(1, 1), ScaleSpec(1, 2), ScaleSpec(1, 5), ScaleSpec(1, 10), ScaleSpec(1, 20)];
  static const motoScales = [ScaleSpec(1, 100, 'm'), ScaleSpec(1, 200, 'm'), ScaleSpec(1, 500, 'm'), ScaleSpec(1, 1000, 'm')];

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<VoidCallback>(
      tooltip: 'Sayfa',
      onSelected: (fn) => fn(),
      itemBuilder: (_) => [
        const PopupMenuItem(enabled: false, child: Text('Kullanım')),
        for (final m in PageMode.values)
          CheckedPopupMenuItem(value: () => ctrl.setMode(m), checked: ctrl.page.mode == m, child: Text(m.label)),
        const PopupMenuDivider(),
        const PopupMenuItem(enabled: false, child: Text('Ölçek')),
        for (final s in [...engScales, ...motoScales])
          CheckedPopupMenuItem(value: () => ctrl.setScale(s), checked: ctrl.page.scale == s, child: Text(s.label)),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(
            value: () => ctrl.update(() => ctrl.stylusOnly = !ctrl.stylusOnly), checked: ctrl.stylusOnly, child: const Text('Yalnızca kalem çizer')),
        CheckedPopupMenuItem(
            value: () => ctrl.update(() => ctrl.fingerScroll = !ctrl.fingerScroll),
            checked: ctrl.fingerScroll,
            child: const Text('Tek parmakla kaydır')),
        CheckedPopupMenuItem(
            value: () => ctrl.update(() => ctrl.canvasLocked = !ctrl.canvasLocked), checked: ctrl.canvasLocked, child: const Text('Sayfayı kilitle')),
        const PopupMenuDivider(),
        PopupMenuItem(value: onCalendar, child: const ListTile(dense: true, leading: Icon(Icons.event_outlined), title: Text('Takvime ekle…'))),
        PopupMenuItem(value: onPresent, child: const ListTile(dense: true, leading: Icon(Icons.slideshow_outlined), title: Text('Sunum modu'))),
      ],
    );
  }
}
