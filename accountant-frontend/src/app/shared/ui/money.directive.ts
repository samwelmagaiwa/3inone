import { Directive, ElementRef, HostListener, inject } from '@angular/core';

/** 1000000 -> "1,000,000" (a decimal part, if one is being typed, is kept as it is). Anything that is not a digit is dropped. */
export function withCommas(text: string): string {
  const clean = text.replace(/[^\d.]/g, '');
  const [whole, ...rest] = clean.split('.');
  const digits = whole.replace(/^0+(?=\d)/, '');
  const grouped = digits.replace(/\B(?=(\d{3})+(?!\d))/g, ',');

  return rest.length ? `${grouped}.${rest.join('')}` : grouped;
}

/**
 * Money is written with its thousands commas as it is typed (1,000,000, not 1000000), so a big amount can be read at a glance and a
 * missing zero is noticed. The text keeps working everywhere amounts are read (parseAmount drops the commas). Put it on a text box:
 *   <input appMoney inputmode="numeric" [(ngModel)]="amountText">
 * A value set by the page (an amount filled in for the person) is shown with its commas too once the box is not being typed in.
 */
@Directive({ selector: 'input[appMoney]', standalone: true })
export class MoneyDirective {
  private readonly el = inject<ElementRef<HTMLInputElement>>(ElementRef);

  @HostListener('input')
  onInput(): void {
    const input = this.el.nativeElement;
    const before = input.value;
    const caret = input.selectionStart ?? before.length;
    // How many digits are left of the caret: that is where the caret belongs after the commas move.
    const digitsLeft = before.slice(0, caret).replace(/[^\d.]/g, '').length;
    const after = withCommas(before);
    if (after === before) return;

    input.value = after;
    let seen = 0;
    let pos = after.length;
    for (let i = 0; i < after.length; i++) {
      if (/[\d.]/.test(after[i])) seen++;
      if (seen >= digitsLeft) {
        pos = i + 1;
        break;
      }
    }
    input.setSelectionRange(digitsLeft === 0 ? 0 : pos, digitsLeft === 0 ? 0 : pos);
  }

  /** The page filled the box (a prefilled price, a payment amount): show its commas, unless the person is typing in it. */
  ngDoCheck(): void {
    const input = this.el.nativeElement;
    if (document.activeElement === input) return;
    const shown = withCommas(input.value);
    if (shown !== input.value) input.value = shown;
  }
}
