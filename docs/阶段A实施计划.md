# 《回响 Echo》阶段 A 实施计划

> 依据：《回响 Echo》双模式集成版 APP 规划书 v2.1
> 范围：阶段 A —— 微视频演示 MVP
> 日期：2026-09-11
> 目标一句话：**让一部真机上的 APP 能稳定、零成本、可重复地演完微视频三幕。**

---

## 0. 环境安装清单（动手第一步）

当前机器缺口：Flutter 未安装、`ANDROID_HOME` 为空、Java 为 1.8（Flutter 打包 Android 需 **JDK 17+**）。
磁盘：C 剩 148G、D 剩 78G，预估新增占用 **6~8G**，够用。

| # | 项目 | 方案 | 备注 |
|---|------|------|------|
| 1 | Flutter SDK | 解压到 `D:\flutter`（从 `storage.flutter-io.cn` 镜像取最新 stable zip） | 不装在 C 盘，省系统盘 |
| 2 | 环境变量 | `PUB_HOSTED_URL=https://pub.flutter-io.cn`、`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`、`PATH` 加 `D:\flutter\bin` | 国内拉包提速关键 |
| 3 | JDK 17 | 优先用 Android Studio 自带的 JBR；或单独装 Temurin 17 并设 `JAVA_HOME` | `flutter config --jdk-dir` 可指定 |
| 4 | Android SDK | 装 Android Studio → SDK Manager 勾：platform-tools、platforms;android-35、build-tools;35.x、cmdline-tools | 模拟器可选（真机更稳） |
| 5 | Gradle 镜像 | `android/settings.gradle.kts` 与 `gradle-wrapper.properties` 换阿里云 maven / 腾讯镜像 | 否则首次构建能卡半小时 |
| 6 | 验收 | `flutter doctor -v` 全绿、`flutter devices` 能看到真机、跑通官方 counter demo | 这一步不过不写业务代码 |

**风险点**：Android Studio + SDK 下载是今天最耗时的一环（受网络影响大）。若真机连接不顺（USB 驱动/授权），退而用 Android 模拟器，但微视频拍摄建议用真机（画面真实、性能稳）。

---

## 1. 阶段 A 范围界定

### 1.1 做（阶段 A 验收范围内的）

- 启动引导页、模式选择页
- **回响模式**：首页信息流（帖子卡片、点赞/评论数、热/新标签）、发布页（图文、话题可选）、帖子详情页、评论区
- **预置 AI 人格**（12 个，程序化头像，JSON 配置）
- **演示模式**：一键触发三幕（第一幕三条评论+语音、第二幕垃圾桶千字长评、第三幕切清醒+客观描述）
- **通知与红点**：通知页 + 底部导航红点 + 本地通知基础
- **合规小字**：所有回响模式页面底部固定「内容由AI生成，仅供参考」；数据层 `is_ai = true`
- **模式切换**：回响 ↔ 清醒 状态机、数据归档/删除、二次确认、冷却期
- **清醒模式**：记录页、发布页、客观分析结果页（预置数据 + 可选真实 API）、设置页、永久提示、价值澄清与真实行动的**简版**
- **模型配置中心**：一键配置主流模型（OpenAI 兼容优先）+ 自定义 + 校验/测试对话 + 密钥加密
- **素材系统（头像 / 表情包）**：内置图片优先、文字头像兜底、用户可上传自定义头像与表情包
- 防沉迷提醒简版、心理安全入口、未成年人年龄门

### 1.2 不做（明确推给阶段 B）

- ❌ AI 住民自主发帖 / 动态 / 关系网 / 互相关注 / 私信 / 热榜 / 话题页 / 校园事件系统
- ❌ 后台精确 0—48 小时调度（A 阶段只做**本地队列 + 冷启动补发 + 演示模式加速**，`workmanager` 接入留到 B）
- ❌ TTS/STT 真实语音合成（A 阶段用**预置音频** + 静态波形，`just_audio` 播放）
- ❌ AI 人格专属表情包偏好、AI 发图片评论、进阶数据看板、云端同步、上架合规材料
- ❌ SQLCipher 数据库加密（A 阶段仅 API Key 加密）

---

