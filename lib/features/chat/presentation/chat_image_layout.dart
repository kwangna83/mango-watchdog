import 'package:flutter/widgets.dart';

const chatImageFallbackSize = Size(240, 160);

class ChatImageFrame extends StatelessWidget {
  const ChatImageFrame({
    required this.width,
    required this.height,
    required this.child,
    super.key,
  });

  final int? width;
  final int? height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = chatImageDisplaySize(width: width, height: height);
    return SizedBox(width: size.width, height: size.height, child: child);
  }
}

Size chatImageDisplaySize({int? width, int? height}) {
  if (width == null || height == null || width <= 0 || height <= 0) {
    return chatImageFallbackSize;
  }
  final ratio = width / height;
  if (ratio >= 1) {
    const displayWidth = 260.0;
    return Size(displayWidth, (displayWidth / ratio).clamp(80, 320));
  }
  const displayHeight = 320.0;
  return Size((displayHeight * ratio).clamp(120, 260), displayHeight);
}
