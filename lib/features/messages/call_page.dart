import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../core/theme/app_colors.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../../data/repositories/private_message_repository.dart';
import '../../domain/models/custom_resident.dart';
import '../../domain/services/asr_service.dart';
import '../../domain/services/call_registry.dart';
import '../../domain/services/call_service.dart';
import '../../domain/services/tts_service.dart';
import '../../domain/services/voice_playback.dart';
import '../../domain/services/voice_recorder.dart';
import '../shared_widgets/user_avatar.dart';

/// 私信内通话（v4.0 P4）。
///
/// 不把通话内容写进私信。视频通话时摄像头每 0.5 秒留一帧（带时间戳），
/// 用户说完一句后，把最近几秒的画面 + 这句话交给模型，让它像接电话一样回。
/// 退出时私信里只留一条「通话 03:12」，正文和临时画面在总结成记忆后丢弃。
class CallPage extends ConsumerStatefulWidget {
  const CallPage({
    super.key,
    required this.personaId,
    this.video = false,
  });

  final String personaId;
  final bool video;

  @override
  ConsumerState<CallPage> createState() => _CallPageState();
}

class _CallPageState extends ConsumerState<CallPage> {
  final VoiceRecorder _recorder = VoiceRecorder();
  final DateTime _startedAt = DateTime.now();

  CameraController? _camera;
  bool _cameraReady = false;
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  final List<CallFrame> _frames = [];
  final List<CallTurn> _turns = [];

  Timer? _clockTicker;
  Timer? _recordTicker;
  bool _recording = false;
  bool _busy = false;
  bool _ending = false;
  int _recordSeconds = 0;
  bool _voiceReply = true;
  String _lastReply = '';
  bool _speaking = false;
  int _speakToken = 0;
  bool _interrupted = false;

  @override
  void initState() {
    super.initState();
    CallRegistry.begin(widget.personaId);
    _clockTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    if (widget.video) unawaited(_initCamera());
  }

