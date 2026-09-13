import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/db/database_provider.dart';

/// 界面明暗：跟模式走，还是用户说了算。
///
/// 默认 [auto]——保留"回响模式深紫、清醒模式暖白"这套原本的语义；
/// 但用户想固定成日间或夜间时，也可以不被模式绑架（拍摄现场光线不同，
/// 这很实际）。
enum AppearanceMode {
  auto('跟随模式'),
  light('日间'),
  dark('夜间');

  const AppearanceMode(this.label);

  final String label;

  String get key => name;

  static AppearanceMode fromKey(String? key) => switch (key) {
    'light' => AppearanceMode.light,
    'dark' => AppearanceMode.dark,
    _ => AppearanceMode.auto,
  };
}

class AppearanceController extends Notifier<AppearanceMode> {
  static const String settingKey = 'appearance.theme';

  @override
  AppearanceMode build() {
    // 先按默认值渲染，读到存档后再纠正一次——设置是一行 key/value，
    // 读得很快，用户基本看不到这一跳。
    _restore();
    return AppearanceMode.auto;
  }

  Future<void> _restore() async {
    final db = ref.read(databaseProvider);
    final query = db.select(db.appSettings)
      ..where((t) => t.key.equals(settingKey));
    final row = await query.getSingleOrNull();
    if (row == null) return;
    state = AppearanceMode.fromKey(row.value);
  }

  Future<void> setMode(AppearanceMode mode) async {
    state = mode;

    final db = ref.read(databaseProvider);
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: settingKey, value: mode.key),
        );
  }
}

final appearanceControllerProvider =
    NotifierProvider<AppearanceController, AppearanceMode>(
      AppearanceController.new,
    );