## 2. 技术选型（最终确认）

| 层级 | 选型 | 理由 |
|------|------|------|
| 框架 | Flutter stable + Dart 3 | 规划书既定，一套代码 Android/iOS |
| 状态管理 | **Riverpod**（不启用 codegen） | 可测试、依赖注入友好；不用 build_runner 生成，减少构建摩擦 |
| 路由 | go_router | 声明式，支持深链（通知点击跳转） |
| 数据库 | **Drift** + sqlite3_flutter_libs | 类型安全、外键/索引/迁移齐全，契合规划书 §8 |
| 密钥存储 | flutter_secure_storage | 走 Android Keystore |
| 网络 | dio | 拦截器、超时、错误映射成熟 |
| 通知 | flutter_local_notifications | 本地通知，无需服务端 |
| 图片 | image_picker + path_provider | 相册/相机；用户上传的素材存 APP 私有目录；清 EXIF 在 B 阶段做实，A 先留接口 |
| 素材 | 内置 assets + 文件路径 + 文字兜底 | 统一走 `AvatarResolver` / `StickerRepository`，随时可换成真实图片，业务代码零改动 |
| 音频 | just_audio | 播放预置语音条 |
| 时间格式化 | intl + 自写相对时间 | "3分钟前 / 昨天 20:14" |

> **A 阶段调度策略（重要决策）**：不做系统级后台任务，改为
> ①发帖时同步在本地 DB 生成 `pending` 互动队列（0—48h 随机 `scheduled_at`）
> ②APP 冷启动/回前台时扫描到期任务并补发
> ③演示模式手动/加速触发
> 这样**零后台限制风险、零服务器成本**，微视频拍摄完全够用；真正的 WorkManager/BGTaskScheduler 放 B 阶段。

---

## 3. 目录结构（feature-first）

```
D:\Project\Echo\
├─ android\  ios\            # flutter create 生成
├─ assets\
│  ├─ personas\personas.json # 12 个预置 AI 人格
│  ├─ demo\                  # 演示模式三幕脚本 + 预置帖子
│  ├─ audio\                 # 预置语音条
│  ├─ avatars\               # 人格头像图片（后续丢图进目录即可替换）
│  ├─ stickers\               # 内置表情包图片
│  ├─ stickers.json          # 表情包清单（名称 / 分类 / 路径）
│  └─ images\                # 程序化生成的文字头像兜底
├─ docs\
│  ├─ 阶段A实施计划.md        # 本文档
│  └─ 架构设计.md             # 后续补充
├─ lib\
│  ├─ main.dart
│  ├─ app.dart               # MaterialApp.router + 主题 + 合规包裹
│  ├─ core\
│  │  ├─ constants\          # 合规文案、阈值、演示脚本常量
│  │  ├─ theme\              # 双主题 tokens（回响深色 / 清醒浅色）
│  │  ├─ router\             # go_router 路由表 + 守卫
│  │  ├─ media\              # AvatarResolver：图片 / 文件 / 文字 三级兜底
│  │  └─ utils\              # 相对时间、ID 生成、错误中文映射
│  ├─ domain\
│  │  ├─ models\             # Post / Persona / Interaction / AnalysisResult
│  │  ├─ repositories\       # 抽象接口
│  │  └─ services\           # 模式状态机、调度器、分析、人格、通知
│  ├─ data\
│  │  ├─ db\                 # Drift 表 / DAO / 迁移 / 种子数据
│  │  ├─ repositories\       # 仓储实现
│  │  └─ secure\             # 密钥加密读写
│  ├─ gateway\               # ModelProvider 抽象 + OpenAI/Anthropic/Gemini/自定义适配器
│  └─ features\
│     ├─ onboarding\  feed\  composer\  post_detail\
│     ├─ notifications\  profile\  settings\  analysis\
│     ├─ stickers\           # 头像 / 表情包管理（含用户上传）
│     ├─ demo\  safety\
│     └─ shared_widgets\     # AiDisclaimerBar、PermanentNoticeBanner、按钮、卡片
└─ test\
```

约定：单文件 < 400 行，超了就拆；每个 feature 内部按 `presentation / application / data` 三层组织。

---

