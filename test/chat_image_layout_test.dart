import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangotalk/features/chat/presentation/chat_image_layout.dart';

void main() {
  test('known landscape image reserves its final ratio', () {
    final size = chatImageDisplaySize(width: 1200, height: 800);

    expect(size.width, 260);
    expect(size.height, closeTo(173.33, 0.01));
  });

  test('portrait and extreme ratios stay inside bubble constraints', () {
    final portrait = chatImageDisplaySize(width: 800, height: 1200);
    final extreme = chatImageDisplaySize(width: 100, height: 2000);

    expect(portrait.height, 320);
    expect(portrait.width, closeTo(213.33, 0.01));
    expect(extreme.width, 120);
    expect(extreme.height, 320);
  });

  test('legacy images use a stable fallback size', () {
    expect(chatImageDisplaySize(), chatImageFallbackSize);
  });

  testWidgets('placeholder and loaded child keep the same frame size', (
    tester,
  ) async {
    const frameKey = Key('image-frame');

    Future<void> pump(Widget child) => tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: ChatImageFrame(
            key: frameKey,
            width: 1200,
            height: 800,
            child: child,
          ),
        ),
      ),
    );

    await pump(const CircularProgressIndicator());
    final loadingSize = tester.getSize(find.byKey(frameKey));
    await pump(const ColoredBox(color: Colors.orange));

    expect(tester.getSize(find.byKey(frameKey)), loadingSize);
  });
}
