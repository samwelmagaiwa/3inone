import { readFileSync } from 'node:fs';
import { join } from 'node:path';

/**
 * Every label with a red asterisk (class "req") belongs to a field that is really required (the control has `required`, or `[required]`
 * while a condition holds), so what the screen says and what the browser checks cannot drift apart.
 */
const PAGES = ['branch-stock/branch-stock', 'branches/branches', 'credit/credit', 'debts/debts', 'expenses/expenses', 'products/products', 'sales/sales', 'till/till'];

function html(page: string): string {
  return readFileSync(join(process.cwd(), 'src/app/pages', `${page}.html`), 'utf8');
}

function startTag(source: string, id: string): string | null {
  const at = source.indexOf(`id="${id}"`);
  if (at < 0) return null;
  const start = Math.max(source.lastIndexOf('<input', at), source.lastIndexOf('<select', at), source.lastIndexOf('<textarea', at));
  let quote = '';
  for (let i = start; i < source.length; i++) {
    const c = source[i];
    if (quote) {
      if (c === quote) quote = '';
    } else if (c === '"' || c === "'") quote = c;
    else if (c === '>') return source.slice(start, i + 1);
  }
  return null;
}

const isRequired = (tag: string) => / required|\[required\]/.test(tag);

describe('required fields', () => {
  for (const page of PAGES) {
    it(`${page}: a label with an asterisk has a required control, and every required control has an asterisk`, () => {
      const source = html(page);
      const labels = [...source.matchAll(/<label class="modal-label(?: req)?"([^>]*?)for="([^"]+)"/g)].map((m) => ({ id: m[2], star: m[0].includes(' req"') || m[1].includes('[class.req]') }));

      const stars = labels.filter((l) => l.star);
      expect(stars.length).toBeGreaterThan(0);
      for (const l of stars) {
        const tag = startTag(source, l.id);
        expect(tag, `${page}: no control with id ${l.id}`).not.toBeNull();
        expect(isRequired(tag ?? ''), `${page}: #${l.id} has an asterisk but is not required`).toBe(true);
      }
      // the other way round: a required control that has a label must show the asterisk
      for (const m of source.matchAll(/<(?:input|select|textarea)\b[^>]*\bid="([^"]+)"[^>]*>/g)) {
        const tag = startTag(source, m[1]) ?? '';
        if (!isRequired(tag)) continue;
        const label = labels.find((l) => l.id === m[1]);
        if (label) expect(label.star, `${page}: #${m[1]} is required but its label has no asterisk`).toBe(true);
      }
    });
  }

  it('the text fields of the main forms all have a placeholder', () => {
    const missing: string[] = [];
    for (const page of ['expenses/expenses', 'debts/debts', 'branches/branches', 'products/products']) {
      const source = html(page);
      for (const m of source.matchAll(/<input\b[^>]*\bid="([^"]+)"[^>]*>/g)) {
        const tag = startTag(source, m[1]) ?? '';
        if (/type="(date|file|checkbox|radio)"/.test(tag) || /placeholder/.test(tag)) continue;
        missing.push(`${page}#${m[1]}`);
      }
    }
    expect(missing).toEqual([]);
  });
});
