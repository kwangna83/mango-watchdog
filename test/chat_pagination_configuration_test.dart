import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mangotalk/core/constants/chat_constants.dart';

void main() {
  final controller =
      File(
        'lib/features/chat/presentation/chat_controller.dart',
      ).readAsStringSync();
  final screen =
      File(
        'lib/features/chat/presentation/chat_screen.dart',
      ).readAsStringSync();

  test('initial and older message pages are limited to 50', () {
    expect(ChatConstants.pageSize, 50);
    expect(controller, contains('messages.length == ChatConstants.pageSize'));
    expect(controller, contains('older.length == ChatConstants.pageSize'));
  });

  test('older loading is coalesced and triggered near the top', () {
    expect(controller, contains('current.loadingOlder || !current.hasMore'));
    expect(screen, contains('_scroll.position.pixels < 120'));
    expect(screen, contains('_loadOlderPreservingPosition()'));
  });
}
