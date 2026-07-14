import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// 声纹底部导航 — 与设计稿一致的 2 Tab 结构（练习 / 录音记录）
///
/// 选中态：图标填充 + 染主色；非选中态：图标描边 + 灰色。
enum VpTab { practice, recordings, settings }

class VpTabBar extends StatelessWidget {
  final VpTab active;
  final ValueChanged<VpTab> onTap;

  const VpTabBar({super.key, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: VpTokens.surface,
        border: Border(
          top: BorderSide(color: VpTokens.borderLight, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: VpTokens.tabBarItemHeight,
          child: Row(
            children: [
              Expanded(
                child: _TabItem(
                  label: '练习',
                  active: active == VpTab.practice,
                  iconOutline: const _MicOutlineIcon(),
                  iconFilled: const _MicFilledIcon(),
                  onTap: () => onTap(VpTab.practice),
                ),
              ),
              Expanded(
                child: _TabItem(
                  label: '录音记录',
                  active: active == VpTab.recordings,
                  iconOutline: const _FolderOutlineIcon(),
                  iconFilled: const _FolderFilledIcon(),
                  onTap: () => onTap(VpTab.recordings),
                ),
              ),
              Expanded(
                child: _TabItem(
                  label: '设置',
                  active: active == VpTab.settings,
                  iconOutline: const _GearOutlineIcon(),
                  iconFilled: const _GearFilledIcon(),
                  onTap: () => onTap(VpTab.settings),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  final String label;
  final bool active;
  final Widget iconOutline;
  final Widget iconFilled;
  final VoidCallback onTap;

  const _TabItem({
    required this.label,
    required this.active,
    required this.iconOutline,
    required this.iconFilled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? VpTokens.primary : VpTokens.textSecondary;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: IconTheme(
              data: IconThemeData(color: color),
              child: active ? iconFilled : iconOutline,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: VpTokens.wMedium,
              color: color,
              letterSpacing: -0.01,
            ),
          ),
        ],
      ),
    );
  }
}

// ===== 麦克风图标 =====
class _MicOutlineIcon extends StatelessWidget {
  const _MicOutlineIcon();

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color;
    return CustomPaint(
      size: const Size(24, 24),
      painter: _MicOutlinePainter(color ?? VpTokens.textSecondary),
    );
  }
}

class _MicOutlinePainter extends CustomPainter {
  final Color color;
  _MicOutlinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final rect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(9, 2, 6, 12),
      const Radius.circular(3),
    );
    canvas.drawRRect(rect, paint);
    final path = Path()
      ..moveTo(5, 10)
      ..lineTo(5, 12)
      ..arcToPoint(const Offset(19, 12),
          radius: const Radius.circular(7), clockwise: false)
      ..lineTo(19, 10);
    canvas.drawPath(path, paint);
    canvas.drawLine(const Offset(12, 19), const Offset(12, 22), paint);
    canvas.drawLine(const Offset(8, 22), const Offset(16, 22), paint);
  }

  @override
  bool shouldRepaint(covariant _MicOutlinePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _MicFilledIcon extends StatelessWidget {
  const _MicFilledIcon();

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color;
    return CustomPaint(
      size: const Size(24, 24),
      painter: _MicFilledPainter(color ?? VpTokens.primary),
    );
  }
}

class _MicFilledPainter extends CustomPainter {
  final Color color;
  _MicFilledPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final rect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(9, 2, 6, 12),
      const Radius.circular(3),
    );
    canvas.drawRRect(rect, fill);
    final path = Path()
      ..moveTo(5, 10)
      ..lineTo(5, 12)
      ..arcToPoint(const Offset(19, 12),
          radius: const Radius.circular(7), clockwise: false)
      ..lineTo(19, 10);
    canvas.drawPath(path, stroke);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(11, 19, 2, 3),
        const Radius.circular(1),
      ),
      fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(8, 21, 8, 2),
        const Radius.circular(1),
      ),
      fill,
    );
  }

  @override
  bool shouldRepaint(covariant _MicFilledPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ===== 文件夹图标 =====
class _FolderOutlineIcon extends StatelessWidget {
  const _FolderOutlineIcon();

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color;
    return CustomPaint(
      size: const Size(24, 24),
      painter: _FolderOutlinePainter(color ?? VpTokens.textSecondary),
    );
  }
}

class _FolderOutlinePainter extends CustomPainter {
  final Color color;
  _FolderOutlinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(3, 7)
      ..relativeLineTo(0, 12)
      ..relativeCubicTo(0, 0.55, 0.45, 1, 1, 1)
      ..relativeLineTo(16, 0)
      ..relativeCubicTo(0.55, 0, 1, -0.45, 1, -1)
      ..relativeLineTo(0, -10)
      ..relativeCubicTo(0, -0.55, -0.45, -1, -1, -1)
      ..relativeLineTo(-9, 0)
      ..relativeLineTo(-2, -3)
      ..relativeLineTo(-3, 0)
      ..relativeCubicTo(-0.55, 0, -1, 0.45, -1, 1)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _FolderOutlinePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _FolderFilledIcon extends StatelessWidget {
  const _FolderFilledIcon();

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color;
    return CustomPaint(
      size: const Size(24, 24),
      painter: _FolderFilledPainter(color ?? VpTokens.primary),
    );
  }
}

class _FolderFilledPainter extends CustomPainter {
  final Color color;
  _FolderFilledPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(3, 7)
      ..relativeLineTo(0, 12)
      ..relativeCubicTo(0, 0.55, 0.45, 1, 1, 1)
      ..relativeLineTo(16, 0)
      ..relativeCubicTo(0.55, 0, 1, -0.45, 1, -1)
      ..relativeLineTo(0, -10)
      ..relativeCubicTo(0, -0.55, -0.45, -1, -1, -1)
      ..relativeLineTo(-9, 0)
      ..relativeLineTo(-2, -3)
      ..relativeLineTo(-3, 0)
      ..relativeCubicTo(-0.55, 0, -1, 0.45, -1, 1)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _FolderFilledPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ===== 齿轮图标 =====
class _GearOutlineIcon extends StatelessWidget {
  const _GearOutlineIcon();

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color;
    return Icon(Icons.settings_outlined, size: 24, color: color);
  }
}

class _GearFilledIcon extends StatelessWidget {
  const _GearFilledIcon();

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color;
    return Icon(Icons.settings, size: 24, color: color);
  }
}
