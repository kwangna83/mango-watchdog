import 'dart:js_interop';

enum ImageSaveResult { shared, downloaded, cancelled, failed, unsupported }

@JS('mangoTalkPrepareImage')
external JSPromise<JSBoolean> _prepareImage(
  JSString source,
  JSString cacheKey,
  JSString mimeType,
);

@JS('mangoTalkSaveImage')
external JSPromise<JSString> _saveImage(
  JSString cacheKey,
  JSString fileName,
  JSString mimeType,
);

Future<void> prepareImageForSave({
  required String source,
  required String cacheKey,
  required String mimeType,
}) async {
  await _prepareImage(source.toJS, cacheKey.toJS, mimeType.toJS).toDart;
}

Future<ImageSaveResult> savePreparedImage({
  required String cacheKey,
  required String fileName,
  required String mimeType,
}) async {
  final value =
      (await _saveImage(cacheKey.toJS, fileName.toJS, mimeType.toJS).toDart)
          .toDart;
  return switch (value) {
    'shared' => ImageSaveResult.shared,
    'downloaded' => ImageSaveResult.downloaded,
    'cancelled' => ImageSaveResult.cancelled,
    'unsupported' => ImageSaveResult.unsupported,
    _ => ImageSaveResult.failed,
  };
}
