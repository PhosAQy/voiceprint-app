import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// 录音详情页的波形概览：左侧已播放（蓝），右侧未播放（灰），中央有播放头
class WaveformOverview extends StatelessWidget {
  /// 0.0–1.0 振幅数组
  final List<double> amplitudes;

  /// 0.0–1.0 播放进度
  final double progress;

  final double height;

  const WaveformOverview({
    super.key,
    required this.amplitudes,
    required this.progress,
    this.height = 60,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _OverviewPainter(amplitudes, progress),
      ),
    );
  }
}

class _OverviewPainter extends CustomPainter {
  final List<double> amps;
  final double progress;
  _OverviewPainter(this.amps, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final n = amps.length;
    if (n == 0) return;
    const gap = 3.0;
    final barWidth = (size.width - gap * (n - 1)) / n;
    final playX = progress * size.width;

    final playedPaint = Paint()..color = VpTokens.primary;
    final unplayedPaint = Paint()..color = VpTokens.border;

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
        x <= playX ? playedPaint : unplayedPaint,
      );
    }

    // 播放头：竖线 + 顶部小圆
    final linePaint = Paint()
      ..color = VpTokens.primary.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(playX, 2),
      Offset(playX, size.height - 2),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _OverviewPainter oldDelegate) =>
      oldDelegate.amps != amps || oldDelegate.progress != progress;
}
