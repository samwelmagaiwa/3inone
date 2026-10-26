import { AfterViewInit, Directive, ElementRef, OnDestroy, PLATFORM_ID, Optional, Self, inject } from '@angular/core';
import { isPlatformBrowser } from '@angular/common';
import { NgModel } from '@angular/forms';
import { Subscription } from 'rxjs';
import { CALENDAR_ICON, openPopover } from './bs-popover';
import { uiText } from './ui-text';

const pad = (n: number) => String(n).padStart(2, '0');
const toIso = (y: number, m: number, d: number) => `${y}-${pad(m + 1)}-${pad(d)}`;
const parseIso = (v: string): { y: number; m: number; d: number } | null => {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(v || '');
  return m ? { y: +m[1], m: +m[2] - 1, d: +m[3] } : null;
};

/**
 * Replaces the browser's date picker with a calendar that matches the app.
 * The real <input type="date"> stays in the DOM (hidden), so ngModel, min/max and (change) keep working.
 */
@Directive({ selector: 'input[type=date]', standalone: true })
export class BsDateDirective implements AfterViewInit, OnDestroy {
  private host = inject<ElementRef<HTMLInputElement>>(ElementRef);
  private isBrowser = isPlatformBrowser(inject(PLATFORM_ID));

  private trigger?: HTMLButtonElement;
  private labelEl?: HTMLElement;
  private observer?: MutationObserver;
  private sub?: Subscription;
  private closePopover?: () => void;

  constructor(@Optional() @Self() private ngModel: NgModel | null) {}

  ngAfterViewInit() {
    if (!this.isBrowser) return;
    const input = this.host.nativeElement;

    const trigger = document.createElement('button');
    trigger.type = 'button';
    trigger.className = `${input.className} bs-trigger`;
    const style = input.getAttribute('style');
    if (style) trigger.setAttribute('style', style);
    trigger.setAttribute('aria-haspopup', 'dialog');
    trigger.setAttribute('aria-expanded', 'false');
    trigger.innerHTML = `<span class="bs-trigger-label"></span>${CALENDAR_ICON}`;
    this.labelEl = trigger.querySelector('.bs-trigger-label') as HTMLElement;
    this.trigger = trigger;

    input.parentNode?.insertBefore(trigger, input);
    input.classList.add('bs-native-hidden');
    input.tabIndex = -1;

    trigger.addEventListener('click', () => (this.closePopover ? this.closePopover() : this.open()));
    input.addEventListener('input', this.sync);
    input.addEventListener('change', this.sync);

    this.observer = new MutationObserver(this.sync);
    this.observer.observe(input, { attributes: true, attributeFilter: ['disabled', 'min', 'max', 'value'] });
    this.sub = this.ngModel?.valueChanges?.subscribe(() => queueMicrotask(this.sync));

    this.sync();
    setTimeout(this.sync, 0);
  }

  ngOnDestroy() {
    this.closePopover?.();
    this.observer?.disconnect();
    this.sub?.unsubscribe();
    this.host.nativeElement.removeEventListener('input', this.sync);
    this.host.nativeElement.removeEventListener('change', this.sync);
    this.trigger?.remove();
  }

  private sync = () => {
    const input = this.host.nativeElement;
    if (!this.trigger || !this.labelEl) return;
    const p = parseIso(input.value);
    if (p) {
      const date = new Date(p.y, p.m, p.d);
      this.labelEl.textContent = date.toLocaleDateString(uiText().locale, { weekday: 'short', day: '2-digit', month: 'short', year: 'numeric' });
      this.labelEl.classList.remove('is-placeholder');
    } else {
      this.labelEl.textContent = uiText().selectDate;
      this.labelEl.classList.add('is-placeholder');
    }
    this.trigger.disabled = input.disabled;
  };

