import React, { useEffect, useState } from 'react';
import {
  createUserWithEmailAndPassword,
  getRedirectResult,
  sendEmailVerification,
  sendPasswordResetEmail,
  signInWithEmailAndPassword,
  signInWithPopup,
  signInWithRedirect,
  User,
} from 'firebase/auth';
import { Eye, EyeOff, KeyRound, Mail, RefreshCw } from 'lucide-react';
import { auth, googleProvider } from '../firebase/client';
import { createWorkspaceWithOptionalDemo } from '../firebase/seedDemo';
import { newId } from '../firebase/workspaceService';
import { BusinessFormat, SOFT_ATELIER_THEMES } from '../types/domain';
import { RECIPE_IMAGES } from '../firebase/seedDemo';
import { ImageWithFallback } from './UiPrimitives';

import firebaseConfig from '../../firebase-applet-config.json';

export function translateFirebaseAuthError(err: unknown): string {
  const code =
    typeof err === 'object' && err !== null && 'code' in err
      ? String((err as { code?: unknown }).code || '')
      : '';
  switch (code) {
    case 'auth/invalid-email':
      return 'Проверьте формат электронной почты.';
    case 'auth/user-disabled':
      return 'Этот аккаунт заблокирован.';
    case 'auth/user-not-found':
    case 'auth/wrong-password':
    case 'auth/invalid-credential':
      return 'Неверный email или пароль.';
    case 'auth/email-already-in-use':
      return 'Этот email уже зарегистрирован. Войдите или восстановите пароль.';
    case 'auth/weak-password':
      return 'Пароль должен содержать минимум 6 символов.';
    case 'auth/too-many-requests':
      return 'Слишком много попыток входа. Подождите пару минут и повторите.';
    case 'auth/operation-not-allowed':
      return 'Вход по Email и паролю ещё не включён в Firebase Console (Authentication → Sign-in method → Email/Password).';
    case 'auth/requires-recent-login':
      return 'Для изменения почты или привязки нужно подтвердить вход: выйдите и войдите заново.';
    case 'auth/provider-already-linked':
      return 'Этот способ входа уже привязан к вашему аккаунту.';
    case 'auth/credential-already-in-use':
      return 'Этот email или аккаунт Google уже привязан к другому пользователю.';
    case 'auth/unauthorized-domain':
      return 'Текущий домен не добавлен в Firebase Console (Authentication → Settings → Authorized domains).';
    case 'auth/popup-closed-by-user':
      return 'Окно входа закрыто до завершения авторизации.';
    case 'auth/popup-blocked':
      return 'Браузер заблокировал всплывающее окно Google.';
    default:
      return err instanceof Error
        ? err.message
        : 'Не удалось выполнить вход. Попробуйте ещё раз.';
  }
}

function getFirebaseErrorCode(err: unknown): string {
  return typeof err === 'object' && err !== null && 'code' in err
    ? String((err as { code?: unknown }).code || '')
    : '';
}

function GoogleIcon() {
  return (
    <svg viewBox="0 0 24 24" className="w-4 h-4 shrink-0" aria-hidden="true">
      <path
        fill="#4285F4"
        d="M23.745 12.27c0-.7-.06-1.4-.19-2.07H12v4.51h6.6c-.29 1.52-1.14 2.82-2.4 3.68v3.05h3.88c2.27-2.09 3.665-5.17 3.665-9.17Z"
      />
      <path
        fill="#34A853"
        d="M12 24c3.24 0 5.95-1.08 7.93-2.91l-3.88-3.05c-1.08.72-2.45 1.16-4.05 1.16-3.12 0-5.77-2.11-6.72-4.96H1.29v3.14C3.26 21.3 7.31 24 12 24Z"
      />
      <path
        fill="#FBBC05"
        d="M5.28 14.24c-.24-.72-.38-1.49-.38-2.24s.14-1.52.38-2.24V6.62H1.29C.47 8.24 0 10.06 0 12s.47 3.76 1.29 5.38l3.99-3.14Z"
      />
      <path
        fill="#EA4335"
        d="M12 4.75c1.77 0 3.35.61 4.6 1.8l3.42-3.42C17.95 1.19 15.24 0 12 0 7.31 0 3.26 2.7 1.29 6.62l3.99 3.14c.95-2.85 3.6-4.96 6.72-4.96Z"
      />
    </svg>
  );
}