## 4. 数据模型（阶段 A 建表）

沿用规划书 §8，A 阶段先建 10 张表（新增 `stickers` 素材表），B 阶段再补 `ai_relationships`、`private_messages`、`topics`、`hot_rankings`。

| 表 | 用途 | A 阶段要点 |
|---|---|---|
| `app_settings` | 键值配置（模式、频率、拟人度、主题…） | `scope` 字段区分 shared/echo/clear |
| `user_profile` | 昵称、头像、等级、经验、粉丝 | 单行 |
| `posts` | 帖子（正文、图片 JSON、话题、删除软标记） | `is_ai_generated`、`deleted_at`、`scope` 索引 |
| `ai_personas` | AI 人格 12 个 | 含 `active_hours`、`like_probability`、`personality_type` |
| `ai_interactions` | 互动队列（like/comment/voice） | **A 阶段核心表**：`scheduled_at`、`status`、`is_ai`、`parent_id`（楼中楼）+ 唯一约束防重复 |
| `analysis_results` | 客观分析结果 | image_description / emotion / logic / fact_check / suggestions |
| `mode_switch_logs` | 模式切换日志 | from/to/archive_action/冷却期校验依据 |
| `notification_logs` | 通知记录 | 红点计数与聚合 |
| `feedback_view_logs` | 查看反馈次数 | 防沉迷阈值提醒依据 |
| `stickers` | 头像 / 表情包素材 | 内置(`asset`) 与用户上传(`file`) 统一登记：`source`、`path`、`category`、`is_user`、`deleted_at` |

约束（照规划书 §8）：外键 `ai_interactions.post_id → posts.id`；索引 `posts.created_at`、`ai_interactions(post_id, persona_id, status)`；软删除统一 `deleted_at`。

---

## 5. 关键接口（先定接口再写实现）

```dart
// 模式状态机
abstract class ModeController {
  AppMode get current;
  Future<void> switchToClear({bool purgeAI = false});
  Future<void> switchToEcho();                 // 含二次确认 + 年龄门 + 冷却期
}

// 互动调度
abstract class InteractionScheduler {
  Future<void> planForPost(Post post, EchoSettings s); // 生成 0—48h 队列
  Future<void> flushDue();                             // 冷启动/回前台补发
  Future<void> triggerDemoAct(DemoAct act);            // 演示模式一键三幕
}

// 模型网关
abstract class ModelProvider {
  Future<ModelResponse> chat(ChatRequest request);
  Future<bool> validate();
  Future<List<String>> listModels();
}

// 素材（头像 / 表情包：图片优先、文字兜底、支持用户上传）
abstract class AvatarResolver {
  ImageProvider? resolve(String? avatarRef);   // asset: → file: → null（调用方降级为文字头像）
}

abstract class StickerRepository {
  Future<List<Sticker>> list({StickerCategory? category});
  Future<Sticker> importFromPicker();          // 复制进 APP 私有目录 + 入库
  Future<void> delete(String id);              // 软删除；内置素材不可删
}

// 客观分析（清醒模式）
abstract class ObjectiveAnalysisService {
  Future<AnalysisResult> analyze(Post post);    // 预置数据 or 真实 API
}
```

---

## 6. 页面与路由

| 路由 | 页面 | 模式 |
|---|---|---|
| `/onboarding` | 启动引导（含隐私政策、风险提示） | 共用 |
| `/mode-select` | 模式选择 | 共用 |
| `/feed` | 首页信息流 | 回响 |
| `/records` | 自我记录流 | 清醒 |
| `/compose` | 发布页 | 共用 |
| `/post/:id` | 帖子详情 + 评论区 | 回响 |
| `/notifications` | 通知页 | 回响 |
| `/profile` | 我的 | 回响 |
| `/settings` `/settings/mode` `/settings/models` `/settings/personas` `/settings/safety` | 设置族 | 共用 |
| `/analysis/:postId` | 客观分析结果 | 清醒 |
| `/settings/stickers` | 头像 / 表情包管理（含用户上传） | 共用 |
| `/values` `/actions` | 价值澄清 / 真实行动（简版） | 清醒 |
| `/demo` | 演示模式控制台 | 隐藏入口（长按标题 3 秒 / 设置内开关） |