  @override
  void dispose() {
    CallRegistry.end(widget.personaId);
    _clockTicker?.cancel();
    _recordTicker?.cancel();
    unawaited(_recorder.dispose());
    unawaited(_camera?.stopImageStream());
    unawaited(_camera?.dispose());
    unawaited(ref.read(voicePlaybackProvider.notifier).stop());
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _toast('这台设备没有可用的摄像头，先用语音通话');
        return;
      }
      final front = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      await controller.startImageStream(_onCameraFrame);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _cameraReady = true;
      });
    } catch (error) {
      debugPrint('[通话] 摄像头没起来：$error');
      _toast('摄像头没打开，先用语音通话');
    }
  }

  /// 两句话之间每 0.5 秒留一帧。只存最近 8 帧（约 4 秒），
  /// 更早的边收边删——通话不是录像。
  void _onCameraFrame(CameraImage frame) {
    final now = DateTime.now();
    if (now.difference(_lastFrameAt) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastFrameAt = now;
    try {
      final image = _yuvToRgb(frame);
      final resized = img.copyResize(image, width: 480);
      final jpeg = img.encodeJpg(resized, quality: 70);
      unawaited(_persistFrame(jpeg, now));
    } catch (error) {
      debugPrint('[通话] 这一帧没接住：$error');
    }
  }

  Future<void> _persistFrame(Uint8List jpeg, DateTime at) async {
    try {
      final dir = Directory(
        '${(await getTemporaryDirectory()).path}/call_frames',
      );
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File(
        '${dir.path}/frame_${at.microsecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(jpeg, flush: true);
      _frames.add(CallFrame(ref: 'file:${file.path}', at: at));
      while (_frames.length > 8) {
        _deleteFrame(_frames.removeAt(0).ref);
      }
    } catch (error) {
      debugPrint('[通话] 这一帧没存下来：$error');
    }
  }

  /// YUV_420_888 → RGB。只跑在 0.5 秒一帧的低分辨率流上，
  /// 不追求把整段视频转出来。
  static img.Image _yuvToRgb(CameraImage frame) {
    final width = frame.width;
    final height = frame.height;
    final yPlane = frame.planes[0];
    final uPlane = frame.planes[1];
    final vPlane = frame.planes[2];
    final rgb = Uint8List(width * height * 3);
    final yStride = yPlane.bytesPerRow;
    final uStride = uPlane.bytesPerRow;
    final yPixel = yPlane.bytesPerPixel ?? 1;
    final uPixel = uPlane.bytesPerPixel ?? 1;
    var out = 0;
    for (var y = 0; y < height; y++) {
      final yRow = y * yStride;
      final uvRow = (y >> 1) * uStride;
      for (var x = 0; x < width; x++) {
        final yValue = yPlane.bytes[yRow + x * yPixel];
        final uvIndex = uvRow + (x >> 1) * uPixel;
        final uValue = uPlane.bytes[uvIndex];
        final vValue = vPlane.bytes[uvIndex];
        final r = (yValue + 1.402 * (vValue - 128)).round().clamp(0, 255);
        final g = (yValue -
                0.344 * (uValue - 128) -
                0.714 * (vValue - 128))
            .round()
            .clamp(0, 255);
        final b = (yValue + 1.772 * (uValue - 128)).round().clamp(0, 255);
        rgb[out++] = r;
        rgb[out++] = g;
        rgb[out++] = b;
      }
    }
    return img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgb.buffer,
      order: img.ChannelOrder.rgb,
    );
  }

  Future<void> _holdStart() async {
    if (_busy || _ending) return;
    if (_speaking) {
      _speakToken++;
      _interrupted = true;
      await ref.read(voicePlaybackProvider.notifier).stop();
      if (mounted) setState(() => _speaking = false);
    }
    final ok = await _recorder.start();
    if (!ok) {
      _toast('没有麦克风权限');
      return;
    }
    if (!mounted) return;
    setState(() {
      _recording = true;
      _recordSeconds = 0;
    });
    _recordTicker?.cancel();
    _recordTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _recordSeconds++);
      if (_recordSeconds >= VoiceRecorder.maxDuration.inSeconds) {
        unawaited(_holdEnd());
      }
    });
  }

  Future<void> _holdEnd() async {
    if (!_recording) return;
    _recordTicker?.cancel();
    final recorded = await _recorder.stop();
    if (!mounted) return;
    setState(() => _recording = false);
    if (recorded == null) {
      _toast('说得太短了');
      return;
    }

    setState(() => _busy = true);
    try {
      final result = await ref
          .read(asrServiceProvider)
          .transcribeWav(recorded.path);
      // 通话不把录音落库：识别完就删。
      await _deleteQuietly(recorded.path);

      final interrupted = _interrupted;
      _interrupted = false;
      setState(() => _lastReply = '');
      final reply = await ref
          .read(callServiceProvider)
          .reply(
            residentId: widget.personaId,
            userText: result.text,
            history: _turns,
            frames: List<CallFrame>.of(_frames),
            video: widget.video,
            interrupted: interrupted,
          );
      final now = DateTime.now();
      _turns
        ..add(CallTurn(fromMe: true, text: result.text, at: now))
        ..add(CallTurn(fromMe: false, text: reply, at: DateTime.now()));
      if (!mounted) return;
      setState(() => _lastReply = reply);
      if (_voiceReply) {
        unawaited(_speak(reply));
      }
    } catch (error) {
      _toast('没听清：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _speak(String text) async {
    if (!_voiceReply) return;
    final resident = ref.read(customResidentByIdProvider(widget.personaId));
    if (resident == null || !resident.voiceEnabled) return;
    try {
      final clip = await ref
          .read(ttsServiceProvider)
          .speak(
            text: text,
            personaId: resident.id,
            voiceModel: resident.voiceRef,
            voiceDescription: resident.voiceDescription,
            wantsDescription: resident.voiceMode.usesDescription,
            referenceAudioPath: resident.voiceSamplePath,
            referenceText: resident.voiceSampleText,
            preferLocalClone:
                resident.voiceMode == ResidentVoiceMode.referenceTranscript &&
                resident.voiceSamplePath.isNotEmpty,
          );
      if (clip == null || !mounted) return;
      final token = ++_speakToken;
      setState(() => _speaking = true);
      await ref.read(voicePlaybackProvider.notifier).toggle(clip.ref);
      await Future<void>.delayed(
        Duration(milliseconds: clip.durationMs.clamp(300, 60000)),
      );
      if (mounted && token == _speakToken) {
        setState(() => _speaking = false);
      }
    } catch (error) {
      debugPrint('[通话] 这句没念出来：$error');
      if (mounted) setState(() => _speaking = false);
    }
  }

  Future<void> _endCall() async {
    if (_ending) return;
    setState(() => _ending = true);
    final duration = DateTime.now().difference(_startedAt);
    CallRegistry.end(widget.personaId);
    _recordTicker?.cancel();
    _clockTicker?.cancel();

    final turns = List<CallTurn>.of(_turns);
    final frames = List<CallFrame>.of(_frames);
    _frames.clear();
    await _stopMedia();

    // 私信里只留一条通话时长，像微信的“通话 03:12”。
    try {
      await ref
          .read(privateMessageRepositoryProvider)
          .send(
            personaId: widget.personaId,
            content: '通话 ${_clock(duration)}',
            mediaType: 'call',
          );
    } catch (error) {
      debugPrint('[通话] 通话记录没写上：$error');
    }

    // 总结写记忆 + 删临时帧放到后台：页面先退，不能让人干等模型。
    unawaited(
      ref
          .read(callServiceProvider)
          .finishAndRemember(
            residentId: widget.personaId,
            turns: turns,
            frames: frames,
            duration: duration,
            video: widget.video,
          ),
    );

    if (mounted) context.pop();
  }

  Future<void> _stopMedia() async {
    final camera = _camera;
    _camera = null;
    _cameraReady = false;
    if (camera != null) {
      try {
        await camera.stopImageStream();
      } catch (_) {}
      await camera.dispose();
    }
    await ref.read(voicePlaybackProvider.notifier).stop();
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final resident = ref.watch(customResidentByIdProvider(widget.personaId));
    final name = resident?.name ?? '已离开的住民';
    final avatarRef = resident?.avatarAsset;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0812),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _background(),
          SafeArea(child: _content(name, avatarRef)),
        ],
      ),
    );
  }

  Widget _background() {
    final camera = _camera;
    if (widget.video && _cameraReady && camera != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: camera.value.previewSize?.height ?? 720,
              height: camera.value.previewSize?.width ?? 1280,
              child: CameraPreview(camera),
            ),
          ),
          Container(color: Colors.black.withValues(alpha: 0.52)),
        ],
      );
    }
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF171022), Color(0xFF0B0812)],
        ),
      ),
    );
  }

  Widget _content(String name, String? avatarRef) {
    return Column(
      children: [
        const SizedBox(height: 14),
        UserAvatar(
          name: name,
          avatarRef: avatarRef,
          size: widget.video ? 84 : 96,
          showRing: true,
        ),
        const SizedBox(height: 12),
        Text(
          name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _clock(DateTime.now().difference(_startedAt)),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 34),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_lastReply.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _lastReply,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.86),
                          fontSize: 14,
                          height: 1.6,
                        ),
                      ),
                    ),
                  if (_busy) ...[
                    const SizedBox(height: 18),
                    Text(
                      '正在接住你说的话…',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                  if (_ending) ...[
                    const SizedBox(height: 18),
                    Text(
                      '正在挂断…',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (_recording) ...[
          Text(
            '正在听 ${_recordSeconds}s · 松开发送',
            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
        ] else if (_speaking) ...[
          Text(
            'TA 正在说… 按住下面的按钮可以打断',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _RoundCallButton(
              icon: Icons.call_end,
              color: const Color(0xFFE45757),
              label: '挂断',
              onTap: _ending ? null : () => unawaited(_endCall()),
            ),
            GestureDetector(
              onTap: () => _toast('按住说话，松开发送'),
              onLongPressStart: (_) => unawaited(_holdStart()),
              onLongPressEnd: (_) => unawaited(_holdEnd()),
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _recording
                      ? EchoColors.primary
                      : Colors.white.withValues(alpha: 0.12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                child: Icon(
                  _recording ? Icons.stop : Icons.mic,
                  size: 34,
                  color: Colors.white,
                ),
              ),
            ),
            _RoundCallButton(
              icon: _voiceReply ? Icons.volume_up : Icons.volume_off,
              color: Colors.white.withValues(alpha: 0.12),
              label: _voiceReply ? 'TA 出声' : '只发文字',
              onTap: () => setState(() => _voiceReply = !_voiceReply),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          widget.video && _cameraReady
              ? '视频通话 · 每 0.5 秒留一帧，退出只留时长'
              : '语音通话 · 退出只留时长',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  static String _clock(Duration span) {
    final mm = span.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = span.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static void _deleteFrame(String ref) {
    try {
      final file = File(ref.startsWith('file:') ? ref.substring(5) : ref);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }
}

class _RoundCallButton extends StatelessWidget {
  const _RoundCallButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }
}
