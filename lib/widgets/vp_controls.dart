import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// iOS 风格的卡片容器 — 与设计稿 .vp-card 一致
class VpCard extends StatelessWidget {
  final List<Widget> sections;
  final EdgeInsets padding;
  final double radius;

  const VpCard({
    super.key,
    required this.sections,
    this.padding = const EdgeInsets.all(16),
    this.radius = VpTokens.radiusLg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: VpTokens.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: VpTokens.borderLight),
        boxShadow: VpTokens.shadowSm,
      ),
      child: Column(
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            Padding(padding: padding, child: sections[i]),
            if (i != sections.length - 1)
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 0),
                color: VpTokens.borderLight,
              ),
          ],
        ],
      ),
    );
  }
}

/// 小标题 — 例如 "混响效果"、"麦克风模拟"
class VpSectionLabel extends StatelessWidget {
  final String text;
  const VpSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: VpTokens.wSemibold,
        color: VpTokens.textSecondary,
        letterSpacing: -0.01,
        height: 1.2,
      ),
    );
  }
}

/// iOS 风格的 Toggle 开关（直接使用 CupertinoSwitch）
class VpToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? activeColor;

  const VpToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 51,
      height: 31,
      child: FittedBox(
        child: CupertinoSwitch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: activeColor ?? VpTokens.success,
        ),
      ),
    );
  }
}

/// 芯片选择器
class VpChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const VpChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? VpTokens.primary50 : VpTokens.surface;
    final fg = selected ? VpTokens.primary : VpTokens.textSecondary;
    final bd = selected ? VpTokens.primary : VpTokens.border;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VpTokens.radiusFull),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(VpTokens.radiusFull),
            border: Border.all(color: bd),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: fg,
              fontWeight: selected ? VpTokens.wMedium : VpTokens.wRegular,
            ),
          ),
        ),
      ),
    );
  }
}

/// 一行带标签 + 数值的滑块
class VpSliderRow extends StatelessWidget {
  final String label;
  final double value; // 0.0–1.0
  final String valueLabel;
  final ValueChanged<double> onChanged;
  final bool centerOrigin; // EQ 风格：中心为 0

  const VpSliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.valueLabel,
    required this.onChanged,
    this.centerOrigin = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: centerOrigin ? 40 : 56,
          child: Text(
            label,
            style: TextStyle(
              fontSize: centerOrigin ? 13.0 : 14.0,
              color: VpTokens.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _Track(
            value: value,
            centerOrigin: centerOrigin,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: centerOrigin ? 52 : 48,
          child: Text(
            valueLabel,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 13,
              color: VpTokens.textSecondary,
              fontFamily: 'SF Mono',
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _Track extends StatelessWidget {
  final double value;
  final bool centerOrigin;
  final ValueChanged<double> onChanged;

  const _Track({
    required this.value,
    required this.centerOrigin,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (d) {
            final delta = d.delta.dx / trackWidth;
            onChanged((value + delta).clamp(0.0, 1.0));
          },
          onTapDown: (d) {
            final v = d.localPosition.dx / trackWidth;
            onChanged(v.clamp(0.0, 1.0));
          },
          child: SizedBox(
            height: 24,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // 轨道
                Container(
                  height: 4,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: VpTokens.borderLight,
                    borderRadius: BorderRadius.circular(VpTokens.radiusFull),
                  ),
                ),
                // 填充
                if (centerOrigin) ...[
                  // 中心标记
                  Positioned(
                    left: trackWidth / 2 - 1,
                    child: Container(
                      width: 2,
                      height: 10,
                      decoration: BoxDecoration(
                        color: VpTokens.borderStrong,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                  // 填充：从中心向 knob 方向延伸
                  Positioned(
                    left: value >= 0.5
                        ? trackWidth / 2
                        : value * trackWidth,
                    child: Container(
                      height: 4,
                      width: (value - 0.5).abs() * trackWidth,
                      decoration: BoxDecoration(
                        color: VpTokens.primary,
                        borderRadius: BorderRadius.circular(VpTokens.radiusFull),
                      ),
                    ),
                  ),
                ] else
                  Positioned(
                    left: 0,
                    child: Container(
                      height: 4,
                      width: value * trackWidth,
                      decoration: BoxDecoration(
                        color: VpTokens.primary,
                        borderRadius: BorderRadius.circular(VpTokens.radiusFull),
                      ),
                    ),
                  ),
                // Knob
                Positioned(
                  left: (value * trackWidth) - 11,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: VpTokens.surface,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x14000000),
                          offset: Offset(0, 1),
                          blurRadius: 3,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