底部导航：回响 = 首页 / 发布 / 消息(B 占位) / 通知 / 我的；清醒 = 记录 / 发布 / 分析 / 行动 / 设置。

---

## 7. 演示模式（微视频的命脉）

预置三幕脚本 JSON，**不依赖真实 API**，保证拍摄稳定、零成本、可重复：

| 幕 | 触发后发生什么 | 素材来源 |
|---|---|---|
| 第一幕 建立幻觉 | 用户发"天空照"→ 3 位人格（温柔学姐/技术宅/深夜树洞）依次点赞、评论、一条语音条 | `assets/demo/act1.json` + 预置音频 |
| 第二幕 异化与崩溃 | 发"垃圾桶照片"→ 切换高频档 → 生成千字荒谬长评 + 点赞暴涨动画 + 热榜火焰 | `assets/demo/act2.json` |
| 第三幕 觉醒与重构 | 设置中切清醒模式 → 同一张天空照只返回客观描述（无点赞无评论） | `assets/demo/act3.json` + 预置分析结果 |

细节要求：每幕之间可单步、可重播、可重置；演示态下底部小字与清醒模式永久提示**照常显示**（合规不能演掉）。

### 7.1 素材策略（头像 / 表情包）

统一走「**图片优先，文字兜底**」三级解析，开发期不被素材卡住：

| 级别 | 来源 | 说明 |
|---|---|---|
| ① 内置图片 | `assets/avatars/`、`assets/stickers/` + `stickers.json` | 项目作者把"网友常见风格"的图丢进目录、在 json 里登记即可生效，**业务代码零改动** |
| ② 用户上传 | APP 私有目录（`path_provider`）+ `stickers` 表 | 用户自选头像/表情包：`image_picker` 选图 → 复制进私有目录 → 入库 → 全局可选 |
| ③ 文字兜底 | 昵称首字母 + 配色圆角块 | 素材缺失时自动降级；**开发期默认走这一级** |

- 人格配置里的 `avatar` 存的是**引用**（`asset:` / `file:` / 空字符串），不是硬编码路径，换素材不用改代码
- 内置素材不可删除；用户上传的走软删除
- 表情包分类：开心 / 安慰 / 吐槽 / 震惊 / 点赞 / 无语 / 鼓励 / 自定义
- **版权说明**：内置图片素材由项目作者自行准备或选用无版权素材，本项目不擅自下载网图；用户上传时弹一次"请确认你有权使用该图片"提示
- A 阶段先做「选图 → 入库 → 显示」简版；AI 人格专属表情包偏好、AI 发图片评论留到 B 阶段

---

## 8. 里程碑与验收

| 里程碑 | 交付物 | 验收方式 |
|---|---|---|
| **M0 环境** | Flutter + JDK17 + Android SDK 就绪 | `flutter doctor -v` 全绿；真机跑通 counter demo |
| **M1 骨架** | 项目初始化、目录、双主题、路由、Drift 建库、米粒种子数据 | 真机打开能进首页，DB 能写入读取，`flutter test` 通过 |
| **M2 回响基础** | 发布页（图文）、信息流卡片、帖子详情、评论区 UI、12 人格 | 手动发一帖，列表/详情/评论 UI 正确渲染 |
| **M3 互动与演示** | 调度器（本地队列 + 冷启动补发）、演示模式三幕、通知红点、合规小字 | 演示模式一键演完三幕；杀进程重开能补发到期互动 |
| **M4 清醒模式** | 模式状态机、切换规则、客观分析页（预置+真实 API 可切）、永久提示、价值澄清/行动简版 | 来回切换数据不丢；归档生效；永久提示无法关闭 |
| **M5 模型中心** | 一键配置主流模型、自定义模板、连通性/鉴权/模型列表/测试对话、密钥加密 | 用项目作者的真实 Key 跑通一次测试对话；重启 APP Key 仍在且为密文 |
| **M6 收尾** | 防沉迷提醒、心理安全入口、年龄门、README、GitHub 私有仓库 | 真机完整彩排一遍微视频三幕；仓库推送成功 |

