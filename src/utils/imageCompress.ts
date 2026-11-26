/**
 * Resizes and compresses an uploaded image File into a JPEG/WebP DataURL
 * guaranteed to stay under Firestore security rule limits (<= 220 KB string).
 */
export async function compressImageFileToDataUrl(
  file: File,
  maxChars = 220_000,
): Promise<string> {
  if (!file.type.startsWith('image/')) {
    throw new Error('Выберите файл изображения (JPG, PNG или WebP).');
  }

  const objectUrl = URL.createObjectURL(file);
  try {
    const img = await new Promise<HTMLImageElement>((resolve, reject) => {
      const el = new Image();
      el.onload = () => resolve(el);
      el.onerror = () => reject(new Error('Не удалось прочитать изображение.'));
      el.src = objectUrl;
    });

    const attempts: Array<{ maxDim: number; quality: number }> = [
      { maxDim: 800, quality: 0.8 },
      { maxDim: 680, quality: 0.72 },
      { maxDim: 540, quality: 0.62 },
      { maxDim: 420, quality: 0.55 },
    ];

    for (const { maxDim, quality } of attempts) {
      const ratio = Math.min(1, maxDim / Math.max(img.width || 1, img.height || 1));
      const w = Math.max(1, Math.round((img.width || 1) * ratio));
      const h = Math.max(1, Math.round((img.height || 1) * ratio));

      const canvas = document.createElement('canvas');
      canvas.width = w;
      canvas.height = h;
      const ctx = canvas.getContext('2d');
      if (!ctx) throw new Error('Не удалось обработать изображение.');
      ctx.fillStyle = '#FFFFFF';
      ctx.fillRect(0, 0, w, h);
      ctx.drawImage(img, 0, 0, w, h);

      const dataUrl = canvas.toDataURL('image/jpeg', quality);
      if (dataUrl.length <= maxChars) {
        return dataUrl;
      }
    }

    throw new Error('Фотография слишком большая даже после сжатия. Выберите файл поменьше.');
  } finally {
    URL.revokeObjectURL(objectUrl);
  }
}
