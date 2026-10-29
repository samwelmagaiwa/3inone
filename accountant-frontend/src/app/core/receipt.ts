import { eatDateTime, tsh } from './format';
import { SaleDetail } from './till-api.service';

const esc = (s: string): string => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c] as string);

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
export function receiptHtml(sale: SaleDetail, header: ReceiptHeader | string, t: (key: string) => string): string {
  const h: ReceiptHeader = typeof header === 'string' ? { business: header, tagline: '', address: '', phone: '', email: '', website: '', tin: '', footer: '' } : header;
  const word = (key: string, raw: string): string => {
    const v = t(key);
    return v === key ? raw : v;
  };
  const cancelled = !!sale.cancelled_at;
  const owing = Math.max(0, sale.total - sale.paid_total);
  const status = cancelled ? t('sales.cancelled') : t(`sales.status.${sale.payment_status}`);

  const items = sale.items
    .map((i) => {
      const qty = i.qty ?? i.quantity;
      const extra = [i.unit_name ? esc(i.unit_name) : '', i.staff_name ? `${esc(t('receipt.served'))}: ${esc(i.staff_name)}` : ''].filter(Boolean).join(' · ');
      return `<tr><td class="name">${esc(i.product_name)}${extra ? `<small>${extra}</small>` : ''}</td><td class="c">${qty}</td><td class="r">${tsh(i.unit_price)}</td><td class="r">${tsh(i.total)}</td></tr>`;
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
    .map((p) => `<tr><td>${esc(eatDateTime(p.paid_at))}<small>${esc(word(`pay.${p.method ?? 'cash'}`, p.method ?? ''))}${p.reference ? ` · ${esc(t('receipt.ref'))} ${esc(p.reference)}` : ''}</small></td><td class="r">${tsh(p.amount)}</td></tr>`)
    .join('');

  const contact = [h.phone ? `${esc(t('receipt.tel'))} ${esc(h.phone)}` : '', h.email ? esc(h.email) : '', h.website ? esc(h.website) : ''].filter(Boolean).join(' · ');
  const phone = sale.customer_phone ? ` · ${esc(sale.customer_phone)}` : '';

  return `<!doctype html><html><head><meta charset="utf-8"><title>${esc(sale.number)}</title>
<style>
@page{margin:8mm}
*{box-sizing:border-box}
body{font:12.5px/1.45 Arial,Helvetica,sans-serif;max-width:340px;margin:0 auto;padding:14px;color:#111}
.head{text-align:center;padding-bottom:8px;border-bottom:2px solid #111}
.head h1{font-size:18px;margin:0 0 2px;letter-spacing:.3px}
.head p{margin:1px 0;color:#333}
.title{text-align:center;font-weight:700;letter-spacing:2px;margin:10px 0 6px;font-size:12px}
.meta{width:100%;border-collapse:collapse}
.meta td{padding:1px 0;vertical-align:top}
.meta td:first-child{color:#555;width:38%}
.status{display:inline-block;padding:1px 8px;border:1px solid #111;border-radius:3px;font-weight:700;font-size:11px;text-transform:uppercase}
.status.cancelled{border-color:#b00;color:#b00}
table.lines{width:100%;border-collapse:collapse;margin-top:8px}
table.lines th{text-align:left;font-size:11px;color:#555;border-bottom:1px solid #111;padding:3px 0}
table.lines th.c,table.lines td.c{text-align:center}
table.lines th.r,table.lines td.r,.tot td.r,.pay td.r{text-align:right}
table.lines td{padding:4px 0;border-bottom:1px dotted #bbb;vertical-align:top}
td.name small,.pay small{display:block;color:#666;font-size:11px}
.tot,.pay{width:100%;border-collapse:collapse;margin-top:8px}
.tot td{padding:2px 0}
.tot tr.grand td{font-size:15px;font-weight:700;border-top:1px dashed #111;padding-top:6px}
.tot tr.owing td{font-weight:700;border-top:1px solid #111;padding-top:4px}
h2{font-size:11px;letter-spacing:1.5px;text-transform:uppercase;margin:12px 0 2px;border-bottom:1px solid #ccc;padding-bottom:2px;color:#444}
.pay td{padding:2px 0;vertical-align:top}
.due{margin-top:6px;font-weight:700}
.foot{text-align:center;margin-top:14px;padding-top:8px;border-top:1px dashed #111}
.foot p{margin:2px 0}
.foot .small{color:#666;font-size:10.5px}
.stamp{text-align:center;color:#b00;border:2px solid #b00;font-weight:700;letter-spacing:3px;padding:3px;margin-top:8px;transform:rotate(-3deg)}
</style></head><body>
<div class="head"><h1>${esc(h.business)}</h1>${h.tagline ? `<p>${esc(h.tagline)}</p>` : ''}${h.address ? `<p>${esc(h.address)}</p>` : ''}${contact ? `<p>${contact}</p>` : ''}${h.tin ? `<p>${esc(t('receipt.tin'))}: ${esc(h.tin)}</p>` : ''}</div>
<div class="title">${esc(t('receipt.title'))}</div>
<table class="meta">
<tr><td>${esc(t('receipt.no'))}</td><td><b>${esc(sale.number)}</b></td></tr>
<tr><td>${esc(t('receipt.date'))}</td><td>${esc(eatDateTime(sale.created_at))}</td></tr>
<tr><td>${esc(t('receipt.customer'))}</td><td>${sale.customer_name ? esc(sale.customer_name) + phone : esc(t('sales.walkin'))}</td></tr>
<tr><td></td><td><span class="status${cancelled ? ' cancelled' : ''}">${esc(status)}</span></td></tr>
</table>
${cancelled ? `<div class="stamp">${esc(t('sales.cancelled'))}</div>` : ''}
<table class="lines"><thead><tr><th>${esc(t('receipt.item'))}</th><th class="c">${esc(t('receipt.qty'))}</th><th class="r">${esc(t('receipt.price'))}</th><th class="r">${esc(t('receipt.amount'))}</th></tr></thead><tbody>${items}</tbody></table>
<table class="tot">${totals}</table>
${payments ? `<h2>${esc(t('receipt.payments'))}</h2><table class="pay">${payments}</table>` : ''}
${owing > 0 && sale.due_date && !cancelled ? `<p class="due">${esc(t('receipt.due'))}: ${esc(day(sale.due_date))}</p>` : ''}
<div class="foot">${h.footer ? `<p>${esc(h.footer)}</p>` : ''}<p><b>${esc(t('till.thanks'))}</b></p><p class="small">${esc(t('receipt.printed'))} ${esc(eatDateTime(new Date().toISOString()))}</p></div>
<script>window.onload=function(){window.print()}</script></body></html>`;
}

export function printReceipt(sale: SaleDetail, header: ReceiptHeader | string, t: (key: string) => string): void {
  const w = window.open('', '_blank', 'width=420,height=720');
  if (!w) return;
  w.document.write(receiptHtml(sale, header, t));
  w.document.close();
}
