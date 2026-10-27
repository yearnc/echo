import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../data/media/media_service.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../models/custom_resident.dart';
import '../models/model_config.dart';
import '../models/resident_voice.dart';
import '../models/voice_settings.dart';
import 'model_gateway.dart';
import 'speech_models.dart';
import 'speech_runtime.dart';
import 'voice_settings_controller.dart';
import 'voice_waveform.dart';

/// 合成好的一条语音。
class VoiceClip {
  const VoiceClip({
    required this.ref,
    required this.transcript,
    required this.durationMs,
    required this.waveform,
  });

  /// `file:` 引用，跟图片、头像同一套约定。
  final String ref;

  /// 转写稿。语音条下面那行字就是它——用户不开声音也知道说了什么。
  final String transcript;

  final int durationMs;

  /// 波形柱子（0—1，[VoiceWaveform.defaultBars] 根）。
  final List<double> waveform;
}

/// 住民说话的嗓子：本机离线合成（B8）。
///
/// 用的是随包发布的 AISHELL-3 多说话人模型，不联网、不花钱，
/// 而且**合成完就把 wav 落盘**——这样飞行模式下已经收到的语音照样能播，
/// 那是这一里程碑的验收条件之一。
///
/// 拿不到模型（比如开发者没按说明放模型文件）时一律返回 null，
/// 调用方保持纯文本，不报错、不阻塞——社区的正常运转不该被一个语音功能拖住。
class TtsService {
  TtsService({
    SpeechModelStore? store,
    this.media = const MediaService(),
    this.gateway,
    this.readSource,
    this.lookupResident,
  }) : _store = store ?? SpeechModelStore();

  final SpeechModelStore _store;
  final MediaService media;

  /// 云端 TTS 的通道。为空（或没配 TTS 配置）就只走本机。
  final ModelGateway? gateway;

  /// 用户选的是哪条路。每次合成现读，改完设置不用重启 APP。
  final VoiceSource Function()? readSource;

  /// 评论区的语音只有 personaId，没有住民对象；靠它把参考音频找回来，
  /// 这样同一个住民在私信和评论里听起来是同一个人。
  final Future<CustomResident?> Function(String residentId)? lookupResident;

  /// 两套本机模型共用一个引擎槽：ZipVoice 内存占用不小，和 vits 同时常驻
  /// 在手机上不划算。切模型时先 free 旧的，再建新的——多花一两次初始化的时间，
  /// 换手机不 OOM。
  sherpa.OfflineTts? _engine;
  _LocalModel? _engineKind;
  final Set<_LocalModel> _unavailable = {};

  /// 一句话最多合成这么多字。
  ///
  /// 语音评论本来就不长（住在评论区里，用户要等它放完），
  /// 超过这个长度的一律退回文字——一分钟的语音条没人会听。
  static const int maxTranscriptLength = 120;

  Future<sherpa.OfflineTts?> _ensureLocal(_LocalModel kind) async {
    if (_unavailable.contains(kind)) return null;
    if (_engine != null && _engineKind == kind) return _engine;

    if (_engine != null) {
      try {
        _engine!.free();
      } catch (_) {
        // 释放失败也继续建新的；真有问题会落在下面的 try 里。
      }
      _engine = null;
      _engineKind = null;
    }

    try {
      SpeechRuntime.ensure();
      final sherpa.OfflineTtsConfig config;
      if (kind == _LocalModel.vits) {
        final models = await _store.prepareTts();
        config = sherpa.OfflineTtsConfig(
          model: sherpa.OfflineTtsModelConfig(
            vits: sherpa.OfflineTtsVitsModelConfig(
              model: models.pathOf('model.onnx'),
              lexicon: models.pathOf('lexicon.txt'),
              tokens: models.pathOf('tokens.txt'),
            ),
            // 合成是纯 CPU 活，两个线程够用：再多会跟 UI 抢，
            // 而这条路径本来就不该让人等太久。
            numThreads: 2,
            debug: false,
          ),
          // 日期/数字/电话这类文本正则化。vits-zh-ll 的 README 里给了
          // 对应的 fst；不传的话“3月24日”会被念成“三月二十四日”之外的东西。
          ruleFsts: [
            models.pathOf('date.fst'),
            models.pathOf('number.fst'),
            models.pathOf('phone.fst'),
          ].join(','),
        );
      } else {
        final models = await _store.prepareZipVoice();
        config = sherpa.OfflineTtsConfig(
          model: sherpa.OfflineTtsModelConfig(
            zipvoice: sherpa.OfflineTtsZipVoiceModelConfig(
              tokens: models.pathOf('tokens.txt'),
              encoder: models.pathOf('encoder.int8.onnx'),
              decoder: models.pathOf('decoder.int8.onnx'),
              // 声码器单独一份，归档里叫 vocos_24khz.onnx。
              vocoder: models.pathOf('vocos_24khz.onnx'),
              dataDir: models.pathOf('espeak-ng-data'),
              lexicon: models.pathOf('lexicon.txt'),
            ),
            numThreads: 2,
            debug: false,
          ),
        );
      }

      _engine = sherpa.OfflineTts(config);
      _engineKind = kind;
      return _engine;
    } catch (error) {
      // 记一次就够，不必每条评论都试一遍引擎。
      _unavailable.add(kind);
      debugPrint('[语音] ${kind.name} 引擎起不来，本次运行跳过：$error');
      return null;
    }
  }

