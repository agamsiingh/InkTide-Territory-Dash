import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Simplified, procedurally drawn flags for the campaign countries.
void paintFlag(Canvas canvas, Rect r, String iso) {
  final p = Paint();
  canvas.save();
  canvas.clipRRect(RRect.fromRectAndRadius(r, Radius.circular(r.height * 0.12)));
  void fill(Rect rect, int c) => canvas.drawRect(rect, p..color = Color(c));
  Rect hBand(int i, int n) => Rect.fromLTWH(r.left, r.top + r.height * i / n, r.width, r.height / n);
  Rect vBand(int i, int n) => Rect.fromLTWH(r.left + r.width * i / n, r.top, r.width / n, r.height);
  void star(Offset c, double rad, int color, {int points = 5}) {
    final path = Path();
    for (var i = 0; i < points * 2; i++) {
      final rr = i.isEven ? rad : rad * 0.42;
      final a = -math.pi / 2 + i * math.pi / points;
      final pt = c + Offset(math.cos(a) * rr, math.sin(a) * rr);
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(path..close(), p..color = Color(color));
  }

  final w = r.width, h = r.height;
  switch (iso) {
    case 'CAN':
      fill(r, 0xFFFFFFFF);
      fill(Rect.fromLTWH(r.left, r.top, w / 4, h), 0xFFD52B1E);
      fill(Rect.fromLTWH(r.right - w / 4, r.top, w / 4, h), 0xFFD52B1E);
      // Stylised maple leaf: a spiky star with a stem.
      star(r.center.translate(0, -h * 0.03), h * 0.3, 0xFFD52B1E, points: 7);
      fill(Rect.fromCenter(center: r.center.translate(0, h * 0.26), width: w * 0.03, height: h * 0.16), 0xFFD52B1E);
    case 'USA':
      for (var i = 0; i < 13; i++) {
        fill(hBand(i, 13), i.isEven ? 0xFFB22234 : 0xFFFFFFFF);
      }
      final canton = Rect.fromLTWH(r.left, r.top, w * 0.42, h * 7 / 13);
      fill(canton, 0xFF3C3B6E);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 5; x++) {
          canvas.drawCircle(
              Offset(canton.left + canton.width * (x + 0.5) / 5, canton.top + canton.height * (y + 0.5) / 4),
              h * 0.025, p..color = const Color(0xFFFFFFFF));
        }
      }
    case 'MEX':
      fill(vBand(0, 3), 0xFF006847);
      fill(vBand(1, 3), 0xFFFFFFFF);
      fill(vBand(2, 3), 0xFFCE1126);
      canvas.drawCircle(r.center, h * 0.14, p..color = const Color(0xFF8C5A2B));
    case 'BRA':
      fill(r, 0xFF009C3B);
      final d = Path()
        ..moveTo(r.left + w * 0.08, r.center.dy)
        ..lineTo(r.center.dx, r.top + h * 0.1)
        ..lineTo(r.right - w * 0.08, r.center.dy)
        ..lineTo(r.center.dx, r.bottom - h * 0.1)
        ..close();
      canvas.drawPath(d, p..color = const Color(0xFFFFDF00));
      canvas.drawCircle(r.center, h * 0.24, p..color = const Color(0xFF002776));
    case 'GBR':
      fill(r, 0xFF012169);
      final white = Paint()
        ..color = const Color(0xFFFFFFFF)
        ..strokeWidth = h * 0.2;
      final red = Paint()
        ..color = const Color(0xFFC8102E)
        ..strokeWidth = h * 0.08;
      canvas.drawLine(r.topLeft, r.bottomRight, white);
      canvas.drawLine(r.topRight, r.bottomLeft, white);
      canvas.drawLine(r.topLeft, r.bottomRight, red);
      canvas.drawLine(r.topRight, r.bottomLeft, red);
      fill(Rect.fromCenter(center: r.center, width: w, height: h * 0.33), 0xFFFFFFFF);
      fill(Rect.fromCenter(center: r.center, width: h * 0.33, height: h), 0xFFFFFFFF);
      fill(Rect.fromCenter(center: r.center, width: w, height: h * 0.2), 0xFFC8102E);
      fill(Rect.fromCenter(center: r.center, width: h * 0.2, height: h), 0xFFC8102E);
    case 'FRA':
      fill(vBand(0, 3), 0xFF0055A4);
      fill(vBand(1, 3), 0xFFFFFFFF);
      fill(vBand(2, 3), 0xFFEF4135);
    case 'DEU':
      fill(hBand(0, 3), 0xFF000000);
      fill(hBand(1, 3), 0xFFDD0000);
      fill(hBand(2, 3), 0xFFFFCE00);
    case 'ITA':
      fill(vBand(0, 3), 0xFF009246);
      fill(vBand(1, 3), 0xFFFFFFFF);
      fill(vBand(2, 3), 0xFFCE2B37);
    case 'EGY':
      fill(hBand(0, 3), 0xFFCE1126);
      fill(hBand(1, 3), 0xFFFFFFFF);
      fill(hBand(2, 3), 0xFF000000);
      canvas.drawCircle(r.center, h * 0.1, p..color = const Color(0xFFC09300));
    case 'IND':
      fill(hBand(0, 3), 0xFFFF9933);
      fill(hBand(1, 3), 0xFFFFFFFF);
      fill(hBand(2, 3), 0xFF138808);
      canvas.drawCircle(
          r.center,
          h * 0.12,
          p
            ..color = const Color(0xFF000080)
            ..style = PaintingStyle.stroke
            ..strokeWidth = h * 0.03);
      p.style = PaintingStyle.fill;
    case 'JPN':
      fill(r, 0xFFFFFFFF);
      canvas.drawCircle(r.center, h * 0.3, p..color = const Color(0xFFBC002D));
    case 'AUS':
      fill(r, 0xFF00008B);
      final c = Rect.fromLTWH(r.left, r.top, w / 2, h / 2);
      canvas.save();
      canvas.clipRect(c);
      paintFlag(canvas, c, 'GBR');
      canvas.restore();
      star(Offset(r.left + w * 0.25, r.top + h * 0.75), h * 0.13, 0xFFFFFFFF, points: 7);
      for (final o in const [Offset(0.75, 0.25), Offset(0.62, 0.5), Offset(0.88, 0.45), Offset(0.75, 0.82)]) {
        star(Offset(r.left + w * o.dx, r.top + h * o.dy), h * 0.07, 0xFFFFFFFF, points: 7);
      }
    default:
      fill(r, 0xFFB0B8C8);
  }
  canvas.restore();
  canvas.drawRRect(
      RRect.fromRectAndRadius(r, Radius.circular(r.height * 0.12)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, h * 0.05)
        ..color = const Color(0x5516204A));
}

class FlagIcon extends StatelessWidget {
  const FlagIcon({super.key, required this.iso, this.width = 36});
  final String iso;
  final double width;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(width, width * 2 / 3),
        painter: _FlagPainter(iso),
      );
}

class _FlagPainter extends CustomPainter {
  _FlagPainter(this.iso);
  final String iso;

  @override
  void paint(Canvas canvas, Size size) => paintFlag(canvas, Offset.zero & size, iso);

  @override
  bool shouldRepaint(covariant _FlagPainter old) => old.iso != iso;
}