export function AuthScreen() {
  const [mode, setMode] = useState<'login' | 'register' | 'reset'>('login');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [errorCode, setErrorCode] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    getRedirectResult(auth).catch((err) => {
      if (!active) return;
      const code = getFirebaseErrorCode(err);
      if (code) {
        setErrorCode(code);
        setError(translateFirebaseAuthError(err));
      }
    });
    return () => {
      active = false;
    };
  }, []);

  const switchMode = (next: 'login' | 'register' | 'reset') => {
    setMode(next);
    setError(null);
    setErrorCode(null);
    setNotice(null);
  };

  const handleEmailSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const cleanEmail = email.trim();
    if (!cleanEmail) return;
    setLoading(true);
    setError(null);
    setErrorCode(null);
    setNotice(null);
    try {
      if (mode === 'reset') {
        await sendPasswordResetEmail(auth, cleanEmail);
        setNotice(`Ссылка для сброса пароля отправлена на ${cleanEmail}.`);
      } else if (mode === 'register') {
        if (password.length < 6) {
          setError('Пароль должен содержать минимум 6 символов.');
          return;
        }
        const cred = await createUserWithEmailAndPassword(auth, cleanEmail, password);
        await sendEmailVerification(cred.user);
      } else {
        await signInWithEmailAndPassword(auth, cleanEmail, password);
      }
    } catch (err) {
      setErrorCode(getFirebaseErrorCode(err));
      setError(translateFirebaseAuthError(err));
    } finally {
      setLoading(false);
    }
  };

  const handleGoogleLogin = async (forceRedirect = false) => {
    setLoading(true);
    setError(null);
    setErrorCode(null);
    setNotice(null);
    try {
      if (forceRedirect) {
        await signInWithRedirect(auth, googleProvider);
        return;
      }
      await signInWithPopup(auth, googleProvider);
    } catch (err) {
      const code = getFirebaseErrorCode(err);
      if (
        code === 'auth/popup-blocked' ||
        code === 'auth/operation-not-supported-in-this-environment'
      ) {
        try {
          await signInWithRedirect(auth, googleProvider);
          return;
        } catch (redirErr) {
          setErrorCode(getFirebaseErrorCode(redirErr));
          setError(translateFirebaseAuthError(redirErr));
        }
      } else {
        setErrorCode(code);
        setError(translateFirebaseAuthError(err));
      }
    } finally {
      setLoading(false);
    }
  };

  const titleText =
    mode === 'register'
      ? 'Создать аккаунт'
      : mode === 'reset'
        ? 'Восстановление пароля'
        : 'Вход в SweetStudio';

  const subtitleText =
    mode === 'register'
      ? 'Начните вести заказы, рецепты и склад в единой системе'
      : mode === 'reset'
        ? 'Отправим ссылку для установки нового пароля на вашу почту'
        : 'Войдите в рабочее пространство вашей кондитерской';

  return (
    <div className="min-h-screen bg-[var(--bg)] text-[var(--ink)] grid lg:grid-cols-2">
      <div className="flex flex-col justify-center px-5 py-10 sm:px-10">
        <div className="w-full max-w-[390px] mx-auto space-y-6">
          <div className="space-y-4">
            <div className="inline-flex items-center gap-2.5">
              <img
                src="/Sweet_Studio_icon.png"
                alt="SweetStudio"
                className="w-9 h-9 rounded-xl object-cover"
              />
              <span className="text-lg font-semibold tracking-tight font-display">
                SweetStudio
              </span>
            </div>
            <div className="space-y-1.5">
              <h1 className="text-2xl font-semibold tracking-tight text-balance">
                {titleText}
              </h1>
              <p className="text-sm text-[var(--muted)]">{subtitleText}</p>
            </div>
          </div>

          {error && (
            <div className="p-3.5 rounded-xl bg-[var(--danger-bg)] text-[var(--danger)] text-xs leading-relaxed space-y-2">
              <p>{error}</p>
              {errorCode === 'auth/operation-not-allowed' && (
                <p className="text-[11px] opacity-90">
                  Владельцу проекта: откройте{' '}
                  <a
                    href={`https://console.firebase.google.com/project/${firebaseConfig.projectId}/authentication/providers`}
                    target="_blank"
                    rel="noreferrer"
                    className="underline font-medium"
                  >
                    Firebase Console → Sign-in method
                  </a>{' '}
                  и включите провайдер <strong>Email/Password</strong> (сейчас можно войти через Google выше).
                </p>
              )}
              {errorCode === 'auth/popup-blocked' && (
                <button
                  type="button"
                  onClick={() => void handleGoogleLogin(true)}
                  className="underline font-medium text-left"
                >
                  Войти через перенаправление страницы
                </button>
              )}
            </div>
          )}

          {notice && (
            <div className="p-3.5 rounded-xl bg-[var(--soft)] text-[var(--ink)] text-xs leading-relaxed">
              {notice}
            </div>
          )}

          {mode !== 'reset' && (
            <>
              <button
                type="button"
                disabled={loading}
                onClick={() => void handleGoogleLogin(false)}
                className="w-full min-h-[44px] px-4 rounded-xl border border-[var(--line)] bg-[var(--card)] hover:bg-[var(--soft)] text-sm font-medium transition-colors disabled:opacity-60 inline-flex items-center justify-center gap-2.5"
              >
                <GoogleIcon />
                <span>Продолжить с Google</span>
              </button>

              <div className="relative flex items-center">
                <div className="flex-grow border-t border-[var(--line)]" />
                <span className="shrink mx-3 text-xs text-[var(--muted)]">или</span>
                <div className="flex-grow border-t border-[var(--line)]" />
              </div>
            </>
          )}

          <form onSubmit={handleEmailSubmit} className="space-y-4">
            <label className="block space-y-1.5 text-xs font-medium">
              <span>Электронная почта</span>
              <input
                type="email"
                required
                autoComplete="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="name@example.com"
                className="w-full min-h-[44px] px-3.5 rounded-xl border border-[var(--line)] bg-[var(--card)] text-sm focus:outline-none focus:ring-2 focus:ring-[var(--accent)]/30"
              />
            </label>

            {mode !== 'reset' && (
              <div className="space-y-1.5">
                <div className="flex items-center justify-between text-xs font-medium">
                  <label htmlFor="auth-password-input">Пароль</label>
                  {mode === 'login' && (
                    <button
                      type="button"
                      onClick={() => switchMode('reset')}
                      className="text-[var(--muted)] hover:text-[var(--ink)] transition-colors"
                    >
                      Забыли пароль?
                    </button>
                  )}
                </div>
                <div className="relative">
                  <input
                    id="auth-password-input"
                    type={showPassword ? 'text' : 'password'}
                    required
                    minLength={6}
                    autoComplete={mode === 'register' ? 'new-password' : 'current-password'}
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    placeholder={mode === 'register' ? 'Минимум 6 символов' : 'Введите пароль'}
                    className="w-full min-h-[44px] pl-3.5 pr-10 rounded-xl border border-[var(--line)] bg-[var(--card)] text-sm focus:outline-none focus:ring-2 focus:ring-[var(--accent)]/30"
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword((v) => !v)}
                    aria-label={showPassword ? 'Скрыть пароль' : 'Показать пароль'}
                    className="absolute right-2 top-1/2 -translate-y-1/2 p-1.5 text-[var(--muted)] hover:text-[var(--ink)]"
                  >
                    {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                  </button>
                </div>
              </div>
            )}

            <button
              type="submit"
              disabled={loading}
              className="w-full min-h-[46px] px-5 py-2.5 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium hover:opacity-95 transition-opacity disabled:opacity-60 inline-flex items-center justify-center gap-2"
            >
              {mode === 'reset' ? (
                <KeyRound className="w-4 h-4" />
              ) : (
                <Mail className="w-4 h-4" />
              )}
              <span>
                {loading
                  ? 'Выполняется...'
                  : mode === 'register'
                    ? 'Создать аккаунт'
                    : mode === 'reset'
                      ? 'Отправить ссылку'
                      : 'Войти'}
              </span>
            </button>
          </form>

          <div className="text-center text-xs text-[var(--muted)] pt-1">
            {mode === 'login' ? (
              <>
                Нет аккаунта?{' '}
                <button
                  type="button"
                  onClick={() => switchMode('register')}
                  className="font-medium text-[var(--ink)] hover:underline"
                >
                  Зарегистрироваться
                </button>
              </>
            ) : (
              <>
                {mode === 'register' ? 'Уже есть аккаунт? ' : ''}
                <button
                  type="button"
                  onClick={() => switchMode('login')}
                  className="font-medium text-[var(--ink)] hover:underline"
                >
                  {mode === 'reset' ? '← Вернуться ко входу' : 'Войти'}
                </button>
              </>
            )}
          </div>
        </div>
      </div>

      <div className="hidden lg:block relative overflow-hidden bg-[var(--soft)]">
        <ImageWithFallback
          src={RECIPE_IMAGES.berryCake}
          alt="SweetStudio — рабочее пространство кондитерской"
          className="w-full h-full object-cover"
        />
        <div className="absolute inset-0 bg-gradient-to-t from-black/75 via-black/25 to-transparent" />
        <div className="absolute inset-x-0 bottom-0 p-10 text-white space-y-2 max-w-lg">
          <p className="text-lg font-medium leading-snug text-balance">
            Рецепты, калькулятор себестоимости, склад по FEFO, заказы и касса в одном месте.
          </p>
          <p className="text-xs text-white/75">
            Изолированное облачное пространство для домашней кухни, студии и сети витрин.
          </p>
        </div>
      </div>
    </div>
  );
}

