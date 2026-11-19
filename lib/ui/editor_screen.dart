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
import 'layout.dart';
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
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    final map = <LogicalKeyboardKey, ToolKind>{
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

  @override
  Widget build(BuildContext context) {
    final ff = formFactorOf(context);
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final page = ctrl.page;
        final tools = toolsFor(page.mode);
        final canvas = NoteCanvas(key: _canvasKey, controller: ctrl, onRequestText: (s) => _askText(s));
        final selectionBar = ctrl.selection.isEmpty ? null : _SelectionBar(ctrl: ctrl, onConvert: _convertToText);

        final appBar = AppBar(
          title: InkWell(
            onTap: _rename,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(page.title, overflow: TextOverflow.ellipsis),
              Text(
                [
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
            if (ff != FormFactor.phone)
              IconButton(tooltip: 'Sayfaya sığdır (Ctrl+0)', onPressed: () => _canvasKey.currentState?.fitPage(), icon: const Icon(Icons.fit_screen)),
            const SyncButton(),
            PageMenu(ctrl: ctrl),
          ],
        );

        if (ff == FormFactor.phone) {
          final primary = primaryToolsFor(page.mode);
          return Scaffold(
            appBar: appBar,
            body: Focus(
              focusNode: _focus,
              autofocus: true,
              onKeyEvent: _onKey,
              child: Stack(children: [
                Positioned.fill(child: canvas),
                if (selectionBar != null) Positioned(left: 8, right: 8, top: 8, child: Center(child: selectionBar)),
              ]),
            ),
            bottomNavigationBar: SafeArea(
              child: Material(
                elevation: 6,
                child: SizedBox(
                  height: 60,
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    for (final t in primary)
                      _ToolButton(
                        info: toolInfos[t]!,
                        selected: ctrl.tool == t,
                        onTap: () => ctrl.tool == t ? _showOptionsSheet() : ctrl.setTool(t),
                      ),
                    IconButton(
                      tooltip: 'Daha fazla',
                      icon: Icon(primary.contains(ctrl.tool) ? Icons.apps : toolInfos[ctrl.tool]!.icon),
                      isSelected: !primary.contains(ctrl.tool),
                      onPressed: () => _showAllToolsSheet(tools),
                    ),
                  ]),
                ),
              ),
            ),
          );
        }

        // Tablet + Windows
        return Scaffold(
          appBar: appBar,
          body: Focus(
            focusNode: _focus,
            autofocus: true,
            onKeyEvent: _onKey,
            child: Column(children: [
              Material(
                elevation: 1,
                child: SizedBox(
                  height: 52,
                  child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
                    for (final t in tools) ...[
                      if (t == ToolKind.dimension || t == ToolKind.cone) const VerticalDivider(indent: 10, endIndent: 10),
                      _ToolButton(info: toolInfos[t]!, selected: ctrl.tool == t, onTap: () => ctrl.setTool(t), showShortcut: ff == FormFactor.desktop),
                    ],
                  ]),
                ),
              ),
              Material(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: SizedBox(height: 44, child: ToolOptionsBar(ctrl: ctrl)),
                ),
              ),
              Expanded(
                child: Stack(children: [
                  Positioned.fill(child: canvas),
                  if (selectionBar != null) Positioned(left: 0, right: 0, top: 12, child: Center(child: selectionBar)),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }

  void _showOptionsSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => ListenableBuilder(
        listenable: ctrl,
        builder: (_, __) => Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), child: ToolOptionsPanel(ctrl: ctrl)),
      ),
    );
  }

  void _showAllToolsSheet(List<ToolKind> tools) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in tools)
            SizedBox(
              width: 84,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  ctrl.setTool(t);
                  Navigator.pop(ctx);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(children: [
                    Icon(toolInfos[t]!.icon, color: ctrl.tool == t ? Theme.of(ctx).colorScheme.primary : null),
                    const SizedBox(height: 4),
                    Text(toolInfos[t]!.label, style: Theme.of(ctx).textTheme.labelSmall, textAlign: TextAlign.center),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final ToolInfo info;
  final bool selected;
  final VoidCallback onTap;
  final bool showShortcut;
  const _ToolButton({required this.info, required this.selected, required this.onTap, this.showShortcut = false});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: showShortcut && info.shortcut != null ? '${info.label} (${info.shortcut})' : info.label,
      child: IconButton(
        isSelected: selected,
        style: IconButton.styleFrom(
          backgroundColor: selected ? Theme.of(context).colorScheme.primaryContainer : null,
        ),
        icon: Icon(info.icon),
        onPressed: onTap,
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  final EditorController ctrl;
  final VoidCallback onConvert;
  const _SelectionBar({required this.ctrl, required this.onConvert});

  @override
  Widget build(BuildContext context) {
    final hasStrokes = ctrl.selected.any((e) => e is StrokeElement);
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('${ctrl.selection.length} seçili')),
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
  const PageMenu({super.key, required this.ctrl});

  static const engScales = [ScaleSpec(5, 1), ScaleSpec(2, 1), ScaleSpec(1, 1), ScaleSpec(1, 2), ScaleSpec(1, 5), ScaleSpec(1, 10), ScaleSpec(1, 20)];
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
      ],
    );
  }
}
