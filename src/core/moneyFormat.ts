/**
 * Ported from Masters lib/core/money_format.dart.
 * All money values are stored strictly as integer kopecks/cents.
 */
export function formatMoneyCents(cents: number, hideAmounts = false): string {
  if (hideAmounts) return '••• ₽';
  const safe = Number.isFinite(cents) ? Math.round(cents) : 0;
  const sign = safe < 0 ? '−' : '';
  const abs = Math.abs(safe);
  const rub = Math.floor(abs / 100);
  const kop = abs % 100;
  const formattedRub = rub.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
  if (kop === 0) {
    return `${sign}${formattedRub} ₽`;
  }
  return `${sign}${formattedRub},${kop.toString().padStart(2, '0')} ₽`;
}

export function parseRubToCents(raw: string | number): number {
  if (typeof raw === 'number') {
    return Number.isFinite(raw) ? Math.round(raw * 100) : 0;
  }
  const normalized = raw.trim().replace(/\s+/g, '').replace(',', '.');
  if (!normalized) return 0;
  const num = Number(normalized);
  if (!Number.isFinite(num)) return 0;
  return Math.round(num * 100);
}

export function centsToRubInput(cents: number): string {
  const safe = Number.isFinite(cents) ? Math.round(cents) : 0;
  if (safe % 100 === 0) return String(safe / 100);
  return (safe / 100).toFixed(2);
}
