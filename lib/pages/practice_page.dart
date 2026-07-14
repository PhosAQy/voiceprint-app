import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../services/recording_service.dart';
import '../theme/tokens.dart';
import '../widgets/vp_controls.dart';
import '../widgets/vp_record_button.dart';

/// 练习页 — 实时耳返设置 + 真实录音
class PracticePage extends StatefulWidget {
  final VoidCallback onRecordingComplete;
  final VoidCallback onOpenRecordings;

  const PracticePage({
    super.key,
    required this.onRecordingComplete,
    required this.onOpenRecordings,
  });

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage>
    with TickerProviderStateMixin {
  final RecordingService _recordingService = RecordingService();

  bool _isRecording = false;
  bool _isAnalyzing = false;
  Duration _recordDuration = Duration.zero;
  Timer? _timer;

  // 耳返设置
  bool _earOn = true;
  int _reverbIndex = 1;
  int _micIndex = 1;
  double _dryWet = 0.30;
  double _decay = 0.40;
  double _preDelay = 0.33;
  double _monitorVol = 0.75;
  double _eqLow = 0.58;
  double _eqMid = 0.50;
  double _eqHigh = 0.42;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _onRecordTap() async {
    if (_isAnalyzing) return;

    if (_isRecording) {
      // 停止录音
      _timer?.cancel();
      setState(() {
        _isRecording = false;
        _isAnalyzing = true;
      });

      final recording = await _recordingService.stop();

      if (mounted) {
        setState(() => _isAnalyzing = false);
        if (recording != null) {
          widget.onRecordingComplete();
        } else {
          _showMessage('录音太短，无法分析');
        }
      }
    } else {
      // 开始录音
      final started = await _recordingService.start();
      if (!mounted) return;

      if (!started) {
        _showPermissionDialog();
        return;
      }

      setState(() {
        _isRecording = true;
        _recordDuration = Duration.zero;
      });

      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _recordDuration += const Duration(seconds: 1));
        }
      });
    }
  }

  void _showPermissionDialog() {
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('需要麦克风权限'),
        content: const Text('请在设置中允许「声纹」访问麦克风，以使用录音功能。'),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('去设置'),
            onPressed: () {
              Navigator.pop(ctx);
              // 跳转到系统设置（简化处理）
            },
          ),
        ],
      ),
    );
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VpTokens.bg,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 4,
                      bottom: 200,
                    ),
                    children: [_buildEarCard()],
                  ),
                ),
              ],
            ),
            // 悬浮录音按钮
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(
                child: VpRecordButton(
                  onTap: _onRecordTap,
                  recording: _isRecording,
                ),
              ),
            ),
            // 录音中遮罩
            if (_isRecording) _buildRecordingOverlay(),
            // 分析中遮罩
            if (_isAnalyzing) _buildAnalyzingOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingOverlay() {
    return Positioned.fill(
      child: Container(
        color: const Color(0xDD000000),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 脉冲红点
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.8, end: 1.3),
              duration: const Duration(milliseconds: 800),
              builder: (context, scale, child) {
                return Transform.scale(scale: scale, child: child);
              },
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: VpTokens.error,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '录音中',
              style: TextStyle(
                fontSize: 17,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _fmtDuration(_recordDuration),
              style: const TextStyle(
                fontSize: 48,
                color: Colors.white,
                fontFamily: 'SF Mono',
                fontFeatures: [FontFeature.tabularFigures()],
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 40),
            // 停止按钮
            GestureDetector(
              onTap: _onRecordTap,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: VpTokens.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white54, width: 4),
                ),
                child: const Icon(
                  Icons.stop_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyzingOverlay() {
    return Positioned.fill(
      child: Container(
        color: const Color(0xDD000000),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CupertinoActivityIndicator(color: Colors.white, radius: 16),
            SizedBox(height: 20),
            Text(
              '正在分析声音...',
              style: TextStyle(
                fontSize: 17,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '提取波形 · 音高 · 共鸣比例',
              style: TextStyle(fontSize: 13, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return SizedBox(
      height: 44,
      child: const Center(
        child: Text(
          '声纹',
          style: TextStyle(
            fontSize: 17,
            fontWeight: VpTokens.wSemibold,
            color: VpTokens.textPrimary,
            letterSpacing: -0.02,
          ),
        ),
      ),
    );
  }

  Widget _buildEarCard() {
    return VpCard(
      sections: [
        _buildEarHeader(),
        _buildReverbSection(),
        _buildMonitorVolume(),
        _buildMicAndEQ(),
      ],
    );
  }

  Widget _buildEarHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '实时耳返',
              style: TextStyle(
                fontSize: 17,
                fontWeight: VpTokens.wSemibold,
                color: VpTokens.textPrimary,
                letterSpacing: -0.02,
              ),
            ),
            VpToggle(value: _earOn, onChanged: (v) => setState(() => _earOn = v)),
          ],
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(height: 0),
          secondChild: Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: VpTokens.surfaceTertiary,
              borderRadius: BorderRadius.circular(VpTokens.radiusMd),
            ),
            child: const Row(
              children: [
                Icon(CupertinoIcons.mic_slash_fill, size: 18, color: VpTokens.textTertiary),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '开启耳返以实时监听你的声音',
                    style: TextStyle(fontSize: 13, color: VpTokens.textTertiary),
                  ),
                ),
              ],
            ),
          ),
          crossFadeState: _earOn ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }

  Widget _buildReverbSection() {
    final reverbs = <_Reverb>[
      _Reverb(name: '原声', icon: CupertinoIcons.speaker_2_fill),
      _Reverb(name: '录音室', icon: CupertinoIcons.mic_fill),
      _Reverb(name: '大厅', icon: CupertinoIcons.building_2_fill),
      _Reverb(name: 'KTV', icon: CupertinoIcons.music_note),
      _Reverb(name: '演唱会', icon: CupertinoIcons.star_fill),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: VpSectionLabel('混响效果'),
        ),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.1,
          children: [
            for (var i = 0; i < reverbs.length; i++)
              _ReverbCard(
                reverb: reverbs[i],
                selected: _reverbIndex == i,
                onTap: () => setState(() => _reverbIndex = i),
              ),
          ],
        ),
        const SizedBox(height: 18),
        VpSliderRow(
          label: '干湿比',
          value: _dryWet,
          valueLabel: '${(_dryWet * 100).round()}%',
          onChanged: (v) => setState(() => _dryWet = v),
        ),
        const SizedBox(height: 14),
        VpSliderRow(
          label: '衰减时间',
          value: _decay,
          valueLabel: '${(_decay * 3).toStringAsFixed(1)}s',
          onChanged: (v) => setState(() => _decay = v),
        ),
        const SizedBox(height: 14),
        VpSliderRow(
          label: '预延迟',
          value: _preDelay,
          valueLabel: '${(_preDelay * 60).round()}ms',
          onChanged: (v) => setState(() => _preDelay = v),
        ),
      ],
    );
  }

  Widget _buildMonitorVolume() {
    return VpSliderRow(
      label: '监听音量',
      value: _monitorVol,
      valueLabel: '${(_monitorVol * 100).round()}%',
      onChanged: (v) => setState(() => _monitorVol = v),
    );
  }

  Widget _buildMicAndEQ() {
    const mics = ['动圈', '电容', '屏幕麦'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: VpSectionLabel('麦克风模拟'),
        ),
        Wrap(
          spacing: 8,
          children: [
            for (var i = 0; i < mics.length; i++)
              VpChip(
                label: mics[i],
                selected: _micIndex == i,
                onTap: () => setState(() => _micIndex = i),
              ),
          ],
        ),
        const SizedBox(height: 16),
        VpSliderRow(
          label: '低频',
          value: _eqLow,
          valueLabel: _eqLabel(_eqLow),
          onChanged: (v) => setState(() => _eqLow = v),
          centerOrigin: true,
        ),
        const SizedBox(height: 14),
        VpSliderRow(
          label: '中频',
          value: _eqMid,
          valueLabel: _eqLabel(_eqMid),
          onChanged: (v) => setState(() => _eqMid = v),
          centerOrigin: true,
        ),
        const SizedBox(height: 14),
        VpSliderRow(
          label: '高频',
          value: _eqHigh,
          valueLabel: _eqLabel(_eqHigh),
          onChanged: (v) => setState(() => _eqHigh = v),
          centerOrigin: true,
        ),
      ],
    );
  }

  String _eqLabel(double v) {
    final db = ((v - 0.5) * 24).round();
    if (db == 0) return '0dB';
    return '${db > 0 ? '+' : ''}$db dB';
  }
}

class _Reverb {
  final String name;
  final IconData icon;
  const _Reverb({required this.name, required this.icon});
}

class _ReverbCard extends StatelessWidget {
  final _Reverb reverb;
  final bool selected;
  final VoidCallback onTap;

  const _ReverbCard({
    required this.reverb,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? VpTokens.primary : VpTokens.textSecondary;
    final bg = selected ? VpTokens.primary50 : VpTokens.surface;
    final bd = selected ? VpTokens.primary : VpTokens.borderLight;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VpTokens.radiusMd),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(VpTokens.radiusMd),
            border: Border.all(color: bd),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(reverb.icon, size: 22, color: color),
              const SizedBox(height: 6),
              Text(
                reverb.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: VpTokens.wMedium,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
