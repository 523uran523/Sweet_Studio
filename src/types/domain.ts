export type BusinessFormat = 'home' | 'studio' | 'network';
export type UiDensity = 'standard' | 'compact' | 'spacious';
export type UserRole =
  | 'owner'
  | 'admin'
  | 'confectioner'
  | 'seller'
  | 'marketer'
  | 'storekeeper'
  | 'accountant';

export type PayType = 'hourly' | 'piece' | 'percent' | 'salary' | 'mixed';

export type NavSectionId =
  | 'dashboard'
  | 'work'
  | 'orders'
  | 'leads'
  | 'pos'
  | 'recipes'
  | 'calculator'
  | 'inventory'
  | 'production'
  | 'clients'
  | 'loyalty'
  | 'quality'
  | 'marketing'
  | 'money'
  | 'analytics'
  | 'team'
  | 'settings'
  | 'academy';

export interface ThemeSpec {
  index: number;
  name: string;
  bg: string;
  card: string;
  accent: string;
  soft: string;
  ink: string;
  green: string;
  warm: string;
  muted: string;
}

export const SOFT_ATELIER_THEMES: ThemeSpec[] = [
  {
    index: 0,
    name: 'Berry Cream',
    bg: '#FBF6F4',
    card: '#FFFFFF',
    accent: '#A45C7A',
    soft: '#EEDCE5',
    ink: '#49333F',
    green: '#E3EBD9',
    warm: '#F3E4D5',
    muted: '#796B74',
  },
  {
    index: 1,
    name: 'Vanilla Pistachio',
    bg: '#F8F6EE',
    card: '#FFFFFF',
    accent: '#748B64',
    soft: '#E4EBD8',
    ink: '#394335',
    green: '#E7EDDA',
    warm: '#F1E2CE',
    muted: '#72796A',
  },
  {
    index: 2,
    name: 'Porcelain',
    bg: '#F2F4F7',
    card: '#FFFFFF',
    accent: '#647B9D',
    soft: '#E0E7F0',
    ink: '#273344',
    green: '#E3EAE8',
    warm: '#EDE6DC',
    muted: '#687586',
  },
  {
    index: 3,
    name: 'Dark Chocolate',
    bg: '#211C20',
    card: '#30282D',
    accent: '#D4A4B8',
    soft: '#49343F',
    ink: '#F3E8ED',
    green: '#35443B',
    warm: '#493B30',
    muted: '#C1AEB8',
  },
];

export interface UserProfile {
  id: string;
  uid: string;
  email?: string;
  displayName: string;
  activeWorkspaceId?: string;
  createdAt?: unknown;
  updatedAt?: unknown;
}

export interface Workspace {
  id: string;
  name: string;
  slogan?: string;
  businessFormat: BusinessFormat;
  ownerId: string;
  memberUids?: string[];
  themeIndex?: number;
  density?: UiDensity;
  pins?: string[];
  hiddenModules?: string[];
  demoLoaded?: boolean;
  plan?: 'trial' | 'pro';
  subscriptionStatus?: 'trialing' | 'active' | 'past_due' | 'expired';
  trialEndsAt?: string;
  currentPeriodEnd?: string;
  graceEndsAt?: string;
  billingEmail?: string;
  lastPaymentId?: string;
  createdAt?: unknown;
  updatedAt?: unknown;
}

export interface WorkspaceMember {
  id: string;
  workspaceId: string;
  ownerId: string;
  uid?: string;
  inviteId?: string;
  name: string;
  email?: string;
  role: UserRole;
  payType: PayType;
  rateCents?: number;
  percent?: number;
  allowedRecipeIds?: string[];
  locationId?: string;
  active: boolean;
  createdAt?: unknown;
  updatedAt?: unknown;
}

export interface WorkspaceInvitation {
  id: string;
  workspaceId: string;
  workspaceName: string;
  ownerId: string;
  email: string;
  invitedByName: string;
  role: UserRole;
  payType: PayType;
  rateCents?: number;
  percent?: number;
  allowedRecipeIds?: string[];
  locationId?: string;
  status: 'pending' | 'accepted' | 'revoked';
  acceptedByUid?: string;
  createdAt?: unknown;
  updatedAt?: unknown;
}

export interface LocationItem {
  id: string;
  workspaceId: string;
  ownerId: string;
  name: string;
  kind: 'kitchen' | 'store' | 'warehouse';
  address?: string;
  isDefault?: boolean;
}

export interface RecipeIngredientLine {
  itemId?: string;
  subRecipeId?: string;
  name: string;
  qty: number;
  unit: string;
  lossPercent: number;
  priceCents: number;
  priceUnit: string;
  isPackaging?: boolean;
}

export interface RecipePackVariant {
  id: string;
  label: string;
  qtyOrGrams: number;
  mode: 'grams' | 'pieces';
  packagingCents: number;
  priceCents?: number;
}

