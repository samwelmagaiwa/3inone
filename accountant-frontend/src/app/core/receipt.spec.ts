import { receiptHeaderFrom, receiptHtml } from './receipt';
import { SaleDetail } from './till-api.service';

const WORDS: Record<string, string> = {
  'receipt.title': 'SALES RECEIPT', 'receipt.no': 'Receipt no.', 'receipt.date': 'Date', 'receipt.customer': 'Customer', 'receipt.item': 'Item', 'receipt.qty': 'Qty',
  'receipt.price': 'Price', 'receipt.amount': 'Amount', 'receipt.served': 'Served by', 'receipt.payments': 'Payments', 'receipt.ref': 'Ref', 'receipt.due': 'To be paid by',
  'receipt.tin': 'TIN', 'receipt.tel': 'Tel', 'receipt.printed': 'Printed', 'till.sub': 'Sub-total', 'till.discount': 'Discount', 'till.vat': 'VAT', 'till.total': 'Total',
  'till.paid': 'Paid', 'till.owing': 'Still owed', 'till.thanks': 'Thank you!', 'sales.cancelled': 'Cancelled', 'sales.walkin': 'Walk-in customer',
  'sales.status.paid': 'Paid', 'sales.status.partial': 'Part paid', 'sales.status.debt': 'On credit', 'pay.mpesa': 'M-Pesa', 'pay.cash': 'Cash',
};
const t = (k: string) => WORDS[k] ?? k;

const header = receiptHeaderFrom(
  { depot_name: 'Glow Salon', depot_address: 'Kariakoo, Dar es Salaam', depot_phone: '0617919104', receipt_email: 'hi@glow.test', receipt_tagline: 'Beauty you can trust', receipt_tin: '123-456-789', receipt_footer_note: 'Goods sold are not returned.' },
  'Fallback Name',
);

const sale = (over: Partial<SaleDetail> = {}): SaleDetail => ({
  id: 1, number: 'S-20261029-0027', customer_id: 4, customer_name: 'john mpya', customer_phone: '0712000111', payment_status: 'partial', subtotal: 77000, discount: 34999, discount_reason: 'Regular client',
  tax: 0, total: 42001, paid_total: 30000, due_date: '2026-11-05', created_at: '2026-10-29 09:27:00', cancelled_at: null,
  items: [
    { id: 1, product_id: 1, product_name: 'Knotless Braids', quantity: 1, qty: 1, unit_name: null, unit_price: 22000, total: 22000, tax_amount: 0, is_service: true, staff_name: 'Rehema' },
    { id: 2, product_id: 2, product_name: 'Gel', quantity: 2, qty: 2, unit_name: 'tube', unit_price: 27500, total: 55000, tax_amount: 0, is_service: false, staff_name: null },
  ],
  payments: [{ id: 1, amount: 30000, method: 'mpesa', reference: 'QWE123', paid_at: '2026-10-29 09:27:30' }],
  ...over,
});

describe('the printed receipt', () => {
  it('names the business, with its address, contact, TIN and tagline', () => {
    const html = receiptHtml(sale(), header, t);
    for (const part of ['Glow Salon', 'Beauty you can trust', 'Kariakoo, Dar es Salaam', 'Tel 0617919104', 'hi@glow.test', 'TIN: 123-456-789']) expect(html).toContain(part);
  });

  it('shows the number, the date and time, the customer with the phone, and how it stands', () => {
    const html = receiptHtml(sale(), header, t);
    expect(html).toContain('SALES RECEIPT');
    expect(html).toContain('S-20261029-0027');
    expect(html).toContain('29/10/2026 12:27'); // Tanzania time
    expect(html).toContain('john mpya · 0712000111');
    expect(html).toContain('Part paid');
  });

  it('lists every item with its quantity, price, total, unit and who served', () => {
    const html = receiptHtml(sale(), header, t);
    expect(html).toContain('Knotless Braids');
    expect(html).toContain('Served by: Rehema');
    expect(html).toContain('tube');
    expect(html).toContain('TSH 27,500');
    expect(html).toContain('TSH 55,000');
    expect(html).toMatch(/<td class="c">2<\/td>/);
  });

  it('adds up: sub-total, discount with its reason, total, paid and what is still owed, and when to pay', () => {
    const html = receiptHtml(sale(), header, t);
    expect(html).toContain('TSH 77,000');
    expect(html).toContain('Discount (Regular client)');
    expect(html).toContain('-TSH 34,999');
    expect(html).toContain('TSH 42,001');
    expect(html).toContain('Still owed');
    expect(html).toContain('TSH 12,001');
    expect(html).toContain('To be paid by: 05/11/2026');
  });

  it('lists each payment with when, how and its reference number', () => {
    const html = receiptHtml(sale(), header, t);
    expect(html).toContain('Payments');
    expect(html).toContain('M-Pesa · Ref QWE123');
    expect(html).toContain('29/10/2026 12:27');
  });

  it("ends with the business's own note and a thank you", () => {
    const html = receiptHtml(sale(), header, t);
    expect(html).toContain('Goods sold are not returned.');
    expect(html).toContain('Thank you!');
  });

  it('a fully paid sale shows no owing line and no due date', () => {
    const html = receiptHtml(sale({ payment_status: 'paid', paid_total: 42001, due_date: null }), header, t);
    expect(html).not.toContain('Still owed');
    expect(html).not.toContain('To be paid by');
  });

  it('a cancelled sale is stamped and shows no due date', () => {
    const html = receiptHtml(sale({ cancelled_at: '2026-10-29 10:00:00' }), header, t);
    expect(html).toContain('class="stamp"');
    expect(html).not.toContain('To be paid by');
  });

  it('a walk-in sale says so, and a sale with no discount or VAT has no such lines', () => {
    const html = receiptHtml(sale({ customer_name: null, customer_phone: null, discount: 0, discount_reason: null, tax: 0, payment_status: 'paid', paid_total: 42001, payments: [] }), header, t);
    expect(html).toContain('Walk-in customer');
    expect(html).not.toContain('Discount');
    expect(html).not.toContain('VAT');
    expect(html).not.toContain('Payments');
  });

  it('shows VAT when the sale carries it, and escapes what people typed', () => {
    const html = receiptHtml(sale({ tax: 6407, customer_name: '<b>Mama</b> & Co' }), header, t);
    expect(html).toContain('TSH 6,407');
    expect(html).toContain('&lt;b&gt;Mama&lt;/b&gt; &amp; Co');
    expect(html).not.toContain('<b>Mama</b>');
  });

  it('keeps working when only the business name is known (old callers), and hides the TIN when the business asked not to show it', () => {
    expect(receiptHtml(sale(), 'Mama Shop', t)).toContain('Mama Shop');
    const hidden = receiptHeaderFrom({ receipt_tin: '999', receipt_show_tin: '0' }, 'Shop');
    expect(hidden.tin).toBe('');
    expect(hidden.business).toBe('Shop');
  });
});
