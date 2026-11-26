/**
 * Ported directly from Masters lib/core/units.dart.
 * Handles unit families, conversion, price bases, and formatting.
 */
export const QTY_UNITS = [
  'шт',
  'г',
  'мг',
  'кг',
  'мл',
  'л',
  'см',
  'мм',
  'м',
  'см²',
  'дм²',
  'м²',
  'сек',
  'мин',
  'ч',
  'кВт·ч',
  'упак',
] as const;

export const PRICE_UNITS = [
  'за шт',
  'за г',
  'за 100 г',
  'за мг',
  'за кг',
  'за мл',
  'за л',
  'за см',
  'за мм',
  'за м',
  'за см²',
  'за дм²',
  'за м²',
  'за сек',
  'за мин',
  'за ч',
  'за кВт·ч',
  'за упак',
  'за услугу',
] as const;

export type UnitFamily =
  | 'count'
  | 'mass'
  | 'volume'
  | 'length'
  | 'area'
  | 'time'
  | 'energy'
  | 'other';

export function unitFamily(unit: string): UnitFamily {
  switch (unit.trim().toLowerCase()) {
    case 'шт':
    case 'упак':
    case 'услуга':
      return 'count';
    case 'г':
    case 'мг':
    case 'кг':
      return 'mass';
    case 'мл':
    case 'л':
      return 'volume';
    case 'см':
    case 'мм':
    case 'м':
      return 'length';
    case 'см²':
    case 'см2':
    case 'дм²':
    case 'дм2':
    case 'м²':
    case 'м2':
      return 'area';
    case 'сек':
    case 'мин':
    case 'ч':
      return 'time';
    case 'квт·ч':
      return 'energy';
    default:
      return 'other';
  }
}

const TO_BASE: Record<string, number> = {
  'шт': 1,
  'упак': 1,
  'услуга': 1,
  'мг': 0.000001,
  'г': 0.001,
  'кг': 1,
  'мл': 0.001,
  'л': 1,
  'мм': 0.001,
  'см': 0.01,
  'м': 1,
  'см²': 0.0001,
  'см2': 0.0001,
  'дм²': 0.01,
  'дм2': 0.01,
  'м²': 1,
  'м2': 1,
  'сек': 1 / 60,
  'мин': 1,
  'ч': 60,
  'кВт·ч': 1,
  'квт·ч': 1,
};

export function qtyBaseOf(unit: string): number {
  return TO_BASE[unit] ?? 1;
}

export function priceBaseOf(priceUnit: string): number {
  switch (priceUnit) {
    case 'за шт':
    case 'за упак':
    case 'за услугу':
    case 'за кг':
    case 'за л':
    case 'за м':
    case 'за м²':
    case 'за кВт·ч':
    case 'за мин':
      return 1;
    case 'за мг':
      return 0.000001;
    case 'за г':
    case 'за мл':
    case 'за мм':
      return 0.001;
    case 'за 100 г':
      return 0.1;
    case 'за см':
    case 'за дм²':
      return 0.01;
    case 'за см²':
      return 0.0001;
    case 'за сек':
      return 1 / 60;
    case 'за ч':
      return 60;
    default:
      return 1;
  }
}

export function unitsCompatible(a: string, b: string): boolean {
  const fam = unitFamily(a);
  return fam !== 'other' && fam === unitFamily(b);
}

export function convertQty(value: number, from: string, to: string): number | null {
  if (from === to) return value;
  if (!unitsCompatible(from, to)) return null;
  const source = TO_BASE[from];
  const target = TO_BASE[to];
  if (source === undefined || target === undefined || target === 0) return null;
  return (value * source) / target;
}

export function convertQtyWithDensity(
  value: number,
  from: string,
  to: string,
  densityGPerMl?: number,
): number | null {
  const direct = convertQty(value, from, to);
  if (direct !== null) return direct;
  if (!densityGPerMl || !Number.isFinite(densityGPerMl) || densityGPerMl <= 0) {
    return null;
  }
  const fFrom = unitFamily(from);
  const fTo = unitFamily(to);
  if (fFrom === 'mass' && fTo === 'volume') {
    const grams = convertQty(value, from, 'г');
    if (grams === null) return null;
    const ml = grams / densityGPerMl;
    return convertQty(ml, 'мл', to);
  }
  if (fFrom === 'volume' && fTo === 'mass') {
    const ml = convertQty(value, from, 'мл');
    if (ml === null) return null;
    const grams = ml * densityGPerMl;
    return convertQty(grams, 'г', to);
  }
  return null;
}

export function defaultPriceUnit(qtyUnit: string): string {
  switch (qtyUnit) {
    case 'г':
      return 'за г';
    case 'мг':
      return 'за мг';
    case 'кг':
      return 'за кг';
    case 'мл':
      return 'за мл';
    case 'л':
      return 'за л';
    case 'см':
      return 'за см';
    case 'мм':
      return 'за мм';
    case 'м':
      return 'за м';
    case 'см²':
      return 'за см²';
    case 'дм²':
      return 'за дм²';
    case 'м²':
      return 'за м²';
    case 'сек':
      return 'за сек';
    case 'мин':
      return 'за мин';
    case 'ч':
      return 'за ч';
    case 'кВт·ч':
      return 'за кВт·ч';
    case 'упак':
      return 'за упак';
    case 'услуга':
      return 'за услугу';
    default:
      return 'за шт';
  }
}

export function priceUnitsFor(qtyUnit: string): string[] {
  switch (unitFamily(qtyUnit)) {
    case 'mass':
      return ['за мг', 'за г', 'за 100 г', 'за кг'];
    case 'volume':
      return ['за мл', 'за л'];
    case 'length':
      return ['за мм', 'за см', 'за м'];
    case 'area':
      return ['за см²', 'за дм²', 'за м²'];
    case 'time':
      return ['за сек', 'за мин', 'за ч'];
    case 'energy':
      return ['за кВт·ч'];
    case 'count':
      if (qtyUnit === 'упак') return ['за упак'];
      if (qtyUnit === 'услуга') return ['за услугу'];
      return ['за шт'];
    default:
      return [...PRICE_UNITS];
  }
}

export function formatQty(value: number, unit?: string): string {
  if (!Number.isFinite(value)) return '0';
  const rounded = Math.round(value * 1000) / 1000;
  const formatted =
    rounded % 1 === 0
      ? rounded.toString()
      : rounded.toFixed(3).replace(/0+$/, '').replace(/\.$/, '');
  return unit ? `${formatted.replace('.', ',')} ${unit}` : formatted.replace('.', ',');
}
