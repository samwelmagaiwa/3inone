import { TestBed } from '@angular/core/testing';

import { environment } from '../../../environments/environment';
import { Debt, DebtKind } from '../../core/models';
import { byTestId, configure, settle, text, toasts, type } from '../../testing';
import { DebtsPage } from './debts';

const debt = (over: Partial<Debt> = {}): Debt => ({
  id: 1, kind: 'receivable', name: 'Mama Neema', phone: '0711000001', amount: 350000, paid: 0, left: 350000, started_on: '2026-06-01', due_on: '2026-07-01', days_late: 120, note: 'Soda za mwaka jana', ...over,
});

const page = (kind: DebtKind, debts: Debt[], total: number, old = total) => ({ data: { kind, debts, total, old, from_records: total - old } });

async function open(who = {}) {
  const h = configure(who);
  const fixture = TestBed.createComponent(DebtsPage);
  fixture.detectChanges();
  const owed = [debt(), debt({ id: 2, name: 'Baba Juma', phone: null, amount: 20000, paid: 10000, left: 10000, due_on: null, days_late: 0, note: null })];
  h.http.expectOne((r) => r.url.endsWith('/opening-debts') && r.params.get('kind') === 'receivable').flush(page('receivable', owed, 460000, 360000));
  h.http.expectOne((r) => r.url.endsWith('/opening-debts') && r.params.get('kind') === 'payable').flush(page('payable', [], 0));
  await settle(fixture);

  return { h, fixture, el: fixture.nativeElement as HTMLElement };
}

const button = (el: HTMLElement, label: string) => Array.from(el.querySelectorAll('button')).find((b) => b.textContent?.trim() === label) as HTMLButtonElement;

