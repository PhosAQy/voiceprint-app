import 'package:flutter/material.dart';
import '../models/recording.dart';
import '../theme/tokens.dart';
import '../widgets/vp_tab_bar.dart';
import 'practice_page.dart';
import 'recording_detail_page.dart';
import 'recordings_page.dart';
import 'settings_page.dart';

/// 声纹 App 主壳：底部 Tab + 页面栈
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  VpTab _tab = VpTab.practice;
  Recording? _detailRecording;
  int _refreshTrigger = 0;

  void _switchTab(VpTab t) {
    if (_detailRecording != null) {
      setState(() => _detailRecording = null);
    }
    setState(() => _tab = t);
  }

  void _openDetail(Recording r) {
    setState(() => _detailRecording = r);
  }

  void _closeDetail() {
    setState(() => _detailRecording = null);
    // 详情页关闭时刷新列表（可能删除了录音）
    setState(() => _refreshTrigger++);
  }

  void _onRecordingComplete() {
    setState(() {
      _refreshTrigger++;
      _tab = VpTab.recordings;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 详情页：覆盖在 Tab 之上
    if (_detailRecording != null) {
      return RecordingDetailPage(
        recording: _detailRecording!,
        onBack: _closeDetail,
        onDeleted: () => setState(() => _refreshTrigger++),
      );
    }

    return Scaffold(
      backgroundColor: VpTokens.bg,
      body: IndexedStack(
        index: _tab == VpTab.practice
            ? 0
            : _tab == VpTab.recordings
                ? 1
                : 2,
        children: [
          PracticePage(
            onRecordingComplete: _onRecordingComplete,
            onOpenRecordings: () => setState(() => _tab = VpTab.recordings),
          ),
          RecordingsPage(
            onOpenDetail: _openDetail,
            onOpenPractice: () => setState(() => _tab = VpTab.practice),
            refreshTrigger: _refreshTrigger,
          ),
          const SettingsPage(),
        ],
      ),
      bottomNavigationBar: VpTabBar(active: _tab, onTap: _switchTab),
    );
  }
}
