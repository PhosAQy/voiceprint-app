import 'dart:async';
import 'package:audioplayers/audioplayers.dart';

/// 播放服务 — 管理音频播放、进度、完成回调
class PlaybackService {
  static final PlaybackService _instance = PlaybackService._internal();
  factory PlaybackService() => _instance;
  PlaybackService._internal();

  final AudioPlayer _player = AudioPlayer();

  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  String? _currentPath;

  final _controller = StreamController<PlaybackState>.broadcast();
  Stream<PlaybackState> get stateStream => _controller.stream;

  bool get isPlaying => _isPlaying;
  Duration get duration => _duration;
  Duration get position => _position;
  String? get currentPath => _currentPath;

  void init() {
    _player.onPositionChanged.listen((pos) {
      _position = pos;
      _emit();
    });
    _player.onDurationChanged.listen((dur) {
      _duration = dur;
      _emit();
    });
    _player.onPlayerComplete.listen((_) {
      _isPlaying = false;
      _position = Duration.zero;
      _emit();
    });
    _player.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      _emit();
    });
  }

  /// 播放指定文件
  Future<void> play(String filePath) async {
    if (_currentPath != filePath) {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setSource(DeviceFileSource(filePath));
      _currentPath = filePath;
      _position = Duration.zero;
    }
    await _player.resume();
  }

  /// 暂停
  Future<void> pause() async {
    await _player.pause();
  }

  /// 停止
  Future<void> stop() async {
    await _player.stop();
    _position = Duration.zero;
    _currentPath = null;
    _emit();
  }

  /// 跳转
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _position = position;
    _emit();
  }

  /// 切换播放/暂停
  Future<void> togglePlay(String filePath) async {
    if (_isPlaying) {
      await pause();
    } else {
      await play(filePath);
    }
  }

  void _emit() {
    _controller.add(PlaybackState(
      isPlaying: _isPlaying,
      position: _position,
      duration: _duration,
    ));
  }

  void dispose() {
    _player.dispose();
    _controller.close();
  }
}

/// 播放状态
class PlaybackState {
  final bool isPlaying;
  final Duration position;
  final Duration duration;

  const PlaybackState({
    required this.isPlaying,
    required this.position,
    required this.duration,
  });

  double get progress =>
      duration.inMilliseconds > 0
          ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
          : 0.0;
}
