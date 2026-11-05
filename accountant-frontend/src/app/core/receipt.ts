import { eatDateTime, tsh } from './format';
import { SaleDetail } from './till-api.service';

const esc = (s: string): string => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c] as string);

/** The paper a receipt is printed on: a full A4 page, or a thermal roll 80 mm or 58 mm wide. */
export type ReceiptSize = 'a4' | 'thermal80' | 'thermal58';
export const RECEIPT_SIZES: ReceiptSize[] = ['a4', 'thermal80', 'thermal58'];

const SIZE_KEY = 'receipt_size';

/** The size chosen last time (A4 the first time), kept in this browser. */
export function lastReceiptSize(): ReceiptSize {
  try {
    const v = localStorage.getItem(SIZE_KEY);
    return v === 'thermal80' || v === 'thermal58' ? v : 'a4';
  } catch {
    return 'a4';
  }
}

export function rememberReceiptSize(size: ReceiptSize): void {
  try {
    localStorage.setItem(SIZE_KEY, size);
  } catch {
    // the choice is simply not kept
  }
}

/** The line every shop's receipt carries by default: it does not belong on a salon's. */
export const SHOP_RETURN_LINE = 'Bidhaa zilizouzwa haziruhusiwi kurudishwa bila risiti.';

/** What the top and the bottom of a receipt say about the business: all set once in the business's settings. */
export interface ReceiptHeader {
  business: string;
  tagline: string;
  address: string;
  phone: string;
  email: string;
  website: string;
  /** Shown only when the business asked for it. */
  tin: string;
  footer: string;
}

/** The receipt header from the business's settings (the same ones the mobile app prints), the business's name when none is set. */
export function receiptHeaderFrom(settings: Record<string, string>, business: string, salon = false): ReceiptHeader {
  const text = (k: string) => (settings[k] ?? '').trim();
  return {
    business: text('depot_name') || business,
    tagline: text('receipt_tagline'),
    address: text('depot_address'),
    phone: text('depot_phone'),
    email: text('receipt_email'),
    website: text('receipt_website'),
    tin: (settings['receipt_show_tin'] ?? '1') !== '0' ? text('receipt_tin') : '',
    // a salon's receipt never carries the shop's "goods sold cannot be returned" line (the owner's own note stays)
    footer: salon && text('receipt_footer_note').includes(SHOP_RETURN_LINE) ? '' : text('receipt_footer_note'),
  };
}

/** "2026-11-05" (or a full server time) as "05/11/2026". */
function day(value: string | null | undefined): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(value ?? '');
  return m ? `${m[3]}/${m[2]}/${m[1]}` : '';
}

/**
 * The receipt as a printable page: who sold, to whom, what, how it was paid and what is still owed. Narrow like a till roll, and it
 * prints as well on a sheet of paper. `t` turns a key into words in the person's language.
 */
