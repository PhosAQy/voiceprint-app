import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'pages/home_page.dart';
import 'services/github_config.dart';
import 'services/playback_service.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化播放服务
  PlaybackService().init();
  // 预加载 GitHub 配置
  GithubConfig.load();
  // 让状态栏与导航栏透明，与设计稿的 iOS 全屏观感对齐
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: VpTokens.surface,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const VoiceprintApp());
}

class VoiceprintApp extends StatelessWidget {
  const VoiceprintApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '声纹',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const HomePage(),
    );
  }
}
