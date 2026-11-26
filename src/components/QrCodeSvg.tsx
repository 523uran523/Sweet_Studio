import React, { useMemo } from 'react';
import QRCode from 'qrcode';

export function QrCodeSvg({
  value,
  sizeClassName = 'w-28 h-28',
  margin = 2,
  label,
}: {
  value: string;
  sizeClassName?: string;
  margin?: number;
  label?: string;
}) {
  const qrPathData = useMemo(() => {
    const trimmed = value.trim();
    if (!trimmed) return null;
    try {
      const qr = QRCode.create(trimmed, { errorCorrectionLevel: 'M' });
      const count = qr.modules.size;
      const parts: string[] = [];
      for (let r = 0; r < count; r++) {
        for (let c = 0; c < count; c++) {
          if (qr.modules.get(r, c)) {
            parts.push(`M${c + margin},${r + margin}h1v1h-1z`);
          }
        }
      }
      return {
        viewBoxSize: count + margin * 2,
        d: parts.join(''),
      };
    } catch {
      return null;
    }
  }, [value, margin]);

  if (!qrPathData) return null;

  return (
    <svg
      viewBox={`0 0 ${qrPathData.viewBoxSize} ${qrPathData.viewBoxSize}`}
      className={`${sizeClassName} rounded-lg bg-white p-1.5 border border-[var(--line)]`}
      role="img"
      aria-label={label || `QR-код для ${value}`}
      shapeRendering="crispEdges"
    >
      <rect width={qrPathData.viewBoxSize} height={qrPathData.viewBoxSize} fill="#FFFFFF" />
      <path d={qrPathData.d} fill="#141414" />
    </svg>
  );
}
