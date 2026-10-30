import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/media/media_service.dart';
import '../../data/repositories/custom_resident_repository.dart';
import '../models/custom_resident.dart';
import '../models/model_config.dart';
import '../models/resident_voice.dart';
import 'model_gateway.dart';
import 'speech_models.dart';
import 'speech_runtime.dart';
import 'speech_worker.dart';
import 'voice_waveform.dart';
import 'wav_pcm.dart';

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
    this.lookupResident,
  }) : _store = store ?? SpeechModelStore();

  final SpeechModelStore _store;
  final MediaService media;

  /// 云端 TTS 的通道。为空（或没配 TTS 配置）就只走本机。
  final ModelGateway? gateway;

  /// 评论区的语音只有 personaId，没有住民对象；靠它把参考音频找回来，
  /// 这样同一个住民在私信和评论里听起来是同一个人。
  final Future<CustomResident?> Function(String residentId)? lookupResident;

  /// 一句话最多合成这么多字。
  ///
  /// 语音评论本来就不长（住在评论区里，用户要等它放完），
  /// 超过这个长度的一律退回文字——一分钟的语音条没人会听。
  static const int maxTranscriptLength = 120;

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
    _lastLocalMissing = null;

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
    // 不该被云端配置顶掉。没有明确指定云端音色时一律走本机——
    // 全局“语音来源”开关已经下线，音色方式本身决定走哪条路。
    final forceLocal = voiceModel.startsWith('local:');
    final preferCloud = forceCloud;
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
      final cloud = await _speakCloud(
        config: cloudConfig,
        transcript: transcript,
        personaId: personaId,
        voiceModel: voiceModel,
        voiceOverride: cloudVoice,
        instructions: wantsDescription ? voiceDescription : '',
      );
      if (cloud != null) return cloud;
    }
    // 两条路都没成，但本机是“模型没下载”而不是合成失败：把下载提示抛出去。
    final missing = _lastLocalMissing;
    if (missing != null) throw missing;
    return null;
  }

  /// 本机 ZipVoice 克隆合成。失败抛 [StateError]，由调用方把原因交回模型。
  Future<VoiceClip> _speakZipVoice({
    required String transcript,
    required String referenceAudioPath,
    required String referenceText,
    required double speed,
  }) async {
    final path = referenceAudioPath.replaceFirst('file:', '');
    if (!await File(path).exists()) {
      throw StateError('找不到参考音频文件');
    }
    // 目前没有引入 mp3/m4a 解码器；在编辑页选 wav 就能走本机克隆。
    if (!path.toLowerCase().endsWith('.wav')) {
      throw StateError('本地克隆需要 wav 格式的参考音频');
    }

    final models = await _store.prepareZipVoice();
    final out = await media.newVoiceFile();
    final reply = await SpeechWorker.instance.synthesize(
      SpeechWorkerRequest(
        kind: 'zipvoice',
        text: transcript,
        outputPath: out.path,
        files: {
          'tokens': models.pathOf('tokens.txt'),
          'encoder': models.pathOf('encoder.int8.onnx'),
          'decoder': models.pathOf('decoder.int8.onnx'),
          // 声码器单独一份，归档里叫 vocos_24khz.onnx。
          'vocoder': models.pathOf('vocos_24khz.onnx'),
          'dataDir': models.pathOf('espeak-ng-data'),
          'lexicon': models.pathOf('lexicon.txt'),
        },
        speed: speed,
        referenceAudioPath: path,
        referenceText: referenceText,
        libraryPath: SpeechRuntime.resolveLibraryPath(),
      ),
    );
    if (!reply.ok) throw StateError(reply.error);

    return VoiceClip(
      ref: 'file:${reply.path}',
      transcript: transcript,
      durationMs: reply.durationMs,
      waveform: reply.waveform,
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
      final wav = WavPcm.tryParse(bytes);
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
  SpeechModelMissing? _lastLocalMissing;

  Future<VoiceClip?> _speakLocal({
    required String transcript,
    required String personaId,
    required String voiceModel,
    int? sid,
  }) async {
    try {
      final models = await _store.prepareTts();
      final file = await media.newVoiceFile();
      final reply = await SpeechWorker.instance.synthesize(
        SpeechWorkerRequest(
          kind: 'vits',
          text: transcript,
          outputPath: file.path,
          files: {
            'model': models.pathOf('model.onnx'),
            'lexicon': models.pathOf('lexicon.txt'),
            'tokens': models.pathOf('tokens.txt'),
            // 不传的话“3月24日”会被念成别的东西。
            'date': models.pathOf('date.fst'),
            'number': models.pathOf('number.fst'),
            'phone': models.pathOf('phone.fst'),
          },
          sid:
              sid ??
              ResidentVoice.sidFor(personaId, voiceModel: voiceModel),
          speed: ResidentVoice.speedFor(voiceModel),
        ),
      );
      if (!reply.ok) {
        debugPrint('[语音] 本机这句没合成出来：${reply.error}');
        return null;
      }

      return VoiceClip(
        ref: 'file:${reply.path}',
        transcript: transcript,
        durationMs: reply.durationMs,
        waveform: reply.waveform,
      );
    } on SpeechModelMissing catch (error) {
      // 精简版没内置模型。先记住原因：如果云端还能合成，就继续走云端；
      // 最后还是没合成出来，再把“去下载”这句话原样交给调用方。
      _lastLocalMissing = error;
      return null;
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

final ttsServiceProvider = Provider<TtsService>(
  (ref) => TtsService(
    store: ref.watch(speechModelStoreProvider),
    gateway: ref.watch(modelGatewayProvider),
    lookupResident: (id) =>
        ref.read(customResidentRepositoryProvider).findById(id),
  ),
);