  /// 把一句话合成成语音条。失败或不可用时返回 null。
  Future<VoiceClip?> speak({
    required String text,
    required String personaId,
    String voiceModel = '',
    String voiceDescription = '',
    bool wantsDescription = false,
    String referenceAudioPath = '',
    String referenceText = '',
    bool preferLocalClone = false,
  }) async {
    final transcript = _clean(text);
    if (transcript.isEmpty) return null;

    // 用户的帖子里会出现话题标签、@、"哈哈哈哈"这类东西，
    // 念出来很奇怪；能读出人话才合成，读不出来就退回文字。
    if (!_worthSpeaking(transcript)) return null;

    // 评论区只传得到 personaId；住民已经把音色定成“本机克隆”时，
    // 从这里把参考音频和逐字稿找回来，保证评论和私信是同一把嗓子。
    var cloneAudio = referenceAudioPath;
    var cloneText = referenceText;
    var localClone = preferLocalClone;
    if (!localClone && cloneAudio.isEmpty && voiceModel == 'local:zipvoice') {
      final resident = await lookupResident?.call(personaId);
      if (resident != null &&
          resident.voiceSamplePath.trim().isNotEmpty &&
          resident.voiceSampleText.trim().isNotEmpty) {
        cloneAudio = resident.voiceSamplePath;
        cloneText = resident.voiceSampleText;
        localClone = true;
      }
    }

    // 克隆出来的音色、或者明确指定云端音色的，必须走云端——
    // 否则“本机优先”会拿一个内置嗓子把它顶掉。
    final forceCloud =
        voiceModel.startsWith('cloud:') || voiceModel.startsWith('speech:');
    // 本机声线（local:<sid> / local:zipvoice）已经定死了嗓子，
    // 不该因为“语音来源”是云端就被换成一个陌生预设音色。
    final forceLocal = voiceModel.startsWith('local:');
    final preferCloud =
        forceCloud || (!forceLocal && readSource?.call() == VoiceSource.cloud);
    final cloudConfig = await _cloudConfig();
    final localSid = _localSidOf(voiceModel);
    final cloudVoice = _cloudVoiceOf(voiceModel);

    // 本机克隆：参考音频 + 逐字稿交给 ZipVoice。它要排在云端偏好之前——
    // 住民已经用本机克隆定了嗓子，不该因为“语音来源”切到云端就变成
    // 一个陌生的预设音色。失败把原因抛回给模型，不悄悄换嗓子。
    if (localClone &&
        cloneAudio.trim().isNotEmpty &&
        cloneText.trim().isNotEmpty) {
      return _speakZipVoice(
        transcript: transcript,
        referenceAudioPath: cloneAudio,
        referenceText: cloneText,
        speed: ResidentVoice.speedFor(voiceModel),
      );
    }

    // 用户选了云端、而且确实有一条能用的 TTS 配置：先走云端。
    // 云端失败（断网、额度、服务商抽风）就继续往下走本机，
    // 评论区不该因为一次网络抖动就少一条语音。
    if (!forceLocal && preferCloud && cloudConfig != null) {
      final clip = await _speakCloud(
        config: cloudConfig,
        transcript: transcript,
        personaId: personaId,
        voiceModel: voiceModel,
        voiceOverride: cloudVoice,
        instructions: wantsDescription ? voiceDescription : '',
      );
      if (clip != null) return clip;
      debugPrint('[语音] 云端没合成出来，退回本机');
    }

    final local = await _speakLocal(
      transcript: transcript,
      personaId: personaId,
      voiceModel: voiceModel,
      sid: localSid,
    );
    if (local != null) return local;

    // 用户选的是本机，但本机模型没放、引擎起不来；这时有云端配置就补上。
    if (!forceLocal && !preferCloud && cloudConfig != null) {
      return _speakCloud(
        config: cloudConfig,
        transcript: transcript,
        personaId: personaId,
        voiceModel: voiceModel,
        voiceOverride: cloudVoice,
        instructions: wantsDescription ? voiceDescription : '',
      );
    }
    return null;
  }

