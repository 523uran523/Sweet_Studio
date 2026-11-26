import { describe, expect, it } from 'vitest';
import {
  computeWorkspacePayrollPreview,
  hourlyAccrualCents,
  percentAccrualCents,
} from '../payrollEngine';
import { Order, TimeEntry, WorkspaceMember } from '../../types/domain';

describe('payrollEngine', () => {
  it('calculates hourly and percentage accruals in integer cents', () => {
    // 90 minutes at 600 ₽/h = 900 ₽ (90 000 cents)
    expect(hourlyAccrualCents(90, 60000)).toBe(90000);
    // 15% of 4200 ₽ = 630 ₽ (63 000 cents)
    expect(percentAccrualCents(420000, 15)).toBe(63000);
  });

  it('computes workspace payroll preview for hourly, piece, percent, and inactive members', () => {
    const members: WorkspaceMember[] = [
      {
        id: 'm1',
        workspaceId: 'ws1',
        ownerId: 'owner1',
        name: 'Анна',
        role: 'confectioner',
        payType: 'hourly',
        rateCents: 60000,
        active: true,
      },
      {
        id: 'm2',
        workspaceId: 'ws1',
        ownerId: 'owner1',
        name: 'Борис',
        role: 'seller',
        payType: 'percent',
        percent: 10,
        active: true,
      },
      {
        id: 'm3',
        workspaceId: 'ws1',
        ownerId: 'owner1',
        name: 'Вера',
        role: 'confectioner',
        payType: 'piece',
        rateCents: 0,
        active: true,
      },
      {
        id: 'm4',
        workspaceId: 'ws1',
        ownerId: 'owner1',
        name: 'Архивный',
        role: 'confectioner',
        payType: 'hourly',
        rateCents: 50000,
        active: false,
      },
    ];

    const timeEntries: TimeEntry[] = [
      {
        id: 'te1',
        workspaceId: 'ws1',
        ownerId: 'owner1',
        employeeId: 'm1',
        employeeName: 'Анна',
        startedAt: '2026-11-10T09:00:00Z',
        minutes: 120,
      },
      {
        id: 'te2',
        workspaceId: 'ws1',
        ownerId: 'owner1',
        employeeId: 'm1',
        employeeName: 'Анна',
        startedAt: '2026-10-01T09:00:00Z', // outside range
        minutes: 600,
      },
    ];

    const orders: Order[] = [
      {
        id: 'o1',
        workspaceId: 'ws1',
        ownerId: 'owner1',
        orderNumber: '№101',
        clientName: 'Иван',
        title: 'Медовик',
        status: 'delivered',
        dueDate: '2026-11-12',
        priceCents: 500000,
        paidCents: 500000,
        costCents: 180000,
        assigneeName: 'Борис',
      },
      {
        id: 'o2',
        workspaceId: 'ws1',
        ownerId: 'owner1',
        orderNumber: '№102',
        clientName: 'Ольга',
        title: 'Капкейки',
        status: 'ready',
        dueDate: '2026-11-15',
        priceCents: 200000,
        paidCents: 0,
        costCents: 80000,
        assigneeName: 'Вера',
      },
    ];

    const lines = computeWorkspacePayrollPreview({
      startDate: '2026-11-01',
      endDate: '2026-11-30',
      members,
      timeEntries,
      orders,
    });

    expect(lines).toHaveLength(3); // inactive excluded
    const anna = lines.find((l) => l.memberId === 'm1')!;
    expect(anna.minutes).toBe(120);
    expect(anna.amountCents).toBe(120000);
    expect(anna.needsReview).toBe(false);

    const boris = lines.find((l) => l.memberId === 'm2')!;
    expect(boris.ordersCount).toBe(1);
    expect(boris.amountCents).toBe(50000);

    const vera = lines.find((l) => l.memberId === 'm3')!;
    expect(vera.amountCents).toBe(0);
    expect(vera.needsReview).toBe(true);
  });
});
