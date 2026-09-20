import 'package:flutter/material.dart';

import '../../../core/theme/opener_home_style.dart';

enum OpenerEntryKind { photos, partner }

/// Physical cards, painted as scalable vector artwork. Decorative only: the
/// surrounding entry owns the single action and accessibility label.
class OpenerEntryIcon extends StatelessWidget {
  const OpenerEntryIcon({super.key, required this.kind, this.size = 64});

  final OpenerEntryKind kind;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(painter: _EntryPainter(kind)),
        ),
      );
}

class _EntryPainter extends CustomPainter {
  const _EntryPainter(this.kind);
  final OpenerEntryKind kind;

  Paint _gradient(Rect rect, List<Color> colors) => Paint()
    ..shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colors,
    ).createShader(rect);

  void _relief(Canvas canvas, Path shape, {required bool back}) {
    final light =
        back ? OpenerHomeStyle.iconBackLight : OpenerHomeStyle.iconSymbol;
    final dark =
        back ? OpenerHomeStyle.iconBack : OpenerHomeStyle.iconSymbolDark;
    canvas.drawShadow(
        shape.shift(const Offset(0.3, 1.2)), Colors.black, 1.6, false);
    canvas.drawPath(shape.shift(const Offset(0.2, 0.8)), Paint()..color = dark);
    canvas.drawPath(
        shape,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.65, -0.8),
            radius: 1.7,
            colors: [light, dark],
          ).createShader(shape.getBounds()));
    canvas.save();
    canvas.clipPath(shape);
    canvas.drawPath(
        shape.shift(const Offset(0.2, 0.35)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.45
          ..color = Colors.white.withValues(alpha: back ? 0.16 : 0.12));
    canvas.restore();
  }

  void _card(Canvas canvas, {required bool back}) {
    const rect = Rect.fromLTWH(-18, -23, 36, 46);
    // The icon is drawn in a 64-unit canvas; this micro radius is the bevel,
    // not an application surface corner.
    final face = RRect.fromRectAndRadius(rect, const Radius.circular(6));
    final path = Path()..addRRect(face);
    canvas.drawShadow(path.shift(const Offset(1, 4)), Colors.black, 5, false);
    // A continuous sidewall remains visible below the lit face, making the
    // boards visibly thick at the entry's 104–128 logical-pixel size.
    for (var depth = 2.5; depth >= 0; depth -= 0.4) {
      canvas.drawRRect(
          face.shift(Offset(depth * 0.2, depth)),
          _gradient(
              rect,
              back
                  ? [OpenerHomeStyle.iconBack, OpenerHomeStyle.iconBackEdge]
                  : [
                      OpenerHomeStyle.iconPaperShade,
                      OpenerHomeStyle.iconPaperEdge
                    ]));
    }
    canvas.drawRRect(
        face,
        _gradient(
            rect,
            back
                ? [OpenerHomeStyle.iconBackLight, OpenerHomeStyle.iconBack]
                : [
                    OpenerHomeStyle.icon,
                    OpenerHomeStyle.icon,
                    OpenerHomeStyle.iconPaperShade
                  ]));
    // Soft, shaded bevel, with a narrow upper-left highlight. Unlike an
    // outline, it darkens towards the lower-right edge of the material.
    canvas.drawRRect(
        face.deflate(0.8),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.45)
          ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: back ? 0.3 : 0.6),
                back ? OpenerHomeStyle.iconBack : OpenerHomeStyle.iconRim
              ]).createShader(rect));
    canvas.drawRRect(
        face.deflate(0.6),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6
          ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: back ? 0.28 : 0.5),
                Colors.white.withValues(alpha: 0.03)
              ]).createShader(rect));

    if (kind == OpenerEntryKind.photos) {
      const picture = Rect.fromLTWH(-14, -18, 28, 35);
      final inset = RRect.fromRectAndRadius(picture, const Radius.circular(3));
      canvas.drawRRect(inset.shift(const Offset(0.3, 0.5)),
          Paint()..color = Colors.white.withValues(alpha: 0.65));
      canvas.drawRRect(
          inset,
          _gradient(
              picture,
              back
                  ? [OpenerHomeStyle.iconBack, OpenerHomeStyle.iconBackLight]
                  : [
                      OpenerHomeStyle.iconInset,
                      OpenerHomeStyle.iconInsetShade
                    ]));
      canvas.save();
      canvas.clipRRect(inset);
      // Inner shadow makes the picture window sit below the warm frame.
      canvas.drawRRect(
          inset.shift(const Offset(0.6, 0.8)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.7)
            ..color = OpenerHomeStyle.iconBackEdge.withValues(alpha: 0.3));
      final mountain = Path()
        ..moveTo(-12, 9)
        ..lineTo(-4, -3)
        ..quadraticBezierTo(-2.3, -5.4, -0.6, -2.8)
        ..lineTo(5, 5)
        ..lineTo(7.8, 1.5)
        ..quadraticBezierTo(9.4, -0.5, 10.8, 1.9)
        ..lineTo(14, 8)
        ..lineTo(14, 12)
        ..quadraticBezierTo(14, 14.5, 11.5, 14.5)
        ..lineTo(-9.7, 14.5)
        ..quadraticBezierTo(-13, 14.5, -12, 9)
        ..close();
      _relief(canvas, mountain, back: back);
      const sun = Rect.fromLTWH(3.5, -13.5, 7, 7);
      _relief(canvas, Path()..addOval(sun), back: back);
      canvas.restore();
    } else {
      canvas.save();
      // The rear portrait is offset to stay legible beside the overlapping
      // front board, as in the supplied reference.
      if (back) canvas.translate(-5, 0);
      final head = Path()..addOval(const Rect.fromLTWH(-5.2, -15, 10.4, 11));
      final shoulders = Path()
        ..moveTo(-10, 8.5)
        ..cubicTo(-10.5, -4, 10.5, -4, 10, 8.5)
        ..quadraticBezierTo(9.8, 10, 8.5, 10)
        ..lineTo(-8.5, 10)
        ..quadraticBezierTo(-9.8, 10, -10, 8.5)
        ..close();
      for (final shape in [head, shoulders]) {
        _relief(canvas, shape, back: back);
      }
      final line = Paint()
        ..shader = const LinearGradient(colors: [
          OpenerHomeStyle.iconBackLight,
          OpenerHomeStyle.iconBack
        ]).createShader(const Rect.fromLTWH(-10, 14, 20, 6))
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      final lineShadow = Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6);
      canvas.drawLine(
          const Offset(-10, 15.7), const Offset(9, 15.7), lineShadow);
      canvas.drawLine(
          const Offset(-10, 19.7), const Offset(1, 19.7), lineShadow);
      canvas.drawLine(const Offset(-10, 15), const Offset(9, 15), line);
      canvas.drawLine(const Offset(-10, 19), const Offset(1, 19), line);
      canvas.restore();
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);
    canvas.drawOval(
        const Rect.fromLTWH(9, 48, 49, 12),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.save();
    canvas.translate(23, 28);
    canvas.rotate(-0.18);
    _card(canvas, back: true);
    canvas.restore();
    canvas.save();
    canvas.translate(37, 31);
    canvas.rotate(0.11);
    _card(canvas, back: false);
    canvas.restore();

    const badge = Rect.fromLTWH(41, 40, 22, 22);
    final badgePath = Path()..addOval(badge);
    canvas.drawShadow(badgePath, Colors.black, 3, false);
    canvas.drawOval(badge.shift(const Offset(0.5, 2)),
        Paint()..color = OpenerHomeStyle.iconOrangeEdge);
    canvas.drawOval(
        badge,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-0.55, -0.65),
            radius: 1.65,
            colors: [
              OpenerHomeStyle.iconOrangeLight,
              OpenerHomeStyle.orange,
              OpenerHomeStyle.iconOrangeEdge
            ],
            stops: [0, 0.65, 1],
          ).createShader(badge));
    canvas.drawOval(
        badge.deflate(0.7),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.5),
                OpenerHomeStyle.iconOrangeEdge
              ]).createShader(badge));
    canvas.drawArc(
        badge.deflate(1),
        3.4,
        2.2,
        false,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8);
    final plus = Paint()
      ..color = OpenerHomeStyle.ink
      ..strokeWidth = 3.1
      ..strokeCap = StrokeCap.round;
    final plusShadow = Paint()
      ..color = OpenerHomeStyle.iconOrangeEdge
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5);
    canvas.drawLine(const Offset(47, 51.7), const Offset(57, 51.7), plusShadow);
    canvas.drawLine(const Offset(52, 46.7), const Offset(52, 56.7), plusShadow);
    canvas.drawLine(const Offset(47, 51), const Offset(57, 51), plus);
    canvas.drawLine(const Offset(52, 46), const Offset(52, 56), plus);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EntryPainter oldDelegate) => oldDelegate.kind != kind;
}
