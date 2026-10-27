import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:echo/data/db/app_database.dart';
import 'package:echo/data/repositories/post_repository.dart';
import 'package:echo/domain/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('全量备份与恢复', () {
    late AppDatabase db;
    late Directory temp;
    late BackupService service;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      temp = Directory.systemTemp.createTempSync('echo_backup_test');
      service = BackupService(db, documents: () async => temp);
    });

    tearDown(() async {
      await db.close();
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    test('默认模式往返：导出、清空、再导入', () async {
      final posts = PostRepository(db);
      await posts.create(content: '备份前的一条帖子', scope: 'echo');

      final path = await service.export();
      expect(File(path).existsSync(), isTrue);

      await db.delete(db.posts).go();
      expect(await db.select(db.posts).get(), isEmpty);

      final envelope = await service.read(path);
      expect(envelope.mode, 'integrity');
      expect(envelope.needsPassword, isFalse);

      final payload = await service.decode(envelope);
      final result = await service.restore(payload);

      expect(result.rows, greaterThan(0));
      final rows = await db.select(db.posts).get();
      expect(rows.single.content, '备份前的一条帖子');
    });

    test('密码模式：没有密码或密码不对都解不开', () async {
      await PostRepository(db).create(content: '密码备份里的帖子', scope: 'echo');
      final path = await service.export(password: 'echo-2026');
      final envelope = await service.read(path);

      expect(envelope.needsPassword, isTrue);
      await expectLater(
        service.decode(envelope),
        throwsA(isA<BackupException>()),
      );
      await expectLater(
        service.decode(envelope, password: 'wrong'),
        throwsA(isA<BackupException>()),
      );

      final payload = await service.decode(envelope, password: 'echo-2026');
      expect(payload.rowCount, greaterThan(0));
    });

    test('文件被改过一个字符就解不开', () async {
      await PostRepository(db).create(content: '会被篡改的帖子', scope: 'echo');
      final path = await service.export(password: 'echo-2026');
      final file = File(path);
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final payload = map['payload'] as String;
      map['payload'] = payload.replaceRange(0, 1, payload[0] == 'A' ? 'B' : 'A');
      await file.writeAsString(jsonEncode(map));

      final envelope = await service.read(path);
      await expectLater(
        service.decode(envelope, password: 'echo-2026'),
        throwsA(isA<BackupException>()),
      );
    });

    test('不是回响的备份文件会被拒绝', () async {
      final file = File('${temp.path}/random.echobak');
      await file.writeAsString('{"hello":"world"}');
      await expectLater(
        service.read(file.path),
        throwsA(isA<BackupException>()),
      );
    });
  });
}
