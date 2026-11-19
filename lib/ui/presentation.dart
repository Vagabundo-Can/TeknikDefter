// Sunum modu: defterin sayfaları tam ekran, ok tuşları / kaydırma ile geçiş, lazer işaretçi.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../canvas/element_painter.dart';
import '../media/asset_images.dart';
import '../models/note_models.dart';
import '../templates/templates.dart';

class PresentationScreen extends StatefulWidget {
  final List<NotePage> pages;
  final int initialIndex;
  const PresentationScreen({super.key, required this.pages, this.initialIndex = 0});
  @override
  State<PresentationScreen> createState() => _PresentationScreenState();
}

class _Laser {
  final Offset p;
  final DateTime t;
  _Laser(this.p, this.t);
}

class _PresentationScreenState extends State<PresentationScreen> {
  late final PageController pc = PageController(initialPage: widget.initialIndex);
  late int index = widget.initialIndex;
  final List<_Laser> laser = [];
  Timer? _fade;
  bool chrome = true;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    AssetImages.instance.addListener(_repaint);
    _fade = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final now = DateTime.now();
      if (laser.isNotEmpty) {
        setState(() => laser.removeWhere((l) => now.difference(l.t) > const Duration(milliseconds: 900)));
      }
    });
  }

  void _repaint() => setState(() {});

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    AssetImages.instance.removeListener(_repaint);
    _fade?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _go(int d) {
    final n = (index + d).clamp(0, widget.pages.length - 1);
    pc.animateToPage(n, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (_, e) {
          if (e is! KeyDownEvent) return KeyEventResult.ignored;
          final k = e.logicalKey;
          if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.pageDown) {
            _go(1);
          } else if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.pageUp) {
            _go(-1);
          } else if (k == LogicalKeyboardKey.escape) {
            Navigator.pop(context);
          } else {
            return KeyEventResult.ignored;
          }
          return KeyEventResult.handled;
        },
        child: Stack(children: [
          PageView.builder(
            controller: pc,
            itemCount: widget.pages.length,
            onPageChanged: (i) => setState(() => index = i),
            itemBuilder: (_, i) => Listener(
              onPointerMove: (e) {
                if (e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.mouse && e.buttons != 0) {
                  setState(() => laser.add(_Laser(e.localPosition, DateTime.now())));
                }
              },
              child: GestureDetector(
                onTap: () => setState(() => chrome = !chrome),
                child: CustomPaint(size: Size.infinite, painter: _SlidePainter(widget.pages[i], AssetImages.instance.version)),
              ),
            ),
          ),
          IgnorePointer(child: CustomPaint(size: Size.infinite, painter: _LaserPainter(List.of(laser)))),
          if (chrome)
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(
                child: Material(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(24),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(color: Colors.white, onPressed: index > 0 ? () => _go(-1) : null, icon: const Icon(Icons.chevron_left)),
                    Text('${index + 1} / ${widget.pages.length}  ·  ${widget.pages[index].title}', style: const TextStyle(color: Colors.white)),
                    IconButton(
                        color: Colors.white, onPressed: index < widget.pages.length - 1 ? () => _go(1) : null, icon: const Icon(Icons.chevron_right)),
                    IconButton(color: Colors.white, tooltip: 'Kapat (Esc)', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _SlidePainter extends CustomPainter {
  final NotePage page;
  final int v;
  _SlidePainter(this.page, this.v);

  @override
  void paint(Canvas c, Size size) {
    final region = page.infinite
        ? (page.visible.isEmpty ? const Rect.fromLTWH(0, 0, 297, 210) : page.visible.map((e) => e.bounds).reduce((a, b) => a.expandToInclude(b)).inflate(8))
        : Rect.fromLTWH(0, 0, page.widthMm, page.heightMm);
    final z = math.min(size.width / region.width, size.height / region.height);
    c.translate((size.width - region.width * z) / 2, (size.height - region.height * z) / 2);
    c.scale(z);
    c.translate(-region.left, -region.top);
    c.drawRect(region, Paint()..color = Colors.white);
    if (!page.infinite) {
      c.save();
      c.clipRect(region);
      templateById(page.templateId).painter(c, page);
      c.restore();
    }
    for (final e in page.visible) {
      paintElement(c, e, page.scale);
    }
  }

  @override
  bool shouldRepaint(covariant _SlidePainter o) => o.page != page || o.v != v || true;
}

class _LaserPainter extends CustomPainter {
  final List<_Laser> pts;
  _LaserPainter(this.pts);
  @override
  void paint(Canvas c, Size size) {
    final now = DateTime.now();
    for (var i = 1; i < pts.length; i++) {
      final age = now.difference(pts[i].t).inMilliseconds / 900;
      final a = (1 - age).clamp(0.0, 1.0);
      c.drawLine(
          pts[i - 1].p,
          pts[i].p,
          Paint()
            ..color = Colors.red.withValues(alpha: a)
            ..strokeWidth = 6
            ..strokeCap = StrokeCap.round);
    }
    if (pts.isNotEmpty) {
      c.drawCircle(pts.last.p, 9, Paint()..color = Colors.red.withValues(alpha: 0.35));
      c.drawCircle(pts.last.p, 4, Paint()..color = Colors.red);
    }
  }

  @override
  bool shouldRepaint(covariant _LaserPainter o) => true;
}
