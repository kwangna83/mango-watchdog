import 'package:flutter/material.dart';

import 'decoded_chat_image_cache.dart';

/// A cache hit paints RawImage on its very first frame, without resolving a new
/// ImageStream. Recreating this widget must not introduce a blank/loading frame.
class ChatThumbnail extends StatefulWidget {
  const ChatThumbnail({
    required this.cache,
    required this.userId,
    required this.source,
    this.provider,
    super.key,
  });

  final DecodedChatImageCache cache;
  final String userId;
  final String source;
  final ImageProvider? provider;

  @override
  State<ChatThumbnail> createState() => _ChatThumbnailState();
}

class _ChatThumbnailState extends State<ChatThumbnail> {
  ImageInfo? _image;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  bool _failed = false;
  int _request = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_image == null && _stream == null) _load();
  }

  @override
  void didUpdateWidget(ChatThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.userId != widget.userId ||
        oldWidget.cache != widget.cache ||
        oldWidget.provider != widget.provider) {
      _reset();
      _load();
    }
  }

  void _load() {
    _image = widget.cache.acquire(widget.userId, widget.source);
    if (_image != null) return;
    final request = ++_request;
    final cache = widget.cache;
    final userId = widget.userId;
    final source = widget.source;
    final generation = cache.generation(userId);
    _stream = (widget.provider ?? NetworkImage(source)).resolve(
      createLocalImageConfiguration(context),
    );
    _listener = ImageStreamListener(
      (image, synchronous) {
        if (!mounted ||
            request != _request ||
            generation != cache.generation(userId)) {
          image.dispose();
          return;
        }
        cache.store(userId, source, image, generation);
        final previous = _image;
        setState(() {
          _image = image;
          _failed = false;
        });
        if (previous != null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => previous.dispose(),
          );
        }
      },
      onError: (Object error, StackTrace? stack) {
        if (mounted && request == _request) setState(() => _failed = true);
      },
    );
    _stream!.addListener(_listener!);
  }

  void _reset() {
    _request++;
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
    final previous = _image;
    _image = null;
    _failed = false;
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  @override
  void dispose() {
    _reset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image != null) {
      return RawImage(
        image: image.image,
        scale: image.scale,
        fit: BoxFit.contain,
      );
    }
    if (_failed) return const Center(child: Icon(Icons.broken_image_outlined));
    return const Center(child: CircularProgressIndicator());
  }
}