  /// 本机 ZipVoice 克隆合成。失败抛 [StateError]，由调用方把原因交回模型。
  Future<VoiceClip> _speakZipVoice({
    required String transcript,
    required String referenceAudioPath,
    required String referenceText,
    required double speed,
  }) async {
    final engine = await _ensureLocal(_LocalModel.zipvoice);
    if (engine == null) {
      throw StateError('本地克隆模型没有装好');
    }

    final path = referenceAudioPath.replaceFirst('file:', '');
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('找不到参考音频文件');
    }
    final pcm = _WavPcm.tryParse(await file.readAsBytes());
    if (pcm == null) {
      // 目前没有引入 mp3/m4a 解码器；在编辑页选 wav 就能走本机克隆。
      throw StateError('本地克隆需要 wav 格式的参考音频');
    }

    final audio = engine.generateWithConfig(
      text: transcript,
      config: sherpa.OfflineTtsGenerationConfig(
        referenceAudio: pcm.samples,
        referenceSampleRate: pcm.sampleRate,
        referenceText: referenceText.trim(),
        // ZipVoice 蒸馏版推荐 4 步；再少会有明显底噪。
        numSteps: 4,
        speed: speed,
      ),
    );
    if (audio.samples.isEmpty || audio.sampleRate <= 0) {
      throw StateError('本地克隆没有生成出音频');
    }

    final out = await media.newVoiceFile();
    final written = sherpa.writeWave(
      filename: out.path,
      samples: audio.samples,
      sampleRate: audio.sampleRate,
    );
    if (!written) throw StateError('语音文件没写出来');

    return VoiceClip(
      ref: 'file:${out.path}',
      transcript: transcript,
      durationMs: VoiceWaveform.durationMs(
        audio.samples.length,
        audio.sampleRate,
      ),
      waveform: VoiceWaveform.bars(audio.samples),
    );
  }

  /// `local:42` → 42；不是这个格式就返回 null（说明走默认映射）。
  static int? _localSidOf(String voiceModel) {
    if (!voiceModel.startsWith('local:')) return null;
    return int.tryParse(voiceModel.substring('local:'.length));
  }

  /// `cloud:anna` / `speech:...` → 直接交给服务商。
  static String? _cloudVoiceOf(String voiceModel) {
    if (voiceModel.startsWith('cloud:')) {
      final value = voiceModel.substring('cloud:'.length).trim();
      return value.isEmpty ? null : value;
    }
    if (voiceModel.startsWith('speech:')) return voiceModel;
    return null;
  }

  /// 当前能用的云端 TTS 配置。读不出来就当没配。
  Future<ModelConfig?> _cloudConfig() async {
    final client = gateway;
    if (client == null) return null;
    try {
      return await client.activeConfig(kind: ModelKind.tts);
    } catch (error) {
      debugPrint('[语音] 读云端语音配置失败：$error');
      return null;
    }
  }

  /// 走云端合成：音频字节直接落盘，播放那一层不需要知道它是谁生成的。
  Future<VoiceClip?> _speakCloud({
    required ModelConfig config,
    required String transcript,
    required String personaId,
    required String voiceModel,
    String? voiceOverride,
    String instructions = '',
  }) async {
    final client = gateway;
    if (client == null) return null;

    try {
      final bytes = await client.speech(
        config: config,
        text: transcript,
        voice:
            voiceOverride ??
            ResidentVoice.cloudVoiceFor(
              personaId,
              voiceModel: voiceModel,
              baseUrl: config.baseUrl,
            ),
        instructions: instructions,
      );
      if (bytes.isEmpty) return null;

      // 有的服务商回 wav（44.1kHz PCM），能直接算波形和时长；
      // 其他家多是 mp3，拿不到采样点就按字数估时长、波形交给播放层。
      final wav = _WavPcm.tryParse(bytes);
      final file = await media.newVoiceFile(
        extension: wav == null ? '.mp3' : '.wav',
      );
      await file.writeAsBytes(bytes, flush: true);

      return VoiceClip(
        ref: 'file:${file.path}',
        transcript: transcript,
        durationMs: wav == null
            ? _estimateDurationMs(transcript)
            : VoiceWaveform.durationMs(
                wav.samples.length,
                wav.sampleRate,
              ),
        waveform: wav == null ? const [] : VoiceWaveform.bars(wav.samples),
      );
    } catch (error) {
      debugPrint('[语音] 云端这句没合成出来：$error');
      return null;
    }
  }

  /// 本机离线合成。
  Future<VoiceClip?> _speakLocal({
    required String transcript,
    required String personaId,
    required String voiceModel,
    int? sid,
  }) async {
    final engine = await _ensureLocal(_LocalModel.vits);
    if (engine == null) return null;

    try {
      final audio = engine.generate(
        text: transcript,
        sid:
            sid ??
            ResidentVoice.sidFor(personaId, voiceModel: voiceModel),
        speed: ResidentVoice.speedFor(voiceModel),
      );
      if (audio.samples.isEmpty || audio.sampleRate <= 0) return null;

      final file = await media.newVoiceFile();
      final written = sherpa.writeWave(
        filename: file.path,
        samples: audio.samples,
        sampleRate: audio.sampleRate,
      );
      if (!written) return null;

      return VoiceClip(
        ref: 'file:${file.path}',
        transcript: transcript,
        durationMs: VoiceWaveform.durationMs(
          audio.samples.length,
          audio.sampleRate,
        ),
        waveform: VoiceWaveform.bars(audio.samples),
      );
    } catch (error) {
      debugPrint('[语音] 本机这句没合成出来：$error');
      return null;
    }
  }

  /// 中文大约每秒四五个字。只用于气泡上的秒数，不参与任何调度。
  static int _estimateDurationMs(String text) =>
      (text.runes.length * 240).clamp(900, 20000);

  /// 合成前的清理：一行、不带话题标签、不超过长度上限。
  static String _clean(String text) {
    var cleaned = text
        .replaceAll(RegExp(r'#([^#]{1,20})#'), r'$1')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.length > maxTranscriptLength) {
      cleaned = cleaned.substring(0, maxTranscriptLength);
    }
    return cleaned;
  }

  /// 这句话值不值得念。
  ///
  /// 全是表情、标点或者语气词的（"哈哈哈哈"、"？"、"蹲"）合成出来只有噪音，
  /// 判断放在合成之前：白合成一次要等好几秒，而用户看到的是一个占位语音条。
  static bool _worthSpeaking(String text) {
    final meaningful = text.replaceAll(
      RegExp(r'[\s\p{P}\p{S}哈呵嘿嘻呜唉诶嗯哦噢啊呀吧呢嘛]', unicode: true),
      '',
    );
    return meaningful.length >= 2;
  }
}

