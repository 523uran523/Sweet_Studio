# Sweet Studio Security Specification (Phase 0)

## 1. Data Invariants
1. **Strict Tenant Isolation**: Every domain document under `/workspaces/{workspaceId}/...` belongs to a single workspace (`data.workspaceId == workspaceId`). Only the workspace `ownerId` or an active verified member in `/workspaces/{workspaceId}/members/{request.auth.uid}` can read or write workspace documents.
2. **Identity Integrity**:
   - `/users/{userId}`: Only `request.auth.uid == userId` with verified email can read or write; `uid` must match `userId` and cannot be spoofed.
   - `/workspaces/{workspaceId}`: On create, `ownerId` must equal `request.auth.uid`. `ownerId` and `createdAt` are immutable after creation.
   - `/workspaces/{workspaceId}/members/{memberId}`: Only the workspace `owner` (or `admin` for non-owner roles) can create/update/delete members. A member cannot self-elevate `role` to `owner` or `admin`.
3. **Path Variable & Payload Hygiene**: Every single-document ID (`workspaceId`, `recipeId`, `orderId`, etc.) must satisfy `isValidId(id)` (`^[a-zA-Z0-9_\-]+$`, max 128 chars). Every string field has an explicit `.size()` bound. No undeclared keys (`hasOnly`).
4. **Temporal & Financial Integrity**: `createdAt` and `updatedAt` are strictly validated with `request.time`. Monetary amounts are integer cents.
5. **Terminal State Locking**:
   - `Lead` with `status == 'converted'` cannot change `convertedOrderId` or revert to `new`.
   - `Coupon` with `status == 'redeemed'` cannot be redeemed again (`existing().status != 'redeemed'`).
   - `PayrollPeriod` with `status == 'closed'` cannot have its accrued snapshot altered by non-owners (and closed periods lock line items).

## 2. Dirty Dozen Payloads (Must Return PERMISSION_DENIED)
1. Unauthenticated read/write to `/workspaces/ws1/orders/ord1`.
2. Creating `/workspaces/ws1` with `ownerId: "victim_uid"` != `request.auth.uid`.
3. Updating `/workspaces/ws1` to change `ownerId` or `createdAt`.
4. Cross-tenant read/write from user A into `/workspaces/ws_of_user_B/clients/c1`.
5. Creating `/workspaces/ws1/orders/ord1` with `workspaceId: "ws2"` (tenant mismatch).
6. Creating `/workspaces/ws1/recipes/r1` with an undeclared ghost field (`isVerified: true`).
7. Creating `/workspaces/ws1/orders/bad..id/../../` (invalid document ID failing `isValidId`).
8. Injecting a 10KB string into `Client.name` (exceeds `maxLength: 140`).
9. Non-member attempting `list` on `/workspaces/ws1/transactions`.
10. Redeeming an already-redeemed coupon (`existing().status == 'redeemed'`).
11. Self-assigning `role: "owner"` by creating `/workspaces/ws1/members/{uid}` as a non-owner.
12. Spoofing `createdAt` / `updatedAt` with a client timestamp != `request.time`.
