/// 模型接入配置（规划书 §6.9 / M5）。
///
/// 只放"怎么连"（地址、模型名）——**API Key 不在这里**，
/// 它存在系统钥匙串里，由仓储按 id 取。
class ModelConfig {
  const ModelConfig({
    required this.id,
    required this.provider,
    required this.label,
    required this.baseUrl,
    required this.model,
    this.enabled = false,
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  final String id;

  /// 预设服务商标识：deepseek / openai / qwen / zhipu / custom
  final String provider;

  /// 展示名，用户可改
  final String label;

  /// OpenAI 兼容的 base url（不带 /chat/completions）
  final String baseUrl;
  final String model;

  /// 当前启用中的那一条（同一时间只允许一条）
  final bool enabled;

  final int createdAt;
  final int updatedAt;

  bool get isComplete => baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;

  /// 预设服务商（2026-09 逐一按各家官方文档核对过）。
  ///
  /// 地址和模型名都只是"默认值"，用户随时能改——预设不是白名单。
  /// 顺序按国内常用度排，OpenAI 放最后（中国大陆连不上，留着给有海外网络的）。
  static const List<ModelPreset> presets = [
    ModelPreset(
      id: 'deepseek',
      label: 'DeepSeek',
      // 官方给的 base_url 就是裸域，**不加 /v1**
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-flash',
      altModels: ['deepseek-v4-pro'],
    ),
    ModelPreset(
      id: 'qwen',
      label: '通义千问',
      // 国际版是 dashscope-intl，两个地域的 Key 不通用
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      model: 'qwen3.7-plus',
      altModels: ['qwen3.8-max', 'qwen3.8-flash', 'qwen-long'],
    ),
    ModelPreset(
      id: 'zhipu',
      label: '智谱 GLM',
      // /api/paas/v4 是 base_url 的一部分，少了会 404
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      model: 'glm-5.3',
      altModels: ['glm-5-turbo', 'glm-5.2', 'glm-4.7-flash'],
    ),
    ModelPreset(
      id: 'kimi',
      label: 'Kimi（月之暗面）',
      // 必须带 /v1；中国站与国际站的 Key 完全隔离
      baseUrl: 'https://api.moonshot.cn/v1',
      model: 'kimi-k2.6',
      altModels: ['kimi-k3', 'kimi-k2.7-code'],
    ),
    ModelPreset(
      id: 'doubao',
      label: '豆包（火山方舟）',
      // 要先在控制台"开通管理"里开通对应模型，否则报错
      baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
      model: 'doubao-seed-2-1-pro-260628',
      altModels: [
        'doubao-seed-2-1-turbo-260628',
        'doubao-seed-2-0-lite-260428',
        'doubao-seed-evolving',
      ],
    ),
    ModelPreset(
      id: 'siliconflow',
      label: '硅基流动',
      // 聚合平台：一个 Key 用多家开源模型。模型 id 大小写敏感
      baseUrl: 'https://api.siliconflow.cn/v1',
      model: 'deepseek-ai/DeepSeek-V4-Flash',
      altModels: [
        'deepseek-ai/DeepSeek-V3.2',
        'Pro/deepseek-ai/DeepSeek-V4',
        'Pro/zai-org/GLM-5.2',
        'Pro/moonshotai/Kimi-K2.6',
      ],
    ),
    ModelPreset(
      id: 'hunyuan',
      label: '腾讯混元',
      // 旧的 api.hunyuan.cloud.tencent.com 已停服，走 TokenHub
      baseUrl: 'https://tokenhub.tencentmaas.com/v1',
      model: 'hy4-preview',
      altModels: ['hy3', 'hunyuan-role-latest'],
    ),
    ModelPreset(
      id: 'ernie',
      label: '百度文心',
      // 老的 access_token 那套 V1 接口已下线，走千帆 V2
      baseUrl: 'https://qianfan.baidubce.com/v2',
      model: 'ernie-5.1',
      altModels: [
        'ernie-5.0',
        'ernie-4.5-turbo-128k',
        'ernie-5.0-thinking-preview',
      ],
    ),
    ModelPreset(
      id: 'minimax',
      label: 'MiniMax',
      // 国内站是 .cn，国际站是 .io，两套 Key 不通用
      baseUrl: 'https://api.minimax.cn/v1',
      model: 'MiniMax-M3',
      altModels: ['MiniMax-M2.7', 'MiniMax-M2.7-highspeed'],
    ),
    ModelPreset(
      id: 'openai',
      label: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-6-astra',
      altModels: ['gpt-5.4-mini', 'gpt-5.4-nano', 'o4-mini'],
    ),
    ModelPreset(id: 'custom', label: '自定义（OpenAI 兼容）', baseUrl: '', model: ''),
  ];

  static ModelPreset presetOf(String providerId) => presets.firstWhere(
    (preset) => preset.id == providerId,
    orElse: () => presets.last,
  );

  ModelConfig copyWith({
    String? provider,
    String? label,
    String? baseUrl,
    String? model,
    bool? enabled,
    int? createdAt,
    int? updatedAt,
  }) {
    return ModelConfig(
      id: id,
      provider: provider ?? this.provider,
      label: label ?? this.label,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 预设服务商。
class ModelPreset {
  const ModelPreset({
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.model,
    this.altModels = const [],
  });

  final String id;
  final String label;
  final String baseUrl;

  /// 默认模型
  final String model;

  /// 同一家的其他常用模型（点一下就换上，省得记名字）
  final List<String> altModels;
}
