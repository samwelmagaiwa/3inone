import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

import { TestBed } from '@angular/core/testing';

import { I18nService } from './i18n.service';
import { TRANSLATIONS } from './translations';

const { en, sw } = TRANSLATIONS;

function sourceFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return sourceFiles(path);
    return /\.(ts|html)$/.test(name) && !name.endsWith('.spec.ts') && name !== 'translations.ts' && name !== 'testing.ts' ? [path] : [];
  });
}

describe('translations', () => {
  it('Swahili and English have exactly the same texts to write', () => {
    expect(Object.keys(sw).sort()).toEqual(Object.keys(en).sort());
  });

  it('no text is empty, and both languages fill the same {0} {1} blanks', () => {
    const blanks = (s: string) => (s.match(/\{\d\}/g) ?? []).sort().join(',');
    for (const key of Object.keys(en)) {
      expect(en[key].trim(), key).not.toBe('');
      expect(sw[key].trim(), key).not.toBe('');
      expect(blanks(sw[key]), `blanks of ${key}`).toBe(blanks(en[key]));
    }
  });

  it('every key the code asks for exists (a missing one would show as its own name)', () => {
    const used = new Set<string>();
    for (const file of sourceFiles('src/app')) {
      const source = readFileSync(file, 'utf8');
      for (const m of source.matchAll(/(?:i18n\.t|[^a-zA-Z.]t)\(\s*'([a-z0-9_.]+)'/g)) used.add(m[1]);
      for (const m of source.matchAll(/(?:labelKey|hintKey):\s*'([a-z0-9_.]+)'/g)) used.add(m[1]);
      // keys inside a ternary: i18n.t(cond ? 'a.b' : 'c.d')
      for (const call of source.matchAll(/i18n\.t\(([^()]*\?[^()]*)\)/g)) for (const m of call[1].matchAll(/'([a-z0-9_.]+)'/g)) used.add(m[1]);
    }
    const missing = [...used].filter((k) => !k.endsWith('.') && !(k in en));
    expect(missing).toEqual([]);
    expect(used.size).toBeGreaterThan(100);
  });

  it('the keys built from a value have a text for every value the server can send', () => {
    const families: Record<string, string[]> = {
      'period.': ['today', 'week', 'month', 'year'],
      'sales.status.': ['all', 'paid', 'partial', 'debt'],
      'target.status.': ['not_started', 'on_track', 'behind', 'reached', 'missed'],
      'cat.': ['rent', 'salaries', 'transport', 'utilities', 'supplies', 'maintenance', 'marketing', 'licences', 'loan_repayment', 'drawings', 'family', 'other'],
      'pay.': ['cash', 'mobile_money', 'bank_transfer', 'mpesa', 'mixx', 'airtel_money', 'halopesa'],
      'service.': ['inventory', 'salon'],
    };
    for (const [prefix, values] of Object.entries(families)) for (const v of values) expect(prefix + v in en, prefix + v).toBe(true);
  });

  it('a screen is never half in one language: no Swahili-only word in English texts and the reverse', () => {
    // words that only Swahili uses, which must not be in an English text
    const swahiliOnly = ['mauzo', 'madeni', 'matumizi', 'nywila', 'tafadhali', 'biashara', 'hesabu'];
    for (const [key, text] of Object.entries(en)) for (const w of swahiliOnly) expect(text.toLowerCase().split(/\W+/), `${key} (en)`).not.toContain(w);
    // and English words that must not leak into Swahili texts (product names and codes are allowed)
    const englishOnly = ['please', 'sales', 'debts', 'expenses', 'password', 'business'];
    for (const [key, text] of Object.entries(sw)) for (const w of englishOnly) expect(text.toLowerCase().split(/\W+/), `${key} (sw)`).not.toContain(w);
  });
});

describe('I18nService', () => {
  it('fills blanks, falls back to English, and shows an unknown key as itself', () => {
    localStorage.clear();
    const i18n = TestBed.runInInjectionContext(() => new I18nService());
    i18n.setLang('en');
    expect(i18n.t('login.welcome', 'Amina')).toBe('Welcome back, Amina.');
    i18n.setLang('sw');
    expect(i18n.t('login.welcome', 'Amina')).toBe('Karibu tena, Amina.');
    expect(i18n.t('no.such.key')).toBe('no.such.key');
    expect(localStorage.getItem('accountant_lang')).toBe('sw');
  });

  it('starts in Swahili and remembers the choice', () => {
    localStorage.clear();
    expect(TestBed.runInInjectionContext(() => new I18nService()).lang()).toBe('sw');
    localStorage.setItem('accountant_lang', 'en');
    expect(TestBed.runInInjectionContext(() => new I18nService()).lang()).toBe('en');
  });
});
