import { HttpClient } from '@angular/common/http';
import { Component, computed, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';

import { environment } from '../../../environments/environment';
import { AuthService } from '../../core/auth.service';
import { dayLabel, dayOf, serverMessage } from '../../core/format';
import { I18nService } from '../../core/i18n.service';
import { MenuItem, RowMenuComponent } from '../../shared/components/row-menu/row-menu';

export const EXPORT_TYPES = ['sales', 'expenses', 'payroll', 'stylists', 'profit-loss', 'tax', 'cashbook'] as const;
export type ExportType = (typeof EXPORT_TYPES)[number];

/** The right each report needs (the same ones the server checks, so a chip is shown only when the file would be given). */
export const EXPORT_RIGHTS: Record<ExportType, string> = {
  sales: 'inv_salon_money',
  expenses: 'inv_view_expenses',
  payroll: 'inv_salon_payroll',
  stylists: 'inv_salon_stylists',
  'profit-loss': 'inv_salon_profit',
  tax: 'inv_salon_money',
  cashbook: 'inv_salon_cashbook',
};

export type ExportPeriod = 'today' | 'month' | 'last';

/** The first and last day of the three periods the phone offers. */
export function exportRange(p: ExportPeriod, now: Date): [string, string] {
  const t = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  if (p === 'today') return [dayOf(t), dayOf(t)];
  if (p === 'last') return [dayOf(new Date(t.getFullYear(), t.getMonth() - 1, 1)), dayOf(new Date(t.getFullYear(), t.getMonth(), 0))];

  return [dayOf(new Date(t.getFullYear(), t.getMonth(), 1)), dayOf(t)];
}

/** The server address of one report as a file, the way the phone asks for it. */
export function exportUrl(type: ExportType, format: 'pdf' | 'csv', lang: string, from: string, to: string): string {
  return `${environment.apiUrl}/inventory/salon/export/${type}?format=${format}&lang=${lang === 'sw' ? 'sw' : 'en'}&from=${from}&to=${to}&month=${to.substring(0, 7)}`;
}

@Component({
  selector: 'app-export',
  imports: [RowMenuComponent],
  template: `
    <div class="ad ph-page" data-testid="export-page">
      <!-- the period and the file kind stay pinned; every report is a row with its three dots -->
      <div class="g-pin">
        <div class="g-toolbar">
          <div class="ph-chips g-seg">
            <button type="button" class="pill-tab" [class.is-active]="period() === 'today'" (click)="period.set('today')" data-testid="ex-today">{{ i18n.t('pl.p.today') }}</button>
            <button type="button" class="pill-tab" [class.is-active]="period() === 'month'" (click)="period.set('month')" data-testid="ex-month">{{ i18n.t('pl.p.thisMonth') }}</button>
            <button type="button" class="pill-tab" [class.is-active]="period() === 'last'" (click)="period.set('last')" data-testid="ex-last">{{ i18n.t('pl.p.lastMonth') }}</button>
          </div>
          <div class="ph-chips g-seg">
            <button type="button" class="pill-tab" [class.is-active]="format() === 'pdf'" (click)="format.set('pdf')" data-testid="ex-pdf">PDF</button>
            <button type="button" class="pill-tab" [class.is-active]="format() === 'csv'" (click)="format.set('csv')" data-testid="ex-csv">CSV</button>
          </div>
          <span class="ph-muted">{{ rangeLabel() }}</span>
        </div>
        <div class="ph-tiles g-tiles-row" data-testid="ex-tiles">
          <div class="ph-tile g-t-teal"><span class="ph-muted">{{ i18n.t('ex.period') }}</span><b>{{ rangeLabel() }}</b></div>
          <div class="ph-tile g-t-blue"><span class="ph-muted">{{ i18n.t('ex.format') }}</span><b>{{ format().toUpperCase() }}</b></div>
          <div class="ph-tile g-t-purple"><span class="ph-muted">{{ i18n.t('ex.reports') }}</span><b>{{ allowed().length }}</b></div>
          <div class="ph-tile g-t-green"><span class="ph-muted">{{ i18n.t('ex.language') }}</span><b>{{ i18n.lang() === 'sw' ? 'Kiswahili' : 'English' }}</b></div>
        </div>
      </div>

      <div class="table-scroll-container fit-page ex-wide">
        <table class="grid-table g-grid" data-testid="ex-table">
          <thead><tr>
            <th class="no-col">#</th><th>{{ i18n.t('ex.report') }}</th><th>{{ i18n.t('ex.holds') }}</th><th class="text-right">{{ i18n.t('g.actions') }}</th>
          </tr></thead>
          <tbody>
            @for (t of allowed(); track t) {
              <tr [attr.data-testid]="'ex-type-' + t" [class.ex-busy]="busy() && type() === t">
                <td class="no-col">{{ $index + 1 }}</td>
                <td class="font-bold">{{ typeName(t) }}</td>
                <td class="ph-muted">{{ i18n.t('ex.d.' + t) }}</td>
                <td class="text-right"><app-row-menu [items]="menuFor()" [testid]="'ex-menu-' + t" (picked)="get(t, $event)" /></td>
              </tr>
            } @empty {
              <tr><td colspan="4" class="ph-muted" data-testid="ex-none">{{ i18n.t('ex.none') }}</td></tr>
            }
          </tbody>
        </table>
      </div>
      @if (busy()) { <p class="ph-muted ex-wide">{{ i18n.t('common.saving') }}</p> }
      @if (error()) { <p class="ph-bad ex-wide" data-testid="ex-error">{{ error() }}</p> }
    </div>
  `,
  styles: [`.ex-wide { grid-column: 1 / -1; } tr.ex-busy td { opacity: 0.6; }`],
})
export class ExportPage {
  private readonly http = inject(HttpClient);
  private readonly auth = inject(AuthService);
  protected readonly i18n = inject(I18nService);

  protected readonly type = signal<ExportType>('sales');
  protected readonly period = signal<ExportPeriod>('month');
  protected readonly format = signal<'pdf' | 'csv'>('pdf');
  protected readonly busy = signal(false);
  protected readonly error = signal('');

  protected readonly allowed = computed(() => EXPORT_TYPES.filter((t) => this.auth.can(EXPORT_RIGHTS[t])));
  protected readonly rangeLabel = computed(() => {
    const [a, b] = exportRange(this.period(), new Date());
    return a === b ? dayLabel(a) : `${dayLabel(a)} – ${dayLabel(b)}`;
  });

  /** The row's three dots: the file in the kind chosen first, then the other kind. */
  protected menuFor(): MenuItem[] {
    const other = this.format() === 'pdf' ? 'csv' : 'pdf';
    return [
      { id: this.format(), label: this.i18n.t('ex.download.as', this.format().toUpperCase()), primary: true },
      { id: other, label: this.i18n.t('ex.download.as', other.toUpperCase()) },
    ];
  }

  /** Download one report in the kind picked from its menu. */
  protected async get(t: ExportType, kind: string): Promise<void> {
    this.type.set(t);
    this.format.set(kind === 'csv' ? 'csv' : 'pdf');
    await this.download();
  }

  protected typeName(t: ExportType): string {
    switch (t) {
      case 'sales': return this.i18n.t('ex.t.sales');
      case 'expenses': return this.i18n.t('pl.expenses');
      case 'payroll': return this.i18n.t('ex.t.payroll');
      case 'stylists': return this.i18n.t('nav.ph.stylists');
      case 'profit-loss': return this.i18n.t('ex.t.pl');
      case 'cashbook': return this.i18n.t('nav.cashbook');
      default: return this.i18n.t('ex.t.tax');
    }
  }

  protected async download(): Promise<void> {
    const list = this.allowed();
    const type = list.includes(this.type()) ? this.type() : list[0];
    if (!type) return;
    const [from, to] = exportRange(this.period(), new Date());
    this.busy.set(true);
    this.error.set('');
    try {
      const blob = await firstValueFrom(this.http.get(exportUrl(type, this.format(), this.i18n.lang(), from, to), { responseType: 'blob' }));
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `salon_${type}_${to}.${this.format()}`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 2000);
    } catch (e) {
      this.error.set(serverMessage(e) || this.i18n.t('pl.error'));
    }
    this.busy.set(false);
  }
}
