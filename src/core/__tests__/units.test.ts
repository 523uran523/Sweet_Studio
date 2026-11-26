import { describe, expect, it } from 'vitest';
import {
  convertQty,
  convertQtyWithDensity,
  formatQty,
  unitFamily,
  unitsCompatible,
} from '../units';

describe('units', () => {
  it('identifies unit families and compatibility', () => {
    expect(unitFamily('кг')).toBe('mass');
    expect(unitFamily('мл')).toBe('volume');
    expect(unitFamily('шт')).toBe('count');
    expect(unitsCompatible('г', 'кг')).toBe(true);
    expect(unitsCompatible('г', 'мл')).toBe(false);
  });

  it('converts compatible units directly', () => {
    expect(convertQty(1500, 'г', 'кг')).toBeCloseTo(1.5, 6);
    expect(convertQty(0.75, 'л', 'мл')).toBeCloseTo(750, 6);
    expect(convertQty(90, 'мин', 'ч')).toBeCloseTo(1.5, 6);
    expect(convertQty(100, 'г', 'мл')).toBeNull();
  });

  it('converts mass <-> volume using density g/ml', () => {
    // Milk density ~1.03 g/ml: 500 ml = 515 g
    expect(convertQtyWithDensity(500, 'мл', 'г', 1.03)).toBeCloseTo(515, 5);
    // Oil density ~0.92 g/ml: 460 g = 500 ml
    expect(convertQtyWithDensity(460, 'г', 'мл', 0.92)).toBeCloseTo(500, 5);
    // Missing density falls back to null
    expect(convertQtyWithDensity(500, 'мл', 'г')).toBeNull();
  });

  it('formats quantities cleanly in Russian locale style', () => {
    expect(formatQty(1.5, 'кг')).toBe('1,5 кг');
    expect(formatQty(250, 'г')).toBe('250 г');
  });
});