export function receiptHtml(sale: SaleDetail, header: ReceiptHeader | string, t: (key: string) => string, size: ReceiptSize = 'a4'): string {
  const h: ReceiptHeader = typeof header === 'string' ? { business: header, tagline: '', address: '', phone: '', email: '', website: '', tin: '', footer: '' } : header;
  const word = (key: string, raw: string): string => {
    const v = t(key);
    return v === key ? raw : v;
  };
  const cancelled = !!sale.cancelled_at;
  const owing = Math.max(0, sale.total - sale.paid_total);
  const status = cancelled ? t('sales.cancelled') : t(`sales.status.${sale.payment_status}`);

  const items = sale.items
    .map((i, n) => {
      const qty = i.qty ?? i.quantity;
      const extra = [i.unit_name ? esc(i.unit_name) : '', i.staff_name ? `${esc(t('receipt.served'))}: ${esc(i.staff_name)}` : ''].filter(Boolean).join(' · ');
      return `<tr><td class="no">${n + 1}</td><td class="name">${esc(i.product_name)}${extra ? `<small>${extra}</small>` : ''}</td><td class="c">${qty}</td><td class="r">${tsh(i.unit_price)}</td><td class="r">${tsh(i.total)}</td></tr>`;
    })
    .join('');

  const line = (label: string, value: string, cls = '') => `<tr class="${cls}"><td>${esc(label)}</td><td class="r">${esc(value)}</td></tr>`;
  const totals = [
    line(t('till.sub'), tsh(sale.subtotal)),
    sale.discount > 0 ? line(t('till.discount') + (sale.discount_reason ? ` (${sale.discount_reason})` : ''), '-' + tsh(sale.discount)) : '',
    sale.tax > 0 ? line(t('till.vat'), tsh(sale.tax)) : '',
    line(t('till.total'), tsh(sale.total), 'grand'),
    line(t('till.paid'), tsh(sale.paid_total)),
    owing > 0 ? line(t('till.owing'), tsh(owing), 'owing') : '',
  ].join('');

  const payments = (sale.payments ?? [])
    .map((p) => `<tr><td>${esc(eatDateTime(p.paid_at))}</td><td>${esc(word(`pay.${p.method ?? 'cash'}`, p.method ?? ''))}${p.reference ? ` · ${esc(t('receipt.ref'))} ${esc(p.reference)}` : ''}</td><td class="r">${tsh(p.amount)}</td></tr>`)
    .join('');

  const contact = [h.phone ? `${esc(t('receipt.tel'))} ${esc(h.phone)}` : '', h.email ? esc(h.email) : '', h.website ? esc(h.website) : ''].filter(Boolean).join(' · ');
  const phone = sale.customer_phone ? ` · ${esc(sale.customer_phone)}` : '';
  const state = cancelled ? 'cancelled' : sale.payment_status;

  if (size !== 'a4') {
    const narrow = size === 'thermal58';
    const stacked = sale.items
      .map((i) => {
        const qty = i.qty ?? i.quantity;
        const extra = [i.unit_name ? esc(i.unit_name) : '', i.staff_name ? `${esc(t('receipt.served'))}: ${esc(i.staff_name)}` : ''].filter(Boolean).join(' · ');
        return `<div class="it"><div class="nm">${esc(i.product_name)}</div>${extra ? `<div class="sm">${extra}</div>` : ''}<div class="rw"><span>${qty} x ${tsh(i.unit_price)}</span><b>${tsh(i.total)}</b></div></div>`;
      })
      .join('');
    const rows = (pairs: [string, string, string?][]) => pairs.filter((p) => p[1] !== '').map(([k, v, c]) => `<div class="rw ${c ?? ''}"><span>${esc(k)}</span><b>${esc(v)}</b></div>`).join('');
    const sums = rows([
      [t('till.sub'), tsh(sale.subtotal)],
      [t('till.discount') + (sale.discount_reason ? ` (${sale.discount_reason})` : ''), sale.discount > 0 ? '-' + tsh(sale.discount) : ''],
      [t('till.vat'), sale.tax > 0 ? tsh(sale.tax) : ''],
      [t('till.total'), tsh(sale.total), 'grand'],
      [t('till.paid'), tsh(sale.paid_total)],
      [t('till.owing'), owing > 0 ? tsh(owing) : '', 'owing'],
    ]);
    const paid = (sale.payments ?? [])
      .map((p) => `<div class="rw"><span>${esc(word(`pay.${p.method ?? 'cash'}`, p.method ?? ''))}${p.reference ? ` · ${esc(t('receipt.ref'))} ${esc(p.reference)}` : ''}</span><b>${tsh(p.amount)}</b></div>`)
      .join('');

    return `<!doctype html><html><head><meta charset="utf-8"><title>${esc(sale.number)}</title>
<style>
@page{size:${narrow ? '58mm' : '80mm'} auto;margin:2mm}
*{box-sizing:border-box}
body{font:${narrow ? '11px' : '12.5px'}/1.4 "Courier New",Courier,monospace;width:${narrow ? '52mm' : '74mm'};margin:0 auto;padding:4px;color:#000}
.c{text-align:center}
h1{font-size:${narrow ? '14px' : '17px'};margin:0 0 2px;text-transform:uppercase}
p{margin:1px 0}
.hr{border-top:1px dashed #000;margin:6px 0}
.title{text-align:center;font-weight:700;letter-spacing:1px;margin:2px 0}
.rw{display:flex;justify-content:space-between;gap:6px}
.rw b{white-space:nowrap}
.it{margin:4px 0}
.nm{font-weight:700}
.sm{font-size:${narrow ? '9.5px' : '10.5px'};color:#333}
.grand{font-size:${narrow ? '13px' : '15px'};border-top:1px solid #000;margin-top:3px;padding-top:3px}
.owing{font-weight:700}
.stamp{border:2px solid #000;text-align:center;font-weight:700;letter-spacing:2px;padding:2px;margin:6px 0}
.bar{text-align:center;padding-bottom:6px}
.bar button{padding:6px 12px;border:1px solid #000;border-radius:6px;background:#fff;font-weight:700;cursor:pointer}
@media print{.bar{display:none}body{padding:0}}
</style></head><body>
<div class="bar"><button onclick="window.print()">${esc(t('receipt.print'))}</button></div>
<div class="c"><h1>${esc(h.business)}</h1>${h.tagline ? `<p>${esc(h.tagline)}</p>` : ''}${h.address ? `<p>${esc(h.address)}</p>` : ''}${contact ? `<p>${contact}</p>` : ''}${h.tin ? `<p>${esc(t('receipt.tin'))}: ${esc(h.tin)}</p>` : ''}</div>
<div class="hr"></div>
<div class="title">${esc(t('receipt.title'))}</div>
<div class="rw"><span>${esc(t('receipt.no'))}</span><b>${esc(sale.number)}</b></div>
<div class="rw"><span>${esc(t('receipt.date'))}</span><b>${esc(eatDateTime(sale.created_at))}</b></div>
<div class="rw"><span>${esc(t('receipt.customer'))}</span><b>${sale.customer_name ? esc(sale.customer_name) + phone : esc(t('sales.walkin'))}</b></div>
<div class="rw"><span></span><b>${esc(status)}</b></div>
${cancelled ? `<div class="stamp">${esc(t('sales.cancelled'))}</div>` : ''}
<div class="hr"></div>
${stacked}
<div class="hr"></div>
${sums}
${paid ? `<div class="hr"></div><div class="title">${esc(t('receipt.payments'))}</div>${paid}` : ''}
${owing > 0 && sale.due_date && !cancelled ? `<p class="owing">${esc(t('receipt.due'))}: ${esc(day(sale.due_date))}</p>` : ''}
<div class="hr"></div>
<div class="c">${h.footer ? `<p>${esc(h.footer)}</p>` : ''}<p><b>${esc(t('till.thanks'))}</b></p><p class="sm">${esc(t('receipt.printed'))} ${esc(eatDateTime(new Date().toISOString()))}</p></div>
<script>window.onload=function(){setTimeout(function(){window.print()},250)}</script></body></html>`;
  }


  return `<!doctype html><html><head><meta charset="utf-8"><title>${esc(sale.number)}</title>
<style>
@page{size:A4;margin:12mm}
*{box-sizing:border-box;-webkit-print-color-adjust:exact;print-color-adjust:exact}
body{font:13px/1.5 "Segoe UI",Arial,Helvetica,sans-serif;max-width:190mm;margin:0 auto;padding:18px;color:#1e293b;background:#fff}
.top{display:flex;justify-content:space-between;gap:24px;padding-bottom:14px;border-bottom:3px solid #1a2f6e}
.biz h1{font-size:24px;margin:0 0 2px;color:#1a2f6e;letter-spacing:-.2px}
.biz p{margin:1px 0;color:#475569}
.doc{text-align:right}
.doc .title{font-size:20px;font-weight:800;letter-spacing:2px;color:#1a2f6e}
.doc .no{margin-top:4px;font-size:15px;font-weight:700}
.doc .when{color:#475569}
.status{display:inline-block;margin-top:6px;padding:3px 12px;border-radius:999px;font-size:11px;font-weight:800;letter-spacing:.6px;text-transform:uppercase;color:#fff;background:#16a34a}
.status.partial{background:#d97706}
.status.debt,.status.cancelled{background:#dc2626}
.parties{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-top:14px}
.box{border:1px solid #cfd9f3;border-radius:8px;padding:10px 14px;background:#f6f8ff}
.box h2{margin:0 0 4px;font-size:10.5px;letter-spacing:1.4px;text-transform:uppercase;color:#64748b}
.box p{margin:0;font-weight:700;font-size:14px}
table{width:100%;border-collapse:collapse}
table.lines{margin-top:16px;border:1px solid #cfd9f3}
table.lines th{background:#1a2f6e;color:#fff;text-align:left;font-size:11.5px;letter-spacing:.4px;padding:8px 10px;border:1px solid #1a2f6e}
table.lines td{padding:8px 10px;border:1px solid #dbe4f7;vertical-align:top}
table.lines tbody tr:nth-child(even){background:#f6f8ff}
table.lines .no{width:34px;text-align:center;color:#64748b}
table.lines .c,table.lines th.c{text-align:center;width:60px}
table.lines .r,table.lines th.r{text-align:right;white-space:nowrap}
td.name{font-weight:700}
td.name small{display:block;color:#64748b;font-weight:400;font-size:11.5px}
.sum{display:grid;grid-template-columns:1.1fr 1fr;gap:20px;margin-top:16px;align-items:start}
.sum h3{margin:0 0 4px;font-size:10.5px;letter-spacing:1.4px;text-transform:uppercase;color:#64748b}
table.pay td{padding:6px 8px;border:1px solid #dbe4f7;font-size:12px}
table.pay .r{text-align:right;font-weight:700}
table.tot{border:1px solid #cfd9f3}
table.tot td{padding:6px 12px}
table.tot td.r{text-align:right}
table.tot tr.grand td{font-size:16px;font-weight:800;background:#e8eefc;color:#1a2f6e;border-top:1px solid #cfd9f3}
table.tot tr.owing td{font-weight:800;color:#dc2626;border-top:1px solid #cfd9f3}
.due{margin-top:10px;font-weight:700;color:#b45309}
.stamp{margin:12px auto 0;width:max-content;color:#dc2626;border:3px solid #dc2626;font-weight:800;letter-spacing:4px;padding:4px 18px;transform:rotate(-4deg);border-radius:6px}
.signs{display:grid;grid-template-columns:1fr 1fr;gap:40px;margin-top:38px}
.signs div{border-top:1px solid #94a3b8;padding-top:4px;text-align:center;font-size:11.5px;color:#64748b}
.foot{text-align:center;margin-top:22px;padding-top:10px;border-top:2px solid #1a2f6e}
.foot p{margin:2px 0}
.foot .small{color:#94a3b8;font-size:10.5px}
.bar{display:flex;gap:8px;justify-content:flex-end;padding-bottom:10px}
.bar button{padding:8px 16px;border:1px solid #1a2f6e;border-radius:8px;background:#1a2f6e;color:#fff;font-weight:700;cursor:pointer}
@media print{.bar{display:none}body{padding:0}}
</style></head><body>
<div class="bar"><button onclick="window.print()">${esc(t('receipt.print'))}</button></div>
<div class="top">
<div class="biz"><h1>${esc(h.business)}</h1>${h.tagline ? `<p>${esc(h.tagline)}</p>` : ''}${h.address ? `<p>${esc(h.address)}</p>` : ''}${contact ? `<p>${contact}</p>` : ''}${h.tin ? `<p>${esc(t('receipt.tin'))}: ${esc(h.tin)}</p>` : ''}</div>
<div class="doc"><div class="title">${esc(t('receipt.title'))}</div><div class="no">${esc(t('receipt.no'))} <b>${esc(sale.number)}</b></div><div class="when">${esc(eatDateTime(sale.created_at))}</div><span class="status ${state}">${esc(status)}</span></div>
</div>
<div class="parties">
<div class="box"><h2>${esc(t('receipt.customer'))}</h2><p>${sale.customer_name ? esc(sale.customer_name) + phone : esc(t('sales.walkin'))}</p></div>
<div class="box"><h2>${esc(t('receipt.date'))}</h2><p>${esc(eatDateTime(sale.created_at))}</p></div>
</div>
${cancelled ? `<div class="stamp">${esc(t('sales.cancelled'))}</div>` : ''}
<table class="lines"><thead><tr><th class="no">#</th><th>${esc(t('receipt.item'))}</th><th class="c">${esc(t('receipt.qty'))}</th><th class="r">${esc(t('receipt.price'))}</th><th class="r">${esc(t('receipt.amount'))}</th></tr></thead><tbody>${items}</tbody></table>
<div class="sum">
<div>${payments ? `<h3>${esc(t('receipt.payments'))}</h3><table class="pay">${payments}</table>` : ''}${owing > 0 && sale.due_date && !cancelled ? `<p class="due">${esc(t('receipt.due'))}: ${esc(day(sale.due_date))}</p>` : ''}</div>
<table class="tot">${totals}</table>
</div>
<div class="signs"><div>${esc(t('receipt.sign.seller'))}</div><div>${esc(t('receipt.sign.customer'))}</div></div>
<div class="foot">${h.footer ? `<p>${esc(h.footer)}</p>` : ''}<p><b>${esc(t('till.thanks'))}</b></p><p class="small">${esc(t('receipt.printed'))} ${esc(eatDateTime(new Date().toISOString()))}</p></div>
<script>window.onload=function(){setTimeout(function(){window.print()},250)}</script></body></html>`;
}

export function printReceipt(sale: SaleDetail, header: ReceiptHeader | string, t: (key: string) => string, size: ReceiptSize = 'a4'): void {
  const w = window.open('', '_blank', size === 'a4' ? 'width=980,height=900' : 'width=420,height=760');
  if (!w) return;
  w.document.write(receiptHtml(sale, header, t, size));
  w.document.close();
}
