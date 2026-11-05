import { TestBed } from '@angular/core/testing';

import { byTestId, configure, settle } from '../../../testing';
import { ReceiptSize, lastReceiptSize, rememberReceiptSize } from '../../../core/receipt';
import { ReceiptSizeComponent } from './receipt-size';

describe('choosing the paper for a receipt', () => {
  it('offers A4 and the two thermal rolls, and hands back the one picked', async () => {
    configure({});
    const fixture = TestBed.createComponent(ReceiptSizeComponent);
    fixture.componentRef.setInput('show', true);
    let got: ReceiptSize | null = null;
    fixture.componentInstance.picked.subscribe((s) => (got = s));
    await settle(fixture);
    const el = fixture.nativeElement as HTMLElement;

    for (const s of ['a4', 'thermal80', 'thermal58']) expect(byTestId(el, `receipt-size-${s}`)).not.toBeNull();
    (byTestId(el, 'receipt-size-thermal80') as HTMLElement).click();
    expect(got).toBe('thermal80');
  });

  it('remembers the last choice, and starts with A4', () => {
    localStorage.clear();
    expect(lastReceiptSize()).toBe('a4');
    rememberReceiptSize('thermal58');
    expect(lastReceiptSize()).toBe('thermal58');
  });
});
