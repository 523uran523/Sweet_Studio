/**
 * Ported from Masters lib/core/utils/app_utils.dart (Russian pluralization).
 */
export function pluralRu(n: number, one: string, few: string, many: string): string {
  const abs = Math.abs(Math.trunc(n));
  const mod100 = abs % 100;
  if (mod100 >= 11 && mod100 <= 14) return `${n} ${many}`;
  const mod10 = abs % 10;
  if (mod10 === 1) return `${n} ${one}`;
  if (mod10 >= 2 && mod10 <= 4) return `${n} ${few}`;
  return `${n} ${many}`;
}

export const ordersWord = (n: number) => pluralRu(n, 'заказ', 'заказа', 'заказов');
export const recipesWord = (n: number) => pluralRu(n, 'рецепт', 'рецепта', 'рецептов');
export const clientsWord = (n: number) => pluralRu(n, 'клиент', 'клиента', 'клиентов');
export const lotsWord = (n: number) => pluralRu(n, 'партия', 'партии', 'партий');
export const itemsWord = (n: number) => pluralRu(n, 'позиция', 'позиции', 'позиций');
export const minutesWord = (n: number) => pluralRu(n, 'минута', 'минуты', 'минут');
export const tasksWord = (n: number) => pluralRu(n, 'задача', 'задачи', 'задач');
export const employeesWord = (n: number) => pluralRu(n, 'сотрудник', 'сотрудника', 'сотрудников');
