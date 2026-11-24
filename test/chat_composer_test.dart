import 'package:echo/domain/models/sticker.dart';
import 'package:echo/features/shared_widgets/chat_composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _noop({
  String? text,
  StickerItem? sticker,
  String? imageRef,
  String? voiceRef,
  String? transcript,
  int? voiceDurationMs,
}) async {}

void main() {
  testWidgets('麦克风按钮切到语音模式，再点一次回到文字输入', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ChatComposer(
              controller: controller,
              sending: false,
              onSend: _noop,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.byTooltip('语音输入'));
    await tester.pump();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('按住 说话'), findsOneWidget);

    await tester.tap(find.byTooltip('切换文字输入'));
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('按住 说话'), findsNothing);
  });
}
