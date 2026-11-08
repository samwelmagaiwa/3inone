import { Location } from '@angular/common';
import { TestBed } from '@angular/core/testing';
import { Router } from '@angular/router';

import { configure, user } from '../testing';
import { AuthService } from './auth.service';
import { IDLE_LIMIT_MS, IDLE_NOTICE_KEY, IdleService } from './idle.service';
import { ResumeService } from './resume.service';
import { TillService } from './till.service';

const MIN = 60 * 1000;

function setup() {
  const h = configure({});
  vi.spyOn(TestBed.inject(Router), 'navigate').mockResolvedValue(true);
  vi.spyOn(TestBed.inject(Location), 'path').mockReturnValue('/credit?only=owing');
  const auth = TestBed.inject(AuthService);
  const till = TestBed.inject(TillService);
  const idle = TestBed.inject(IdleService);
  TestBed.tick();
  h.http.match(() => true);

  return { h, auth, till, idle };
}

describe('signing out after ten minutes of doing nothing', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it('the limit is ten minutes', () => {
    expect(IDLE_LIMIT_MS).toBe(10 * MIN);
  });

  it('signs the person out once ten minutes have passed with nothing touched, and says why on the sign-in page', () => {
    const { auth, idle } = setup();
    idle.start();

    vi.advanceTimersByTime(9 * MIN);
    expect(auth.isLoggedIn()).toBe(true);

    vi.advanceTimersByTime(2 * MIN);
    expect(auth.isLoggedIn()).toBe(false);
    expect(localStorage.getItem(IDLE_NOTICE_KEY)).toBe('1');
  });

  it('any movement or key keeps them in: the ten minutes start again', () => {
    const { auth, idle } = setup();
    idle.start();

    vi.advanceTimersByTime(9 * MIN);
    window.dispatchEvent(new Event('mousemove'));
    vi.advanceTimersByTime(9 * MIN);
    expect(auth.isLoggedIn()).toBe(true);

    window.dispatchEvent(new Event('keydown'));
    vi.advanceTimersByTime(9 * MIN);
    expect(auth.isLoggedIn()).toBe(true);

    vi.advanceTimersByTime(2 * MIN);
    expect(auth.isLoggedIn()).toBe(false);
  });

  it('a computer that slept past the limit finds the person signed out as soon as the page runs again', () => {
    const { auth, idle } = setup();
    localStorage.setItem('last_activity', String(Date.now() - 30 * MIN));

    idle.start();

    expect(auth.isLoggedIn()).toBe(false);
  });

  it('signing out by hand, then in again later, is not mistaken for idleness', () => {
    const { auth, idle } = setup();
    idle.start();
    auth.logout();
    vi.advanceTimersByTime(3 * 60 * MIN);

    expect(localStorage.getItem('last_activity')).toBeNull();
  });

  it('keeps the page and the sale being made, and gives both back when the same person signs in again', () => {
    const { auth, till, idle } = setup();
    const me = auth.user()!;
    till.restore([{ product_id: 1, name: 'Soda', qty: 2, unit_price: 1000, unit_cost: 600 }], { id: 4, name: 'Asha', phone: '0711000000' });
    till.progressProvider = () => '#wz:{"step":3}';
    idle.start();

    vi.advanceTimersByTime(11 * MIN);
    expect(auth.isLoggedIn()).toBe(false);
    TestBed.tick();
    expect(till.lines()).toHaveLength(0); // signed out: the screen holds nothing

    // the same person signs in again
    auth.user.set(user({ id: me.id }));
    TestBed.tick();
    expect(till.lines()).toHaveLength(1);
    expect(till.lines()[0].name).toBe('Soda');
    expect(till.lines()[0].qty).toBe(2);
    expect(till.customer()?.name).toBe('Asha');
    expect(till.takePendingProgress()).toBe('#wz:{"step":3}');
    expect(TestBed.inject(ResumeService).takeUrl(me.id)).toBe('/credit?only=owing');
    expect(TestBed.inject(ResumeService).takeUrl(me.id)).toBeNull(); // only once
  });

  it('somebody else signing in is not handed the first person\'s page or sale', () => {
    const { auth, till, idle } = setup();
    till.restore([{ product_id: 1, name: 'Soda', qty: 1, unit_price: 1000, unit_cost: 600 }], null);
    idle.start();
    vi.advanceTimersByTime(11 * MIN);
    TestBed.tick();

    auth.user.set(user({ id: '99' }));
    TestBed.tick();

    expect(till.lines()).toHaveLength(0);
    expect(TestBed.inject(ResumeService).takeUrl('99')).toBeNull();
  });
});