  private open() {
    const input = this.host.nativeElement;
    const trigger = this.trigger;
    if (!trigger || input.disabled) return;

    const selected = parseIso(input.value);
    const today = new Date();
    const min = parseIso(input.min);
    const max = parseIso(input.max);
    let view = { y: selected?.y ?? today.getFullYear(), m: selected?.m ?? today.getMonth() };
    let mode: 'days' | 'months' = 'days';

    const pop = document.createElement('div');
    pop.className = 'bs-cal';
    pop.setAttribute('role', 'dialog');
    pop.setAttribute('aria-label', 'Choose a date');

    const isoMin = min ? toIso(min.y, min.m, min.d) : '';
    const isoMax = max ? toIso(max.y, max.m, max.d) : '';
    const todayIso = toIso(today.getFullYear(), today.getMonth(), today.getDate());
    const selectedIso = selected ? toIso(selected.y, selected.m, selected.d) : '';

    const chevron = (dir: 'left' | 'right') =>
      `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6"><path stroke-linecap="round" stroke-linejoin="round" d="${dir === 'left' ? 'M15 19l-7-7 7-7' : 'M9 5l7 7-7 7'}"/></svg>`;

    const render = () => {
      if (mode === 'months') {
        pop.innerHTML = `
          <div class="bs-cal-head">
            <button type="button" class="bs-cal-nav" data-act="prev-year" aria-label="Previous year">${chevron('left')}</button>
            <span class="bs-cal-title" style="cursor:default">${view.y}</span>
            <button type="button" class="bs-cal-nav" data-act="next-year" aria-label="Next year">${chevron('right')}</button>
          </div>
          <div class="bs-months">${uiText().months.map((n, i) => `<button type="button" class="bs-month${i === view.m ? ' is-selected' : ''}" data-month="${i}">${n.slice(0, 3)}</button>`).join('')}</div>`;
        return;
      }

      const first = new Date(view.y, view.m, 1);
      const offset = (first.getDay() + 6) % 7; // Monday first
      const start = new Date(view.y, view.m, 1 - offset);
      const cells: string[] = [];
      for (let i = 0; i < 42; i++) {
        const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
        const iso = toIso(d.getFullYear(), d.getMonth(), d.getDate());
        const out = d.getMonth() !== view.m;
        const disabled = (isoMin && iso < isoMin) || (isoMax && iso > isoMax);
        cells.push(
          `<button type="button" class="bs-day${out ? ' is-out' : ''}${iso === todayIso ? ' is-today' : ''}${iso === selectedIso ? ' is-selected' : ''}" data-date="${iso}"${disabled ? ' disabled' : ''}>${d.getDate()}</button>`
        );
      }
      const prevDisabled = isoMin && toIso(view.y, view.m, 0) < isoMin ? ' disabled' : '';
      const nextDisabled = isoMax && toIso(view.y, view.m + 1, 1) > isoMax ? ' disabled' : '';
      const todayDisabled = (isoMin && todayIso < isoMin) || (isoMax && todayIso > isoMax) ? ' disabled' : '';
      pop.innerHTML = `
        <div class="bs-cal-head">
          <button type="button" class="bs-cal-nav" data-act="prev" aria-label="Previous month"${prevDisabled}>${chevron('left')}</button>
          <button type="button" class="bs-cal-title" data-act="months">${uiText().months[view.m]} ${view.y}</button>
          <button type="button" class="bs-cal-nav" data-act="next" aria-label="Next month"${nextDisabled}>${chevron('right')}</button>
        </div>
        <div class="bs-cal-week">${uiText().week.map((w) => `<span>${w}</span>`).join('')}</div>
        <div class="bs-cal-grid">${cells.join('')}</div>
        <div class="bs-cal-foot">
          <button type="button" class="bs-cal-link" data-act="today"${todayDisabled}>${uiText().today}</button>
          ${input.required ? '' : `<button type="button" class="bs-cal-link" data-act="clear">${uiText().clear}</button>`}
        </div>`;
    };

    const commit = (iso: string) => {
      input.value = iso;
      input.dispatchEvent(new Event('input', { bubbles: true }));
      input.dispatchEvent(new Event('change', { bubbles: true }));
      this.sync();
      this.closePopover?.();
      trigger.focus();
    };

    pop.addEventListener('click', e => {
      const el = (e.target as HTMLElement).closest('button') as HTMLButtonElement | null;
      if (!el || el.disabled) return;
      const act = el.dataset['act'];
      if (el.dataset['date']) return commit(el.dataset['date']);
      if (el.dataset['month'] !== undefined) { view.m = +el.dataset['month']!; mode = 'days'; return render(); }
      if (act === 'prev') { view = view.m === 0 ? { y: view.y - 1, m: 11 } : { y: view.y, m: view.m - 1 }; render(); }
      else if (act === 'next') { view = view.m === 11 ? { y: view.y + 1, m: 0 } : { y: view.y, m: view.m + 1 }; render(); }
      else if (act === 'prev-year') { view.y -= 1; render(); }
      else if (act === 'next-year') { view.y += 1; render(); }
      else if (act === 'months') { mode = 'months'; render(); }
      else if (act === 'today') commit(todayIso);
      else if (act === 'clear') commit('');
    });

    render();
    trigger.setAttribute('aria-expanded', 'true');
    this.closePopover = openPopover(trigger, pop, {
      onClose: () => {
        trigger.setAttribute('aria-expanded', 'false');
        this.closePopover = undefined;
      },
    });
  }
}
