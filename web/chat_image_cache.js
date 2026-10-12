(() => {
  if (!('caches' in window)) {
    window.mangoTalkChatImageCacheGet = async () => '';
    window.mangoTalkChatImageCachePeek = () => '';
    window.mangoTalkChatImageCacheFetch = async (
      _key, _userId, url, _mimeType, width, height,
    ) => JSON.stringify({
      source: url,
      isObjectUrl: false,
      width: width || null,
      height: height || null,
    });
    window.mangoTalkChatImageCacheRemove = async () => {};
    window.mangoTalkChatImageCacheClearUser = async () => {};
    window.mangoTalkChatImageCacheRetain = () => {};
    window.mangoTalkChatImageCacheRelease = () => {};
    return;
  }

  const CACHE_PREFIX = 'mangotalk-chat-images-';
  const CACHE_NAME = `${CACHE_PREFIX}v1`;
  const INDEX_KEY = `${CACHE_NAME}:index`;
  const MAX_BYTES = 64 * 1024 * 1024;
  const MAX_ENTRIES = 100;
  const MAX_CONCURRENT = 4;
  const MAX_SESSION_BLOBS = 50;
  const PREVIEW_MAX_EDGE = 960;
  const pending = new Map();
  const sessionBlobs = new Map();
  const sessionKeyBySource = new Map();
  const queue = [];
  let active = 0;
  let saveTimer;
  let index;

  const loadIndex = () => {
    if (index) return index;
    try {
      index = JSON.parse(localStorage.getItem(INDEX_KEY) || '{}');
    } catch (_) {
      index = {};
    }
    return index;
  };

  const scheduleSave = () => {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => {
      try { localStorage.setItem(INDEX_KEY, JSON.stringify(loadIndex())); }
      catch (_) { /* Cache is an optional optimization. */ }
    }, 1000);
  };

  const requestFor = (key) => new Request(
    `${location.origin}${location.pathname.replace(/[^/]*$/, '')}__chat_image_cache__/${encodeURIComponent(key)}`,
  );

  const runLimited = (operation) => new Promise((resolve, reject) => {
    queue.push({ operation, resolve, reject });
    const pump = () => {
      while (active < MAX_CONCURRENT && queue.length) {
        const item = queue.shift();
        active++;
        item.operation().then(item.resolve, item.reject).finally(() => {
          active--;
          pump();
        });
      }
    };
    pump();
  });

  const sessionResult = (entry) => JSON.stringify({
    source: entry.source,
    isObjectUrl: true,
    width: entry.width || null,
    height: entry.height || null,
    previewSource: entry.previewSource,
  });

  const revokeSessionEntry = (operationKey, entry) => {
    URL.revokeObjectURL(entry.source);
    if (entry.previewSource && entry.previewSource !== entry.source) {
      URL.revokeObjectURL(entry.previewSource);
    }
    sessionKeyBySource.delete(entry.source);
    sessionBlobs.delete(operationKey);
  };

  const trimSessionBlobs = () => {
    if (sessionBlobs.size <= MAX_SESSION_BLOBS) return;
    const candidates = [...sessionBlobs.entries()]
      .filter((entry) => entry[1].refs === 0)
      .sort((a, b) => a[1].lastAccess - b[1].lastAccess);
    while (sessionBlobs.size > MAX_SESSION_BLOBS && candidates.length) {
      const [operationKey, entry] = candidates.shift();
      revokeSessionEntry(operationKey, entry);
    }
  };

  // Resize actual pixels before Flutter decodes them. cacheWidth alone is not
  // a dependable Web resize mechanism. The original blob remains untouched.
  const makePreview = async (blob) => {
    if (!('createImageBitmap' in window)) return null;
    const bitmap = await createImageBitmap(blob);
    try {
      const scale = Math.min(1, PREVIEW_MAX_EDGE / Math.max(bitmap.width, bitmap.height));
      if (scale === 1) return null;
      const canvas = document.createElement('canvas');
      canvas.width = Math.max(1, Math.round(bitmap.width * scale));
      canvas.height = Math.max(1, Math.round(bitmap.height * scale));
      const context = canvas.getContext('2d');
      if (!context) throw new Error('preview-canvas-unavailable');
      context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
      return await new Promise((resolve, reject) => canvas.toBlob(
        (preview) => preview ? resolve(preview) : reject(new Error('preview-encode-failed')),
        'image/png',
      ));
    } finally {
      bitmap.close();
    }
  };

  const acquireSessionBlob = async (operationKey, userId, key, response, meta) => {
    const existing = sessionBlobs.get(operationKey);
    if (existing) {
      existing.refs++;
      existing.lastAccess = Date.now();
      return sessionResult(existing);
    }
    const blob = await response.blob();
    if (!blob.size || !blob.type.startsWith('image/')) throw new Error('invalid-image');
    let preview;
    try { preview = await makePreview(blob); }
    catch (_) { /* Original remains usable if browser resizing fails. */ }
    // Another reader may have completed while decoding the preview.
    const concurrent = sessionBlobs.get(operationKey);
    if (concurrent) {
      concurrent.refs++;
      concurrent.lastAccess = Date.now();
      return sessionResult(concurrent);
    }
    const source = URL.createObjectURL(blob);
    const entry = {
      source,
      previewSource: preview ? URL.createObjectURL(preview) : source,
      width: meta.width || null,
      height: meta.height || null,
      userId,
      key,
      refs: 1,
      lastAccess: Date.now(),
    };
    sessionBlobs.set(operationKey, entry);
    sessionKeyBySource.set(source, operationKey);
    trimSessionBlobs();
    return sessionResult(entry);
  };

  const measureBlob = async (blob) => {
    if ('createImageBitmap' in window) {
      const bitmap = await createImageBitmap(blob);
      const dimensions = { width: bitmap.width, height: bitmap.height };
      bitmap.close();
      return dimensions;
    }
    return new Promise((resolve, reject) => {
      const source = URL.createObjectURL(blob);
      const image = new Image();
      image.onload = () => {
        URL.revokeObjectURL(source);
        resolve({ width: image.naturalWidth, height: image.naturalHeight });
      };
      image.onerror = () => {
        URL.revokeObjectURL(source);
        reject(new Error('image-decode-failed'));
      };
      image.src = source;
    });
  };

  const trim = async (cache) => {
    const values = Object.entries(loadIndex());
    let maxBytes = MAX_BYTES;
    try {
      const estimate = await navigator.storage?.estimate?.();
      if (estimate?.quota) maxBytes = Math.min(maxBytes, Math.floor(estimate.quota * 0.2));
    } catch (_) { /* Use conservative defaults. */ }
    values.sort((a, b) => (a[1].lastAccess || 0) - (b[1].lastAccess || 0));
    let total = values.reduce((sum, entry) => sum + (entry[1].size || 0), 0);
    while (values.length > MAX_ENTRIES || total > maxBytes) {
      const [key, meta] = values.shift();
      await cache.delete(requestFor(key));
      total -= meta.size || 0;
      delete loadIndex()[key];
    }
    scheduleSave();
  };

  const remove = async (key) => {
    const cache = await caches.open(CACHE_NAME);
    await cache.delete(requestFor(key));
    delete loadIndex()[key];
    for (const [operationKey, entry] of sessionBlobs.entries()) {
      if (entry.key === key) revokeSessionEntry(operationKey, entry);
    }
    scheduleSave();
  };

  window.mangoTalkChatImageCacheGet = async (key, userId) => {
    try {
      const operationKey = `${userId}:${key}`;
      const sessionEntry = sessionBlobs.get(operationKey);
      if (sessionEntry) {
        sessionEntry.refs++;
        sessionEntry.lastAccess = Date.now();
        return sessionResult(sessionEntry);
      }
      const meta = loadIndex()[key];
      if (!meta || meta.userId !== userId) return '';
      const cache = await caches.open(CACHE_NAME);
      const response = await cache.match(requestFor(key));
      if (!response) {
        delete loadIndex()[key];
        scheduleSave();
        return '';
      }
      meta.lastAccess = Date.now();
      scheduleSave();
      return await runLimited(() => acquireSessionBlob(operationKey, userId, key, response, meta));
    } catch (_) {
      return '';
    }
  };

  window.mangoTalkChatImageCachePeek = (key, userId) => {
    const entry = sessionBlobs.get(`${userId}:${key}`);
    if (!entry) return '';
    entry.refs++;
    entry.lastAccess = Date.now();
    return sessionResult(entry);
  };

  window.mangoTalkChatImageCacheFetch = (key, userId, url, mimeType, width, height) => {
    const operationKey = `${userId}:${key}`;
    if (pending.has(operationKey)) return pending.get(operationKey);
    const operation = runLimited(async () => {
      const response = await fetch(url, { credentials: 'omit' });
      if (!response.ok) throw new Error(`image-http-${response.status}`);
      const blob = await response.blob();
      if (!blob.size || !blob.type.startsWith('image/')) throw new Error('invalid-image');
      let measuredWidth = width || 0;
      let measuredHeight = height || 0;
      if (!measuredWidth || !measuredHeight) {
        const dimensions = await measureBlob(blob);
        measuredWidth = dimensions.width;
        measuredHeight = dimensions.height;
      }
      const cache = await caches.open(CACHE_NAME);
      const storedResponse = () => new Response(blob, {
        headers: { 'Content-Type': blob.type || mimeType },
      });
      try {
        await cache.put(requestFor(key), storedResponse());
      } catch (_) {
        await trim(cache);
        await cache.put(requestFor(key), storedResponse());
      }
      const meta = {
        userId,
        mimeType: blob.type || mimeType,
        size: blob.size,
        width: measuredWidth,
        height: measuredHeight,
        createdAt: Date.now(),
        lastAccess: Date.now(),
      };
      loadIndex()[key] = meta;
      await trim(cache);
      return acquireSessionBlob(
        operationKey,
        userId,
        key,
        new Response(blob, { headers: { 'Content-Type': blob.type || mimeType } }),
        meta,
      );
    }).finally(() => pending.delete(operationKey));
    pending.set(operationKey, operation);
    return operation;
  };

  window.mangoTalkChatImageCacheRemove = remove;
  window.mangoTalkChatImageCacheClearUser = async (userId) => {
    const keys = Object.entries(loadIndex())
      .filter((entry) => entry[1].userId === userId)
      .map((entry) => entry[0]);
    await Promise.all(keys.map(remove));
    for (const [operationKey, entry] of sessionBlobs.entries()) {
      if (entry.userId === userId) revokeSessionEntry(operationKey, entry);
    }
  };
  window.mangoTalkChatImageCacheRetain = (source) => {
    const operationKey = sessionKeyBySource.get(source);
    const entry = operationKey ? sessionBlobs.get(operationKey) : null;
    if (!entry) return;
    entry.refs++;
    entry.lastAccess = Date.now();
  };
  window.mangoTalkChatImageCacheRelease = (source) => {
    const operationKey = sessionKeyBySource.get(source);
    const entry = operationKey ? sessionBlobs.get(operationKey) : null;
    if (!entry) return;
    entry.refs = Math.max(0, entry.refs - 1);
    entry.lastAccess = Date.now();
    trimSessionBlobs();
  };

  caches.keys().then((names) => Promise.all(
    names.filter((name) => name.startsWith(CACHE_PREFIX) && name !== CACHE_NAME)
      .map((name) => caches.delete(name)),
  ));
})();
