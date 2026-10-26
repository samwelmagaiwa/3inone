import { TestBed } from '@angular/core/testing';

import { environment } from '../../../environments/environment';
import { monthKey, shiftMonth } from '../../core/format';
import { Comparison } from '../../core/models';
import { byTestId, configure, settle, text, type } from '../../testing';
import { DashboardPage } from './dashboard';

const cmp = (now: number, before: number, direction: Comparison['direction'], percent: number | null, good = true): Comparison => ({ now, before, change: now - before, percent, direction, good });

const report = (month: string, over: Record<string, unknown> = {}) => ({
  month,
  is_current: true,
  is_future: false,
  days_elapsed: 10,
  days_in_month: 30,
  figures: {
    sales: 300000, sales_count: 12, cost_of_goods: 150000, gross_profit: 150000, margin_percent: 50, expenses: 30000, personal_spending: 7000, write_offs: 0, net_profit: 120000,
    expenses_by_category: [{ category: 'rent', total: 20000 }, { category: 'transport', total: 10000 }],
  },
  previous: { month: shiftMonth(month, -1), like_for_like: true },
  compare: { sales: cmp(300000, 200000, 'up', 50), gross_profit: cmp(150000, 100000, 'up', 50), expenses: cmp(30000, 20000, 'up', 50, false), net_profit: cmp(120000, 80000, 'up', 50) },
  overall: { direction: 'up', percent: 50 },
  position: { stock_value: 900000, receivable: 150000, payable: 50000, capital: 1000000 },
  capital_change: cmp(1000000, 800000, 'up', 25),
  target: null,
  top_products: [{ name: 'Soda', qty: 40, sales: 100000, profit: 40000 }],
  top_customers: [],
  slow_stock: [{ name: 'Dusty Dye', quantity: 50, value: 100000 }],
  debtors: [{ name: 'Baba Juma', owed: 90000, days: 200 }],
  ...over,
});

const advice = { items: [{ level: 'warning', title: 'Collect from Baba Juma', detail: 'Baba Juma owes TSh 90,000.' }, { level: 'good', title: 'Soda is carrying you', detail: 'Soda earned TSh 40,000.' }], source: 'ai', ai_available: true, refreshes_left: 4 };

async function open(who = {}, answers: { report?: object; advice?: object } = {}) {
  const h = configure(who);
  const fixture = TestBed.createComponent(DashboardPage);
  fixture.detectChanges();
  const month = monthKey(new Date());
  h.http.expectOne((r) => r.url === `${environment.apiUrl}/inventory/monthly-report` && r.params.get('month') === month).flush({ data: answers.report ?? report(month) });
  await settle(fixture);
  h.http.expectOne((r) => r.url === `${environment.apiUrl}/inventory/advice`).flush({ data: answers.advice ?? advice });
  await settle(fixture);

  return { h, fixture, el: fixture.nativeElement as HTMLElement, month };
}

