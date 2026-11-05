# 回响 Echo

一个**单 App 双模式**的社交媒体模拟器。同一块屏幕，两个世界：

- **回响模式** —— 你发一条帖子，周围会临时聚起一群像真人的网民：有人只看、有人点赞、有人接梗。你也可以自己配置固定住民，他们会自己醒来、用工具决定回不回、发不发帖，并记住你们聊过的事。**这里没有一个真实用户。**
- **清醒模式** —— 关掉所有虚拟反馈，只留**根据本机记录算出来的客观分析**（记录频率 / 互动构成 / AI 占比 / 情绪走向 / 时间分布）、数字关系反思、真实生活相册，以及价值重建练习（价值澄清、真实行动记录）。这里的数字不调用模型，也不评价你。

做这个东西的动机很简单：**「被回应」的感觉是可以被制造的**，而人在多大程度上依赖它，往往要等到它消失时才看得清。这个 APP 想把这件事摆到台面上，让你亲手开关一次。

> 项目背景：思政实践课题《数字时代大学生自我价值感的异化与重建》，同时是一部微电影的核心道具。旧住民的内置三幕脚本已经整套下线；拍摄仍可用「策划脚本」自建事件，见下文。

## 当前版本 · v4.11.0

**知识库**

- 独立知识库：只服务临时网民，或只服务某一位固定住民。
- 共享知识库：自己勾选服务对象——全体临时网民、全体固定住民、指定住民。
- 内置「热门梗」空库：不预置内容，每周自动联网更新，每条写清来源、用处、2—3 个例子，
  30 天过期；更新失败保留旧内容。固定住民也能调用工具查和补。
- 临时网民按知识库分组生成稳定 system 前缀，不同册子形成不同评论风格，同时尽量命中缓存。
- 入口：设置 → 回响模式 → 知识库。

早期的里程碑与逐版本细节已移到 [`更新日志.log`](更新日志.log)，README 不再重复。

## 下载

当前源码 **v4.11.0+69（schema v51）**；公开安装包仍是 **v4.10.0 精简版**：
APK 不内置语音模型，装完约 152.3MB；需要语音识别 / 合成时，在
「我的 → 下载资源」里按需下载（约 117—229MB 一项）。

