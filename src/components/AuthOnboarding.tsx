import React, { useState } from 'react';
import { signInWithPopup, User } from 'firebase/auth';
import { auth, googleProvider } from '../firebase/client';
import { createWorkspaceWithOptionalDemo } from '../firebase/seedDemo';
import { newId } from '../firebase/workspaceService';
import { BusinessFormat, SOFT_ATELIER_THEMES } from '../types/domain';
import { RECIPE_IMAGES } from '../firebase/seedDemo';
import { ImageWithFallback } from './UiPrimitives';

export function AuthScreen() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleGoogleLogin = async () => {
    setLoading(true);
    setError(null);
    try {
      await signInWithPopup(auth, googleProvider);
    } catch (err) {
      setError(
        err instanceof Error
          ? err.message
          : 'Не удалось выполнить вход. Проверьте настройки браузера.',
      );
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-[var(--bg)] text-[var(--ink)] flex items-center justify-center p-4 sm:p-8">
      <div className="max-w-5xl w-full grid lg:grid-cols-2 gap-8 items-stretch">
        <div className="rounded-2xl border border-[var(--line)] bg-[var(--card)] p-6 sm:p-10 flex flex-col justify-between">
          <div>
            <div className="flex items-center gap-3">
              <img
                src="/Sweet_Studio_icon.png"
                alt="Sweet Studio"
                className="w-11 h-11 rounded-xl object-cover"
              />
              <span className="text-xl font-semibold tracking-tight font-display">
                sweet studio.
              </span>
            </div>
            <h1 className="mt-8 text-3xl sm:text-4xl font-semibold tracking-tight leading-tight text-balance">
              Помогаем развивать ваше кондитерское дело.
            </h1>
            <p className="mt-4 text-base text-[var(--muted)] leading-relaxed">
              Единое рабочее пространство от первого домашнего заказа до собственной
              сети кондитерских: рецепты с техкартами, калькулятор себестоимости,
              склад по FEFO, производство, клиенты, финансы и команда.
            </p>
          </div>

          <div className="mt-8 space-y-4">
            {error && (
              <div className="p-3 rounded-xl bg-[var(--danger-bg)] text-[var(--danger)] text-sm">
                {error}
              </div>
            )}
            <button
              type="button"
              disabled={loading}
              onClick={handleGoogleLogin}
              className="w-full min-h-[48px] px-5 py-3 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium hover:opacity-95 transition-opacity disabled:opacity-60 whitespace-nowrap"
            >
              {loading ? 'Выполняется вход...' : 'Войти через Google'}
            </button>
            <p className="text-xs text-[var(--muted)]">
              Данные изолированы на уровне вашего предприятия в защищённом облачном
              хранилище.
            </p>
          </div>
        </div>

        <div className="rounded-2xl border border-[var(--line)] bg-[var(--soft)] p-5 grid grid-cols-2 gap-3">
          <div className="col-span-2">
            <ImageWithFallback
              src={RECIPE_IMAGES.berryCake}
              alt="Медовик с малиной и крем-чизом"
              className="w-full h-56 object-cover rounded-xl"
            />
          </div>
          <ImageWithFallback
            src={RECIPE_IMAGES.pistachioRoll}
            alt="Фисташковый меренговый рулет"
            className="w-full h-40 object-cover rounded-xl"
          />
          <ImageWithFallback
            src={RECIPE_IMAGES.cupcakesVanilla}
            alt="Ванильные капкейки с инжиром"
            className="w-full h-40 object-cover rounded-xl"
          />
        </div>
      </div>
    </div>
  );
}

