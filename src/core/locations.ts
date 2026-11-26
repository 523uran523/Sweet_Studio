import { InventoryItem, LocationItem, Order, PosSale } from '../types/domain';

export function resolveDefaultLocation(locations: LocationItem[]): LocationItem | undefined {
  return locations.find((l) => l.isDefault) || locations[0];
}

export function resolveLocationName(
  locations: LocationItem[],
  locationId?: string,
  fallbackName?: string,
): string {
  if (locationId) {
    const found = locations.find((l) => l.id === locationId);
    if (found) return found.name;
  }
  if (fallbackName) return fallbackName;
  return resolveDefaultLocation(locations)?.name || 'Основная студия';
}

/**
 * Checks whether an entity belongs to the active location filter.
 * Unassigned entities (without locationId/locationName) belong to the default location
 * so legacy single-location data remains visible when selecting the main studio/kitchen.
 */
export function matchesLocationFilter(params: {
  entityLocationId?: string;
  entityLocationName?: string;
  activeLocationId: string;
  locations: LocationItem[];
}): boolean {
  const { entityLocationId, entityLocationName, activeLocationId, locations } = params;
  if (!activeLocationId) return true;
  const activeLoc = locations.find((l) => l.id === activeLocationId);
  if (!activeLoc) return true;

  if (entityLocationId) {
    return entityLocationId === activeLocationId;
  }
  if (entityLocationName && entityLocationName.trim()) {
    return entityLocationName.trim().toLowerCase() === activeLoc.name.trim().toLowerCase();
  }
  const def = resolveDefaultLocation(locations);
  return Boolean(def && def.id === activeLocationId);
}

export interface LocationBreakdownRow {
  locationId: string;
  locationName: string;
  kind: LocationItem['kind'];
  revenueCents: number;
  ordersCount: number;
  posCount: number;
  inventoryValueCents: number;
}

export function computeLocationBreakdown(params: {
  locations: LocationItem[];
  orders: Order[];
  posSales: PosSale[];
  inventoryItems: InventoryItem[];
}): LocationBreakdownRow[] {
  const { locations, orders, posSales, inventoryItems } = params;
  return locations.map((loc) => {
    const locOrders = orders.filter(
      (o) =>
        (o.status === 'delivered' || o.status === 'closed') &&
        matchesLocationFilter({
          entityLocationName: o.locationName,
          activeLocationId: loc.id,
          locations,
        }),
    );
    const locPos = posSales.filter(
      (s) =>
        s.status === 'completed' &&
        matchesLocationFilter({
          entityLocationId: s.locationId,
          entityLocationName: s.locationName,
          activeLocationId: loc.id,
          locations,
        }),
    );
    const locInv = inventoryItems.filter((i) =>
      matchesLocationFilter({
        entityLocationId: i.locationId,
        activeLocationId: loc.id,
        locations,
      }),
    );

    const revenueCents =
      locOrders.reduce((sum, o) => sum + o.priceCents, 0) +
      locPos.reduce((sum, s) => sum + s.totalCents, 0);
    const inventoryValueCents = locInv.reduce(
      (sum, i) => sum + Math.round(i.qtyOnHand * i.avgCostCents),
      0,
    );

    return {
      locationId: loc.id,
      locationName: loc.name,
      kind: loc.kind,
      revenueCents,
      ordersCount: locOrders.length,
      posCount: locPos.length,
      inventoryValueCents,
    };
  });
}
