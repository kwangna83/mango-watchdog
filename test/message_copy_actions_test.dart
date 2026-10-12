import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangotalk/features/chat/presentation/message_copy_actions.dart';

void main() {
  testWidgets('전체 복사는 메시지 전체를 클립보드에 저장한다', (tester) async {
    MethodCall? clipboardCall;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') clipboardCall = call;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await copyMessageToClipboard('복사할 메시지');

    expect(clipboardCall?.method, 'Clipboard.setData');
    expect(clipboardCall?.arguments, <String, dynamic>{'text': '복사할 메시지'});
  });

  testWidgets('메시지 동작 메뉴에 전체 복사, 부분 복사, 답장을 표시한다', (tester) async {
    MessageAction? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => TextButton(
                onPressed: () async {
                  selected = await showMessageActionMenu(context);
                },
                child: const Text('메뉴 열기'),
              ),
        ),
      ),
    );

    await tester.tap(find.text('메뉴 열기'));
    await tester.pumpAndSettle();

    expect(find.text('전체 복사'), findsOneWidget);
    expect(find.text('부분 복사'), findsOneWidget);
    expect(find.text('답장'), findsOneWidget);

    await tester.tap(find.text('답장'));
    await tester.pumpAndSettle();

    expect(selected, MessageAction.reply);
  });

  testWidgets('부분 복사 창에 선택 가능한 메시지를 표시한다', (tester) async {
    const message = '원하는 부분만 복사할 메시지';

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => TextButton(
                onPressed:
                    () =>
                        showPartialMessageCopyDialog(context, message: message),
                child: const Text('부분 복사 열기'),
              ),
        ),
      ),
    );

    await tester.tap(find.text('부분 복사 열기'));
    await tester.pumpAndSettle();

    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text(message), findsOneWidget);

    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
