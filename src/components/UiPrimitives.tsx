import React, { useEffect } from 'react';
import { X } from 'lucide-react';

export function PageHeader({
  title,
  subtitle,
  action,
}: {
  title: string;
  subtitle?: string;
  action?: React.ReactNode;
}) {
  return (
    <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 pb-6">
      <div className="min-w-0">
        <h1 className="text-2xl sm:text-[30px] font-semibold tracking-tight text-[var(--ink)] leading-tight text-balance">
          {title}
        </h1>
        {subtitle && (
          <p className="mt-1 text-sm text-[var(--muted)]">{subtitle}</p>
        )}
      </div>
      {action && <div className="flex items-center gap-2 shrink-0 flex-wrap">{action}</div>}
    </div>
  );
}

export function Card({
  children,
  className = '',
  tone = 'default',
}: {
  children: React.ReactNode;
  className?: string;
  tone?: 'default' | 'soft' | 'green' | 'warm';
}) {
  const bg =
    tone === 'soft'
      ? 'bg-[var(--soft)]'
      : tone === 'green'
        ? 'bg-[var(--green)]'
        : tone === 'warm'
          ? 'bg-[var(--warm)]'
          : 'bg-[var(--card)]';

  return (
    <div
      className={`rounded-2xl border border-[var(--line)] ${bg} p-5 ${className}`}
    >
      {children}
    </div>
  );
}

export function MetricTile({
  label,
  value,
  hint,
  onClick,
}: {
  label: string;
  value: string;
  hint?: string;
  onClick?: () => void;
}) {
  const inner = (
    <div className="space-y-1.5 text-left">
      <div className="text-xs font-medium text-[var(--muted)]">{label}</div>
      <div className="text-2xl sm:text-[26px] font-semibold tracking-tight tabular-nums text-[var(--ink)]">
        {value}
      </div>
      {hint && <div className="text-xs text-[var(--muted)]">{hint}</div>}
    </div>
  );

  if (onClick) {
    return (
      <button
        type="button"
        onClick={onClick}
        className="w-full rounded-2xl border border-[var(--line)] bg-[var(--card)] p-5 hover:border-[var(--accent)] transition-colors text-left"
      >
        {inner}
      </button>
    );
  }
  return <Card>{inner}</Card>;
}

export function EmptyState({
  title,
  description,
  actionLabel,
  onAction,
}: {
  title: string;
  description: string;
  actionLabel?: string;
  onAction?: () => void;
}) {
  return (
    <Card className="text-center py-10">
      <h3 className="text-base font-semibold text-[var(--ink)]">{title}</h3>
      <p className="mt-1.5 text-sm text-[var(--muted)] max-w-md mx-auto">
        {description}
      </p>
      {actionLabel && onAction && (
        <button
          type="button"
          onClick={onAction}
          className="mt-4 inline-flex items-center justify-center px-4 py-2.5 rounded-xl bg-[var(--accent)] text-[var(--accent-ink)] text-sm font-medium whitespace-nowrap shrink-0"
        >
          {actionLabel}
        </button>
      )}
    </Card>
  );
}

export function Drawer({
  open,
  title,
  subtitle,
  wide = false,
  onClose,
  children,
}: {
  open: boolean;
  title: string;
  subtitle?: string;
  wide?: boolean;
  onClose: () => void;
  children: React.ReactNode;
}) {
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex justify-end bg-black/45"
      role="dialog"
      aria-modal="true"
      aria-label={title}
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div
        className={`w-full ${
          wide ? 'max-w-[780px]' : 'max-w-[560px]'
        } h-full bg-[var(--card)] text-[var(--ink)] border-l border-[var(--line)] overflow-y-auto p-6 flex flex-col`}
      >
        <div className="flex items-start justify-between gap-4 pb-4 border-b border-[var(--line)]">
          <div className="min-w-0">
            <h2 className="text-lg font-semibold leading-snug">{title}</h2>
            {subtitle && (
              <p className="text-xs text-[var(--muted)] mt-0.5">{subtitle}</p>
            )}
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Закрыть"
            className="min-w-[40px] min-h-[40px] inline-flex items-center justify-center rounded-xl border border-[var(--line)] hover:bg-[var(--soft)] transition-colors shrink-0"
          >
            <X className="w-4 h-4" />
          </button>
        </div>
        <div className="pt-5 flex-1">{children}</div>
      </div>
    </div>
  );
}

export function ImageWithFallback({
  src,
  alt,
  className = 'w-full h-44 object-cover rounded-xl',
}: {
  src?: string;
  alt: string;
  className?: string;
}) {
  const [failed, setFailed] = React.useState(false);

  React.useEffect(() => {
    setFailed(false);
  }, [src]);

  if (!src || failed) {
    return (
      <div
        className={`${className} flex items-center justify-center bg-[var(--soft)] text-[var(--muted)] text-xs font-medium px-3 text-center`}
      >
        {alt}
      </div>
    );
  }

  return (
    <img
      src={src}
      alt={alt}
      referrerPolicy="no-referrer"
      onError={() => setFailed(true)}
      className={className}
    />
  );
}

export function SegmentedTabs<T extends string>({
  value,
  options,
  onChange,
}: {
  value: T;
  options: Array<{ id: T; label: string; count?: number }>;
  onChange: (id: T) => void;
}) {
  return (
    <div className="inline-flex flex-wrap items-center gap-1 p-1 rounded-xl border border-[var(--line)] bg-[var(--card)]">
      {options.map((opt) => {
        const active = opt.id === value;
        return (
          <button
            key={opt.id}
            type="button"
            onClick={() => onChange(opt.id)}
            className={`px-3.5 py-2 rounded-lg text-sm font-medium transition-colors whitespace-nowrap shrink-0 min-h-[40px] ${
              active
                ? 'bg-[var(--accent)] text-[var(--accent-ink)]'
                : 'text-[var(--muted)] hover:text-[var(--ink)] hover:bg-[var(--soft)]/50'
            }`}
          >
            {opt.label}
            {typeof opt.count === 'number' && (
              <span className="ml-1.5 opacity-80 tabular-nums">{opt.count}</span>
            )}
          </button>
        );
      })}
    </div>
  );
}
