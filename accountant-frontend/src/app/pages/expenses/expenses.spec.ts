import { TestBed } from '@angular/core/testing';

import { Expense, ExpenseSummary } from '../../core/models';
import { byTestId, configure, settle, text, toasts, type } from '../../testing';
import { ExpensesPage } from './expenses';

const rows: Expense[] = [
  { id: 1, category: 'rent', description: 'Shop rent', amount: 100000, expense_date: '2026-11-02', is_personal: false, created_by_name: 'Amina' },
  { id: 2, category: 'family', description: 'School fees', amount: 40000, expense_date: '2026-11-03', is_personal: true },
  { id: 3, category: 'transport', description: 'Fuel', amount: 20000, expense_date: '2026-11-04', is_personal: false, status: 'pending' },
];

const summary: ExpenseSummary = {
  revenue: 500000, cogs: 250000, gross_profit: 250000, total_expenses: 120000, net_profit: 130000, personal_total: 40000,
  by_category: [{ category: 'rent', total: 100000, count: 1 }, { category: 'transport', total: 20000, count: 1 }],
};

async function open(who = {}) {
  const h = configure(who);
  const fixture = TestBed.createComponent(ExpensesPage);
  fixture.detectChanges();
  h.http.expectOne((r) => r.url.endsWith('/expenses/categories')).flush({ data: ['rent', 'transport', 'drawings', 'family', 'other'] });
  h.http.expectOne((r) => r.url.endsWith('/expenses') && r.params.get('period') === 'custom').flush({ data: rows });
  h.http.expectOne((r) => r.url.endsWith('/expenses/summary')).flush({ data: summary });
  await settle(fixture);

  return { h, fixture, el: fixture.nativeElement as HTMLElement };
}

