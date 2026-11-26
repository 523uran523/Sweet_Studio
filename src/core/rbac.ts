import { NavSectionId, Recipe, UserRole, Workspace, WorkspaceMember } from '../types/domain';

export interface RolePermissions {
  role: UserRole;
  canViewCosts: boolean;
  canViewMoney: boolean;
  canViewAnalytics: boolean;
  canManageTeam: boolean;
  canManagePayroll: boolean;
  canManageBilling: boolean;
  canManageSettings: boolean;
  canAccessPos: boolean;
  canEditRecipes: boolean;
  canViewAllRecipes: boolean;
  allowedSections: Set<NavSectionId>;
}

const BASE_SECTIONS: NavSectionId[] = ['dashboard', 'work', 'academy'];

const ROLE_SECTIONS: Record<UserRole, NavSectionId[]> = {
  owner: [
    ...BASE_SECTIONS,
    'orders',
    'leads',
    'pos',
    'recipes',
    'calculator',
    'inventory',
    'production',
    'clients',
    'loyalty',
    'quality',
    'marketing',
    'money',
    'analytics',
    'team',
    'settings',
  ],
  admin: [
    ...BASE_SECTIONS,
    'orders',
    'leads',
    'pos',
    'recipes',
    'calculator',
    'inventory',
    'production',
    'clients',
    'loyalty',
    'quality',
    'marketing',
    'money',
    'analytics',
    'team',
    'settings',
  ],
  confectioner: [
    ...BASE_SECTIONS,
    'orders',
    'recipes',
    'inventory',
    'production',
    'quality',
    'team',
  ],
  seller: [
    ...BASE_SECTIONS,
    'pos',
    'orders',
    'leads',
    'clients',
    'loyalty',
    'quality',
    'team',
  ],
  marketer: [
    ...BASE_SECTIONS,
    'leads',
    'clients',
    'loyalty',
    'quality',
    'marketing',
    'analytics',
    'team',
  ],
  storekeeper: [
    ...BASE_SECTIONS,
    'inventory',
    'production',
    'pos',
    'team',
  ],
  accountant: [
    ...BASE_SECTIONS,
    'orders',
    'pos',
    'inventory',
    'money',
    'analytics',
    'team',
  ],
};

export function resolveEffectiveRole(params: {
  userUid: string;
  userEmail?: string | null;
  workspace: Workspace;
  members: WorkspaceMember[];
}): { role: UserRole; member: WorkspaceMember | null; active: boolean } {
  const { userUid, userEmail, workspace, members } = params;
  if (workspace.ownerId === userUid) {
    const ownerMember = members.find((m) => m.uid === userUid || m.id === userUid) || null;
    return { role: 'owner', member: ownerMember, active: true };
  }
  const normalizedEmail = (userEmail || '').trim().toLowerCase();
  const matched =
    members.find((m) => m.uid === userUid || m.id === userUid) ||
    (normalizedEmail
      ? members.find((m) => (m.email || '').trim().toLowerCase() === normalizedEmail)
      : undefined) ||
    null;
  if (!matched) {
    return { role: 'confectioner', member: null, active: true };
  }
  return {
    role: matched.role,
    member: matched,
    active: matched.active,
  };
}

export function getRolePermissions(role: UserRole): RolePermissions {
  const sections = new Set<NavSectionId>(ROLE_SECTIONS[role] || ROLE_SECTIONS.confectioner);
  return {
    role,
    canViewCosts: role === 'owner' || role === 'admin' || role === 'accountant' || role === 'storekeeper',
    canViewMoney: role === 'owner' || role === 'admin' || role === 'accountant',
    canViewAnalytics: role === 'owner' || role === 'admin' || role === 'accountant' || role === 'marketer',
    canManageTeam: role === 'owner' || role === 'admin',
    canManagePayroll: role === 'owner' || role === 'admin' || role === 'accountant',
    canManageBilling: role === 'owner',
    canManageSettings: role === 'owner' || role === 'admin',
    canAccessPos: role === 'owner' || role === 'admin' || role === 'seller' || role === 'confectioner',
    canEditRecipes: role === 'owner' || role === 'admin' || role === 'confectioner',
    canViewAllRecipes: role === 'owner' || role === 'admin' || role === 'accountant',
    allowedSections: sections,
  };
}

export function filterVisibleRecipesForRole(
  recipes: Recipe[],
  role: UserRole,
  member: WorkspaceMember | null,
): Recipe[] {
  if (role === 'owner' || role === 'admin' || role === 'accountant') {
    return recipes;
  }
  const allowedIds = member?.allowedRecipeIds;
  if (allowedIds && allowedIds.length > 0) {
    const set = new Set(allowedIds);
    return recipes.filter((r) => set.has(r.id));
  }
  return recipes.filter((r) => r.status === 'approved');
}

export const ROLE_LABELS_RU: Record<UserRole, string> = {
  owner: 'Владелец',
  admin: 'Администратор',
  confectioner: 'Кондитер',
  seller: 'Продавец / Кассир',
  marketer: 'Маркетолог',
  storekeeper: 'Кладовщик',
  accountant: 'Бухгалтер',
};
