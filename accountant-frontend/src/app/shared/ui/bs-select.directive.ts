import { AfterViewInit, Directive, ElementRef, OnDestroy, PLATFORM_ID, Optional, Self, inject } from '@angular/core';
import { isPlatformBrowser } from '@angular/common';
import { NgModel } from '@angular/forms';
import { Subscription } from 'rxjs';
import { CHECK, CHEVRON, openPopover } from './bs-popover';

/**
 * Restyles every single-choice <select> as a dropdown with a rounded list and a blue selected row.
 * The real <select> stays in the DOM (hidden), so ngModel, forms, options and (change) keep working.
 */
@Directive({ selector: 'select', standalone: true })
export class BsSelectDirective implements AfterViewInit, OnDestroy {
  private host = inject<ElementRef<HTMLSelectElement>>(ElementRef);
  private isBrowser = isPlatformBrowser(inject(PLATFORM_ID));

  private trigger?: HTMLButtonElement;
  private labelEl?: HTMLElement;
  private observer?: MutationObserver;
  private sub?: Subscription;
  private closePopover?: () => void;
  private hiddenSiblings: HTMLElement[] = [];

  constructor(@Optional() @Self() private ngModel: NgModel | null) {}

  ngAfterViewInit() {
    if (!this.isBrowser) return;
    const select = this.host.nativeElement;
    if (select.multiple || select.size > 1) return; // list boxes keep native behaviour

    const trigger = document.createElement('button');
    trigger.type = 'button';
    // reuse the select's own utility classes so size, border and radius stay as designed
    trigger.className = `${select.className} bs-trigger`.replace(/\bappearance-none\b/g, '');
    const style = select.getAttribute('style');
    if (style) trigger.setAttribute('style', style);
    trigger.setAttribute('aria-haspopup', 'listbox');
    trigger.setAttribute('aria-expanded', 'false');
    trigger.innerHTML = `<span class="bs-trigger-label"></span>${CHEVRON}`;
    this.labelEl = trigger.querySelector('.bs-trigger-label') as HTMLElement;
    this.trigger = trigger;

    // drop the decorative chevron some templates place next to the select
    const next = select.nextElementSibling as HTMLElement | null;
    if (next && next.tagName.toLowerCase() === 'svg') {
      next.style.display = 'none';
      this.hiddenSiblings.push(next);
    }

    select.parentNode?.insertBefore(trigger, select);
    select.classList.add('bs-native-hidden');
    select.tabIndex = -1;

    trigger.addEventListener('click', () => this.toggle());
    trigger.addEventListener('keydown', e => this.onTriggerKey(e));
    select.addEventListener('change', this.sync);

    this.observer = new MutationObserver(this.sync);
    this.observer.observe(select, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ['disabled'] });
    this.sub = this.ngModel?.valueChanges?.subscribe(() => queueMicrotask(this.sync));

    this.sync();
    setTimeout(this.sync, 0);
  }

  ngOnDestroy() {
    this.closePopover?.();
    this.observer?.disconnect();
    this.sub?.unsubscribe();
    this.host.nativeElement.removeEventListener('change', this.sync);
    this.trigger?.remove();
    this.hiddenSiblings.forEach(el => (el.style.display = ''));
  }

  private sync = () => {
    const select = this.host.nativeElement;
    if (!this.trigger || !this.labelEl) return;
    const opt = select.options[select.selectedIndex];
    const text = opt ? opt.text.trim() : '';
    this.labelEl.textContent = text || 'Select…';
    this.labelEl.classList.toggle('is-placeholder', !text || (opt?.value === '' && !!opt));
    this.trigger.disabled = select.disabled;
  };

  private toggle() {
    if (this.closePopover) {
      this.closePopover();
      return;
    }
    this.open();
  }

  private open() {
    const select = this.host.nativeElement;
    const trigger = this.trigger;
    if (!trigger || select.disabled) return;

    const pop = document.createElement('div');
    pop.setAttribute('role', 'listbox');
    const list = document.createElement('div');
    list.className = 'bs-list';
    pop.appendChild(list);

    Array.from(select.options).forEach((opt, index) => {
      const item = document.createElement('button');
      item.type = 'button';
      item.className = 'bs-option' + (index === select.selectedIndex ? ' is-selected' : '');
      item.disabled = opt.disabled;
      item.dataset['index'] = String(index);
      item.setAttribute('role', 'option');
      item.innerHTML = `<span>${this.escape(opt.text.trim() || '—')}</span>${index === select.selectedIndex ? CHECK : ''}`;
      list.appendChild(item);
    });

    list.addEventListener('click', e => {
      const btn = (e.target as HTMLElement).closest('.bs-option') as HTMLButtonElement | null;
      if (!btn || btn.disabled) return;
      this.choose(Number(btn.dataset['index']));
    });
    list.addEventListener('keydown', e => this.onListKey(e as KeyboardEvent, list));

    trigger.setAttribute('aria-expanded', 'true');
    this.closePopover = openPopover(trigger, pop, {
      matchWidth: true,
      onClose: () => {
        trigger.setAttribute('aria-expanded', 'false');
        this.closePopover = undefined;
      },
    });
    (list.querySelector('.is-selected') as HTMLElement | null)?.scrollIntoView({ block: 'nearest' });
    (list.querySelector('.is-selected') as HTMLElement | null)?.focus();
  }

  private choose(index: number) {
    const select = this.host.nativeElement;
    select.selectedIndex = index;
    select.dispatchEvent(new Event('change', { bubbles: true }));
    this.sync();
    this.closePopover?.();
    this.trigger?.focus();
  }

  private onTriggerKey(e: KeyboardEvent) {
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      this.open();
    }
  }

  private onListKey(e: KeyboardEvent, list: HTMLElement) {
    const items = Array.from(list.querySelectorAll<HTMLButtonElement>('.bs-option:not(:disabled)'));
    const i = items.indexOf(document.activeElement as HTMLButtonElement);
    if (e.key === 'ArrowDown') { e.preventDefault(); items[Math.min(items.length - 1, i + 1)]?.focus(); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); items[Math.max(0, i - 1)]?.focus(); }
    else if (e.key === 'Home') { e.preventDefault(); items[0]?.focus(); }
    else if (e.key === 'End') { e.preventDefault(); items[items.length - 1]?.focus(); }
  }

  private escape(text: string): string {
    return text.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c] as string));
  }
}