**v4.10.0 精简版**：
[**Releases v4.10.0**](https://github.com/yearnc/echo/releases/tag/v4.10.0)
`echo-v4.10.0-arm64.apk`（159,681,350 字节 / 约 152.3 MiB，
versionName 4.10.0 / versionCode 2068，
SHA256 `429fb5f4459159d3032bcd3f635d0b194842acb647605156d49d713b2561283d`）。

更早的安装包与逐版本说明见
[**Releases**](https://github.com/yearnc/echo/releases) 和
[`更新日志.log`](更新日志.log)。GitHub 以后只上传精简包；
模型作为 Release `models-v1` 的独立附件：

| 附件 | 内容 |
|---|---|
| `echo-models-asr-v1.zip` | SenseVoice 语音识别（约 229MB） |
| `echo-models-tts-v1.zip` | vits-zh-ll 文字语音，5 个中文声线（约 117MB） |
| `echo-models-zipvoice-v1.zip` | ZipVoice 音色克隆（约 187MB） |
| `echo-models-asr-stream-v1.zip` | 流式识别，通话用（约 190MB） |

模型资源已发布：
[**Releases models-v1**](https://github.com/yearnc/echo/releases/tag/models-v1)
（四个附件均已上传，SHA256 与 `resources/manifest.json` 一致；国内可用
`gh-proxy.com` 镜像，下载页也会在官方源失败时自动换镜像）。
清单在 `resources/manifest.json`；用 `tool/package_resources.py` 重新打包时会
一并算出体积和 SHA256。

- **策划脚本排期、清醒模式**可以离线跑，不需要 API Key；
- **临时网民、帖子解析、固定住民唤醒与私信、表情包选择、身份前缀需要配置一个对话模型**（任意 OpenAI 兼容接口，且支持 function calling）；没配模型时帖子照发，只是不会有人来；
- **固定住民的语音**可以只用本机模型：vits-zh-ll（5 个中文声线五选一）和 ZipVoice（wav 参考音频 + 逐字稿克隆）；精简版要先在「我的 → 下载资源」下载，云端克隆再配硅基流动 CosyVoice2；
- **本机语音识别**（v4.0）同样需要先下载 SenseVoice（私信/发帖转写）或流式 zipformer（通话）；没下载时文字聊天照常，语音按钮会提示先去下载；
- **清醒模式的客观分析不需要模型**：它只统计本机记录；
- **联网搜索默认关闭**，要用就在设置里选 DeepSeek 官方 Search / 智谱 / 百炼。DeepSeek 只要模型配置里有一条填好 Key 的 DeepSeek 配置即可，不需要把它设为当前对话模型；智谱/百炼则需要对应服务商的配置；
- **图片理解**还需要在「设置 → 模型配置」里单独加一条「图片理解」配置；私信图片要让住民看见，则要在对话模型上打开「这个模型能看图」；
- 用的是 Flutter 模板默认的 **debug 签名**，手机可能提示"未知来源"，允许安装即可（正式签名留到后续）；
- 只想自己编译的话看下面的「快速开始」。

## 快速开始

### 环境

开发时用的版本：Flutter stable（3.47.3）、JDK 17+、Android SDK（platform-tools / android-35 / build-tools）。

国内建议先配镜像，否则首次拉依赖会很慢：

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

### 离线语音模型（发布版按需下载）

**v4.4 起发布包不内置模型**：用户在「我的 → 下载资源」里下载，文件落在
应用私有的 `speech_models/`，升级 APP 不会丢。没下载时文字聊天照常，
语音按钮会提示先下载。

模型文件仍然**不进仓库**（几百兆的二进制会毁掉克隆体验），
`assets/models/*/_placeholder.txt` 只说明来源。开发时想打全量离线包，
把 `pubspec.yaml` 里四行 `assets/models/...` 取消注释即可（发布不要用）。
放哪、下哪个，照目录里的 `_placeholder.txt` 做：

- `assets/models/tts/` —— vits-zh-ll（内置 5 个中文声线，约 117MB）
- `assets/models/zipvoice/` —— ZipVoice INT8 + vocos 声码器（参考音频克隆，约 196MB）
- `assets/models/asr/` —— SenseVoice int8 + tokens（私信/发帖语音转写，约 229MB）
- `assets/models/asr-stream/` —— 流式双语 zipformer（P4 通话说一句出一句）
- `assets/pet_frames/` —— 桌宠透明帧序列（106 个动作 × 48 帧**无损 WebP**，共约 107MB；`manifest.json` 是动作清单、语义别名与走路参数。用序列而不是动画 WebP，避免部分 ROM 把 alpha 画成黑框）

合成与识别都在本机完成，录音和音频都不上传；云端 TTS 只在用户自己配置后才会用到。

> 阶段 B 收尾时曾经把“按住说话”移除了（手机输入法自带转文字）。
> v4.0 把它带回来，不是重复造轮子：私信和帖子里的语音由 App 自己转写，
> 才能同时保留音频、标注“这是谁说的”，并在通话里复用同一套识别。

### 跑起来

```bash
flutter pub get

# 数据库代码由 drift 生成；改过 lib/data/db/tables/ 下的表结构后必须重跑
dart run build_runner build

flutter run                 # 真机或模拟器
flutter run -d windows      # 桌面预览（手机尺寸窗口，需开启 Windows 开发人员模式）
```

> 桌面预览下语音**合成**能跑（Windows 用的是包里的 ONNX Runtime，
> 别被 `System32` 里那个旧版本抢了先，见 `lib/domain/services/speech_runtime.dart`），
> 但**播放**要 Android/iOS 才出声——桌面的音频输出靠平台插件，本项目没有接。

### 打包

```bash
# 按 ABI 拆包：每个架构一个 APK，真机装 arm64-v8a 那个就行
flutter build apk --release --split-per-abi
```

不拆的话，一个包里会带上 x86_64 / arm64-v8a / armeabi-v7a 三份原生库
（大头是 ONNX Runtime 与桌宠帧素材）。v4.8.0 精简版实测值：

| APK | 体积 |
|---|---|
| `app-arm64-v8a-release.apk`（真机） | **151.9 MiB**（159,222,122 字节） |
| `app-armeabi-v7a-release.apk` | 148,800,480 字节 |
| `app-x86_64-release.apk`（模拟器） | 164,727,135 字节 |

注意 `--target-platform android-arm64` **不够**：它只管住 Flutter 自己的库，
插件带的 `.so` 照样三个 ABI 全进。给手机只用 `--split-per-abi` 产出的
`app-arm64-v8a-release.apk`。

体积的大头现在是桌宠帧素材（约 107MB）与 ONNX Runtime；
语音模型已经拆成 Release 资源包，按需下载。

### 打包模型资源

```bash
python tool/package_resources.py \
  --models-dir assets/models \
  --out-dir ../echo-models \
  --manifest resources/manifest.json
```

脚本会生成四个 `echo-models-*-v1.zip` 和一份带体积 / SHA256 的
`manifest.json`。把 zip 作为 Release `models-v1` 的附件上传，
再把生成的 manifest 覆盖 `resources/manifest.json`（或至少同步
`version / bytes / sha256`）。以后资源有变，改版本号并发新一轮附件即可；
APP 只会下载版本变了的资源。

### 测试

```bash
flutter test        # 单元测试
flutter analyze     # 静态分析应当零问题
```

## 策划脚本（微视频拍摄）

旧住民的内置三幕脚本已经整套下线。现在「策划模式」仍然可用，只是脚本要自己建：

1. 设置 → **策划脚本** → 新建；
2. 在脚本里安排「第几秒谁点赞 / 谁评论 / 设定计数 / 展示分析」；
3. 评论区事件只能选**固定住民**（旧住民已经不存在）；
4. 回到发布页，在「策划模式」里勾上脚本，发布后不要再碰屏幕。

脚本只安排“这条帖子会收到什么回应”，不切模式、不跳页面、不代替用户点按钮。
拍摄时该手动完成的动作仍然手动完成——这才是这个作品要说的事。

## 配置模型（可选）

清醒模式的客观分析、策划脚本排期**完全离线**，不需要任何 API Key。只有「测试连接」和回响侧的生成（临时网民、固定住民唤醒、图片理解、联网搜索）会用到模型。固定住民用的是 tool calling（function calling），对话模型需要支持；不支持时只会退回一句普通文字。

设置 → **模型配置中心** → 新建，选一家服务商预设（DeepSeek / 通义千问 / 智谱 / Kimi / 豆包 / 硅基流动 / 混元 / 文心 / MiniMax / OpenAI）或「自定义（OpenAI 兼容）」，填 Key 后点测试连接。

- 对话 / 文生图 / 语音合成 / 图片理解是**四种用途**，各自一条配置；它们接口和成本都不同，不强行合并
- 本机语音内置两套：**vits-zh-ll**（5 个中文声线，五选一；1、3 女，2、4、5 男）和 **ZipVoice INT8**（参考音频 + 逐字稿克隆）。云端仍是 OpenAI 兼容 `/audio/speech`（硅基流动 CosyVoice2 / OpenAI）。固定住民的音色方式：内置音色（五选一）/ 文字描述（云端）/ 仅参考音频 / 参考音频 + 文字描述 / 参考音频 + 转录文本；本机支持“内置音色”和“参考 + 转录”，云端再按模型配置里的能力开关追加。**只有固定住民发语音**，临时网民的评论区语音合成已下线
- **本机克隆要 wav 参考音频**；mp3/m4a 请走云端克隆，或先转成 wav。ZipVoice 需要逐字稿，不能只给音频，也不能按文字描述造声音
- 密钥存在**系统钥匙串**（Android Keystore / iOS Keychain / Windows 凭据管理器），不写进数据库、不进代码
- 调用第三方模型时，帖内容、必要的社区上下文，以及你在「我的身份」里填写的资料会发送给你配置的那个 API；`assets` 里的图片只有在开启图片理解或原图直发时才会发送
- 身份资料与图片都不会上传到本项目自己的服务器（项目没有服务器）；其余所有数据只存在本机

## 项目结构

```
lib/
├─ app.dart            应用根组件 + 前台心跳
├─ core/               常量与合规文案、调色板与主题、路由、工具
├─ domain/
│  ├─ models/          Post / AiPersona / PostVoice / CustomResident /
│  │                    ResidentMemory / PostUnderstanding / PlanScript …
│  └─ services/        调度器、围观（AudienceService）、帖子解析、记忆、
│                       固定住民唤醒（ResidentWakeService）与工具会话、
│                       TTS / 音色档案、资源目录与下载（ResourceManager）、
│                       唯一上下文时间线（ResidentTimeline）、
│                       联网搜索、知识库（注入 / 每周热门梗更新）、
│                       清醒分析、数据导出、
│                       模式状态机、策划排期、防沉迷判定、外观
├─ data/
│  ├─ db/              Drift 表定义、迁移、播种（schema v51）
│  ├─ repositories/    仓储实现（帖子 / 网民 / 记忆 / 固定住民 / 收件箱 /
│  │                    网友头像池 / 互动…）
│  └─ media/           图片挑选、私有目录落盘与模型图片编码
└─ features/           按页面分组：feed / composer / post_detail / residents /
                       records / analysis（含反思与相册） / values / actions /
                       safety / stickers / knowledge / scripts / models /
                       settings /
                       messages（私信与通话） / pet（桌宠） /
                       resources（模型下载） / help /
                       onboarding / notifications
```

数据库共 47 张表（见 `lib/data/db/tables/`）：帖子、互动队列、每帖网民快照、
浏览记录、帖子解析、固定住民与长期记忆、住民的收件箱、评论、点赞、私信、
通知、模型配置、网友头像池、策划脚本与事件、清醒分析快照、真实生活相册、
前台使用会话、动作账本、各类日志与真实行动记录；v50 新增住民的睡眠记录、
多人对局参与者、通用对局状态与声明式游戏插件；v51 新增知识库、知识条目与
共享库的服务对象三张表。旧住民的 `ai_personas` /
`ai_relationships` / `persona_routines` 已经在 v37 迁移里删除。

## 合规与边界

这个项目刻意守着几条线：

- 回响模式所有页面底部固定「内容由AI生成，仅供参考」，数据层 `is_ai = true`
- 清醒模式的永久提示**不可关闭、不可删除**（界面上没有关闭按钮，代码里也没有删除入口）
- 防沉迷提醒**默认开启**，但只提醒、不拦截 —— 不锁屏、不劝退、不把使用时长变成需要打败的关卡
- 清醒模式的每日上限由用户自己设，默认关闭；到点只提醒一次
- 清醒侧与回响侧的数据用 `scope` 严格分开：清醒分析只统计 `scope=clear`，导出的 JSON 不含任何 AI 互动
- 清醒数据随时可以导出为文件，也可以一键删干净（相册连图片文件一起删）
- 心理安全页提供求助入口（全国心理援助热线 12356，以官方最新公布为准）
- 情绪持续低落时，请找真实的人聊一聊。这个 APP 里的「网友」不能替代真实的对话

## 许可

[MIT](LICENSE)。这是课程作业、也是公开的实践项目，欢迎拿走改；里面的 AI 住民人格与素材请自行替换成自己的。
