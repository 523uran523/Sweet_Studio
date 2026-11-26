import React, { useEffect, useState } from 'react';
import { Download, Smartphone, WifiOff } from 'lucide-react';

interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed'; platform: string }>;
}

export function usePWAInstall() {
  const [deferredPrompt, setDeferredPrompt] =
    useState<BeforeInstallPromptEvent | null>(null);
  const [isInstalled, setIsInstalled] = useState(false);
  const [isIOS, setIsIOS] = useState(false);

  useEffect(() => {
    const isStandalone =
      window.matchMedia('(display-mode: standalone)').matches ||
      (window.navigator as unknown as { standalone?: boolean }).standalone ===
        true;
    setIsInstalled(isStandalone);

    const ua = window.navigator.userAgent.toLowerCase();
    setIsIOS(/iphone|ipad|ipod/.test(ua));

    const handleBeforeInstallPrompt = (e: Event) => {
      e.preventDefault();
      setDeferredPrompt(e as BeforeInstallPromptEvent);
    };

    const handleAppInstalled = () => {
      setIsInstalled(true);
      setDeferredPrompt(null);
    };

    window.addEventListener('beforeinstallprompt', handleBeforeInstallPrompt);
    window.addEventListener('appinstalled', handleAppInstalled);

    return () => {
      window.removeEventListener(
        'beforeinstallprompt',
        handleBeforeInstallPrompt,
      );
      window.removeEventListener('appinstalled', handleAppInstalled);
    };
  }, []);

  const install = async () => {
    if (!deferredPrompt) return false;
    await deferredPrompt.prompt();
    const { outcome } = await deferredPrompt.userChoice;
    if (outcome === 'accepted') {
      setIsInstalled(true);
      setDeferredPrompt(null);
      return true;
    }
    return false;
  };

  return {
    isInstallable: Boolean(deferredPrompt),
    isInstalled,
    isIOS,
    install,
  };
}

export function useOnlineStatus() {
  const [isOnline, setIsOnline] = useState(
    typeof navigator !== 'undefined' ? navigator.onLine : true,
  );

  useEffect(() => {
    const handleOnline = () => setIsOnline(true);
    const handleOffline = () => setIsOnline(false);

    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);

    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, []);

  return isOnline;
}

export function PWAInstallButton({ compact = false }: { compact?: boolean }) {
  const { isInstallable, isInstalled, isIOS, install } = usePWAInstall();
  const [showIOSGuide, setShowIOSGuide] = useState(false);

  if (isInstalled) return null;

  if (isInstallable) {
    return (
      <button
        type="button"
        onClick={() => void install()}
        className={
          compact
            ? 'w-full min-h-[38px] px-3 py-1.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] hover:bg-[var(--soft)] text-xs font-medium inline-flex items-center justify-center gap-1.5 transition-colors whitespace-nowrap'
            : 'min-h-[40px] px-4 py-2 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-xs font-medium inline-flex items-center gap-2 hover:opacity-95 transition-opacity whitespace-nowrap'
        }
      >
        <Download className="w-3.5 h-3.5 shrink-0" />
        <span>Установить приложение</span>
      </button>
    );
  }

  if (isIOS) {
    return (
      <>
        <button
          type="button"
          onClick={() => setShowIOSGuide(true)}
          className={
            compact
              ? 'w-full min-h-[38px] px-3 py-1.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] hover:bg-[var(--soft)] text-xs font-medium inline-flex items-center justify-center gap-1.5 transition-colors whitespace-nowrap'
              : 'min-h-[40px] px-4 py-2 rounded-xl border border-[var(--line)] bg-[var(--card)] hover:bg-[var(--soft)] text-xs font-medium inline-flex items-center gap-2 whitespace-nowrap'
          }
        >
          <Smartphone className="w-3.5 h-3.5 shrink-0" />
          <span>На экран Домой (iOS)</span>
        </button>

        {showIOSGuide && (
          <div
            className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
            onClick={(e) => {
              if (e.target === e.currentTarget) setShowIOSGuide(false);
            }}
          >
            <div className="w-full max-w-sm rounded-2xl border border-[var(--line)] bg-[var(--card)] p-6 shadow-xl space-y-3">
              <h3 className="text-base font-semibold">
                Установка SweetStudio на iPhone / iPad
              </h3>
              <p className="text-sm text-[var(--muted)] leading-relaxed">
                1. Нажмите кнопку <strong>«Поделиться»</strong> в панели Safari.
                <br />
                2. Выберите пункт <strong>«На экран Домой»</strong>.
              </p>
              <button
                type="button"
                onClick={() => setShowIOSGuide(false)}
                className="w-full min-h-[42px] rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium"
              >
                Понятно
              </button>
            </div>
          </div>
        )}
      </>
    );
  }

  return null;
}

export function OfflineIndicator() {
  const isOnline = useOnlineStatus();

  if (isOnline) return null;

  return (
    <div
      role="status"
      className="mb-4 px-3.5 py-2.5 rounded-xl border border-[var(--line)] bg-[var(--warm)] text-xs font-medium flex items-center gap-2"
    >
      <WifiOff className="w-4 h-4 shrink-0" />
      <span>
        Нет подключения к сети — интерфейс работает из кэша PWA, а черновики форм сохраняются локально.
      </span>
    </div>
  );
}
