import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/pet_settings.dart';
import '../db/app_database.dart';
import '../db/database_provider.dart';

/// 桌宠设置与时段表（v4.0）。
class PetSettingsRepository {
  PetSettingsRepository(this._db);

  final AppDatabase _db;
  static final Random _rand = Random();

  static const String _enabledKey = 'pet.enabled';
  static const String _residentKey = 'pet.defaultResidentId';
  static const String _intervalKey = 'pet.intervalMs';
  static const String _realtimeKey = 'pet.realtime';
  static const String _realtimeFramesKey = 'pet.realtimeFrames';
  static const String _realtimeGapKey = 'pet.realtimeGapSeconds';
  static const String _voiceKey = 'pet.voiceEnabled';
  static const String _watchRequestKey = 'pet.watchRequest';

  Future<String?> _read(String key) async {
    final row = await (_db.select(
      _db.appSettings,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _write(String key, String value) async {
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value),
        );
  }

  Future<PetSettings> load() async {
    final enabled = await _read(_enabledKey);
    final resident = await _read(_residentKey);
    final interval = int.tryParse(await _read(_intervalKey) ?? '');
    final realtime = await _read(_realtimeKey);
    final frames = int.tryParse(await _read(_realtimeFramesKey) ?? '');
    final gap = int.tryParse(await _read(_realtimeGapKey) ?? '');
    final voice = await _read(_voiceKey);
    return PetSettings(
      enabled: enabled == 'true',
      defaultResidentId: resident ?? '',
      intervalMs: (interval ?? 1000).clamp(400, 5000),
      realtime: realtime == 'true',
      realtimeFrames: (frames ?? 3).clamp(1, 6),
      realtimeGapSeconds: (gap ?? 20).clamp(
        PetSettings.minRealtimeGapSeconds,
        PetSettings.maxRealtimeGapSeconds,
      ),
      voiceEnabled: voice == 'true',
    );
  }

  Future<void> setEnabled(bool value) => _write(_enabledKey, '$value');

  Future<void> setDefaultResident(String residentId) =>
      _write(_residentKey, residentId);

  Future<void> setInterval(int ms) =>
      _write(_intervalKey, '${ms.clamp(400, 5000)}');

  Future<void> setRealtime(bool value) => _write(_realtimeKey, '$value');

  Future<void> setRealtimeFrames(int value) =>
      _write(_realtimeFramesKey, '${value.clamp(1, 6)}');

  Future<void> setRealtimeGap(int seconds) => _write(
    _realtimeGapKey,
    '${seconds.clamp(
      PetSettings.minRealtimeGapSeconds,
      PetSettings.maxRealtimeGapSeconds,
    )}',
  );

  Future<void> setVoice(bool value) => _write(_voiceKey, '$value');

  /// 住民请求进入实时观察：只落一个待确认标记，用户同意后才真的开。
  Future<void> requestWatch() => _write(_watchRequestKey, 'true');

  Future<bool> hasWatchRequest() async =>
      (await _read(_watchRequestKey)) == 'true';

  Future<void> clearWatchRequest() => _write(_watchRequestKey, 'false');

  /// 某个时刻由谁控制：先看时段，再看默认控制者。
  Future<String?> controllerAt(
    DateTime at, {
    required String fallbackResidentId,
  }) async {
    final minute = at.hour * 60 + at.minute;
    final shifts = await allShifts();
    for (final shift in shifts) {
      if (shift.covers(minute)) return shift.residentId;
    }
    return fallbackResidentId.trim().isEmpty ? null : fallbackResidentId;
  }

  Future<List<PetShift>> allShifts() async {
    final rows =
        await (_db.select(_db.petShifts)
              ..orderBy([(t) => OrderingTerm.asc(t.startMinute)]))
            .get();
    return [for (final row in rows) _toDomain(row)];
  }

  Stream<List<PetShift>> watchShifts() {
    final query = _db.select(_db.petShifts)
      ..orderBy([(t) => OrderingTerm.asc(t.startMinute)]);
    return query.watch().map(
      (rows) => [for (final row in rows) _toDomain(row)],
    );
  }

  Future<String> addShift({
    required String residentId,
    required int startMinute,
    required int endMinute,
  }) async {
    final id =
        'shift_${DateTime.now().microsecondsSinceEpoch}_${_rand.nextInt(1 << 20)}';
    await _db.into(_db.petShifts).insert(
      PetShiftsCompanion.insert(
        id: id,
        residentId: residentId,
        startMinute: startMinute.clamp(0, 1439),
        endMinute: endMinute.clamp(0, 1439),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    return id;
  }

  Future<void> removeShift(String id) async {
    await (_db.delete(_db.petShifts)..where((t) => t.id.equals(id))).go();
  }

  PetShift _toDomain(PetShiftRow row) => PetShift(
    id: row.id,
    residentId: row.residentId,
    startMinute: row.startMinute,
    endMinute: row.endMinute,
  );
}

final petSettingsRepositoryProvider = Provider<PetSettingsRepository>(
  (ref) => PetSettingsRepository(ref.watch(databaseProvider)),
);

final petShiftsProvider = StreamProvider.autoDispose<List<PetShift>>(
  (ref) => ref.watch(petSettingsRepositoryProvider).watchShifts(),
);