/// 从 wav 里读 PCM，给气泡算时长和波形用。
///
/// 只需要单声道浮点采样，不追求把整份 wav 解析器写完：
/// 44.1kHz / 16-bit PCM 的 wav 是常见格式；解析失败就返回 null，
/// 调用方按“不知道时长”处理，不影响播放。
class _WavPcm {
  const _WavPcm({required this.samples, required this.sampleRate});

  final Float32List samples;
  final int sampleRate;

  static _WavPcm? tryParse(Uint8List bytes) {
    if (bytes.length < 44) return null;
    if (String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      return null;
    }
    final data = ByteData.sublistView(bytes);
    var pos = 12;
    int? sampleRate;
    int? channels;
    int? bits;
    Float32List? pcm;

    while (pos + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      final size = data.getUint32(pos + 4, Endian.little);
      final start = pos + 8;
      if (start + size > bytes.length && id != 'data') break;

      if (id == 'fmt ' && size >= 16) {
        final format = data.getUint16(start, Endian.little);
        channels = data.getUint16(start + 2, Endian.little);
        sampleRate = data.getUint32(start + 4, Endian.little);
        bits = data.getUint16(start + 14, Endian.little);
        // 只认整数 PCM；float32 的 wav 让播放层自己处理。
        if (format != 1) return null;
      } else if (id == 'data') {
        if (sampleRate == null || channels == null || bits == null) return null;
        final available = (bytes.length - start).clamp(0, size);
        if (bits == 16) {
          final frames = available ~/ (2 * channels);
          if (frames <= 0) return null;
          final samples = Float32List(frames);
          var read = start;
          for (var i = 0; i < frames; i++) {
            var sum = 0.0;
            for (var c = 0; c < channels; c++) {
              sum += data.getInt16(read, Endian.little) / 32768.0;
              read += 2;
            }
            samples[i] = sum / channels;
          }
          pcm = samples;
        } else if (bits == 8) {
          final frames = available ~/ channels;
          if (frames <= 0) return null;
          final samples = Float32List(frames);
          var read = start;
          for (var i = 0; i < frames; i++) {
            var sum = 0.0;
            for (var c = 0; c < channels; c++) {
              sum += (bytes[read] - 128) / 128.0;
              read++;
            }
            samples[i] = sum / channels;
          }
          pcm = samples;
        } else {
          return null;
        }
        break;
      }
      pos = start + size + (size.isOdd ? 1 : 0);
    }

    if (pcm == null || sampleRate == null || sampleRate <= 0) return null;
    return _WavPcm(samples: pcm, sampleRate: sampleRate);
  }
}

enum _LocalModel { vits, zipvoice }

final ttsServiceProvider = Provider<TtsService>(
  (ref) => TtsService(
    store: ref.watch(speechModelStoreProvider),
    gateway: ref.watch(modelGatewayProvider),
    readSource: () => ref.read(voiceSettingsControllerProvider).source,
    lookupResident: (id) =>
        ref.read(customResidentRepositoryProvider).findById(id),
  ),
);
