import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// 录音列表里的小波形缩略图（蓝色，56×36）
class WaveformThumbnail extends StatelessWidget {
  final List<double> amplitudes; // 0.0–1.0
  final double width;
  final double height;
  final Color color;

  const WaveformThumbnail({
    super.key,
    required this.amplitudes,
    this.width = 54,
    this.height = 32,
    this.color = VpTokens.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: VpTokens.surfaceTertiary,
        borderRadius: BorderRadius.circular(VpTokens.radiusMd),
      ),
      child: CustomPaint(
        size: Size(width, height),
        painter: _ThumbnailPainter(amplitudes, color),
      ),
    );
  }
}

class _ThumbnailPainter extends CustomPainter {
  final List<double> amps;
  final Color color;
  _ThumbnailPainter(this.amps, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final n = amps.length;
    if (n == 0) return;
    const gap = 2.0;
    final barWidth = (size.width - gap * (n - 1)) / n;
    final paint = Paint()..color = color;

    for (var i = 0; i < n; i++) {
      final a = amps[i].clamp(0.06, 1.0);
      final h = a * size.height;
      final x = i * (barWidth + gap);
      final y = (size.height - h) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, h),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ThumbnailPainter oldDelegate) =>
      oldDelegate.amps != amps || oldDelegate.color != color;
}
