// Samsung Notes tarzı kalem simgeleri: her kalem türü kendi gövdesi ve uç rengiyle.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/note_models.dart';

class PenGlyph extends StatelessWidget {
  final PenType type;
  final Color color;
  final double size;
  final bool selected;
  const PenGlyph({super.key, required this.type, required this.color, this.size = 30, this.selected = false});

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _PenPainter(type, color, Theme.of(context).colorScheme.onSurface, selected),
      );
}

class _PenPainter extends CustomPainter {
  final PenType type;
  final Color ink, body;
  final bool selected;
  _PenPainter(this.type, this.ink, this.body, this.selected);

  @override
  void paint(Canvas c, Size s) {
    final u = s.width / 32;
    c.save();
    // kalem çapraz: uç sol altta; seçiliyse biraz yukarı kalkar
    c.translate(s.width / 2, s.height / 2 + (selected ? -2 * u : 0));
    c.rotate(math.pi / 4);
    c.scale(u);
    final outline = Paint()
      ..color = body
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeJoin = StrokeJoin.round;
    final fillBody = Paint()..color = body.withValues(alpha: 0.08);
    final inkP = Paint()..color = ink;
    // gövde ekseni: y = -15 (arka) … +15 (uç), x merkez
    switch (type) {
      case PenType.fountain:
        final b = RRect.fromLTRBR(-3.6, -15, 3.6, 5, const Radius.circular(2.5));
        c.drawRRect(b, fillBody);
        c.drawRRect(b, outline);
        c.drawRect(const Rect.fromLTRB(-3.6, -2, 3.6, 0.5), inkP); // renk bileziği
        final nib = Path()
          ..moveTo(-3, 5)
          ..lineTo(3, 5)
          ..lineTo(0, 14.5)
          ..close();
        c.drawPath(nib, Paint()..color = ink);
        c.drawLine(const Offset(0, 8), const Offset(0, 12.5), Paint()
          ..color = Colors.white
          ..strokeWidth = 0.8);
      case PenType.ballpoint:
        final b = RRect.fromLTRBR(-2.6, -15, 2.6, 8, const Radius.circular(2.6));
        c.drawRRect(b, fillBody);
        c.drawRRect(b, outline);
        c.drawLine(const Offset(2.6, -14), const Offset(2.6, -4), outline..strokeWidth = 1.6); // klips
        final cone = Path()
          ..moveTo(-2.6, 8)
          ..lineTo(2.6, 8)
          ..lineTo(0.6, 13)
          ..lineTo(-0.6, 13)
          ..close();
        c.drawPath(cone, fillBody);
        c.drawPath(cone, outline..strokeWidth = 1.3);
        c.drawCircle(const Offset(0, 13.8), 1.1, inkP);
      case PenType.pencil:
        final b = Rect.fromLTRB(-3.4, -15, 3.4, 6);
        c.drawRect(b, Paint()..color = const Color(0xFFFFC107));
        c.drawRect(b, outline);
        c.drawLine(const Offset(-1.1, -15), const Offset(-1.1, 6), outline..strokeWidth = 0.7);
        c.drawLine(const Offset(1.1, -15), const Offset(1.1, 6), outline);
        c.drawRect(const Rect.fromLTRB(-3.4, -15, 3.4, -12), Paint()..color = const Color(0xFFF48FB1)); // silgi
        final wood = Path()
          ..moveTo(-3.4, 6)
          ..lineTo(3.4, 6)
          ..lineTo(0, 14.5)
          ..close();
        c.drawPath(wood, Paint()..color = const Color(0xFFFFE0B2));
        c.drawPath(wood, outline..strokeWidth = 1.3);
        final lead = Path()
          ..moveTo(-1.2, 11.5)
          ..lineTo(1.2, 11.5)
          ..lineTo(0, 14.5)
          ..close();
        c.drawPath(lead, inkP);
      case PenType.technical:
        final b = RRect.fromLTRBR(-3, -15, 3, 4, const Radius.circular(1.2));
        c.drawRRect(b, fillBody);
        c.drawRRect(b, outline);
        c.drawRect(const Rect.fromLTRB(-3, -9, 3, -7), inkP);
        final cone = Path()
          ..moveTo(-3, 4)
          ..lineTo(3, 4)
          ..lineTo(0.7, 9)
          ..lineTo(-0.7, 9)
          ..close();
        c.drawPath(cone, outline);
        c.drawLine(const Offset(0, 9), const Offset(0, 15), Paint()
          ..color = ink
          ..strokeWidth = 0.9); // iğne uç
      case PenType.highlighter:
        final b = RRect.fromLTRBR(-4.6, -15, 4.6, 5, const Radius.circular(2));
        c.drawRRect(b, fillBody);
        c.drawRRect(b, outline);
        final tip = Path()
          ..moveTo(-4.6, 5)
          ..lineTo(4.6, 5)
          ..lineTo(3.4, 13)
          ..lineTo(-3.4, 10.5)
          ..close();
        c.drawPath(tip, Paint()..color = ink.withValues(alpha: 0.9));
        c.drawPath(tip, outline);
    }
    c.restore();
  }

  @override
  bool shouldRepaint(covariant _PenPainter o) => o.type != type || o.ink != ink || o.selected != selected || o.body != body;
}

/// Uygulama logosu (assets/logo.png yoksa basit çizim)
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 32});
  @override
  Widget build(BuildContext context) => Image.asset('assets/logo.png', width: size, height: size, errorBuilder: (_, __, ___) {
        return SizedBox(width: size, height: size, child: const Icon(Icons.two_wheeler));
      });
}
