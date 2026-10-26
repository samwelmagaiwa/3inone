/** 45000 -> "TSH 45,000"; negative amounts keep their sign. */
export function tsh(amount: number): string {
  const digits = Math.abs(Math.round(amount)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return `TSH ${amount < 0 ? '-' : ''}${digits}`;
}

/** 1250000 -> "1.25M", 45000 -> "45K", 9500 -> "9,500": for a headline where the full number would crowd. */
export function shortMoney(amount: number): string {
  const a = Math.abs(amount);
  const sign = amount < 0 ? '-' : '';
  const trim = (v: number) => v.toFixed(2).replace(/0+$/, '').replace(/\.$/, '');
  if (a >= 1_000_000) return `${sign}TSH ${trim(a / 1_000_000)}M`;
  if (a >= 10_000) return `${sign}TSH ${trim(a / 1_000)}K`;
  return tsh(amount);
}

/** A date as the user reads it: 05/11/2026. */
export function dayLabel(iso: string | null | undefined): string {
  if (!iso) return '';
  const [y, m, d] = iso.slice(0, 10).split('-');
  return `${d}/${m}/${y}`;
}

/** Today as 2026-11-05 (the computer's own date). */
export function today(): string {
  return dayOf(new Date());
}

export function dayOf(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

/** A date -> "2026-11". */
export function monthKey(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
}

/** "2026-01" moved by -1 -> "2025-12". */
export function shiftMonth(key: string, by: number): string {
  const [year, month] = key.split('-').map(Number);
  return monthKey(new Date(year, month - 1 + by, 1));
}

/** "2026-11" -> the month and year in the given locale ("novemba 2026" / "November 2026"). */
export function monthName(key: string, locale: string): string {
  const [year, month] = key.split('-').map(Number);
  const name = new Date(year, month - 1, 1).toLocaleDateString(locale, { month: 'long', year: 'numeric' });
  return name.charAt(0).toUpperCase() + name.slice(1);
}

/** What a number typed with commas or spaces means ("1,250,000" -> 1250000); NaN when it is not a number. */
export function parseAmount(text: string): number {
  const clean = text.replace(/[,\s]/g, '');
  return /^\d+(\.\d+)?$/.test(clean) ? Number(clean) : NaN;
}

/** The words of a failed request: the server's own message, or its first validation error, or null (the caller then has a plain fallback). */
export function serverMessage(err: unknown): string | null {
  const e = err as { status?: number; error?: { message?: string; errors?: Record<string, string[]> } };
  const firstError = e?.error?.errors ? Object.values(e.error.errors)[0]?.[0] : undefined;
  return firstError || e?.error?.message || null;
}

/** True when the browser could not reach the server at all. */
export function offline(err: unknown): boolean {
  return (err as { status?: number })?.status === 0;
}
