import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/recording.dart';
import '../services/playback_service.dart';
import '../services/recording_service.dart';
import '../theme/tokens.dart';
import '../widgets/sound_report_chart.dart';
import '../widgets/waveform_overview.dart';

/// 录音详情页 — 真实播放 + 真实声音报告
class RecordingDetailPage extends StatefulWidget {
  final Recording recording;
  final VoidCallback onBack;
  final VoidCallback? onDeleted;

  const RecordingDetailPage({
    super.key,
    required this.recording,
    required this.onBack,
    this.onDeleted,
  });

  @override
  State<RecordingDetailPage> createState() => _RecordingDetailPageState();
}

class _RecordingDetailPageState extends State<RecordingDetailPage> {
  final PlaybackService _playback = PlaybackService();
  final RecordingService _recordingService = RecordingService();
  StreamSubscription<PlaybackState>? _sub;

  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _duration = widget.recording.duration;
    _sub = _playback.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.isPlaying;
          _position = state.position;
          if (state.duration.inMilliseconds > 0) {
            _duration = state.duration;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _playback.stop();
    super.dispose();
  }

  double get _progress =>
      _duration.inMilliseconds > 0
          ? (_position.inMilliseconds / _duration.inMilliseconds)
              .clamp(0.0, 1.0)
          : 0.0;

  void _togglePlay() {
    _playback.togglePlay(widget.recording.filePath);
  }

  void _seekTo(double fraction) {
    final pos = Duration(
      milliseconds: (fraction * _duration.inMilliseconds).round(),
    );
    _playback.seek(pos);
  }

  void _exportRecording() async {
    // 复制 WAV 文件到剪贴板路径并提示
    await Clipboard.setData(
      ClipboardData(text: widget.recording.filePath),
    );
    if (mounted) {
      showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('录音文件'),
          content: Text(
            '文件路径已复制到剪贴板：\n${widget.recording.filePath}',
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              child: const Text('好'),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      );
    }
  }

  void _deleteRecording() {
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('删除录音'),
        content: const Text('确定删除这条录音吗？此操作不可撤销。'),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('删除'),
            onPressed: () async {
              Navigator.pop(ctx);
              if (widget.recording.id != null) {
                await _recordingService.deleteRecording(widget.recording.id!);
              }
              if (mounted) {
                widget.onDeleted?.call();
                widget.onBack();
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.recording;
    final pos = _position;
    final datePart = r.dateTimeLabel.split(' ').first;

    return Scaffold(
      backgroundColor: VpTokens.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(datePart),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        Text(
                          '2026.${r.dateTimeLabel}',
                          style: _mono(13, VpTokens.textSecondary),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            '·',
                            style: TextStyle(color: VpTokens.textTertiary),
                          ),
                        ),
                        Text(
                          '时长 ${r.durationLabel}',
                          style: _mono(13, VpTokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildPlayerCard(pos),
                  const SizedBox(height: 12),
                  _buildSoundReport(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          label: '编辑混响',
                          primary: true,
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('请返回练习页调整混响设置后重新录制'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ActionButton(
                          label: '导出',
                          primary: false,
                          onTap: _exportRecording,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String datePart) {
    return Container(
      height: 44,
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: VpTokens.borderLight, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(
                  CupertinoIcons.chevron_back,
                  color: VpTokens.primary,
                  size: 22,
                ),
                onPressed: widget.onBack,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ),
          ),
          const Text(
            '录音详情',
            style: TextStyle(
              fontSize: 17,
              fontWeight: VpTokens.wSemibold,
              color: VpTokens.textPrimary,
              letterSpacing: -0.01,
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(
                  CupertinoIcons.delete,
                  color: VpTokens.textTertiary,
                  size: 20,
                ),
                onPressed: _deleteRecording,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerCard(Duration pos) {
    final r = widget.recording;
    final amps = r.overviewWaveform.isNotEmpty
        ? r.overviewWaveform
        : r.waveform;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VpTokens.surface,
        borderRadius: BorderRadius.circular(VpTokens.radiusLg),
        border: Border.all(color: VpTokens.borderLight),
      ),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _togglePlay,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: VpTokens.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: VpTokens.primary.withValues(alpha: 0.25),
                        offset: const Offset(0, 2),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isPlaying
                        ? CupertinoIcons.pause_fill
                        : CupertinoIcons.play_fill,
                    color: VpTokens.textInverse,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    // 进度条 — 可点击 seek
                    LayoutBuilder(
                      builder: (context, c) {
                        final w = c.maxWidth;
                        return GestureDetector(
                          onTapDown: (details) {
                            _seekTo(details.localPosition.dx / w);
                          },
                          child: SizedBox(
                            height: 14,
                            child: Stack(
                              alignment: Alignment.centerLeft,
                              children: [
                                Container(
                                  height: 4,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: VpTokens.borderLight,
                                    borderRadius: BorderRadius.circular(
                                      VpTokens.radiusFull,
                                    ),
                                  ),
                                ),
                                Container(
                                  height: 4,
                                  width: _progress * w,
                                  decoration: BoxDecoration(
                                    color: VpTokens.primary,
                                    borderRadius: BorderRadius.circular(
                                      VpTokens.radiusFull,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: _progress * w - 7,
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: VpTokens.surface,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: VpTokens.primary,
                                        width: 2,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x24000000),
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
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _fmtDuration(pos),
                          style: _mono(12, VpTokens.textPrimary),
                        ),
                        Text(
                          r.durationLabel,
                          style: _mono(12, VpTokens.textTertiary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          WaveformOverview(
            amplitudes: amps,
            progress: _progress,
            height: 60,
          ),
        ],
      ),
    );
  }

  Widget _buildSoundReport() {
    final r = widget.recording;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VpTokens.surface,
        borderRadius: BorderRadius.circular(VpTokens.radiusLg),
        border: Border.all(color: VpTokens.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '声音报告',
            style: TextStyle(
              fontSize: 17,
              fontWeight: VpTokens.wSemibold,
              color: VpTokens.textPrimary,
              letterSpacing: -0.01,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            '共鸣比例分析',
            style: TextStyle(fontSize: 13, color: VpTokens.textSecondary),
          ),
          const SizedBox(height: 12),
          SoundReportChart(
            stack: r.resonanceStack,
            pitch: r.pitch,
          ),
        ],
      ),
    );
  }

  TextStyle _mono(double size, Color color) => TextStyle(
        fontSize: size,
        color: color,
        fontFamily: 'SF Mono',
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final bool primary;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VpTokens.radiusLg),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: VpTokens.surface,
            borderRadius: BorderRadius.circular(VpTokens.radiusLg),
            border: Border.all(
              color: primary ? VpTokens.primary : VpTokens.border,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: VpTokens.wSemibold,
              color: primary ? VpTokens.primary : VpTokens.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
