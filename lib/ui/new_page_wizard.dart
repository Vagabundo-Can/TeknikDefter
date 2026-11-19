// Yeni sayfa: 1) "Bu sayfayı ne için kullanacaksın?"  2) o moda ait şablon seçimi.

import 'package:flutter/material.dart';

import '../models/note_models.dart';
import '../templates/templates.dart';

class NewPageResult {
  final PageMode mode;
  final PageTemplate template;
  const NewPageResult(this.mode, this.template);
}

Future<NewPageResult?> showNewPageWizard(BuildContext context, {PageMode? lastMode}) {
  return showDialog<NewPageResult>(
    context: context,
    builder: (_) => _Wizard(lastMode: lastMode),
  );
}

class _Wizard extends StatefulWidget {
  final PageMode? lastMode;
  const _Wizard({this.lastMode});
  @override
  State<_Wizard> createState() => _WizardState();
}

class _WizardState extends State<_Wizard> {
  PageMode? mode;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 760, maxHeight: size.height * 0.88),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: mode == null ? _modeStep(context) : _templateStep(context, mode!),
        ),
      ),
    );
  }

  Widget _modeStep(BuildContext context) {
    final t = Theme.of(context);
    Widget card(PageMode m, IconData icon, String sub) => Expanded(
          child: Card(
            clipBehavior: Clip.antiAlias,
            color: m == widget.lastMode ? t.colorScheme.secondaryContainer : null,
            child: InkWell(
              onTap: () => setState(() => mode = m),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
                child: Column(children: [
                  Icon(icon, size: 40),
                  const SizedBox(height: 10),
                  Text(m.label, style: t.textTheme.titleMedium, textAlign: TextAlign.center),
                  const SizedBox(height: 6),
                  Text(sub, style: t.textTheme.bodySmall, textAlign: TextAlign.center),
                ]),
              ),
            ),
          ),
        );
    final narrow = MediaQuery.sizeOf(context).width < 520;
    final cards = [
      card(PageMode.engineering, Icons.architecture, 'Teknik kalem, ölçü, GD&T, yüzey ve kaynak sembolleri'),
      card(PageMode.moto, Icons.two_wheeler, 'Koni, şerit, yol, rota, parkur ve ders şablonları'),
      card(PageMode.both, Icons.dashboard_customize_outlined, 'Tüm araçlar'),
    ];
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Bu sayfayı ne için kullanacaksın?', style: t.textTheme.titleLarge),
      const SizedBox(height: 16),
      if (narrow)
        ...cards.map((c) => Row(children: [c]))
      else
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: cards),
      const SizedBox(height: 8),
      Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç'))),
    ]);
  }

  Widget _templateStep(BuildContext context, PageMode m) {
    final list = templatesFor(m);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        IconButton(onPressed: () => setState(() => mode = null), icon: const Icon(Icons.arrow_back)),
        Text('${m.label} — şablon seç', style: Theme.of(context).textTheme.titleLarge),
      ]),
      const SizedBox(height: 12),
      Flexible(
        child: GridView.builder(
          shrinkWrap: true,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 170, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.62),
          itemCount: list.length,
          itemBuilder: (_, i) {
            final tp = list[i];
            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => Navigator.pop(context, NewPageResult(m, tp)),
              child: Column(children: [
                Expanded(child: Center(child: TemplatePreview(template: tp))),
                const SizedBox(height: 6),
                Text(tp.name, style: Theme.of(context).textTheme.labelLarge, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(tp.description, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            );
          },
        ),
      ),
    ]);
  }
}

class TemplatePreview extends StatelessWidget {
  final PageTemplate template;
  const TemplatePreview({super.key, required this.template});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: template.widthMm / template.heightMm,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black26),
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(4), child: CustomPaint(painter: _PreviewPainter(template))),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  final PageTemplate t;
  _PreviewPainter(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final page = NotePage(
        id: 'preview', notebookId: '', title: '', mode: PageMode.both, templateId: t.id, widthMm: t.widthMm, heightMm: t.heightMm, scale: t.scale);
    canvas.scale(size.width / t.widthMm);
    t.painter(canvas, page);
  }

  @override
  bool shouldRepaint(covariant _PreviewPainter old) => old.t.id != t.id;
}
