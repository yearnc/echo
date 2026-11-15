# 回响 Echo

**双模式社交媒体模拟器**，思政实践课题《数字时代大学生自我价值感的异化与重建》配套应用，同时作为同名思政微电影的核心道具。

同一个界面提供两种彼此对照的使用方式：

- **回响模式**：用户发布内容后，由本地调度的 AI 网民与可配置的固定住民产生浏览、点赞、评论、私信与动态。这里不存在真实用户，所有互动内容均标记为 `is_ai = true`。
- **清醒模式**：关闭全部虚拟反馈，仅呈现依据本机记录计算出的客观数据（记录频率、互动构成、AI 内容占比、情绪走向、时间分布），并提供数字关系反思、真实生活相册与价值重建练习。该模式的统计不调用模型，也不作价值评判。

项目的核心命题是：**“被回应”的体验可以被制造，而对它的依赖程度往往只有在它消失时才被察觉。** 应用将这一机制开放给使用者，由使用者自行切换与观察。

**项目状态**：功能开发已完成，进入维护阶段。后续仅进行兼容性、安全性与缺陷修复，不再新增功能模块。

---

## 1. 功能概览

### 1.1 回响模式

| 模块 | 说明 |
|---|---|
| 临时网民 | 发帖后按内容解析结果聚集不同人群，执行浏览、点赞、评论与接梗；评论支持楼中楼追问 |
| 固定住民 | 用户自行配置的长期角色。可自主唤醒、调用工具、发帖、评论、私信，并维护与用户的关系和长期记忆 |
| 内容生成 | 支持样本内容与模型生成两种来源，按可用性自动选路与降级。未配置模型时仍可完整走通离线流程 |
| 知识库 | 独立库与共享库两种作用域；内置“热门梗”库每周增量更新，条目带来源与有效期 |
| 游戏 | 内置五子棋、中国象棋、多人狼人杀；支持声明式 JSON 插件扩展 |
| 桌宠 | 固定住民的独立形象，可跨应用悬浮，支持普通观察与实时观察 |
| 私信与通话 | 私信、语音消息、按住说话、可打断的（伪）视频通话；支持本机语音识别与合成 |
| 策划脚本 | 为微电影拍摄预设帖子互动时间线，全程离线运行，不替代用户手动操作 |

### 1.2 清醒模式

| 模块 | 说明 |
|---|---|
| 记录时间线 | 统一汇总发布页图文记录与真实行动页的快速打点 |
| 客观分析 | 基于本机数据统计记录频率、互动构成、AI 占比、情绪走向与时间分布，不调用模型 |
| 数字关系反思 | 引导使用者观察自身与虚拟反馈之间的关系 |
| 真实生活相册 | 本地图片，随清醒数据一同管理与删除 |
| 价值重建 | 价值澄清练习、真实行动记录与周报 |
| 心理安全 | 提供心理援助热线入口与自助提示 |
| 防沉迷 | 默认开启提醒，仅提示、不拦截；每日上限由用户自行设置，默认关闭 |

### 1.3 数据边界

- 清醒侧与回响侧数据通过 `scope` 严格隔离：清醒分析只统计 `scope = clear` 的记录，导出数据不含任何 AI 互动。
- 清醒数据支持完整导出与一键删除，相册删除时同步清理图片文件。
- API 密钥保存在系统钥匙串（Android Keystore / iOS Keychain / Windows 凭据管理器），不写入数据库，不进入代码。
- 项目不设自有服务器，除用户主动调用第三方模型接口外，数据仅保存在本机。

---

## 2. 技术栈

| 层次 | 选型 |
|---|---|
| 应用框架 | Flutter 3.47.3 / Dart 3.13 |
| 状态管理 | flutter_riverpod 3.x |
| 路由 | go_router 18.x |
| 本地数据库 | Drift 2.35（SQLite，schema v53，47 张表） |
| 网络 | dio 5.x |
| 安全存储 | flutter_secure_storage 11.x |
| 通知与调度 | flutter_local_notifications 22.x、WorkManager 0.10 |
| 语音 | sherpa_onnx 1.13（离线识别与合成）、record、just_audio、camera |
| 其他 | image、archive、cryptography、cchess、file_picker、share_plus、url_launcher |

代码规模：`lib/` 约 249 个手写 Dart 文件、7.1 万行，另有 Drift 生成的 `app_database.g.dart` 约 4.6 万行；`test/` 68 个测试文件。

