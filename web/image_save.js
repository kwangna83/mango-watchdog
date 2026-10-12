(() => {
  const preparedImages = new Map();

  window.mangoTalkPrepareImage = (source, cacheKey, mimeType) => {
    const prepared = fetch(source)
      .then((response) => {
        if (!response.ok) throw new Error(`image_fetch_${response.status}`);
        return response.blob();
      })
      .then((blob) =>
        blob.type ? blob : new Blob([blob], { type: mimeType || 'image/jpeg' }),
      );
    preparedImages.set(cacheKey, prepared);
    return Promise.resolve(true);
  };

  window.mangoTalkSaveImage = async (cacheKey, fileName, mimeType) => {
    try {
      const prepared = preparedImages.get(cacheKey);
      if (!prepared) return 'failed';
      const blob = await prepared;
      const file = new File([blob], fileName, {
        type: blob.type || mimeType || 'image/jpeg',
      });

      if (navigator.share && navigator.canShare?.({ files: [file] })) {
        try {
          await navigator.share({ files: [file], title: 'MangoTalk 이미지' });
          return 'shared';
        } catch (error) {
          if (error?.name === 'AbortError') return 'cancelled';
        }
      }

      const objectUrl = URL.createObjectURL(blob);
      const anchor = document.createElement('a');
      anchor.href = objectUrl;
      anchor.download = fileName;
      anchor.style.display = 'none';
      document.body.appendChild(anchor);
      anchor.click();
      anchor.remove();
      setTimeout(() => URL.revokeObjectURL(objectUrl), 1000);
      return 'downloaded';
    } catch (_) {
      return 'failed';
    }
  };
})();
