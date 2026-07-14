import 'package:flutter/material.dart';
import '../models/recording.dart';
import '../theme/tokens.dart';

/// 录音详情页的「声音报告」图：4 层堆叠平滑面积图 + 音高平滑曲线叠加
class SoundReportChart extends StatelessWidget {
  final List<List<double>> stack; // 每段 [胸腔, 鼻腔, 头腔, 大白嗓]
  final List<double> pitch; // 音高 0.0–1.0（密集采样）
  final Duration duration; // 音频总时长 — 用于动态生成时间轴
  final List<Color> layerColors;
  final List<String> layerLabels;

  const SoundReportChart({
    super.key,
    required this.stack,
    required this.pitch,
    required this.duration,
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
              duration: duration,
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
  final Duration duration;
  final List<Color> layerColors;

  _ChartPainter({
    required this.stack,
    required this.pitch,
    required this.duration,
    required this.layerColors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final left = 28.0;
    final right = size.width - 32;
    final top = 8.0;
    final bottom = size.height - 22;
    final plotW = right - left;
    final plotH = bottom - top;

    // 网格线 — 虚线 3-3
    final gridPaint = Paint()
      ..color = VpTokens.chartGrid
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i <= 4; i++) {
      final y = top + plotH * (i / 4);
      _drawDashedLine(canvas, Offset(left, y), Offset(right, y), gridPaint, dash: 3, gap: 3);
    }
    final basePaint = Paint()
      ..color = VpTokens.chartGridStrong
      ..strokeWidth = 1;
    canvas.drawLine(Offset(left, bottom), Offset(right, bottom), basePaint);

    // Y 轴左标签
    const pctLabels = ['100%', '75%', '50%', '25%', '0%'];
    final labelStyle = TextStyle(
      fontSize: 10,
      color: VpTokens.textTertiary,
      fontFamily: 'SF Mono',
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    for (var i = 0; i < pctLabels.length; i++) {
      final y = top + plotH * (i / 4);
      _drawText(canvas, pctLabels[i], Offset(left - 4, y), labelStyle,
          align: TextAlign.right, vcenter: true);
    }

    // Y 轴右标签（音名）
    const noteLabels = ['C5', 'C4', 'C3'];
    for (var i = 0; i < noteLabels.length; i++) {
      final y = top + plotH * (i / 2);
      _drawText(canvas, noteLabels[i], Offset(right + 4, y), labelStyle,
          align: TextAlign.left, vcenter: true);
    }

    // 堆叠平滑面积图 — 每层 Catmull-Rom 平滑曲线，连续不分段
    _drawStackedArea(canvas, left, right, bottom, plotW, plotH);

    // 音高曲线 — Catmull-Rom 平滑贝塞尔
    _drawPitchCurve(canvas, left, right, top, plotW, plotH);

    // X 轴时间标签 — 动态生成
    final timeLabels = _genTimeLabels(duration);
    final timeStyle = TextStyle(
      fontSize: 10,
      color: VpTokens.textTertiary,
      fontFamily: 'SF Mono',
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    for (var i = 0; i < timeLabels.length; i++) {
      final x = left + plotW * (i / (timeLabels.length - 1));
      _drawText(canvas, timeLabels[i], Offset(x, bottom + 6), timeStyle,
          align: TextAlign.center);
    }
  }

  /// 绘制堆叠平滑面积图
  void _drawStackedArea(
      Canvas canvas, double left, double right, double bottom, double plotW, double plotH) {
    final n = stack.length;
    if (n == 0) return;

    const layerCount = 4;
    // x 坐标：首尾对齐左右边界
    double xAt(int i) =>
        n > 1 ? left + i * plotW / (n - 1) : left + plotW / 2;

    // 计算每段每层的累积上边界 y 值
    // bounds[i] = [bottom, 胸腔顶, 鼻腔顶, 头腔顶, 大白嗓顶]
    final bounds = List.generate(n, (i) {
      final seg = stack[i];
      var y = bottom;
      final ys = <double>[y];
      for (var j = 0; j < layerCount; j++) {
        y -= seg[j] * plotH;
        ys.add(y);
      }
      return ys;
    });

    for (var layer = 0; layer < layerCount; layer++) {
      // 上边界点（该层顶部）
      final topPts = <Offset>[];
      for (var i = 0; i < n; i++) {
        topPts.add(Offset(xAt(i), bounds[i][layer + 1]));
      }

      final path = Path();
      // 上边界 — 平滑曲线
      _addSmoothCurve(path, topPts);
      // 下边界 — 反向直线回到起点
      for (var i = n - 1; i >= 0; i--) {
        path.lineTo(xAt(i), bounds[i][layer]);
      }
      path.close();

      canvas.drawPath(path, Paint()..color = layerColors[layer]);
    }
  }

  /// 绘制音高平滑曲线
  void _drawPitchCurve(
      Canvas canvas, double left, double right, double top, double plotW, double plotH) {
    if (pitch.length < 2) return;

    double xAt(int i) =>
        pitch.length > 1 ? left + i * plotW / (pitch.length - 1) : left + plotW / 2;

    final pitchPts = <Offset>[];
    for (var i = 0; i < pitch.length; i++) {
      final y = top + plotH * (1.0 - pitch[i]);
      pitchPts.add(Offset(xAt(i), y));
    }

    final linePaint = Paint()
      ..color = VpTokens.chartAnnotation
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    _addSmoothCurve(path, pitchPts);
    canvas.drawPath(path, linePaint);

    // 密集采样时只画首尾点
    final dotPaint = Paint()..color = VpTokens.chartAnnotation;
    if (pitchPts.length <= 30) {
      for (final p in pitchPts) {
        canvas.drawCircle(p, 2.5, dotPaint);
      }
    } else {
      canvas.drawCircle(pitchPts.first, 2.5, dotPaint);
      canvas.drawCircle(pitchPts.last, 2.5, dotPaint);
    }
  }

  /// Catmull-Rom 平滑曲线 — 添加到已有 path
  void _addSmoothCurve(Path path, List<Offset> pts) {
    if (pts.length < 2) {
      if (pts.length == 1) {
        path.moveTo(pts[0].dx, pts[0].dy);
      }
      return;
    }
    path.moveTo(pts[0].dx, pts[0].dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = i > 0 ? pts[i - 1] : pts[i];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = i + 2 < pts.length ? pts[i + 2] : p2;
      final c1x = p1.dx + (p2.dx - p0.dx) / 6;
      final c1y = p1.dy + (p2.dy - p0.dy) / 6;
      final c2x = p2.dx - (p3.dx - p1.dx) / 6;
      final c2y = p2.dy - (p3.dy - p1.dy) / 6;
      path.cubicTo(c1x, c1y, c2x, c2y, p2.dx, p2.dy);
    }
  }

  /// 根据时长动态生成时间轴标签
  List<String> _genTimeLabels(Duration d) {
    final totalSec = d.inSeconds;
    if (totalSec <= 0) return ['0:00'];

    int count;
    if (totalSec <= 20) {
      count = 4;
    } else if (totalSec <= 30) {
      count = 5;
    } else if (totalSec <= 60) {
      count = 6;
    } else if (totalSec <= 180) {
      count = 6;
    } else {
      count = 5;
    }

    final labels = <String>[];
    for (var i = 0; i <= count; i++) {
      final t = (totalSec * i / count).round();
      final m = t ~/ 60;
      final s = t % 60;
      labels.add('$m:${s.toString().padLeft(2, '0')}');
    }
    return labels;
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
      oldDelegate.stack != stack ||
      oldDelegate.pitch != pitch ||
      oldDelegate.duration != duration;
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