---

## 3. 项目结构

```
lib/
├─ app.dart                 应用根组件与前台心跳
├─ core/                    常量、合规文案、主题、路由、通用工具
├─ domain/
│  ├─ models/               领域模型（帖子、住民、记忆、脚本、对局等）
│  └─ services/             调度、围观、内容生成、记忆、唤醒与会话、
│                           语音、知识库、联网搜索、清醒分析、数据导出
├─ data/
│  ├─ db/                   Drift 表定义、迁移与种子数据
│  ├─ repositories/         数据仓储实现
│  └─ media/                图片选择、落盘与模型图片编码
└─ features/                按页面组织：feed / composer / post_detail /
                            residents / messages / pet / games / knowledge /
                            records / analysis / values / actions /
                            settings / resources / help 等

docs/                       设计与实施文档（见第 9 节）
resources/                  离线模型资源清单
tool/                       资源打包等辅助脚本
```

---

## 4. 快速开始

### 4.1 环境要求

- Flutter stable 3.47.3
- JDK 17 及以上
- Android SDK：platform-tools、android-35、build-tools

国内网络环境建议配置镜像：

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

### 4.2 初始化与运行

```bash
flutter pub get

# 数据库代码由 drift 生成；修改 lib/data/db/tables/ 后必须重新生成
dart run build_runner build

flutter run                 # Android / iOS 真机或模拟器
flutter run -d windows      # 桌面预览（手机尺寸窗口，需开启 Windows 开发人员模式）
```

> 桌面预览可运行语音合成，但音频播放依赖移动平台插件，Windows 下无声音输出。

### 4.3 构建

```bash
# 按 ABI 拆包，真机使用 arm64-v8a
flutter build apk --release --split-per-abi
```

`--target-platform android-arm64` 仅约束 Flutter 自身库，插件携带的原生库仍会打包全部 ABI，因此发布应使用 `--split-per-abi`。

当前 release 构建使用模板默认的 debug 签名，仅支持侧载安装；正式签名配置待后续补充。

### 4.4 测试与静态检查

```bash
flutter test        # 539 个测试
flutter analyze     # 应输出 No issues found
```

---

## 5. 离线语音模型

自 v4.4 起，发布包不内置语音模型，用户在「我的 → 下载资源」中按需下载。文件保存在应用私有目录 `speech_models/`，升级应用不会丢失；未下载时文字功能不受影响，语音入口会提示先行下载。

模型文件不纳入仓库。开发环境如需构建全量包，可取消 `pubspec.yaml` 中对应的 `assets/models/...` 注释，并按各目录下的 `_placeholder.txt` 放置文件：

| 目录 | 内容 | 约体积 |
|---|---|---|
| `assets/models/tts/` | vits-zh-ll，内置 5 个中文声线 | 117 MB |
| `assets/models/zipvoice/` | ZipVoice INT8 + vocos 声码器，用于参考音频克隆 | 196 MB |
| `assets/models/asr/` | SenseVoice int8 + tokens，用于私信与发帖转写 | 229 MB |
| `assets/models/asr-stream/` | 流式双语 zipformer，用于通话 | 190 MB |
| `assets/pet_frames/` | 桌宠透明帧序列（106 个动作 × 48 帧无损 WebP） | 107 MB |

语音识别与合成均在本机完成，录音与音频不上传。云端语音合成仅在用户自行配置后启用。

### 5.1 打包模型资源

```bash
python tool/package_resources.py \
  --models-dir assets/models \
  --out-dir ../echo-models \
  --manifest resources/manifest.json
```

脚本生成四个 `echo-models-*-v1.zip` 及包含体积与 SHA256 的 `manifest.json`。将压缩包作为 Release `models-v1` 的附件上传，并同步更新 `resources/manifest.json`。资源版本变化后，应用仅下载版本已变更的文件。

