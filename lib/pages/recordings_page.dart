import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/recording.dart';
import '../services/recording_service.dart';
import '../theme/tokens.dart';
import '../widgets/waveform_thumbnail.dart';

/// 录音记录页 — 从本地数据库加载真实录音
class RecordingsPage extends StatefulWidget {
  final void Function(Recording recording) onOpenDetail;
  final VoidCallback onOpenPractice;
  final int refreshTrigger;

  const RecordingsPage({
    super.key,
    required this.onOpenDetail,
    required this.onOpenPractice,
    required this.refreshTrigger,
  });

  @override
  State<RecordingsPage> createState() => _RecordingsPageState();
}

class _RecordingsPageState extends State<RecordingsPage> {
  final RecordingService _service = RecordingService();
  List<Recording> _all = [];
  List<Recording> _visible = [];
  bool _loading = true;
  bool _importing = false;
  static const int _pageSize = 6;

  @override
  void initState() {
    super.initState();
    _loadRecordings();
  }

  @override
  void didUpdateWidget(covariant RecordingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTrigger != widget.refreshTrigger) {
      _loadRecordings();
    }
  }

  Future<void> _loadRecordings() async {
    setState(() => _loading = true);
    final recordings = await _service.getAllRecordings();
    if (mounted) {
      setState(() {
        _all = recordings;
        _visible = recordings.take(_pageSize).toList();
        _loading = false;
      });
    }
  }

  void _loadMore() {
    setState(() {
      final next = _all.skip(_visible.length).take(_pageSize).toList();
      _visible.addAll(next);
    });
  }

  Future<void> _importFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final filePath = result.files.single.path;
    if (filePath == null) return;

    setState(() => _importing = true);

    // 超时保护 — 最长 2 分钟，避免无限转圈
    final recording = await _service
        .importFile(filePath)
        .timeout(const Duration(minutes: 2), onTimeout: () => null);

    if (mounted) {
      setState(() => _importing = false);
      if (recording != null) {
        _loadRecordings();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('导入成功'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('导入失败：文件无效、格式不支持或超时'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _all.length;
    final hasMore = _visible.length < total;

    return Scaffold(
      backgroundColor: VpTokens.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(total),
            Expanded(
              child: _loading
                  ? const Center(child: CupertinoActivityIndicator())
                  : _visible.isEmpty
                      ? _buildEmptyState()
                      : ListView(
                          padding: const EdgeInsets.only(
                            left: 16,
                            right: 16,
                            top: 4,
                            bottom: 24,
                          ),
                          children: [
                            for (final r in _visible) ...[
                              _RecordingCard(
                                recording: r,
                                onTap: () => widget.onOpenDetail(r),
                              ),
                              const SizedBox(height: 8),
                            ],
                            if (hasMore)
                              Center(
                                child: TextButton(
                                  onPressed: _loadMore,
                                  style: TextButton.styleFrom(
                                    foregroundColor: VpTokens.primary,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                  ),
                                  child: const Text(
                                    '加载更多',
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: VpTokens.primary,
                                    ),
                                  ),
                                ),
                              )
                            else
                              const _EndHint(),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '录音记录',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: VpTokens.wSemibold,
                    color: VpTokens.textPrimary,
                    letterSpacing: -0.02,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '共 $total 次录音',
                  style: const TextStyle(
                    fontSize: 13,
                    color: VpTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: VpTokens.primary,
            onPressed: _importing ? null : _importFile,
            child: _importing
                ? const CupertinoActivityIndicator(color: Colors.white)
                : const Text(
                    '导入文件',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: VpTokens.wMedium,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            CupertinoIcons.mic,
            size: 48,
            color: VpTokens.textTertiary,
          ),
          const SizedBox(height: 16),
          const Text(
            '还没有录音',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: VpTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '点击下方「练习」开始录音',
            style: TextStyle(fontSize: 13, color: VpTokens.textTertiary),
          ),
          const SizedBox(height: 24),
          CupertinoButton(
            color: VpTokens.primary,
            onPressed: widget.onOpenPractice,
            child: const Text(
              '去录音',
              style: TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(height: 12),
          CupertinoButton(
            onPressed: _importing ? null : _importFile,
            child: _importing
                ? const CupertinoActivityIndicator()
                : const Text(
                    '导入本地录音文件',
                    style: TextStyle(color: VpTokens.primary),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RecordingCard extends StatelessWidget {
  final Recording recording;
  final VoidCallback onTap;

  const _RecordingCard({required this.recording, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: VpTokens.surface,
      borderRadius: BorderRadius.circular(VpTokens.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VpTokens.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: VpTokens.surface,
            borderRadius: BorderRadius.circular(VpTokens.radiusLg),
            boxShadow: VpTokens.shadowSm,
          ),
          child: Row(
            children: [
              WaveformThumbnail(amplitudes: recording.waveform),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          recording.dateTimeLabel,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: VpTokens.wSemibold,
                            color: VpTokens.textPrimary,
                            letterSpacing: -0.01,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (recording.isNew) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: VpTokens.primary100,
                              borderRadius:
                                  BorderRadius.circular(VpTokens.radiusFull),
                            ),
                            child: const Text(
                              '最新',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: VpTokens.wMedium,
                                color: VpTokens.primary,
                                letterSpacing: 0.02,
                                height: 1,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      recording.durationLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        color: VpTokens.textSecondary,
                        fontFamily: 'SF Mono',
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: VpTokens.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: VpTokens.textInverse,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: VpTokens.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EndHint extends StatelessWidget {
  const _EndHint();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Text(
          '已加载全部',
          style: TextStyle(fontSize: 13, color: VpTokens.textTertiary),
        ),
      ),
    );
  }
}