**测试要求**：核心逻辑（模式状态机、调度器、网关适配、仓储）写单元测试，目标覆盖率 ≥ 80%；关键流程（发帖 → 回响 → 切清醒 → 分析）写 1 条集成测试。

### 8.1 进度记录

| 里程碑 | 状态 | 完成内容 / 剩余 |
|---|---|---|
| **M0 环境** | ✅ 2026-09-11 | Flutter 3.47.3（`D:\flutter`）+ Android SDK 36（`D:\Android\Sdk`）+ NDK r28c；debug APK 构建成功；Windows 桌面预览跑通（需开发者模式）。踩坑详见 [环境搭建备忘](环境搭建备忘.md) |
| **M1 骨架** | ✅ 2026-09-11 | 双主题、go_router 双模式导航、Drift **10 张表** + 种子（12 住民 / 14 设置）、合规组件、头像三级兜底；analyze 零问题 |
| **M2 回响基础** | ✅ 2026-09-11 | PostRepository / InteractionRepository；信息流/详情/评论区/记录页全部订阅数据库；发布页真实落库；图片选完复制进私有目录 |
| **M3 互动与演示** | 🔄 大部分完成 | ✅ 演示模式三幕（31/34/11 个动作 + 203/986 赞）+ DemoTimeline + 播放器（播放/暂停/单步/重置 + 模式感知配色）<br>⏳ 剩：0—48 小时调度器（本地队列 + 冷启动补发）、通知红点接真实数据 |
| **M4 清醒模式** | ⏳ | 模式状态机目前只有内存态；待补归档、二次确认、年龄门、冷却期、分析接真实 API |
| **M5 模型中心** | ⏳ | 未开始 |
| **M6 收尾** | ⏳ | 未开始；仓库已开源（`yearnc/echo` PUBLIC） |

**已验证的运行时事实**（2026-09-11）：数据库 `echo.sqlite` 建 10 张表、播种 4 帖 + 29 条互动（天空照 203 赞/16 评论，垃圾桶照 986 赞/14 评论，2 条语音）；第一幕 75 秒完整播完、第三幕模式切换与五项客观分析均实测通过；**39 个测试全过**。

**当前代码规模**：`lib/` 约 30 个文件，含 core/domain/data/features 四层；提交 3 次。

---

## 9. 风险与应对

| 风险 | 应对 |
|---|---|
| Android 环境下载慢/装不上 | 全程走国内镜像；Android Studio 装不上就退 cmdline-tools 方案 |
| Gradle 首次构建超时 | 换阿里云/腾讯 maven 镜像 + 预置 `gradle-wrapper` 国内 distributionUrl |
| 真机连不上 | 备用模拟器；拍摄前务必真机彩排 |
| 范围膨胀（想顺手做 B 阶段功能） | 严格按 §1.2 的"不做"清单执行 |
| API 费用 | 测试用最小 token；演示模式完全离线；网关设 token 上限 |
| 版权素材 | 开发期一律文字头像兜底；内置图片由项目作者提供或选无版权素材；用户上传前做版权确认提示 |
| 微视频拍摄当天翻车 | 演示模式预置数据 + 全程离线可跑 + 提前彩排两次 |

---

## 10. Git 与 GitHub 计划

- `D:\Project\Echo` 初始化 git（`main` 分支），`.gitignore` 用 Flutter 官方模板 + 排除 `*.keystore`、`local.properties`、`google-services.json`
- **密钥绝不上库**：API Key 只存设备 Keystore，代码里只留 `assets/personas` 等非敏感配置
- 每个里程碑一个提交，遵循 conventional commits（`feat:` / `fix:` / `chore:` / `test:` / `docs:`）
- 全部跑通后推送私有仓库 `yearnc/echo`（**推送前会先问项目作者确认**，不擅自 push）
- README 写清：项目定位、三幕演示步骤、环境要求、如何填自己的 API Key

---

## 11. 下一步（等项目作者点头就开工）

1. 装环境（M0）——这一步耗时最长，建议先启动下载
2. 下载期间本项目同步准备：`assets/personas/personas.json`（12 人格）、演示三幕脚本、双主题色板、Drift 表定义
3. 环境就绪 → `flutter create` → 进 M1
