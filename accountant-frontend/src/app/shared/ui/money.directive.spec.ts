import { Component } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { FormsModule } from '@angular/forms';

import { parseAmount } from '../../core/format';
import { settle, type } from '../../testing';
import { MoneyDirective, withCommas } from './money.directive';

@Component({
  selector: 'app-host',
  imports: [FormsModule, MoneyDirective],
  template: `<input appMoney name="m" [(ngModel)]="value" data-testid="m">`,
})
class HostComponent {
  value = '';
}

describe('money written with commas', () => {
  it('puts a comma every three digits', () => {
    expect(withCommas('1000000')).toBe('1,000,000');
    expect(withCommas('1000')).toBe('1,000');
    expect(withCommas('999')).toBe('999');
    expect(withCommas('')).toBe('');
  });

  it('keeps a decimal part as typed, drops anything that is not a digit, and does not start with zeros', () => {
    expect(withCommas('1234.5')).toBe('1,234.5');
    expect(withCommas('TSh 12abc34')).toBe('1,234');
    expect(withCommas('0005000')).toBe('5,000');
    expect(withCommas('-5')).toBe('5');
  });

  it('as it is typed the box shows 1,000,000 and the page still reads one million', async () => {
    const fixture = TestBed.configureTestingModule({ imports: [HostComponent] }).createComponent(HostComponent);
    fixture.detectChanges();
    await fixture.whenStable();
    const el = fixture.nativeElement as HTMLElement;

    type(el, '[data-testid="m"]', '1000000');
    await settle(fixture);

    expect((el.querySelector('[data-testid="m"]') as HTMLInputElement).value).toBe('1,000,000');
    expect(parseAmount(fixture.componentInstance.value)).toBe(1000000);
  });

  it('an amount the page fills in is shown with its commas too', async () => {
    const fixture = TestBed.configureTestingModule({ imports: [HostComponent] }).createComponent(HostComponent);
    fixture.componentInstance.value = '2500000';
    fixture.detectChanges();
    await settle(fixture);

    expect(((fixture.nativeElement as HTMLElement).querySelector('[data-testid="m"]') as HTMLInputElement).value).toBe('2,500,000');
  });
});
