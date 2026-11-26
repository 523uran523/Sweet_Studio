import React, { useCallback, useEffect, useId, useRef, useState } from 'react';
import { Html5Qrcode, Html5QrcodeSupportedFormats } from 'html5-qrcode';
import { Camera, ImageUp, Keyboard, QrCode, RefreshCw, X } from 'lucide-react';

const SUPPORTED_FORMATS: Html5QrcodeSupportedFormats[] = [
  Html5QrcodeSupportedFormats.QR_CODE,
  Html5QrcodeSupportedFormats.EAN_13,
  Html5QrcodeSupportedFormats.EAN_8,
  Html5QrcodeSupportedFormats.CODE_128,
  Html5QrcodeSupportedFormats.CODE_39,
  Html5QrcodeSupportedFormats.UPC_A,
  Html5QrcodeSupportedFormats.UPC_E,
  Html5QrcodeSupportedFormats.DATA_MATRIX,
];

interface CameraOption {
  id: string;
  label: string;
}

export function PosScannerModal({
  open,
  title = 'Сканер QR и штрихкодов',
  subtitle = 'Наведите камеру на QR-код купона, код партии или штрихкод позиции',
  onScan,
  onClose,
}: {
  open: boolean;
  title?: string;
  subtitle?: string;
  onScan: (code: string) => boolean | void;
  onClose: () => void;
}) {
  const rawId = useId().replace(/:/g, '');
  const cameraContainerId = `pos_qr_reader_${rawId}`;
  const fileContainerId = `pos_qr_file_${rawId}`;

  const scannerRef = useRef<Html5Qrcode | null>(null);
  const lastScanRef = useRef<{ code: string; at: number }>({ code: '', at: 0 });
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const onScanRef = useRef(onScan);
  onScanRef.current = onScan;

  const [cameras, setCameras] = useState<CameraOption[]>([]);
  const [selectedCameraId, setSelectedCameraId] = useState<string>('');
  const [retryKey, setRetryKey] = useState<number>(0);
  const [status, setStatus] = useState<'idle' | 'starting' | 'active' | 'error'>('idle');
  const [errorMessage, setErrorMessage] = useState<string>('');
  const [manualCode, setManualCode] = useState<string>('');
  const [fileBusy, setFileBusy] = useState<boolean>(false);

  const stopCamera = useCallback(async () => {
    const inst = scannerRef.current;
    scannerRef.current = null;
    if (!inst) return;
    try {
      if (inst.isScanning) {
        await inst.stop();
      }
    } catch {
      // Ignore stop errors if stream was already closed
    }
    try {
      inst.clear();
    } catch {
      // Ignore clear errors on unmount
    }
  }, []);

  const handleDecodedText = useCallback((decodedText: string) => {
    const clean = decodedText.trim();
    if (!clean) return;
    const now = Date.now();
    if (
      lastScanRef.current.code === clean &&
      now - lastScanRef.current.at < 1500
    ) {
      return;
    }
    lastScanRef.current = { code: clean, at: now };
    onScanRef.current(clean);
  }, []);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, onClose]);

  useEffect(() => {
    if (!open) {
      void stopCamera();
      setStatus('idle');
      setErrorMessage('');
      return;
    }

    let cancelled = false;
    lastScanRef.current = { code: '', at: 0 };

    const startScanner = async () => {
      setStatus('starting');
      setErrorMessage('');
      await stopCamera();

      // Wait one frame so container div is mounted in DOM
      await new Promise((resolve) => window.requestAnimationFrame(resolve));
      if (cancelled) return;

      const containerEl = document.getElementById(cameraContainerId);
      if (!containerEl) {
        setStatus('error');
        setErrorMessage('Не удалось инициализировать область видеопотока.');
        return;
      }

      if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
        setStatus('error');
        setErrorMessage(
          'Камера недоступна в текущем браузере (требуется HTTPS или разрешение на доступ к камере). Загрузите фото кода или введите его вручную.',
        );
        return;
      }

      try {
        let availableCameras: CameraOption[] = [];
        try {
          const list = await Html5Qrcode.getCameras();
          availableCameras = list.map((cam, idx) => ({
            id: cam.id,
            label: cam.label || `Камера ${idx + 1}`,
          }));
        } catch {
          availableCameras = [];
        }

        if (cancelled) return;
        setCameras(availableCameras);

        const inst = new Html5Qrcode(cameraContainerId, {
          verbose: false,
          formatsToSupport: SUPPORTED_FORMATS,
          useBarCodeDetectorIfSupported: true,
        });
        scannerRef.current = inst;

        const targetCamera: string | MediaTrackConstraints =
          selectedCameraId && availableCameras.some((c) => c.id === selectedCameraId)
            ? selectedCameraId
            : { facingMode: 'environment' };

        await inst.start(
          targetCamera,
          {
            fps: 10,
            qrbox: (viewfinderWidth, viewfinderHeight) => {
              const edge = Math.max(140, Math.floor(Math.min(viewfinderWidth, viewfinderHeight) * 0.72));
              return { width: edge, height: edge };
            },
            aspectRatio: 1.3333,
          },
          (decodedText) => {
            if (!cancelled) {
              handleDecodedText(decodedText);
            }
          },
          () => {
            // Frame without a code — normal, ignore silently
          },
        );

        if (cancelled) {
          await stopCamera();
          return;
        }
        setStatus('active');
      } catch (err) {
        if (cancelled) return;
        await stopCamera();
        const msg = err instanceof Error ? err.message : String(err);
        if (/notallowed|permission|denied/i.test(msg)) {
          setErrorMessage(
            'Доступ к камере отклонён. Разрешите камеру в настройках браузера, выберите фото с QR-кодом или введите код вручную.',
          );
        } else if (/notfound|requested device not found|no camera/i.test(msg)) {
          setErrorMessage(
            'Камера не найдена. Вы можете отсканировать код с изображения или ввести его вручную ниже.',
          );
        } else {
          setErrorMessage(
            'Не удалось запустить камеру. Используйте загрузку фото, ручной ввод или USB-сканер.',
          );
        }
        setStatus('error');
      }
    };

    void startScanner();

    return () => {
      cancelled = true;
      void stopCamera();
    };
  }, [open, selectedCameraId, retryKey, cameraContainerId, stopCamera, handleDecodedText]);

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    setFileBusy(true);
    setErrorMessage('');
    let fileScanner: Html5Qrcode | null = null;
    try {
      fileScanner = new Html5Qrcode(fileContainerId, {
        verbose: false,
        formatsToSupport: SUPPORTED_FORMATS,
        useBarCodeDetectorIfSupported: true,
      });
      const decoded = await fileScanner.scanFile(file, false);
      handleDecodedText(decoded);
    } catch {
      setErrorMessage('Не удалось распознать QR-код или штрихкод на выбранном изображении.');
    } finally {
      try {
        fileScanner?.clear();
      } catch {
        // ignore
      }
      setFileBusy(false);
    }
  };

  const handleManualSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const clean = manualCode.trim();
    if (!clean) return;
    onScanRef.current(clean);
    setManualCode('');
  };

  if (!open) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/55 p-3 sm:p-4"
      role="dialog"
      aria-modal="true"
      aria-label={title}
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="w-full max-w-md rounded-2xl border border-[var(--line)] bg-[var(--card)] text-[var(--ink)] shadow-xl overflow-hidden flex flex-col max-h-[92vh]">
        <div className="flex items-start justify-between gap-3 px-5 py-4 border-b border-[var(--line)]">
          <div className="min-w-0">
            <h2 className="text-base font-semibold flex items-center gap-2">
              <QrCode className="w-4 h-4 text-[var(--accent)] shrink-0" />
              <span className="truncate">{title}</span>
            </h2>
            <p className="text-xs text-[var(--muted)] mt-0.5">{subtitle}</p>
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Закрыть сканер"
            className="min-w-[40px] min-h-[40px] rounded-xl border border-[var(--line)] hover:bg-[var(--soft)] inline-flex items-center justify-center shrink-0"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="p-4 sm:p-5 space-y-4 overflow-y-auto">
          {cameras.length > 1 && (
            <label className="block space-y-1 text-xs font-medium">
              <span className="text-[var(--muted)]">Камера устройства</span>
              <select
                value={selectedCameraId}
                onChange={(e) => setSelectedCameraId(e.target.value)}
                className="w-full min-h-[40px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] text-sm"
              >
                <option value="">Основная (задняя) камера</option>
                {cameras.map((cam) => (
                  <option key={cam.id} value={cam.id}>
                    {cam.label}
                  </option>
                ))}
              </select>
            </label>
          )}

          {/* Camera viewport */}
          <div className="relative rounded-2xl overflow-hidden border border-[var(--line)] bg-[#141114] min-h-[240px] flex items-center justify-center">
            <div id={cameraContainerId} className="w-full" />
            <div id={fileContainerId} className="hidden" aria-hidden="true" />

            {status === 'starting' && (
              <div className="absolute inset-0 flex flex-col items-center justify-center gap-2 bg-[#141114]/80 text-white text-xs px-4 text-center">
                <Camera className="w-6 h-6 animate-pulse" />
                <span>Запускаем камеру...</span>
              </div>
            )}

            {status === 'error' && (
              <div className="absolute inset-0 flex flex-col items-center justify-center gap-3 bg-[var(--soft)] text-[var(--ink)] p-5 text-center">
                <Camera className="w-7 h-7 text-[var(--muted)]" />
                <p className="text-xs leading-relaxed max-w-xs">{errorMessage}</p>
              </div>
            )}
          </div>

          {errorMessage && status !== 'error' && (
            <div className="rounded-xl border border-[var(--line)] bg-[var(--warm)] px-3 py-2 text-xs text-[var(--ink)]">
              {errorMessage}
            </div>
          )}

          {/* Secondary actions: Upload photo or retry */}
          <div className="flex flex-wrap items-center gap-2">
            <input
              ref={fileInputRef}
              type="file"
              accept="image/*"
              onChange={handleFileChange}
              className="hidden"
            />
            <button
              type="button"
              disabled={fileBusy}
              onClick={() => fileInputRef.current?.click()}
              className="flex-1 min-h-[42px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] hover:bg-[var(--soft)] text-xs font-medium inline-flex items-center justify-center gap-1.5 disabled:opacity-50"
            >
              <ImageUp className="w-4 h-4 text-[var(--accent)]" />
              <span>{fileBusy ? 'Распознаём...' : 'Сканировать с фото'}</span>
            </button>
            {status === 'error' && (
              <button
                type="button"
                onClick={() => setRetryKey((k) => k + 1)}
                className="min-h-[42px] px-3 rounded-xl border border-[var(--line)] hover:bg-[var(--soft)] text-xs font-medium inline-flex items-center justify-center gap-1.5"
              >
                <RefreshCw className="w-3.5 h-3.5" />
                <span>Повторить камеру</span>
              </button>
            )}
          </div>

          {/* Manual fallback / USB barcode scanner */}
          <form onSubmit={handleManualSubmit} className="pt-3 border-t border-[var(--line)] space-y-2">
            <label className="block text-xs font-medium text-[var(--muted)]">
              <span className="inline-flex items-center gap-1.5">
                <Keyboard className="w-3.5 h-3.5" />
                <span>Или введите код вручную / USB-сканером</span>
              </span>
            </label>
            <div className="flex gap-2">
              <input
                type="text"
                value={manualCode}
                onChange={(e) => setManualCode(e.target.value)}
                placeholder="Например: SWEET-104 или LOT-..."
                className="flex-1 min-h-[42px] px-3 rounded-xl border border-[var(--line)] bg-[var(--bg)] text-sm font-mono"
              />
              <button
                type="submit"
                disabled={!manualCode.trim()}
                className="min-h-[42px] px-4 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-xs font-medium disabled:opacity-50 shrink-0"
              >
                Применить
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
}
