import React from 'react';

interface State {
  hasError: boolean;
  message: string;
}

export class ErrorBoundary extends React.Component<
  { children: React.ReactNode },
  State
> {
  state: State = { hasError: false, message: '' };

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, message: error.message || 'Непредвиденная ошибка' };
  }

  render() {
    if (this.state.hasError) {
      let display = this.state.message;
      try {
        const parsed = JSON.parse(this.state.message);
        if (parsed && parsed.error) {
          display = `${parsed.error} (${parsed.operationType || 'op'}: ${parsed.path || ''})`;
        }
      } catch {
        // non-json error message
      }
      return (
        <div className="min-h-screen flex items-center justify-center p-6 bg-[var(--bg)] text-[var(--ink)]">
          <div className="max-w-lg w-full rounded-2xl border border-[var(--line)] bg-[var(--card)] p-6 space-y-4">
            <h1 className="text-xl font-semibold">Произошла ошибка приложения</h1>
            <p className="text-sm text-[var(--muted)] break-words">{display}</p>
            <button
              type="button"
              onClick={() => window.location.reload()}
              className="px-4 py-2.5 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium whitespace-nowrap shrink-0"
            >
              Перезагрузить страницу
            </button>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}