export function WorkspaceOnboarding({
  user,
  themeIndex,
  onSelectTheme,
  onCreated,
}: {
  user: User;
  themeIndex: number;
  onSelectTheme: (idx: number) => void;
  onCreated: (workspaceId: string) => void;
}) {
  const [name, setName] = useState(
    user.displayName ? `Кондитерская ${user.displayName.split(' ')[0]}` : 'Моя кондитерская',
  );
  const [slogan, setSlogan] = useState('Помогаем развивать ваше дело');
  const [format, setFormat] = useState<BusinessFormat>('studio');
  const [withDemo, setWithDemo] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim()) return;
    setSaving(true);
    setError(null);
    const workspaceId = newId('ws');
    try {
      await createWorkspaceWithOptionalDemo({
        workspaceId,
        ownerId: user.uid,
        ownerName: user.displayName || user.email || 'Владелец',
        ownerEmail: user.email || '',
        workspaceName: name.trim(),
        slogan: slogan.trim(),
        businessFormat: format,
        themeIndex,
        withDemo,
      });
      onCreated(workspaceId);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка создания пространства');
      setSaving(false);
    }
  };

  return (
    <div className="min-h-screen bg-[var(--bg)] text-[var(--ink)] flex items-center justify-center p-4 sm:p-8">
      <form
        onSubmit={handleSubmit}
        className="max-w-2xl w-full rounded-2xl border border-[var(--line)] bg-[var(--card)] p-6 sm:p-8 space-y-6"
      >
        <div className="flex items-center gap-3">
          <img
            src="/Sweet_Studio_icon.png"
            alt="Sweet Studio"
            className="w-10 h-10 rounded-xl object-cover"
          />
          <div>
            <h1 className="text-2xl font-semibold tracking-tight">
              Создать рабочее пространство
            </h1>
            <p className="text-xs text-[var(--muted)]">
              Профиль можно переключить позже в настройках без потери данных
            </p>
          </div>
        </div>

        <div className="grid sm:grid-cols-2 gap-4">
          <label className="block space-y-1.5 text-sm font-medium">
            <span>Название мастерской</span>
            <input
              type="text"
              required
              maxLength={120}
              value={name}
              onChange={(e) => setName(e.target.value)}
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] text-[var(--ink)]"
            />
          </label>
          <label className="block space-y-1.5 text-sm font-medium">
            <span>Девиз или профиль</span>
            <input
              type="text"
              maxLength={200}
              value={slogan}
              onChange={(e) => setSlogan(e.target.value)}
              className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] text-[var(--ink)]"
            />
          </label>
        </div>

        <div className="space-y-2">
          <span className="text-sm font-medium block">Формат бизнеса</span>
          <div className="grid sm:grid-cols-3 gap-3">
            {[
              {
                id: 'home' as const,
                title: 'Домашний кондитер',
                desc: 'Заказы, рецепты, кладовая, клиенты, финансы',
              },
              {
                id: 'studio' as const,
                title: 'Кондитерская студия',
                desc: '+ производство, команда, качество, маркетинг',
              },
              {
                id: 'network' as const,
                title: 'Сеть кондитерских',
                desc: 'Несколько точек, партии, кассы и сводки',
              },
            ].map((item) => (
              <button
                key={item.id}
                type="button"
                onClick={() => setFormat(item.id)}
                className={`p-3.5 rounded-xl border text-left transition-colors ${
                  format === item.id
                    ? 'border-[var(--accent)] bg-[var(--soft)]'
                    : 'border-[var(--line)] bg-[var(--bg)] hover:border-[var(--accent)]/60'
                }`}
              >
                <div className="text-sm font-semibold">{item.title}</div>
                <div className="text-xs text-[var(--muted)] mt-1">{item.desc}</div>
              </button>
            ))}
          </div>
        </div>

        <div className="space-y-2">
          <span className="text-sm font-medium block">Тема Soft Atelier</span>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-2.5">
            {SOFT_ATELIER_THEMES.map((t) => (
              <button
                key={t.index}
                type="button"
                onClick={() => onSelectTheme(t.index)}
                className={`p-2.5 rounded-xl border text-left transition-colors ${
                  themeIndex === t.index
                    ? 'border-[var(--accent)] ring-1 ring-[var(--accent)]'
                    : 'border-[var(--line)]'
                }`}
                style={{ backgroundColor: t.bg, color: t.ink }}
              >
                <div className="flex items-center gap-2">
                  <span
                    className="w-4 h-4 rounded-md shrink-0"
                    style={{ backgroundColor: t.accent }}
                  />
                  <span className="text-xs font-semibold truncate">{t.name}</span>
                </div>
              </button>
            ))}
          </div>
        </div>

        <label className="flex items-start gap-3 p-3.5 rounded-xl border border-[var(--line)] bg-[var(--bg)] cursor-pointer">
          <input
            type="checkbox"
            checked={withDemo}
            onChange={(e) => setWithDemo(e.target.checked)}
            className="mt-1 w-4 h-4 accent-[var(--accent)]"
          />
          <div className="text-sm">
            <div className="font-medium">Заполнить изолированную демо-базу</div>
            <div className="text-xs text-[var(--muted)]">
              5 рецептов с фотографиями, партии FEFO, клиенты, заказы и финансовые
              проводки для быстрого старта
            </div>
          </div>
        </label>

        {error && (
          <div className="p-3 rounded-xl bg-[var(--danger-bg)] text-[var(--danger)] text-sm">
            {error}
          </div>
        )}

        <button
          type="submit"
          disabled={saving}
          className="w-full min-h-[48px] px-5 py-3 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium hover:opacity-95 disabled:opacity-60"
        >
          {saving ? 'Создаём пространство...' : 'Открыть Sweet Studio'}
        </button>
      </form>
    </div>
  );
}
