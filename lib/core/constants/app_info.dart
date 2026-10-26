/// 应用版本与阶段标记。
///
/// 这里是设置页显示的那一份。发版时**和 `pubspec.yaml` 的 `version:` 一起改**——
/// Android 上 versionName 就是 pubspec 里那个，APK 里写的和界面上显示的
/// 必须是同一个版本，否则两个地方会各说各话（阶段 A 那次就没跟上，
/// 设置页一直停在 0.1.0）。
const String appVersion = '3.6.4';

/// 括号里那句阶段说明，只给开发者看，不参与版本比较。
const String appStageLabel = '阶段 C · v3.6';
