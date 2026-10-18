export async function prepareImages(files) {
  if (files.length > 2) throw new Error("image_limit");
  return Promise.all(
    Array.from(files).map(async (file) => {
      if (
        !["image/jpeg", "image/png", "image/webp"].includes(file.type) ||
        file.size > 10 * 1024 * 1024
      )
        throw new Error("invalid_image");
      const bitmap = await createImageBitmap(file);
      try {
        if (bitmap.width * bitmap.height > 40_000_000)
          throw new Error("invalid_image");
        const scale = Math.min(1, 1280 / Math.max(bitmap.width, bitmap.height));
        const canvas = document.createElement("canvas");
        canvas.width = Math.max(1, Math.round(bitmap.width * scale));
        canvas.height = Math.max(1, Math.round(bitmap.height * scale));
        const context = canvas.getContext("2d");
        context.fillStyle = "white";
        context.fillRect(0, 0, canvas.width, canvas.height);
        context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
        const dataUrl = canvas.toDataURL("image/jpeg", 0.86);
        return {
          id: crypto.randomUUID(),
          name: file.name,
          dataUrl,
          mimeType: "image/jpeg",
          data: dataUrl.split(",")[1],
          width: canvas.width,
          height: canvas.height,
        };
      } finally {
        bitmap.close();
      }
    }),
  );
}
