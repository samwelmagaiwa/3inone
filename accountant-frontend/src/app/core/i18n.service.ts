import { Injectable, effect, signal } from '@angular/core';

import { Lang, TRANSLATIONS } from './translations';

const KEY = 'accountant_lang';

function saved(): Lang | null {
  try {
    const v = localStorage.getItem(KEY);
    return v === 'sw' || v === 'en' ? v : null;
  } catch {
    return null;
  }
}

/**
 * The words of the app in Swahili or English. Swahili is where the app starts (the people using it are, like the mobile app's users,
 * mostly Swahili speakers); the choice is kept on this computer. `t()` reads the language signal, so every text on screen
 * changes the moment the language does.
 */
@Injectable({ providedIn: 'root' })
export class I18nService {
  readonly lang = signal<Lang>(saved() ?? 'sw');

  constructor() {
    // the page's own language, for screen readers and for the calendar and dropdown (plain DOM) that read it
    effect(() => {
      if (typeof document !== 'undefined') document.documentElement.lang = this.lang();
    });
  }

  setLang(lang: Lang): void {
    this.lang.set(lang);
    try {
      localStorage.setItem(KEY, lang);
    } catch {
      // the choice then lasts until the page is closed
    }
  }

  toggle(): void {
    this.setLang(this.lang() === 'sw' ? 'en' : 'sw');
  }

  /** A text by its key; `{0}`, `{1}` are filled from `params`. A key nobody wrote shows as itself, so it is easy to spot. */
  t(key: string, ...params: (string | number)[]): string {
    const text = TRANSLATIONS[this.lang()][key] ?? TRANSLATIONS.en[key] ?? key;
    return params.reduce<string>((s, p, i) => s.split(`{${i}}`).join(String(p)), text);
  }

  /** For dates and numbers. */
  locale(): string {
    return this.lang() === 'sw' ? 'sw-TZ' : 'en-GB';
  }
}
