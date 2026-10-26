import { tsh } from './format';
import { SaleDetail } from './till-api.service';

const esc = (s: string): string => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c] as string);

/** The receipt as a small printable page (narrow, like a till roll). `t` turns a key into words in the person's language. */
export function receiptHtml(sale: SaleDetail, business: string, t: (key: string) => string): string {
  const rows = sale.items
    .map((i) => `<tr><td>${esc(i.product_name)}${i.unit_name ? ` (${esc(i.unit_name)})` : ''}<br><small>${i.qty ?? i.quantity} × ${tsh(i.unit_price)}</small></td><td class="r">${tsh(i.total)}</td></tr>`)
    .join('');
  const line = (label: string, value: string, bold = false) => `<tr${bold ? ' class="b"' : ''}><td>${esc(label)}</td><td class="r">${esc(value)}</td></tr>`;
  const owing = Math.max(0, sale.total - sale.paid_total);
  return `<!doctype html><html><head><meta charset="utf-8"><title>${esc(sale.number)}</title>
<style>body{font:13px/1.4 Arial,sans-serif;width:300px;margin:0 auto;padding:12px;color:#000}h1{font-size:16px;text-align:center;margin:0}p{text-align:center;margin:2px 0}
table{width:100%;border-collapse:collapse;margin-top:8px}td{padding:3px 0;vertical-align:top}.r{text-align:right}.b td{font-weight:700;border-top:1px dashed #000;padding-top:5px}small{color:#555}</style></head>
<body><h1>${esc(business)}</h1><p>${esc(sale.number)}</p><p>${esc(new Date(sale.created_at).toLocaleString())}</p>
${sale.customer_name ? `<p>${esc(sale.customer_name)}</p>` : ''}
<table>${rows}</table><table>${line(t('till.sub'), tsh(sale.subtotal))}${sale.discount > 0 ? line(t('till.discount'), '-' + tsh(sale.discount)) : ''}${sale.tax > 0 ? line(t('till.vat'), tsh(sale.tax)) : ''}${line(t('till.total'), tsh(sale.total), true)}${line(t('till.paid'), tsh(sale.paid_total))}${owing > 0 ? line(t('till.owing'), tsh(owing), true) : ''}</table>
<p style="margin-top:12px">${esc(t('till.thanks'))}</p><script>window.onload=function(){window.print()}</script></body></html>`;
}

export function printReceipt(sale: SaleDetail, business: string, t: (key: string) => string): void {
  const w = window.open('', '_blank', 'width=360,height=640');
  if (!w) return;
  w.document.write(receiptHtml(sale, business, t));
  w.document.close();
}