export function EmailVerificationScreen({
  user,
  onVerified,
  onSignOut,
}: {
  user: User;
  onVerified: () => void;
  onSignOut: () => void;
}) {
  const [checking, setChecking] = useState(false);
  const [sending, setSending] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const handleCheck = async () => {
    setChecking(true);
    setError(null);
    setMessage(null);
    try {
      await user.reload();
      await user.getIdToken(true);
      if (auth.currentUser?.emailVerified) {
        onVerified();
      } else {
        setMessage('Почта пока не подтверждена. Проверьте письма (и папку «Спам») и перейдите по ссылке.');
      }
    } catch (err) {
      setError(translateFirebaseAuthError(err));
    } finally {
      setChecking(false);
    }
  };

  const handleResend = async () => {
    setSending(true);
    setError(null);
    setMessage(null);
    try {
      await sendEmailVerification(user);
      setMessage(`Письмо с подтверждением повторно отправлено на ${user.email || 'вашу почту'}.`);
    } catch (err) {
      setError(translateFirebaseAuthError(err));
    } finally {
      setSending(false);
    }
  };

  return (
    <div className="min-h-screen bg-[var(--bg)] text-[var(--ink)] flex items-center justify-center p-4 sm:p-8">
      <div className="max-w-md w-full rounded-2xl border border-[var(--line)] bg-[var(--card)] p-6 sm:p-8 space-y-5">
        <div className="flex items-center gap-3">
          <img
            src="/Sweet_Studio_icon.png"
            alt="SweetStudio"
            className="w-10 h-10 rounded-xl object-cover"
          />
          <div>
            <h1 className="text-xl font-semibold">Подтвердите почту</h1>
            <p className="text-xs text-[var(--muted)]">{user.email || 'Аккаунт'}</p>
          </div>
        </div>

        <p className="text-sm text-[var(--muted)] leading-relaxed">
          Для защиты данных кондитерской и приглашений сотрудников правила доступа
          требуют подтверждённую электронную почту. Перейдите по ссылке из письма и
          нажмите кнопку проверки ниже.
        </p>

        {error && (
          <div className="p-3 rounded-xl bg-[var(--danger-bg)] text-[var(--danger)] text-xs">
            {error}
          </div>
        )}
        {message && (
          <div className="p-3 rounded-xl bg-[var(--soft)] text-[var(--ink)] text-xs">
            {message}
          </div>
        )}

        <div className="space-y-2.5">
          <button
            type="button"
            disabled={checking}
            onClick={handleCheck}
            className="w-full min-h-[44px] px-4 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium inline-flex items-center justify-center gap-2 disabled:opacity-60"
          >
            <RefreshCw className="w-4 h-4" />
            <span>{checking ? 'Проверяем...' : 'Я подтвердил почту — войти'}</span>
          </button>

          <button
            type="button"
            disabled={sending}
            onClick={handleResend}
            className="w-full min-h-[42px] px-4 rounded-xl border border-[var(--line)] bg-[var(--bg)] hover:bg-[var(--soft)] text-xs font-medium disabled:opacity-60"
          >
            {sending ? 'Отправляем...' : 'Отправить письмо ещё раз'}
          </button>

          <button
            type="button"
            onClick={onSignOut}
            className="w-full min-h-[40px] px-4 rounded-xl text-xs text-[var(--muted)] hover:text-[var(--ink)]"
          >
            Выйти и использовать другой email
          </button>
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
            alt="SweetStudio"
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
          {saving ? 'Создаём пространство...' : 'Открыть SweetStudio'}
        </button>
      </form>
    </div>
  );
}
