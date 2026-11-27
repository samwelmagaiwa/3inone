import { Directive, inject, signal } from '@angular/core';

import { dayLabel, eatDateTime, serverMessage, today, tsh } from '../../core/format';
import { GroupsApi } from '../../core/groups/groups-api.service';
import { GroupsContext } from '../../core/groups/groups-context.service';
import { I18nService } from '../../core/i18n.service';
import { ConfirmService } from '../../core/services/confirm.service';
import { ToastService } from '../../core/services/toast.service';

/** The ways money moves, as the server knows them. */
export const G_METHODS = ['cash', 'mpesa', 'mixx', 'airtel_money', 'halopesa', 'bank_transfer', 'other'];

/**
 * What every Groups (Vikundi) page shares: the calls, who the person is in the group, the two languages, the yes/no and reason popups,
 * and one way to run an action (busy while it runs, the server's own words when it is refused, a short "done" when it worked).
 */
@Directive()
export abstract class GBase {
  protected readonly api = inject(GroupsApi);
  protected readonly ctx = inject(GroupsContext);
  protected readonly i18n = inject(I18nService);
  private readonly confirm = inject(ConfirmService);
  private readonly toast = inject(ToastService);

  protected readonly tsh = tsh;
  protected readonly day = dayLabel;
  protected readonly when = eatDateTime;
  protected readonly today = today;
  protected readonly methods = G_METHODS;
  protected readonly busy = signal(false);

  /** A count or figure from the server, 0 when it is missing. */
  protected n(v: unknown, fallback = 0): number {
    const x = Number(v);
    return v === null || v === undefined || v === '' || !Number.isFinite(x) ? fallback : x;
  }

  /** A whole number of shillings from what was typed ("1,500,000" or "1500000"); 0 when it is not one. */
  protected amount(v: unknown): number {
    const n = Number(String(v ?? '').replace(/[,\s]/g, ''));
    return Number.isFinite(n) ? n : 0;
  }

  /** Runs [fn]; true when it worked. A refusal shows the server's words; [done] is shown when it worked. */
  protected async act(fn: () => Promise<unknown>, done?: string): Promise<boolean> {
    if (this.busy()) return false;
    this.busy.set(true);
    try {
      await fn();
      if (done) this.toast.success(done, this.i18n.t('g.ok'));
      return true;
    } catch (e) {
      this.toast.error(serverMessage(e) ?? this.i18n.t('pl.error'), this.i18n.t('g.refused'));
      return false;
    } finally {
      this.busy.set(false);
    }
  }

  /** A short "done" note. */
  protected done(message: string): void {
    this.toast.success(message, this.i18n.t('g.ok'));
  }

  /** Something is missing in a form: say what, and do nothing else. */
  protected stop(message: string): void {
    this.toast.warning(message, this.i18n.t('g.check'));
  }

  /** The error of a page that could not load: the server's words, else the plain "could not load". */
  protected failed(e: unknown): string {
    return serverMessage(e) ?? this.i18n.t('pl.error');
  }

  /** A yes/no question before something is done. */
  protected sure(title: string, message: string, yes: string, danger = false): Promise<boolean> {
    return this.confirm.ask({ title, message, danger, confirmLabel: yes, cancelLabel: this.i18n.t('common.cancel') });
  }

  /** A question that needs a reason written; null when cancelled. */
  protected reason(title: string, message: string, yes: string, danger = true): Promise<string | null> {
    return this.confirm.askText({ title, message, danger, confirmLabel: yes, cancelLabel: this.i18n.t('common.cancel'), placeholder: this.i18n.t('g.reason.ph') });
  }

  protected can(...rights: string[]): boolean {
    return this.ctx.can(...rights);
  }

  // ---------------------------------------------------------------- words for the server's values
  protected cat(c: string): string {
    return this.i18n.t('g.cat.' + c);
  }

  protected method(m: string): string {
    return this.i18n.t('g.method.' + m);
  }

  protected office(o: string | null | undefined): string {
    return o ? this.i18n.t('g.office.' + o) : this.i18n.t('g.office.none');
  }

  /** A status word of any kind of record (pending, verified, approved, active, ...). */
  protected status(s: string | null | undefined): string {
    return s ? this.i18n.t('g.st.' + s) : '';
  }

  /** The colour of a status: green done, amber waiting, red refused or overdue. */
  protected tone(s: string | null | undefined): string {
    switch (s) {
      case 'verified': case 'active': case 'approved': case 'paid': case 'completed': case 'closed': case 'done': case 'published': case 'sent': case 'returned':
        return 'ph-good';
      case 'rejected': case 'declined': case 'cancelled': case 'overdue': case 'suspended': case 'exited': case 'deceased': case 'reversed': case 'failed':
        return 'ph-bad';
      default:
        return 'ph-warn';
    }
  }
}
