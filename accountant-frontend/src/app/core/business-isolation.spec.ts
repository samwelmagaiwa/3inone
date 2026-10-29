import { HttpClient } from '@angular/common/http';
import { TestBed } from '@angular/core/testing';

import { environment } from '../../environments/environment';
import { configure, user } from '../testing';
import { AuthService } from './auth.service';
import { BranchesService } from './branches.service';
import { CapabilitiesService } from './capabilities.service';

/**
 * Another business signing in on the same browser never sees what the one before it chose or loaded: its settings, the branch it was
 * looking at, its list of branches.
 */
const SETTINGS = `${environment.apiUrl}/inventory/settings`;

function signIn(auth: AuthService, id: string, name: string, services: ('inventory' | 'salon')[] = ['inventory']): void {
  const u = user({ id, name, business: name, services });
  auth.token.set(`T${id}`);
  auth.user.set(u);
  auth.service.set(services[0]);
}

async function flushEffects(): Promise<void> {
  TestBed.tick();
  await Promise.resolve();
}

describe('what one business chose is never shown to the next one on the same browser', () => {
  it("the settings of the business signed in before are dropped at once, and the new business's own are read", async () => {
    const h = configure(null);
    const auth = TestBed.inject(AuthService);
    const caps = TestBed.inject(CapabilitiesService);

    signIn(auth, 'a1', 'Alpha');
    await flushEffects();
    h.http.expectOne(SETTINGS).flush({ data: { tax_percent: '18', depot_name: 'Alpha Wholesale', receipt_tagline: 'Alpha tagline' } });
    await flushEffects();
    expect(caps.settings()['depot_name']).toBe('Alpha Wholesale');

    // Bravo signs in (the same service, so nothing about the SERVICE changed)
    auth.clear();
    signIn(auth, 'b1', 'Bravo');
    await flushEffects();
    expect(caps.settings()).toEqual({}); // nothing of Alpha's is left to show
    expect(caps.loaded()).toBe(false);
    h.http.expectOne(SETTINGS).flush({ data: { tax_percent: '5', depot_name: 'Bravo Shop' } });
    await flushEffects();

    expect(caps.settings()['depot_name']).toBe('Bravo Shop');
    expect(caps.settings()['tax_percent']).toBe('5');
    expect(caps.settings()['receipt_tagline']).toBeUndefined();
    expect(caps.receiptHeader().business).toBe('Bravo Shop');
  });

  it("an answer that arrives late for the business signed in before is thrown away", async () => {
    const h = configure(null);
    const auth = TestBed.inject(AuthService);
    const caps = TestBed.inject(CapabilitiesService);

    signIn(auth, 'a1', 'Alpha');
    await flushEffects();
    const alphaAsk = h.http.expectOne(SETTINGS);

    auth.clear();
    signIn(auth, 'b1', 'Bravo');
    await flushEffects();
    const bravoAsk = h.http.expectOne(SETTINGS);

    bravoAsk.flush({ data: { depot_name: 'Bravo Shop' } });
    await flushEffects();
    alphaAsk.flush({ data: { depot_name: 'Alpha Wholesale' } }); // the slow one, answering last
    await flushEffects();

    expect(caps.settings()['depot_name']).toBe('Bravo Shop');
  });

  it('signing out leaves no settings behind', async () => {
    const h = configure(null);
    const auth = TestBed.inject(AuthService);
    const caps = TestBed.inject(CapabilitiesService);
    signIn(auth, 'a1', 'Alpha');
    await flushEffects();
    h.http.expectOne(SETTINGS).flush({ data: { depot_name: 'Alpha Wholesale' } });
    await flushEffects();

    auth.logout(false);
    await flushEffects();

    expect(caps.settings()).toEqual({});
    h.http.match(() => true).forEach((r) => r.flush({}));
  });

  it("the branch one business was looking at is not the next business's, and each person gets their own back", async () => {
    const h = configure(null);
    const auth = TestBed.inject(AuthService);
    const branches = TestBed.inject(BranchesService);

    signIn(auth, 'a1', 'Alpha');
    await flushEffects();
    branches.list.set([{ id: 3, name: 'Alpha Kariakoo', address: null, phone: null, active: true }]);
    branches.select(3);
    expect(branches.selected()).toBe(3);

    auth.clear();
    signIn(auth, 'b1', 'Bravo');
    await flushEffects();
    expect(branches.selected()).toBeNull(); // Bravo looks at the whole business
    expect(branches.list()).toEqual([]); // and never sees Alpha's branches
    const http = TestBed.inject(HttpClient);
    http.get(`${environment.apiUrl}/inventory/sales`).subscribe();
    const asked = h.http.expectOne((r) => r.url.endsWith('/inventory/sales'));
    expect(asked.request.headers.has('X-Branch')).toBe(false);
    asked.flush({});

    branches.select(8); // Bravo's own branch
    auth.clear();
    signIn(auth, 'a1', 'Alpha');
    await flushEffects();
    expect(branches.selected()).toBe(3); // Alpha comes back to Alpha's choice, not Bravo's
    h.http.match(() => true).forEach((r) => r.flush({}));
  });

  it('the branch is remembered per service: the shop and the salon each have their own', async () => {
    configure(null);
    const auth = TestBed.inject(AuthService);
    const branches = TestBed.inject(BranchesService);
    signIn(auth, 'a1', 'Alpha', ['inventory', 'salon']);
    await flushEffects();

    branches.select(3);
    auth.switchService('salon');
    await flushEffects();
    expect(branches.selected()).toBeNull();
    branches.select(9);

    auth.switchService('inventory');
    await flushEffects();
    expect(branches.selected()).toBe(3);
    auth.switchService('salon');
    await flushEffects();
    expect(branches.selected()).toBe(9);
  });

  it('the branch is told to the server together with the service it belongs to', async () => {
    const h = configure(null);
    const auth = TestBed.inject(AuthService);
    const branches = TestBed.inject(BranchesService);
    signIn(auth, 'a1', 'Alpha', ['inventory', 'salon']);
    await flushEffects();
    branches.select(3);

    TestBed.inject(HttpClient).get(`${environment.apiUrl}/inventory/sales`).subscribe();
    const asked = h.http.expectOne((r) => r.url.endsWith('/inventory/sales'));
    expect(asked.request.headers.get('X-Branch')).toBe('3');
    expect(asked.request.headers.get('X-Branch-Service')).toBe('inventory');
    asked.flush({});
  });
});
