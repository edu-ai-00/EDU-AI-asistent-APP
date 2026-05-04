import 'package:flutter/material.dart';

/// Custom painter for diagonal stripes pattern
class DiagonalStripesPainter extends CustomPainter {
  final Color stripeColor;
  final double stripeWidth;
  final double spacing;

  DiagonalStripesPainter({
    required this.stripeColor,
    required this.stripeWidth,
    required this.spacing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = stripeColor
      ..strokeWidth = stripeWidth
      ..style = PaintingStyle.stroke;

    final double step = stripeWidth + spacing;
    final double diagonal = size.width + size.height;

    for (double i = -size.height; i < diagonal; i += step) {
      canvas.drawLine(
        Offset(i, size.height),
        Offset(i + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
