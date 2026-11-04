import { monthName } from './format';
import { I18nService } from './i18n.service';
import { MonthlyReport } from './models';

/** "Better than October 2026 by 12%": how the month compares with the one before, in the current language. */
export function headlineText(r: MonthlyReport, i18n: I18nService): string {
  const prev = monthName(r.previous.month, i18n.locale());
  const p = r.overall.percent;
  const pct = p === null ? '' : ` ${Math.abs(p).toFixed(Math.abs(p) >= 10 ? 0 : 1)}%`;
  const key = r.overall.direction === 'up' ? 'headline.up' : r.overall.direction === 'down' ? 'headline.down' : 'headline.same';

  return i18n.t(key, prev, pct);
}