export interface Recipe {
  id: string;
  workspaceId: string;
  ownerId: string;
  title: string;
  category: string;
  version: number;
  status: 'draft' | 'review' | 'approved' | 'archived';
  yieldGrams: number;
  grossGrams?: number;
  yieldPortions?: number;
  formSize?: string;
  photoUrl?: string;
  ingredients?: RecipeIngredientLine[];
  packVariants?: RecipePackVariant[];
  steps?: string[];
  allergens?: string[];
  laborHours?: number;
  laborRateCents?: number;
  packagingCents?: number;
  overheadPercent?: number;
  marginPercent?: number;
  costCents: number;
  recommendedPriceCents: number;
  shelfLifeHours?: number;
  storageCondition?: string;
  favorite?: boolean;
}

export interface InventoryItem {
  id: string;
  workspaceId: string;
  ownerId: string;
  name: string;
  kind: 'raw' | 'semi' | 'finished' | 'packaging';
  category?: string;
  unit: string;
  qtyOnHand: number;
  minQty?: number;
  avgCostCents: number;
  density?: number;
  locationId?: string;
}

export interface StockLot {
  id: string;
  workspaceId: string;
  ownerId: string;
  itemId: string;
  itemName: string;
  lotCode: string;
  unit: string;
  initialQty: number;
  remainingQty: number;
  unitCostCents: number;
  locationId?: string;
  expiresAt?: string;
  status: 'active' | 'quarantine' | 'expired' | 'depleted';
}

export interface StockMovement {
  id: string;
  workspaceId: string;
  ownerId: string;
  kind: 'receipt' | 'issue' | 'transfer' | 'adjustment' | 'production_in' | 'production_out' | 'sale';
  itemId: string;
  itemName: string;
  lotId?: string;
  qty: number;
  unit: string;
  totalCents: number;
  reason?: string;
  createdAt?: unknown;
}

export interface StockTransfer {
  id: string;
  workspaceId: string;
  ownerId: string;
  itemId: string;
  itemName: string;
  lotId?: string;
  fromLocationId?: string;
  fromLocationName: string;
  toLocationId?: string;
  toLocationName: string;
  qty: number;
  unit: string;
  unitCostCents: number;
  status: 'in_transit' | 'received' | 'cancelled';
  note?: string;
  sentAt: string;
  receivedAt?: string;
}

export interface Supplier {
  id: string;
  workspaceId: string;
  ownerId: string;
  name: string;
  contactName?: string;
  phone?: string;
  email?: string;
  category?: string;
  debtCents?: number;
}

export interface Purchase {
  id: string;
  workspaceId: string;
  ownerId: string;
  supplierId?: string;
  supplierName: string;
  itemId?: string;
  itemName: string;
  qty: number;
  unit: string;
  priceCents: number;
  deliveryCents?: number;
  expectedDate?: string;
  status: 'planned' | 'ordered' | 'received' | 'cancelled';
}

export interface Client {
  id: string;
  workspaceId: string;
  ownerId: string;
  name: string;
  phone?: string;
  email?: string;
  source?: string;
  address?: string;
  preferences?: string;
  allergens?: string;
  depositCents?: number;
  ordersCount?: number;
  debtCents?: number;
  favorite?: boolean;
}

export interface Lead {
  id: string;
  workspaceId: string;
  ownerId: string;
  clientName: string;
  phone?: string;
  requestText: string;
  source?: string;
  budgetCents?: number;
  nextStep?: string;
  status: 'new' | 'contacted' | 'quoted' | 'converted' | 'lost';
  convertedOrderId?: string;
}

export type OrderStatus =
  | 'lead'
  | 'negotiation'
  | 'confirmed'
  | 'in_progress'
  | 'ready'
  | 'delivered'
  | 'closed'
  | 'cancelled';

export interface OrderItem {
  id: string;
  recipeId: string;
  recipeTitle: string;
  qty: number;
  weightGrams: number;
  priceCents: number;
  costCents: number;
}

export interface Order {
  id: string;
  workspaceId: string;
  ownerId: string;
  orderNumber: string;
  title: string;
  clientId?: string;
  clientName: string;
  items?: OrderItem[];
  prepaymentCents?: number;
  paidCents: number;
  discountCents?: number;
  couponCode?: string;
  status: OrderStatus;
  dueDate?: string;
  assigneeName?: string;
  locationName?: string;
  deliveryAddress?: string;
  wishes?: string;
  allergens?: string;
  stockDeducted?: boolean;
  favorite?: boolean;
  // Backward compatibility getters / optional helpers
  recipeId?: string;
  recipeTitle?: string;
  weightGrams?: number;
  priceCents: number;
  costCents: number;
}

export type WorkItemType =
  | 'order'
  | 'production'
  | 'promo'
  | 'quality'
  | 'task'
  | 'purchase'
  | 'finance';

