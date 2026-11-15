/// 应用版本与阶段标记。
///
/// 本文件中的版本号用于设置页展示。发版时须与 `pubspec.yaml` 的 `version:`
/// 同步修改。Android 的 versionName 取自 pubspec，界面显示值与 APK 内版本
/// 必须一致，避免版本信息不一致。
const String appVersion = '4.12.2';

/// 阶段说明，仅用于开发标识，不参与版本比较。
const String appStageLabel = '阶段 D · v4.12.2';
