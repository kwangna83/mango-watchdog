enum ImageSaveResult { shared, downloaded, cancelled, failed, unsupported }

Future<void> prepareImageForSave({
  required String source,
  required String cacheKey,
  required String mimeType,
}) async {}

Future<ImageSaveResult> savePreparedImage({
  required String cacheKey,
  required String fileName,
  required String mimeType,
}) async => ImageSaveResult.unsupported;
