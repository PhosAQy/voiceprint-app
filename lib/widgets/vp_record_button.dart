import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// 悬浮录音按钮 — 红色圆，带脉冲动画
/// recording=true 时显示停止图标
class VpRecordButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool recording;

  const VpRecordButton({
    super.key,
    required this.onTap,
    this.recording = false,
  });

  @override
  State<VpRecordButton> createState() => _VpRecordButtonState();
}

class _VpRecordButtonState extends State<VpRecordButton>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ScaleTransition(
          scale: Tween(begin: 1.0, end: 1.06).animate(
            CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
          ),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: VpTokens.error,
                shape: BoxShape.circle,
                border: Border.all(color: VpTokens.surface, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: VpTokens.borderLight.withValues(alpha: 1),
                    offset: const Offset(0, 0),
                    blurRadius: 0,
                    spreadRadius: 1,
                  ),
                  ...VpTokens.shadowLg,
                ],
              ),
              child: widget.recording
                  ? const Icon(
                      Icons.stop_rounded,
                      color: VpTokens.textInverse,
                      size: 36,
                    )
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.recording ? '停止' : '点击录音',
          style: const TextStyle(
            fontSize: 13,
            color: VpTokens.textSecondary,
          ),
        ),
      ],
    );
  }
}
