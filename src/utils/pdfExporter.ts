import { jsPDF } from 'jspdf';
import fontRegularUrl from '../assets/fonts/LiberationSans-Regular.ttf?url';
import fontBoldUrl from '../assets/fonts/LiberationSans-Bold.ttf?url';
import { formatMoneyCents } from '../core/moneyFormat';
import { Order, Workspace } from '../types/domain';

export type OrderPdfKind = 'invoice' | 'act';

let cachedRegularB64: string | null = null;
let cachedBoldB64: string | null = null;

function arrayBufferToBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binary = '';
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}

async function ensureCyrillicFonts(doc: jsPDF): Promise<void> {
  if (!cachedRegularB64 || !cachedBoldB64) {
    const [regRes, boldRes] = await Promise.all([
      fetch(fontRegularUrl),
      fetch(fontBoldUrl),
    ]);
    if (!regRes.ok || !boldRes.ok) {
      throw new Error('Не удалось загрузить шрифты для PDF');
    }
    const [regBuf, boldBuf] = await Promise.all([
      regRes.arrayBuffer(),
      boldRes.arrayBuffer(),
    ]);
    cachedRegularB64 = arrayBufferToBase64(regBuf);
    cachedBoldB64 = arrayBufferToBase64(boldBuf);
  }

  doc.addFileToVFS('LiberationSans-Regular.ttf', cachedRegularB64);
  doc.addFont('LiberationSans-Regular.ttf', 'LiberationSans', 'normal');
  doc.addFileToVFS('LiberationSans-Bold.ttf', cachedBoldB64);
  doc.addFont('LiberationSans-Bold.ttf', 'LiberationSans', 'bold');
  doc.setFont('LiberationSans', 'normal');
}