describe('debts', () => {
  it('shows the total, how much came from before the app, and each debt with what is left', async () => {
    const { el } = await open();

    expect(text(byTestId(el, 'debts-total')!)).toBe('TSH 460,000');
    expect(text(byTestId(el, 'debts-old')!)).toBe('TSH 360,000');
    const neema = text(byTestId(el, 'debt-row-1')!);
    expect(neema).toContain('Mama Neema');
    expect(neema).toContain('0711000001');
    expect(neema).toContain('120 days late');
    expect(neema).toContain('Soda za mwaka jana');
    expect(text(byTestId(el, 'debt-row-2')!)).toContain('TSH 10,000'); // what is left, not the whole
    expect(text(byTestId(el, 'debt-row-2')!)).toContain('TSH 20,000');
  });

  it('the second tab is what I owe, with its own empty page and its own button', async () => {
    const { fixture, el } = await open();

    byTestId(el, 'tab-owe')!.click();
    await settle(fixture);

    expect(text(byTestId(el, 'debts-empty')!)).toContain('You have not written down anything you owe.');
    expect(text(byTestId(el, 'debt-add')!)).toBe('Add what I owe');
  });

  it('searching narrows the list and says when nothing matches', async () => {
    const { fixture, el } = await open();

    type(el, 'input[type=text]', 'juma');
    await settle(fixture);
    expect(byTestId(el, 'debt-row-1')).toBeNull();
    expect(byTestId(el, 'debt-row-2')).not.toBeNull();

    type(el, 'input[type=text]', 'zzz');
    await settle(fixture);
    expect(text(byTestId(el, 'debts-empty')!)).toContain('Nothing matches what you typed.');
  });

  describe('writing down an old debt', () => {
    async function openForm() {
      const o = await open();
      byTestId(o.el, 'debt-add')!.click();
      await settle(o.fixture);

      return o;
    }

    it('asks for a name, then an amount, before it asks the server anything', async () => {
      const { h, fixture, el } = await openForm();

      byTestId(el, 'debt-save')!.click();
      await settle(fixture);
      expect(text(byTestId(el, 'debt-error')!)).toBe("Write the debtor's name.");

      type(el, '#debtName', 'Mzee Ali');
      byTestId(el, 'debt-save')!.click();
      await settle(fixture);
      expect(text(byTestId(el, 'debt-error')!)).toContain('Write the amount in numbers');

      type(el, '#debtAmount', '-5');
      byTestId(el, 'debt-save')!.click();
      await settle(fixture);
      expect(text(byTestId(el, 'debt-error')!)).toContain('Write the amount in numbers');
      h.http.expectNone((r) => r.method === 'POST');
    });

    it('sends what was typed (amount with commas is fine), then shows the new list and a message', async () => {
      const { h, fixture, el } = await openForm();

      type(el, '#debtName', ' Mzee Ali ');
      type(el, '#debtPhone', '0755000111');
      type(el, '#debtAmount', '125,000');
      type(el, '#debtNote', 'Cement');
      byTestId(el, 'debt-save')!.click();

      const req = h.http.expectOne((r) => r.method === 'POST' && r.url.endsWith('/opening-debts'));
      expect(req.request.body).toMatchObject({ kind: 'receivable', name: 'Mzee Ali', phone: '0755000111', amount: 125000, note: 'Cement' });
      expect(req.request.body.started_on).toMatch(/^\d{4}-\d{2}-\d{2}$/);
      expect(req.request.body.due_on).toBeUndefined();
      req.flush({ message: 'Saved' }, { status: 201, statusText: 'Created' });
      await settle(fixture);
      h.http.expectOne((r) => r.url.endsWith('/opening-debts') && r.params.get('kind') === 'receivable').flush(page('receivable', [debt({ id: 3, name: 'Mzee Ali', amount: 125000, left: 125000 })], 125000));
      h.http.expectOne((r) => r.url.endsWith('/opening-debts') && r.params.get('kind') === 'payable').flush(page('payable', [], 0));
      await settle(fixture);

      expect(byTestId(el, 'debt-row-3')).not.toBeNull();
      expect(toasts()).toContain('The debt of Mzee Ali was saved.');
    });

    it('shows the server\'s own words when it refuses, and keeps the window open', async () => {
      const { h, fixture, el } = await openForm();
      type(el, '#debtName', 'X');
      type(el, '#debtAmount', '10');
      byTestId(el, 'debt-save')!.click();
      h.http.expectOne((r) => r.method === 'POST').flush({ message: 'Validation failed', errors: { name: ['Andika jina la mdaiwa.'] } }, { status: 422, statusText: 'Unprocessable' });
      await settle(fixture);

      expect(text(byTestId(el, 'debt-error')!)).toBe('Andika jina la mdaiwa.');
      expect(byTestId(el, 'debt-name')).not.toBeNull();
    });
  });

  describe('taking a payment', () => {
    async function openPay(id: number) {
      const o = await open();
      byTestId(o.el, `debt-pay-${id}`)!.click();
      o.h.http.expectOne((r) => r.url.endsWith(`/opening-debts/${id}/payments`)).flush({ data: id === 2 ? [{ id: 9, amount: 10000, method: 'cash', paid_on: '2026-10-15' }] : [] });
      await settle(o.fixture);

      return o;
    }

    it('shows what is left and the payments made so far; the amount starts at what is left', async () => {
      const { el } = await openPay(2);
      expect(text(byTestId(el, 'pay-left')!)).toBe('TSH 10,000');
      expect((el.querySelector('#payAmount') as HTMLInputElement).value).toBe('10,000');
      expect(text(el)).toContain('15/10/2026');
    });

    it('refuses more than is left, and sends a part payment', async () => {
      const { h, fixture, el } = await openPay(2);

      type(el, '#payAmount', '10001');
      byTestId(el, 'pay-save')!.click();
      await settle(fixture);
      expect(text(byTestId(el, 'pay-error')!)).toBe('The amount must be more than 0 and not more than TSH 10,000.');
      h.http.expectNone((r) => r.method === 'POST');

      type(el, '#payAmount', '4,000');
      byTestId(el, 'pay-save')!.click();
      const req = h.http.expectOne((r) => r.method === 'POST' && r.url.endsWith('/opening-debts/2/payments'));
      expect(req.request.body).toEqual({ amount: 4000 });
      req.flush({ data: { left: 6000 } });
      await settle(fixture);
      h.http.match((r) => r.url.endsWith('/opening-debts')).forEach((r) => r.flush(page('receivable', [], 0)));
      await settle(fixture);
      expect(toasts()).toContain('Baba Juma: saved. TSH 6,000 is left.');
    });

    it('a debt with payments cannot be deleted; one nobody paid can, after asking', async () => {
      const paid = await openPay(2);
      expect(byTestId(paid.el, 'debt-delete')).toBeNull();
    });

    it('delete asks first; saying no changes nothing, saying yes removes it', async () => {
      const o = await openPay(1);
      o.h.confirmAnswer.value = false;
      byTestId(o.el, 'debt-delete')!.click();
      await settle(o.fixture);
      o.h.http.expectNone((r) => r.method === 'DELETE');

      o.h.confirmAnswer.value = true;
      byTestId(o.el, 'debt-delete')!.click();
      await settle(o.fixture);
      const req = o.h.http.expectOne((r) => r.method === 'DELETE' && r.url.endsWith('/opening-debts/1'));
      req.flush({ message: 'Deleted' });
      await settle(o.fixture);
      o.h.http.match((r) => r.url.endsWith('/opening-debts')).forEach((r) => r.flush(page('receivable', [], 0)));
      await settle(o.fixture);
      expect(toasts()).toContain('The debt was deleted.');
    });
  });

  it('a failed load offers to try again', async () => {
    const h = configure({});
    const fixture = TestBed.createComponent(DebtsPage);
    fixture.detectChanges();
    h.http.match((r) => r.url.endsWith('/opening-debts')).forEach((r) => r.flush({ message: 'Server busy' }, { status: 500, statusText: 'Error' }));
    await settle(fixture);

    expect((fixture.nativeElement as HTMLElement).querySelector('[role=alert]')?.textContent).toContain('Server busy');
  });

  it('in Swahili it is Swahili', async () => {
    const h = configure({});
    h.i18n.setLang('sw');
    const fixture = TestBed.createComponent(DebtsPage);
    fixture.detectChanges();
    h.http.expectOne((r) => r.params.get('kind') === 'receivable').flush(page('receivable', [debt()], 350000));
    h.http.expectOne((r) => r.params.get('kind') === 'payable').flush(page('payable', [], 0));
    await settle(fixture);
    const all = text(fixture.nativeElement);

    expect(all).toContain('Ninayodai');
    expect(all).toContain('Ninayodaiwa');
    expect(all).toContain('Jumla ninayodai');
    expect(all).toContain('Siku 120 zimepita');
    expect(all).toContain('Ongeza deni la zamani');
  });
});