export type WorkRecurrence = 'none' | 'daily' | 'weekly' | 'biweekly' | 'monthly';

export interface WorkItem {
  id: string;
  workspaceId: string;
  ownerId: string;
  type: WorkItemType;
  sourceId?: string;
  title: string;
  assigneeName?: string;
  locationName?: string;
  dueDate?: string;
  priority: 'low' | 'normal' | 'high';
  stage: 'queue' | 'in_progress' | 'done';
  tags?: string[];
  recurrence?: WorkRecurrence;
  seriesId?: string;
  occurrenceIndex?: number;
}

export interface ProductionRun {
  id: string;
  workspaceId: string;
  ownerId: string;
  recipeId?: string;
  recipeTitle: string;
  plannedGrams: number;
  actualGrams?: number;
  locationName?: string;
  assigneeName?: string;
  totalCostCents?: number;
  status: 'planned' | 'in_progress' | 'completed' | 'cancelled';
}

export interface Account {
  id: string;
  workspaceId: string;
  ownerId: string;
  name: string;
  type: 'cash' | 'bank' | 'card' | 'acquiring';
  balanceCents: number;
}

export interface MoneyTransaction {
  id: string;
  workspaceId: string;
  ownerId: string;
  kind: 'income' | 'expense' | 'transfer' | 'reversal';
  category: string;
  amountCents: number;
  accountId: string;
  accountName?: string;
  orderId?: string;
  reversesId?: string;
  note?: string;
  occurredAt: string;
}

export interface RecurringPayment {
  id: string;
  workspaceId: string;
  ownerId: string;
  title: string;
  amountCents: number;
  cadence: 'monthly' | 'weekly';
  nextDueDate: string;
  category?: string;
  active: boolean;
}

export interface CashShift {
  id: string;
  workspaceId: string;
  ownerId: string;
  locationId?: string;
  locationName: string;
  accountId: string;
  cashierName: string;
  openedAt: string;
  closedAt?: string;
  openingCashCents: number;
  cashSalesCents: number;
  cardSalesCents: number;
  refundsCents: number;
  cashInCents: number;
  cashOutCents: number;
  salesCount: number;
  closingActualCashCents?: number;
  closingDiscrepancyCents?: number;
  status: 'open' | 'closed';
}

export interface PosSaleLine {
  id: string;
  itemId?: string;
  recipeId?: string;
  title: string;
  qty: number;
  unit: string;
  unitPriceCents: number;
  unitCostCents: number;
}

export interface PosSale {
  id: string;
  workspaceId: string;
  ownerId: string;
  receiptNumber: string;
  shiftId?: string;
  locationId?: string;
  locationName?: string;
  clientId?: string;
  clientName?: string;
  cashierName: string;
  paymentMethod: 'cash' | 'card';
  accountId: string;
  lines: PosSaleLine[];
  subtotalCents: number;
  discountCents: number;
  totalCents: number;
  costCents: number;
  couponCode?: string;
  status: 'completed' | 'refunded';
  occurredAt: string;
}

export interface BillingEvent {
  id: string;
  workspaceId: string;
  ownerId: string;
  idempotencyKey: string;
  plan: 'pro';
  amountCents: number;
  periodMonths: number;
  status: 'paid' | 'failed';
  provider: string;
  occurredAt: string;
}

export interface Coupon {
  id: string;
  workspaceId: string;
  ownerId: string;
  code: string;
  clientId?: string;
  clientName?: string;
  discountType: 'percent' | 'fixed';
  discountValue: number;
  minOrderCents?: number;
  expiresAt?: string;
  status: 'active' | 'redeemed' | 'expired';
  redeemedOrderId?: string;
}

export interface Complaint {
  id: string;
  workspaceId: string;
  ownerId: string;
  title: string;
  orderId?: string;
  lotId?: string;
  severity: 'low' | 'medium' | 'high';
  status: 'open' | 'investigating' | 'resolved';
  responsibleName?: string;
  resolution?: string;
}

export interface ContentPost {
  id: string;
  workspaceId: string;
  ownerId: string;
  channel: string;
  channelUrl?: string;
  title: string;
  scheduledDate: string;
  status: 'idea' | 'draft' | 'scheduled' | 'published';
  budgetCents?: number;
}

export interface PayrollPeriod {
  id: string;
  workspaceId: string;
  ownerId: string;
  title: string;
  startDate: string;
  endDate: string;
  status: 'open' | 'closed';
  totalAccruedCents: number;
  totalPaidCents: number;
  lines?: Array<{
    memberId: string;
    memberName: string;
    payType: string;
    minutes: number;
    ordersCount: number;
    amountCents: number;
    needsReview: boolean;
  }>;
}

export interface TimeEntry {
  id: string;
  workspaceId: string;
  ownerId: string;
  employeeId?: string;
  employeeName: string;
  orderTitle?: string;
  startedAt: string;
  endedAt?: string;
  minutes: number;
}