describe('expenses', () => {
  it('asks for this month, from the first day to today', async () => {
    const h = configure({});
    const fixture = TestBed.createComponent(ExpensesPage);
    fixture.detectChanges();
    const list = h.http.expectOne((r) => r.url.endsWith('/expenses') && r.params.get('period') === 'custom');
    const now = new Date();
    const pad = (n: number) => String(n).padStart(2, '0');
    expect(list.request.params.get('from')).toBe(`${now.getFullYear()}-${pad(now.getMonth() + 1)}-01`);
    expect(list.request.params.get('to')).toBe(`${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`);
    list.flush({ data: [] });
    h.http.expectOne((r) => r.url.endsWith('/expenses/summary')).flush({ data: summary });
    h.http.expectOne((r) => r.url.endsWith('/expenses/categories')).flush({ data: [] });
    await settle(fixture);
  });

  it('shows business spending apart from personal spending, and the profit of the period', async () => {
    const { el } = await open();

    expect(text(byTestId(el, 'exp-business')!)).toBe('TSH 120,000');
    expect(text(byTestId(el, 'exp-personal')!)).toBe('TSH 40,000');
    expect(text(byTestId(el, 'exp-net')!)).toBe('TSH 130,000');
  });

  it('lists each expense with its kind, marks personal ones and ones waiting for approval', async () => {
    const { el } = await open();

    expect(text(byTestId(el, 'exp-row-1')!)).toContain('Shop rent');
    expect(text(byTestId(el, 'exp-row-1')!)).toContain('Rent');
    expect(text(byTestId(el, 'exp-row-1')!)).toContain('02/11/2026');
    expect(text(byTestId(el, 'exp-row-2')!)).toContain('personal');
    expect(text(byTestId(el, 'exp-row-3')!)).toContain('Waiting for approval');
  });

  it('a period button asks again for that period', async () => {
    const { h, fixture, el } = await open();

    byTestId(el, 'period-today')!.click();
    const list = h.http.expectOne((r) => r.url.endsWith('/expenses') && r.params.get('period') === 'custom');
    expect(list.request.params.get('from')).toBe(list.request.params.get('to'));
    list.flush({ data: [] });
    h.http.expectOne((r) => r.url.endsWith('/expenses/summary')).flush({ data: { ...summary, total_expenses: 0, by_category: [] } });
    await settle(fixture);
    expect(text(byTestId(el, 'exp-empty')!)).toContain('No expenses in this period.');
  });

  describe('writing one down', () => {
    async function openForm() {
      const o = await open();
      byTestId(o.el, 'exp-add')!.click();
      await settle(o.fixture);

      return o;
    }

    it('asks for what it was for, then the amount, before it asks the server', async () => {
      const { h, fixture, el } = await openForm();

      byTestId(el, 'exp-save')!.click();
      await settle(fixture);
      expect(text(byTestId(el, 'exp-error')!)).toBe('Write what the money was spent on.');

      type(el, '#expDesc', 'Charcoal');
      byTestId(el, 'exp-save')!.click();
      await settle(fixture);
      expect(text(byTestId(el, 'exp-error')!)).toContain('Write the amount in numbers');
      h.http.expectNone((r) => r.method === 'POST');
    });

    it('sends a business expense as the business\'s, and says it was saved', async () => {
      const { h, fixture, el } = await openForm();

      type(el, '#expDesc', 'Charcoal');
      type(el, '#expAmount', '15,000');
      byTestId(el, 'exp-save')!.click();
      const req = h.http.expectOne((r) => r.method === 'POST' && r.url.endsWith('/inventory/expenses'));
      expect(req.request.body).toMatchObject({ category: 'other', description: 'Charcoal', amount: 15000, is_personal: false });
      expect(req.request.body.expense_date).toMatch(/^\d{4}-\d{2}-\d{2}$/);
      req.flush({ message: 'Expense recorded' }, { status: 201, statusText: 'Created' });
      await settle(fixture);
      h.http.expectOne((r) => r.url.endsWith('/expenses') && r.params.get('period') === 'custom').flush({ data: rows });
      h.http.expectOne((r) => r.url.endsWith('/expenses/summary')).flush({ data: summary });
      await settle(fixture);

      expect(toasts()).toContain('The expense of TSH 15,000 was saved.');
    });

    it('family and drawings are always personal, and the switch cannot be turned off for them', async () => {
      const { h, fixture, el } = await openForm();

      const select = el.querySelector('#expCategory') as HTMLSelectElement;
      select.value = 'family';
      select.dispatchEvent(new Event('change', { bubbles: true }));
      await settle(fixture);
      const sw = el.querySelector('[data-testid="exp-personal-switch"]') as HTMLInputElement;
      expect(sw.disabled).toBe(true);
      expect(sw.checked).toBe(true);
      expect(text(el)).toContain('Family and drawings are always personal.');

      type(el, '#expDesc', 'School fees');
      type(el, '#expAmount', '40000');
      byTestId(el, 'exp-save')!.click();
      const req = h.http.expectOne((r) => r.method === 'POST');
      expect(req.request.body).toMatchObject({ category: 'family', is_personal: true });
      req.flush({}, { status: 201, statusText: 'Created' });
      await settle(fixture);
    });

    it('any other kind can be marked personal with the switch', async () => {
      const { h, fixture, el } = await openForm();

      const sw = el.querySelector('[data-testid="exp-personal-switch"]') as HTMLInputElement;
      sw.checked = true;
      sw.dispatchEvent(new Event('change', { bubbles: true }));
      type(el, '#expDesc', 'Phone bill at home');
      type(el, '#expAmount', '5000');
      byTestId(el, 'exp-save')!.click();
      expect(h.http.expectOne((r) => r.method === 'POST').request.body).toMatchObject({ is_personal: true });
      await settle(fixture);
    });
  });

  it('someone who may only look is not offered to add or delete', async () => {
    const { el } = await open({ permissions: ['inv_view_expenses'] });
    expect(byTestId(el, 'exp-add')).toBeNull();
    expect(byTestId(el, 'exp-del-1')).toBeNull();
    expect(byTestId(el, 'exp-row-1')).not.toBeNull();
  });

  it('delete asks first; the server\'s refusal (not your own expense) is shown as a message', async () => {
    const { h, fixture, el } = await open();

    h.confirmAnswer.value = false;
    byTestId(el, 'exp-del-1')!.click();
    await settle(fixture);
    h.http.expectNone((r) => r.method === 'DELETE');

    h.confirmAnswer.value = true;
    byTestId(el, 'exp-del-1')!.click();
    await settle(fixture);
    h.http.expectOne((r) => r.method === 'DELETE' && r.url.endsWith('/expenses/1')).flush({ message: 'You can only delete your own expenses.' }, { status: 403, statusText: 'Forbidden' });
    await settle(fixture);
    expect(toasts()).toContain('You can only delete your own expenses.');
  });

  it('in Swahili it is Swahili, including the kinds of expense', async () => {
    const h = configure({});
    h.i18n.setLang('sw');
    const fixture = TestBed.createComponent(ExpensesPage);
    fixture.detectChanges();
    h.http.match((r) => r.url.endsWith('/expenses/categories')).forEach((r) => r.flush({ data: [] }));
    h.http.expectOne((r) => r.url.endsWith('/expenses') && r.params.get('period') === 'custom').flush({ data: rows });
    h.http.expectOne((r) => r.url.endsWith('/expenses/summary')).flush({ data: summary });
    await settle(fixture);
    const all = text(fixture.nativeElement);

    expect(all).toContain('Matumizi ya biashara');
    expect(all).toContain('Kodi');
    expect(all).toContain('binafsi');
    expect(all).toContain('Andika matumizi');
  });
});