export async function exportOrderPdf(params: {
  order: Order;
  workspace: Workspace;
  kind: OrderPdfKind;
}): Promise<string> {
  const { order, workspace, kind } = params;
  const doc = new jsPDF({ unit: 'mm', format: 'a4' });
  await ensureCyrillicFonts(doc);

  const today = new Date().toLocaleDateString('ru-RU');
  const marginX = 18;
  const contentWidth = 174;
  let y = 20;

  // Header
  doc.setFont('LiberationSans', 'bold');
  doc.setFontSize(16);
  doc.text(workspace.name || 'SweetStudio', marginX, y);
  y += 6;

  doc.setFont('LiberationSans', 'normal');
  doc.setFontSize(9.5);
  doc.setTextColor(105, 95, 100);
  doc.text(workspace.slogan || 'Кондитерская мастерская', marginX, y);
  doc.text(`Дата формирования: ${today}`, marginX + contentWidth, y, { align: 'right' });
  y += 6;

  doc.setDrawColor(215, 205, 210);
  doc.line(marginX, y, marginX + contentWidth, y);
  y += 10;

  // Document Title
  doc.setTextColor(45, 35, 42);
  doc.setFont('LiberationSans', 'bold');
  doc.setFontSize(14);
  const titleText =
    kind === 'invoice'
      ? `СЧЁТ-СМЕТА НА ЗАКАЗ ${order.orderNumber}`
      : `АКТ ВЫПОЛНЕННЫХ РАБОТ ПО ЗАКАЗУ ${order.orderNumber}`;
  doc.text(titleText, marginX, y);
  y += 9;

  // Parties & Order info
  doc.setFont('LiberationSans', 'normal');
  doc.setFontSize(10.5);
  const infoLines: Array<[string, string]> = [
    ['Исполнитель:', workspace.name],
    ['Заказчик:', order.clientName],
    ['Дата выдачи:', order.dueDate || 'по согласованию'],
  ];
  if (order.deliveryAddress) {
    infoLines.push(['Адрес доставки:', order.deliveryAddress]);
  }
  if (order.locationName) {
    infoLines.push(['Площадка:', order.locationName]);
  }

  for (const [label, val] of infoLines) {
    doc.setFont('LiberationSans', 'bold');
    doc.text(label, marginX, y);
    doc.setFont('LiberationSans', 'normal');
    const wrapped = doc.splitTextToSize(val, contentWidth - 40);
    doc.text(wrapped, marginX + 40, y);
    y += Math.max(6, wrapped.length * 5.2);
  }
  y += 4;

  // Line item table header
  doc.setFillColor(246, 240, 243);
  doc.rect(marginX, y, contentWidth, 9, 'F');
  doc.setFont('LiberationSans', 'bold');
  doc.setFontSize(9.5);
  doc.text('Наименование позиции / изделия', marginX + 3, y + 6);
  doc.text('Вес', marginX + 115, y + 6, { align: 'right' });
  doc.text('Сумма', marginX + contentWidth - 3, y + 6, { align: 'right' });
  y += 9;

  // Line item row
  doc.setDrawColor(225, 218, 222);
  const itemDesc = order.recipeTitle && order.recipeTitle !== order.title
    ? `${order.title} (${order.recipeTitle})`
    : order.title;
  const wrappedDesc = doc.splitTextToSize(itemDesc, 92);
  const rowH = Math.max(10, wrappedDesc.length * 5 + 4);

  doc.rect(marginX, y, contentWidth, rowH);
  doc.setFont('LiberationSans', 'normal');
  doc.setFontSize(10);
  doc.text(wrappedDesc, marginX + 3, y + 6);
  doc.text(order.weightGrams ? `${order.weightGrams} г` : '—', marginX + 115, y + 6, {
    align: 'right',
  });
  const beforeDiscount = order.priceCents + (order.discountCents || 0);
  doc.text(formatMoneyCents(beforeDiscount), marginX + contentWidth - 3, y + 6, {
    align: 'right',
  });
  y += rowH + 6;

  // Financial summary
  const remainingCents = Math.max(0, order.priceCents - order.paidCents);
  const summaryRows: Array<[string, string, boolean]> = [];
  if (order.discountCents && order.discountCents > 0) {
    summaryRows.push([
      `Скидка${order.couponCode ? ` (купон ${order.couponCode})` : ''}:`,
      `−${formatMoneyCents(order.discountCents)}`,
      false,
    ]);
  }
  summaryRows.push(['Итого к оплате:', formatMoneyCents(order.priceCents), true]);
  summaryRows.push(['Внесена оплата:', formatMoneyCents(order.paidCents), false]);
  summaryRows.push(['Остаток к оплате:', formatMoneyCents(remainingCents), true]);

  for (const [label, val, bold] of summaryRows) {
    doc.setFont('LiberationSans', bold ? 'bold' : 'normal');
    doc.setFontSize(bold ? 11 : 10);
    doc.text(label, marginX + 100, y);
    doc.text(val, marginX + contentWidth - 3, y, { align: 'right' });
    y += 6.5;
  }

  // Notes / Allergens
  if (order.wishes || order.allergens) {
    y += 5;
    doc.setFont('LiberationSans', 'bold');
    doc.setFontSize(10);
    if (order.wishes) {
      doc.text('Пожелания по заказу:', marginX, y);
      y += 5;
      doc.setFont('LiberationSans', 'normal');
      const wLines = doc.splitTextToSize(order.wishes, contentWidth);
      doc.text(wLines, marginX, y);
      y += wLines.length * 5 + 3;
    }
    if (order.allergens) {
      doc.setFont('LiberationSans', 'bold');
      doc.text(`Аллергены: ${order.allergens}`, marginX, y);
      y += 6;
    }
  }

  // Act confirmation & signatures
  y = Math.max(y + 12, 215);
  doc.setFont('LiberationSans', 'normal');
  doc.setFontSize(9.5);
  if (kind === 'act') {
    const actText =
      'Вышеуказанные кондитерские изделия переданы Заказчику в полном объёме, надлежащего качества и в согласованный срок. Стороны претензий по качеству и расчётам не имеют.';
    const actLines = doc.splitTextToSize(actText, contentWidth);
    doc.text(actLines, marginX, y);
    y += actLines.length * 5 + 12;
  } else {
    const invText =
      'Смета составлена на основании выбранной рецептуры, веса и декора. Изменение состава или сроков согласуется дополнительно.';
    const invLines = doc.splitTextToSize(invText, contentWidth);
    doc.text(invLines, marginX, y);
    y += invLines.length * 5 + 12;
  }

  doc.setDrawColor(140, 130, 135);
  doc.text('Исполнитель:', marginX, y);
  doc.line(marginX + 26, y, marginX + 78, y);
  doc.text('Заказчик:', marginX + 95, y);
  doc.line(marginX + 116, y, marginX + contentWidth, y);

  const safeNum = order.orderNumber.replace(/[^a-zA-Z0-9_-]+/g, '');
  const fileName = `SweetStudio-${kind}-${safeNum || order.id}.pdf`;
  doc.save(fileName);
  return fileName;
}
