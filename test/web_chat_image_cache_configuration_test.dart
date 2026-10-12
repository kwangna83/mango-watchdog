import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final script = File('web/chat_image_cache.js').readAsStringSync();

  test('web cache is bounded and concurrency limited', () {
    expect(script, contains('64 * 1024 * 1024'));
    expect(script, contains('MAX_ENTRIES = 100'));
    expect(script, contains('MAX_CONCURRENT = 4'));
    expect(script, contains('estimate.quota * 0.2'));
    expect(script, contains('URL.revokeObjectURL'));
    expect(script, contains("!('caches' in window)"));
  });

  test('web cache isolates owners and batches index writes', () {
    expect(script, contains('meta.userId !== userId'));
    expect(script, contains('setTimeout'));
    expect(script, contains('mangoTalkChatImageCacheClearUser'));
  });

  test('web cache reuses a bounded session blob LRU', () {
    expect(script, contains('MAX_SESSION_BLOBS = 50'));
    expect(script, contains('sessionBlobs.get(operationKey)'));
    expect(script, contains('entry.refs++'));
    expect(script, contains('entry.refs = Math.max(0, entry.refs - 1)'));
    expect(script, contains('entry[1].refs === 0'));
    expect(script, contains('mangoTalkChatImageCacheRetain'));
    expect(script, contains('mangoTalkChatImageCachePeek'));
  });
}
