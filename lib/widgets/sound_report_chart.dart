import 'package:flutter/material.dart';
import '../models/recording.dart';
import '../theme/tokens.dart';

/// 录音详情页的「声音报告」图：4 层堆叠柱状图 + 音高曲线叠加
class SoundReportChart extends StatelessWidget {
  final List<List<double>> stack; // 每段 [胸腔, 鼻腔, 头腔, 大白嗓]
  final List<double> pitch; // 音高 0.0–1.0
  final List<Color> layerColors;
  final List<String> layerLabels;

  const SoundReportChart({
    super.key,
    required this.stack,
    required this.pitch,
    this.layerColors = SoundReportConfig.layerColors,
    this.layerLabels = SoundReportConfig.layerLabels,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 320 / 240,
          child: CustomPaint(
            size: Size.infinite,
            painter: _ChartPainter(
              stack: stack,
              pitch: pitch,
              layerColors: layerColors,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _Legend(
          layerColors: layerColors,
          layerLabels: layerLabels,
        ),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<List<double>> stack;
  final List<double> pitch;
  final List<Color> layerColors;

  _ChartPainter({
    required this.stack,
    required this.pitch,
    required this.layerColors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 留白：左 28（百分比）右 32（音名）上 8 下 22（时间标签）
    final left = 28.0;
    final right = size.width - 32;
    final top = 8.0;
    final bottom = size.height - 22;
    final plotW = right - left;
    final plotH = bottom - top;

    // 网格线（25% / 50% / 75% / 100%）— 虚线 3-3
    final gridPaint = Paint()
      ..color = VpTokens.chartGrid
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i <= 4; i++) {
      final y = top + plotH * (i / 4);
      _drawDashedLine(canvas, Offset(left, y), Offset(right, y), gridPaint, dash: 3, gap: 3);
    }
    // 0% 实线
    final basePaint = Paint()
      ..color = VpTokens.chartGridStrong
      ..strokeWidth = 1;
    canvas.drawLine(Offset(left, bottom), Offset(right, bottom), basePaint);

    // Y 轴左标签
    const pctLabels = ['100%', '75%', '50%', '25%', '0%'];
    final pctStyle = TextStyle(
      fontSize: 10,
      color: VpTokens.textTertiary,
      fontFamily: 'SF Mono',
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    for (var i = 0; i < pctLabels.length; i++) {
      final y = top + plotH * (i / 4);
      _drawText(
        canvas,
        pctLabels[i],
        Offset(left - 4, y),
        pctStyle,
        align: TextAlign.right,
        vcenter: true,
      );
    }

    // Y 轴右标签（音名）
    const noteLabels = ['C5', 'C4', 'C3'];
    for (var i = 0; i < noteLabels.length; i++) {
      final y = top + plotH * (i / 2);
      _drawText(
        canvas,
        noteLabels[i],
        Offset(right + 4, y),
        pctStyle,
        align: TextAlign.left,
        vcenter: true,
      );
    }

    // 堆叠柱状图
    final n = stack.length;
    final gap = 1.0;
    final barW = (plotW - gap * (n - 1)) / n;
    for (var i = 0; i < n; i++) {
      final seg = stack[i];
      final x = left + i * (barW + gap);
      var yCursor = bottom;
      // 顺序：从下到上 = 胸腔 → 鼻腔 → 头腔 → 大白嗓
      for (var j = 0; j < seg.length; j++) {
        final h = seg[j] * plotH;
        yCursor -= h;
        canvas.drawRect(
          Rect.fromLTWH(x, yCursor, barW, h),
          Paint()..color = layerColors[j],
        );
      }
    }

    // 音高曲线（C3–C5：归一化 0.0=C3 底部，1.0=C5 顶部）
    final pitchPts = <Offset>[];
    for (var i = 0; i < pitch.length; i++) {
      final x = left + (i + 0.5) * (plotW / pitch.length);
      // 顶部=1.0 → y=top；底部=0.0 → y=bottom
      final y = top + plotH * (1.0 - pitch[i]);
      pitchPts.add(Offset(x, y));
    }
    final linePaint = Paint()
      ..color = VpTokens.chartAnnotation
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(pitchPts.first.dx, pitchPts.first.dy);
    for (var i = 1; i < pitchPts.length; i++) {
      path.lineTo(pitchPts[i].dx, pitchPts[i].dy);
    }
    canvas.drawPath(path, linePaint);

    // 数据点
    final dotPaint = Paint()..color = VpTokens.chartAnnotation;
    for (final p in pitchPts) {
      canvas.drawCircle(p, 2.5, dotPaint);
    }

    // X 轴时间标签
    const timeLabels = ['0:00', '0:30', '1:00', '1:30', '2:00', '2:30', '3:00', '3:30'];
    final timeStyle = TextStyle(
      fontSize: 10,
      color: VpTokens.textTertiary,
      fontFamily: 'SF Mono',
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    for (var i = 0; i < timeLabels.length; i++) {
      final x = left + plotW * (i / (timeLabels.length - 1));
      _drawText(
        canvas,
        timeLabels[i],
        Offset(x, bottom + 6),
        timeStyle,
        align: TextAlign.center,
      );
    }
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint, {
    double dash = 3,
    double gap = 3,
  }) {
    final total = (end - start).distance;
    final dx = (end.dx - start.dx) / total;
    final dy = (end.dy - start.dy) / total;
    var pos = 0.0;
    var on = true;
    while (pos < total) {
      final step = on ? dash : gap;
      final next = (pos + step).clamp(0.0, total);
      if (on) {
        canvas.drawLine(
          Offset(start.dx + dx * pos, start.dy + dy * pos),
          Offset(start.dx + dx * next, start.dy + dy * next),
          paint,
        );
      }
      pos = next;
      on = !on;
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    TextStyle style, {
    TextAlign align = TextAlign.left,
    bool vcenter = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout();
    var dx = offset.dx;
    if (align == TextAlign.right) dx = offset.dx - tp.width;
    if (align == TextAlign.center) dx = offset.dx - tp.width / 2;
    final dy = vcenter ? offset.dy - tp.height / 2 : offset.dy;
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) =>
      oldDelegate.stack != stack || oldDelegate.pitch != pitch;
}

class _Legend extends StatelessWidget {
  final List<Color> layerColors;
  final List<String> layerLabels;

  const _Legend({
    required this.layerColors,
    required this.layerLabels,
  });

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    // 第一个：音高（用线 + 点）
    items.add(_LegendItem(
      icon: _LineIcon(color: VpTokens.chartAnnotation),
      label: '音高',
    ));
    for (var i = 0; i < layerLabels.length; i++) {
      items.add(_LegendItem(
        icon: _SwatchIcon(color: layerColors[i]),
        label: layerLabels[i],
      ));
    }
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: items,
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Widget icon;
  final String label;
  const _LegendItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: VpTokens.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _SwatchIcon extends StatelessWidget {
  final Color color;
  const _SwatchIcon({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _LineIcon extends StatelessWidget {
  final Color color;
  const _LineIcon({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 10,
      child: CustomPaint(painter: _LineIconPainter(color)),
    );
  }
}

class _LineIconPainter extends CustomPainter {
  final Color color;
  _LineIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset.zero, Offset(size.width, size.height / 2), paint);
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      2.5,
      paint..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _LineIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
