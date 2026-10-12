import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_test/flutter_test.dart';
import 'package:mangotalk/features/chat/presentation/chat_thumbnail.dart';
import 'package:mangotalk/features/chat/presentation/decoded_chat_image_cache.dart';

Future<ui.Image> pixels(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(Colors.green, BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

class CountingProvider extends ImageProvider<String> {
  CountingProvider(this.pixels);
  final ui.Image pixels;
  int loads = 0;

  @override
  Future<String> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture('test-thumbnail');

  @override
  ImageStreamCompleter loadImage(String key, ImageDecoderCallback decode) {
    loads++;
    return OneFrameImageStreamCompleter(
      SynchronousFuture(ImageInfo(image: pixels.clone())),
    );
  }
}

void main() {
  testWidgets(
    'scroll reentry paints on its first frame even after Flutter cache eviction',
    (tester) async {
      final image = (await tester.runAsync(() => pixels(32, 16)))!;
      final cache = DecodedChatImageCache();
      final provider = CountingProvider(image);
      final scroll = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 300,
            child: ListView.builder(
              controller: scroll,
              scrollCacheExtent: const ScrollCacheExtent.pixels(0),
              itemCount: 100,
              itemExtent: 150,
              itemBuilder:
                  (context, index) =>
                      index == 0
                          ? ChatThumbnail(
                            cache: cache,
                            userId: 'alice',
                            source: 'preview',
                            provider: provider,
                          )
                          : Text('message $index'),
            ),
          ),
        ),
      );
      await tester.pump();
      final originalState = tester.state(find.byType(ChatThumbnail));
      expect(provider.loads, 1);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);

      scroll.jumpTo(3000);
      await tester.pump();
      expect(find.byType(ChatThumbnail), findsNothing);
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      scroll.jumpTo(0);
      await tester
          .pump(); // Deliberately don't settle: the FIRST returning frame.
      expect(
        tester.state(find.byType(ChatThumbnail)),
        isNot(same(originalState)),
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      expect(provider.loads, 1);
      await tester.pumpWidget(const SizedBox());
      cache.dispose();
      image.dispose();
      scroll.dispose();
    },
  );

  testWidgets(
    'decoded LRU is byte bounded and eviction preserves an acquired handle',
    (tester) async {
      final image = (await tester.runAsync(() => pixels(16, 16)))!;
      final info = ImageInfo(image: image);
      final cache = DecodedChatImageCache(maxEntries: 3, maxBytes: 2048);
      cache.store('alice', 'a', info, 0);
      cache.store('alice', 'b', info, 0);
      final held = cache.acquire('alice', 'a')!;
      cache.store('alice', 'c', info, 0);
      expect(cache.length, 2);
      expect(cache.sizeBytes, 2048);
      expect(cache.acquire('alice', 'b'), isNull);
      cache.clearUser('alice');
      expect(cache.length, 0);
      expect(held.image.width, 16);
      cache.store('alice', 'late-result', info, 0);
      expect(cache.length, 0); // Old async work cannot repopulate after logout.
      expect(cache.acquire('bob', 'a'), isNull);
      held.dispose();
      info.dispose();
      cache.dispose();
    },
  );
}