模型资源已发布：[Releases models-v1](https://github.com/yearnc/echo/releases/tag/models-v1)。

---

## 6. 模型配置（可选）

清醒模式分析、策划脚本排期与样本内容生成**完全离线**，无需 API Key。仅以下能力需要配置模型：

- 临时网民生成
- 帖子解析
- 固定住民唤醒、私信与工具调用
- 图片理解
- 联网搜索

配置入口：设置 → 模型配置中心 → 新建。可选择服务商预设（DeepSeek、通义千问、智谱、Kimi、豆包、硅基流动、混元、文心、MiniMax、OpenAI）或自定义 OpenAI 兼容接口。

注意事项：

- 对话、文生图、语音合成、图片理解是四种独立用途，分别配置，不合并计费与接口。
- 固定住民的工具调用依赖 `function calling`，模型需支持；不支持时退化为普通文本回复。
- 本机语音合成支持 vits-zh-ll（5 个中文声线）与 ZipVoice（参考音频 + 逐字稿克隆）。本机克隆要求 wav 参考音频；mp3/m4a 需先转换或使用云端克隆。
- 临时网民的评论语音合成已下线，语音仅由固定住民发送。
- 调用第三方接口时，帖子内容、必要的社区上下文及用户在「我的身份」中填写的资料会发送至所配置的服务商；图片仅在开启图片理解或原图直发时发送。

---

## 7. 策划脚本（微视频拍摄）

内置三幕脚本已下线，策划模式保留自定义能力：

1. 设置 → 策划脚本 → 新建；
2. 配置第几秒由谁点赞、评论、设定计数或展示分析；
3. 评论区事件仅可选择固定住民；
4. 返回发布页，在策划模式中勾选脚本后发布，拍摄期间不再操作屏幕。

脚本只定义帖子将收到的回应，不切换模式、不跳转页面、不代替用户执行操作。

---

## 8. 版本与发布

当前源码版本：**v4.12.2+72**，数据库 schema **v53**。

**v4.12.2 精简版 APK**：
[Releases v4.12.2](https://github.com/yearnc/echo/releases/tag/v4.12.2)

- 文件：`echo-v4.12.2-arm64.apk`
- 大小：159,878,474 字节（约 152.5 MiB）
- versionName / versionCode：4.12.2 / 2072
- SHA256：`c2c52dc0a9c18a89ffa19b5ea159269f8707a26077358642c53f8b428b8ab630`

GitHub Releases 仅提供精简包，语音模型作为 `models-v1` 的独立附件发布。历史版本与逐版本说明见 [`更新日志.log`](更新日志.log)。

本版主要修复：DeepSeek 接口在接收 `safety_check` 后可能返回空内容，导致固定住民唤醒后无输出。处理方式为保留审核开关但默认关闭，修正 `refusal: false` 的误判，并将思考模式输出预算由 420 提升至 2048。

---

## 9. 文档索引

| 文档 | 内容 |
|---|---|
| [`docs/环境搭建备忘.md`](docs/环境搭建备忘.md) | 开发环境配置、已知构建问题与处理方案 |
| [`docs/阶段A实施计划.md`](docs/阶段A实施计划.md) | 微视频演示 MVP（已归档） |
| [`docs/阶段B实施计划.md`](docs/阶段B实施计划.md) | 完整单机版（已归档） |
| [`docs/阶段C_v3.0重构规划.md`](docs/阶段C_v3.0重构规划.md) | v3.0 重构记录（已归档） |
| [`docs/阶段D_V4.0规划.md`](docs/阶段D_V4.0规划.md) | v4.0 回响模式扩展（已归档） |
| [`docs/游戏插件架构.md`](docs/游戏插件架构.md) | 声明式游戏插件清单格式与安全边界 |
| [`更新日志.log`](更新日志.log) | 逐版本变更记录 |

---

## 10. 合规与伦理边界

本项目在设计与实现中遵循以下约束：

- 回响模式所有页面固定展示「内容由 AI 生成，仅供参考」，数据层以 `is_ai = true` 标记。
- 清醒模式的永久提示不可关闭、不可删除，界面不提供关闭入口，代码不提供删除路径。
- 防沉迷提醒默认开启，仅提醒、不拦截：不锁屏、不劝退、不将使用时长设计为需要攻克的指标。
- 清醒模式的每日上限由用户自行设置，默认关闭，到达后仅提醒一次。
- 清醒侧与回响侧数据严格隔离，导出文件不含 AI 互动记录。
- 清醒数据支持随时导出与彻底删除。
- 心理安全页提供援助热线入口（12356，以官方最新公布为准）。
- 情绪持续低落时，请寻求真实的人际支持。应用内的 AI 网民不能替代真实对话。

---

## 11. 许可

本项目采用 [MIT 许可证](LICENSE)。作为课程作业与公开实践项目，欢迎参考与修改；其中的 AI 住民人格设定与素材请替换为自行准备的内容。