describe('dashboard (this month)', () => {
  it('asks for this month and shows the headline, the four figures and where the business stands', async () => {
    const { el } = await open();

    expect(text(byTestId(el, 'headline')!)).toContain('Better than');
    expect(text(byTestId(el, 'headline')!)).toContain('50%');
    expect(text(byTestId(el, 'headline')!)).toContain('Profit TSH 120,000 against TSH 80,000');
    const cards = text(el);
    expect(cards).toContain('TSH 300,000');
    expect(cards).toContain('TSH 150,000');
    expect(cards).toContain('TSH 120,000');
    expect(cards).toContain('Stock (at cost)');
    expect(cards).toContain('TSH 1,000,000');
    expect(cards).toContain('Capital grew by TSH 200,000 since last month');
    expect(cards).toContain('Personal spending (not taken off the profit): TSH 7,000');
  });

  it('names the products and the people behind the numbers', async () => {
    const { el } = await open();
    const all = text(el);
    expect(all).toContain('Soda');
    expect(all).toContain('Baba Juma');
    expect(all).toContain('200 days');
    expect(all).toContain('Dusty Dye');
    expect(all).toContain('Rent');
    expect(all).toContain('Transport');
  });

  it('shows advice, marked as coming from the AI, each in its own colour', async () => {
    const { el } = await open();
    expect(text(byTestId(el, 'advice-source')!)).toBe('AI');
    expect(text(el)).toContain('Collect from Baba Juma');
    expect(el.querySelectorAll('.advice').length).toBe(2);
    expect(el.querySelector('.advice--warning')).not.toBeNull();
    expect(el.querySelector('.advice--good')).not.toBeNull();
  });

  it('asks for fresh advice, and says so when the AI could not be reached', async () => {
    const { h, fixture, el } = await open({}, { advice: { items: [{ level: 'tip', title: 'Set a profit target', detail: 'x' }], source: 'rules', ai_available: true, refreshes_left: 5 } });
    expect(text(el)).toContain("could not be reached");
    expect(text(byTestId(el, 'advice-source')!)).toBe('From your numbers');

    (Array.from(el.querySelectorAll('button')).find((b) => b.textContent?.includes('New advice')) as HTMLButtonElement).click();
    h.http.expectOne((r) => r.url === `${environment.apiUrl}/inventory/advice` && r.params.get('refresh') === '1').flush({ data: advice });
    await settle(fixture);
    expect(text(byTestId(el, 'advice-source')!)).toBe('AI');
  });

  it('the arrows load the month before, and the page cannot go past the month after this one', async () => {
    const { h, fixture, el, month } = await open();

    (el.querySelector('[aria-label="Previous month"]') as HTMLButtonElement).click();
    const before = shiftMonth(month, -1);
    h.http.expectOne((r) => r.params.get('month') === before && r.url.endsWith('/monthly-report')).flush({ data: report(before, { is_current: false }) });
    await settle(fixture);
    h.http.expectOne((r) => r.url.endsWith('/advice')).flush({ data: advice });
    await settle(fixture);
    expect(text(byTestId(el, 'month-title')!)).toMatch(/\d{4}/);
    expect(text(el)).not.toContain('The month is still going');

    (el.querySelector('[aria-label="Next month"]') as HTMLButtonElement).click(); // back to this month
    h.http.expectOne((r) => r.params.get('month') === month && r.url.endsWith('/monthly-report')).flush({ data: report(month) });
    await settle(fixture);
    h.http.expectOne((r) => r.url.endsWith('/advice')).flush({ data: advice });
    await settle(fixture);
    (el.querySelector('[aria-label="Next month"]') as HTMLButtonElement).click(); // the month after
    const after = shiftMonth(month, 1);
    h.http.expectOne((r) => r.params.get('month') === after && r.url.endsWith('/monthly-report')).flush({ data: report(after, { is_current: false, is_future: true }) });
    await settle(fixture);
    expect((el.querySelector('[aria-label="Next month"]') as HTMLButtonElement).disabled).toBe(true);
    h.http.expectNone((r) => r.url.endsWith('/advice')); // no advice for a month that has not begun
  });

  describe('the profit target', () => {
    const target = { profit_target: 300000, profit: 120000, progress_percent: 40, left: 180000, over_by: 0, expected_by_today: 100000, days_left: 20, status: 'on_track' };

    it('shows how close the month is, with what is left and what it should be by today', async () => {
      const { el } = await open({}, { report: report(monthKey(new Date()), { target }) });
      expect(text(byTestId(el, 'target')!)).toContain('TSH 120K');
      expect(text(byTestId(el, 'target')!)).toContain('TSH 300K');
      expect(text(byTestId(el, 'target-status')!)).toBe('On track');
      expect(text(byTestId(el, 'target-line')!)).toBe('TSH 180,000 to go · 20 days left · by today you should have TSH 100,000');
    });

    it('a person with the settings right can set it: the amount is written like a person writes it', async () => {
      const { h, fixture, el, month } = await open({ permissions: ['inv_view_reports', 'inv_manage_settings'] });
      (Array.from(el.querySelectorAll('button')).find((b) => b.textContent?.includes('Set a profit target')) as HTMLButtonElement).click();
      fixture.detectChanges();
      await settle(fixture);

      type(el, '#targetAmount', '2,000,000');
      (Array.from(el.querySelectorAll('button')).find((b) => b.textContent?.trim() === 'Save') as HTMLButtonElement).click();
      const req = h.http.expectOne((r) => r.url.endsWith('/monthly-target'));
      expect(req.request.method).toBe('PUT');
      expect(req.request.body).toEqual({ month, profit_target: 2000000 });
      req.flush({ data: { profit_target: 2000000 } });
      await settle(fixture);
      h.http.expectOne((r) => r.url.endsWith('/monthly-report')).flush({ data: report(month, { target }) });
      await settle(fixture);
      h.http.expectOne((r) => r.url.endsWith('/advice')).flush({ data: advice });
      await settle(fixture);
      expect(byTestId(el, 'target')).not.toBeNull();
    });

    it('rejects an amount that is not a number, before asking the server', async () => {
      const { h, fixture, el } = await open({ permissions: ['inv_view_reports', 'inv_manage_settings'] });
      (Array.from(el.querySelectorAll('button')).find((b) => b.textContent?.includes('Set a profit target')) as HTMLButtonElement).click();
      await settle(fixture);
      type(el, '#targetAmount', 'two million');
      (Array.from(el.querySelectorAll('button')).find((b) => b.textContent?.trim() === 'Save') as HTMLButtonElement).click();
      await settle(fixture);

      expect(text(el)).toContain('Write the amount in numbers');
      h.http.expectNone((r) => r.url.endsWith('/monthly-target'));
    });

    it('someone without that right sees the target but is not offered to change it', async () => {
      const { el } = await open({}, { report: report(monthKey(new Date()), { target }) });
      expect(byTestId(el, 'target')).not.toBeNull();
      expect(Array.from(el.querySelectorAll('button')).some((b) => b.textContent?.trim() === 'Change')).toBe(false);
    });

    it('and with no target set, such a person is not offered to set one', async () => {
      const { el } = await open({});
      expect(Array.from(el.querySelectorAll('button')).some((b) => b.textContent?.includes('Set a profit target'))).toBe(false);
    });
  });

  it('a failed load says why and offers to try again', async () => {
    const h = configure({});
    const fixture = TestBed.createComponent(DashboardPage);
    fixture.detectChanges();
    h.http.expectOne((r) => r.url.endsWith('/monthly-report')).flush({ message: 'Mwezi si sahihi' }, { status: 422, statusText: 'Unprocessable' });
    await settle(fixture);
    const el = fixture.nativeElement as HTMLElement;

    expect(el.querySelector('[role=alert]')?.textContent).toContain('Mwezi si sahihi');
    expect(text(el)).toContain('Try again');
  });

  it('offline says so in plain words', async () => {
    const h = configure({});
    const fixture = TestBed.createComponent(DashboardPage);
    fixture.detectChanges();
    h.http.expectOne((r) => r.url.endsWith('/monthly-report')).error(new ProgressEvent('error'), { status: 0 });
    await settle(fixture);
    expect(text(fixture.nativeElement)).toContain('Cannot reach the server');
  });

  it('in Swahili the page is Swahili', async () => {
    const h = configure({});
    h.i18n.setLang('sw');
    const fixture = TestBed.createComponent(DashboardPage);
    fixture.detectChanges();
    const month = monthKey(new Date());
    h.http.expectOne((r) => r.url.endsWith('/monthly-report')).flush({ data: report(month) });
    await settle(fixture);
    h.http.expectOne((r) => r.url.endsWith('/advice') && r.params.get('lang') === 'sw').flush({ data: advice });
    await settle(fixture);
    const all = text(fixture.nativeElement);

    expect(all).toContain('Umefanya vizuri kuliko');
    expect(all).toContain('Biashara ilipo');
    expect(all).toContain('Mauzo');
    expect(all).not.toContain('Better than');
  });
});
