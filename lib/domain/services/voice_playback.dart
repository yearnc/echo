import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

/// 语音条此刻在响没响。
class VoicePlaybackState {
  const VoicePlaybackState({
    this.currentRef,
    this.failedRef,
    this.playing = false,
  });

  /// 正在播（或暂停中）的那条语音的 `file:` 引用。
  final String? currentRef;

  /// 最近一次播不出来的那条。
  final String? failedRef;

  final bool playing;

  bool isPlaying(String ref) => currentRef == ref && playing;

  bool hasFailed(String ref) => failedRef == ref;

  VoicePlaybackState copyWith({
    String? currentRef,
    String? failedRef,
    bool? playing,
    bool clearCurrent = false,
    bool clearFailed = false,
  }) {
    return VoicePlaybackState(
      currentRef: clearCurrent ? null : (currentRef ?? this.currentRef),
      failedRef: clearFailed ? null : (failedRef ?? this.failedRef),
      playing: playing ?? this.playing,
    );
  }
}

/// 语音条的播放（B8）。
///
/// 全应用只有**一个**播放器：同一时刻只该有一条语音在响。
/// 每条气泡各建一个播放器的话，手指划得快一点就会叠着响好几条，
/// 而且每个播放器都要占一份系统音频资源。
class VoicePlayback extends Notifier<VoicePlaybackState> {
  late final AudioPlayer _player;
  StreamSubscription<PlayerState>? _subscription;

  @override
  VoicePlaybackState build() {
    _player = AudioPlayer();
    _subscription = _player.playerStateStream.listen(_onPlayerState);
    ref.onDispose(() {
      _subscription?.cancel();
      _player.dispose();
    });
    return const VoicePlaybackState();
  }

  /// 点一下：正在播这条就暂停，否则从这条的开头播。
  Future<void> toggle(String ref) async {
    if (state.isPlaying(ref)) {
      await _player.pause();
      state = state.copyWith(playing: false);
      return;
    }

    final switching = state.currentRef != ref;
    state = VoicePlaybackState(currentRef: ref, playing: true);

    try {
      if (switching) {
        await _player.setFilePath(_filePathOf(ref));
      } else {
        // 播完之后再点一次：从头再来，别停在尾巴上。
        await _player.seek(Duration.zero);
      }
      await _player.play();
      state = state.copyWith(playing: true);
    } catch (error) {
      // 文件没了、格式不对、平台不支持——都算这条播不出来。
      // 评论区不该因为一段音频就整个出错。
      debugPrint('[语音] 这条没播出来：$error');
      state = VoicePlaybackState(failedRef: ref);
    }
  }

  /// 停下来（切模式、离开页面时用）。
  Future<void> stop() async {
    state = const VoicePlaybackState();
    await _player.stop();
  }

  void _onPlayerState(PlayerState playerState) {
    if (playerState.processingState == ProcessingState.completed) {
      state = state.copyWith(clearCurrent: true, playing: false);
      return;
    }
    if (state.playing != playerState.playing) {
      state = state.copyWith(playing: playerState.playing);
    }
  }

  static String _filePathOf(String ref) =>
      ref.startsWith('file:') ? ref.substring('file:'.length) : ref;
}

final voicePlaybackProvider =
    NotifierProvider<VoicePlayback, VoicePlaybackState>(VoicePlayback.new);
