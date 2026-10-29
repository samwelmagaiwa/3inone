import { TestBed } from '@angular/core/testing';

import { SaleRow } from '../../core/models';
import { byTestId, configure, settle, text, type } from '../../testing';
import { SalesPage } from './sales';

const owed: SaleRow = {
  id: 2, number: 'S-2', total: 10000, paid_total: 4000, payment_status: 'partial', customer_name: 'Mama Neema', created_at: '2026-11-05 07:30:00', items: [], payments: [],
};

async function open(who = {}, returns: unknown[] = []) {
  const h = configure(who);
  const fixture = TestBed.createComponent(SalesPage);
  fixture.detectChanges();
  h.http.match((r) => r.url.endsWith('/inventory/returns')).forEach((r) => r.flush({ data: returns }));
  h.http.expectOne((r) => r.url.endsWith('/inventory/sales') && !r.url.includes('summary')).flush({ data: [owed], meta: { total: 1 } });
  h.http.expectOne((r) => r.url.endsWith('/sales/summary')).flush({ data: { count: 1, total: 10000, paid: 4000, debt: 6000 } });
  await settle(fixture);
  return { h, fixture, el: fixture.nativeElement as HTMLElement };
}

/** What the page asks for again after a change: answer it with an empty list. */
function reload(h: ReturnType<typeof configure>) {
  h.http.match(() => true).forEach((r) => r.flush({ data: [], meta: { total: 0 } }));
}

describe('what can be done to a sale', () => {
  it('someone who may sell sees the New sale button; someone who may not does not', async () => {
    const yes = await open();
    expect(byTestId(yes.el, 'sales-new')).not.toBeNull();
    TestBed.resetTestingModule();
    const no = await open({ permissions: ['inv_view_reports'] });
    expect(byTestId(no.el, 'sales-new')).toBeNull();
  });

  it('records a payment on a sale that is still owed, and refuses more than is owed', async () => {
    const { h, fixture, el } = await open();
    byTestId(el, 'sale-row-2')!.click();
    await settle(fixture);
    byTestId(el, 'pay-2')!.click();
    await settle(fixture);

    type(el, '[data-testid=pay-amount]', '9000');
    byTestId(el, 'pay-save')!.click();
    await settle(fixture);
    expect(text(el)).toContain('Only TSH 6,000 is still owed');

    type(el, '[data-testid=pay-amount]', '6000');
    byTestId(el, 'pay-save')!.click();
    const post = h.http.expectOne((r) => r.url.endsWith('/inventory/sales/2/payments'));
    expect(post.request.body).toEqual({ amount: 6000, method: 'cash' });
    post.flush({ data: { balance: 0, payment_status: 'paid' } });
    await settle(fixture);
    reload(h);
  });

  it('a payment by mobile money needs its reference number and sends it', async () => {
    const { h, fixture, el } = await open();
    byTestId(el, 'sale-row-2')!.click();
    await settle(fixture);
    byTestId(el, 'pay-2')!.click();
    await settle(fixture);
    expect(byTestId(el, 'pay-ref')).toBeNull();

    const method = el.querySelector('#pmeth') as HTMLSelectElement;
    method.value = 'mpesa';
    method.dispatchEvent(new Event('change', { bubbles: true }));
    await settle(fixture);
    type(el, '[data-testid=pay-amount]', '6000');
    byTestId(el, 'pay-save')!.click();
    await settle(fixture);
    expect(text(el)).toContain('Write the reference number');
    h.http.expectNone((r) => r.url.endsWith('/inventory/sales/2/payments'));

    type(el, '[data-testid=pay-ref]', 'QWE123');
    byTestId(el, 'pay-save')!.click();
    const post = h.http.expectOne((r) => r.url.endsWith('/inventory/sales/2/payments'));
    expect(post.request.body).toEqual({ amount: 6000, method: 'mpesa', reference: 'QWE123' });
    post.flush({ data: { balance: 0, payment_status: 'paid' } });
    await settle(fixture);
    reload(h);
  });

  it('cancelling needs a reason', async () => {
    const { h, fixture, el } = await open();
    byTestId(el, 'sale-row-2')!.click();
    await settle(fixture);
    byTestId(el, 'cancel-2')!.click();
    await settle(fixture);
    byTestId(el, 'cancel-save')!.click();
    await settle(fixture);
    expect(text(el)).toContain('Write the reason first.');

    type(el, '[data-testid=cancel-reason]', 'Wrong goods');
    byTestId(el, 'cancel-save')!.click();
    const post = h.http.expectOne((r) => r.url.endsWith('/inventory/sales/2/cancel'));
    expect(post.request.body).toEqual({ reason: 'Wrong goods' });
    post.flush({});
    await settle(fixture);
    reload(h);
  });

  it('a sales officer without the right to manage sales cannot cancel, but can take a payment', async () => {
    const { fixture, el } = await open({ permissions: ['inv_create_sales'] });
    byTestId(el, 'sale-row-2')!.click();
    await settle(fixture);
    expect(byTestId(el, 'cancel-2')).toBeNull();
    expect(byTestId(el, 'pay-2')).not.toBeNull();
  });

  it('lists returns waiting for approval, and a manager can approve one', async () => {
    const pending = { id: 9, reference: 'R-9', sale_id: 1, sale_number: 'S-1', type: 'return', amount: 3000, reason: 'Damaged', status: 'pending', requested_by_name: 'Juma', created_at: '' };
    const { h, fixture, el } = await open({}, [pending]);
    expect(text(byTestId(el, 'returns')!)).toContain('S-1');
    byTestId(el, 'approve-9')!.click();
    const post = h.http.expectOne((r) => r.url.endsWith('/inventory/returns/9/decide'));
    expect(post.request.body).toEqual({ decision: 'approved' });
    post.flush({});
    await settle(fixture);
    reload(h);
  });
});
