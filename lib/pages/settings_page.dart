import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../services/github_config.dart';
import '../services/update_service.dart';
import '../theme/tokens.dart';
import '../widgets/vp_controls.dart';

/// 设置页 — 检查更新 + 仓库配置
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _ownerCtrl = TextEditingController();
  final _repoCtrl = TextEditingController();

  bool _checking = false;
  ReleaseInfo? _release;
  String? _checkError;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    await GithubConfig.load();
    _ownerCtrl.text = GithubConfig.owner;
    _repoCtrl.text = GithubConfig.repo;
    if (mounted) setState(() {});
  }

  Future<void> _saveConfig() async {
    await GithubConfig.save(
      owner: _ownerCtrl.text.trim().isEmpty
          ? GithubConfig.defaultOwner
          : _ownerCtrl.text.trim(),
      repo: _repoCtrl.text.trim().isEmpty
          ? GithubConfig.defaultRepo
          : _repoCtrl.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('配置已保存'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _checkUpdate() async {
    setState(() {
      _checking = true;
      _checkError = null;
      _release = null;
    });
    try {
      final info = await UpdateService.checkLatest();
      if (mounted) {
        setState(() {
          _checking = false;
          _release = info;
          if (info == null) {
            _checkError = '无法获取版本信息';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _checking = false;
          _checkError = '$e';
        });
      }
    }
  }

  Future<void> _downloadAndInstall() async {
    if (_release?.apkDownloadUrl == null) return;
    setState(() => _downloading = true);
    try {
      final path = await UpdateService.downloadApk(_release!.apkDownloadUrl!);
      if (mounted) setState(() => _downloading = false);
      await OpenFilex.open(path);
    } catch (e) {
      if (mounted) {
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('下载失败: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _ownerCtrl.dispose();
    _repoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VpTokens.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  _buildUpdateCard(),
                  const SizedBox(height: 12),
                  _buildRepoCard(),
                ],
              ),
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
          '设置',
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

  Widget _buildUpdateCard() {
    return VpCard(
      sections: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '应用更新',
              style: TextStyle(
                fontSize: 17,
                fontWeight: VpTokens.wSemibold,
                color: VpTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '当前版本 v${AppVersion.current}',
              style: const TextStyle(
                fontSize: 13,
                color: VpTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                color: VpTokens.primary,
                onPressed: _checking ? null : _checkUpdate,
                child: _checking
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : const Text('检查更新'),
              ),
            ),
            if (_checkError != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEDED),
                  borderRadius: BorderRadius.circular(VpTokens.radiusMd),
                ),
                child: Text(
                  _checkError!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: VpTokens.error,
                  ),
                ),
              ),
            ],
            if (_release != null) ...[
              const SizedBox(height: 16),
              _buildReleaseInfo(_release!),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildReleaseInfo(ReleaseInfo info) {
    final isNewer = info.isNewer;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isNewer ? VpTokens.primary50 : VpTokens.surfaceTertiary,
        borderRadius: BorderRadius.circular(VpTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '最新版本 v${info.version}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: VpTokens.wSemibold,
                  color: VpTokens.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              if (isNewer)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: VpTokens.primary,
                    borderRadius: BorderRadius.circular(VpTokens.radiusFull),
                  ),
                  child: const Text(
                    '有新版本',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: VpTokens.wMedium,
                      color: VpTokens.textInverse,
                      height: 1.2,
                    ),
                  ),
                )
              else
                const Text(
                  '已是最新',
                  style: TextStyle(
                    fontSize: 12,
                    color: VpTokens.textSecondary,
                  ),
                ),
            ],
          ),
          if (info.apkSizeLabel.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '大小 ${info.apkSizeLabel}',
              style: const TextStyle(
                fontSize: 13,
                color: VpTokens.textSecondary,
              ),
            ),
          ],
          if (info.body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              info.body,
              style: const TextStyle(
                fontSize: 13,
                color: VpTokens.textSecondary,
              ),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (isNewer && info.apkDownloadUrl != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                color: VpTokens.primary,
                onPressed: _downloading ? null : _downloadAndInstall,
                child: _downloading
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CupertinoActivityIndicator(color: Colors.white),
                          SizedBox(width: 8),
                          Text('下载中...'),
                        ],
                      )
                    : const Text('下载并安装'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRepoCard() {
    return VpCard(
      sections: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '更新源配置',
              style: TextStyle(
                fontSize: 17,
                fontWeight: VpTokens.wSemibold,
                color: VpTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '配置 GitHub 仓库地址，用于检测 App 更新',
              style: TextStyle(
                fontSize: 13,
                color: VpTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            _buildLabel('仓库 Owner'),
            const SizedBox(height: 6),
            _buildTextField(_ownerCtrl, '如 PhosAQy'),
            const SizedBox(height: 14),
            _buildLabel('仓库名'),
            const SizedBox(height: 6),
            _buildTextField(_repoCtrl, '如 voiceprint-app'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                color: VpTokens.primary,
                onPressed: _saveConfig,
                child: const Text('保存配置'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: VpTokens.wMedium,
        color: VpTokens.textSecondary,
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String hint,
  ) {
    return CupertinoTextField(
      controller: ctrl,
      placeholder: hint,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: VpTokens.surfaceTertiary,
        borderRadius: BorderRadius.circular(VpTokens.radiusMd),
      ),
      style: const TextStyle(
        fontSize: 15,
        color: VpTokens.textPrimary,
      ),
    );
  }
}
