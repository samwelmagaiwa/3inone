import { Injectable, computed, effect, inject, signal, untracked } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { firstValueFrom } from 'rxjs';

import { environment } from '../../environments/environment';
import { AuthService } from './auth.service';
import { ReceiptHeader, receiptHeaderFrom } from './receipt';

const KINDS = ['retail', 'wholesale', 'mixed', 'depot'];

/**
 * What this business's stock is set up to do, read from its settings exactly as the mobile app reads them (InvCapabilities): a
 * business that has not chosen a kind behaves as a depot, which is what inventory was before kinds existed. Also the receipt wording.
 * Read again when the person switches between shop and salon (each has its own settings).
 */
@Injectable({ providedIn: 'root' })
export class CapabilitiesService {
  private readonly http = inject(HttpClient);
  private readonly auth = inject(AuthService);

  readonly settings = signal<Record<string, string>>({});
  readonly loaded = signal(false);
  /** Which asking is the latest: an answer for a business that was signed in a moment ago must never be kept. */
  private generation = 0;
  private who: string | null = null;

  readonly inventoryType = computed(() => (KINDS.includes(this.settings()['inventory_type']) ? this.settings()['inventory_type'] : 'depot'));
  readonly useCrates = computed(() => (this.settings()['use_crates'] ?? '1') !== '0');
  readonly saleTier = computed(() => (['retail', 'wholesale'].includes(this.settings()['sale_tier']) ? this.settings()['sale_tier'] : 'product'));
  readonly usesPriceLevels = computed(() => this.saleTier() !== 'product');
  readonly pricesIncludeVat = computed(() => (this.settings()['prices_include_vat'] ?? '1') !== '0');
  readonly defaultTaxPercent = computed(() => Number.parseFloat(this.settings()['tax_percent'] ?? '') || 0);
  /** The price level the till starts on: the business's own, or retail for a depot (which prices by product). */
  readonly startingTier = computed<'retail' | 'wholesale'>(() => (this.saleTier() === 'wholesale' ? 'wholesale' : 'retail'));
  /** What the top and bottom of a printed receipt say (the business's name, address, phone, TIN and footer note). */
  readonly receiptHeader = computed<ReceiptHeader>(() => receiptHeaderFrom(this.settings(), this.auth.user()?.business ?? '', this.auth.service() === 'salon'));
  readonly maxDiscountPercent = computed(() => Number.parseFloat(this.settings()['max_discount_percent'] ?? '') || 0);

  constructor() {
    // a different service, or a different person (another business signing in on this browser), has different settings: the old ones
    // are dropped at once, never shown to the new business, and the new ones are read
    effect(() => {
      this.auth.user();
      this.auth.service();
      untracked(() => {
        const now = `${this.auth.user()?.id ?? ''}|${this.auth.service()}`;
        // the first time round nothing belonged to anybody yet: only a real change of person or service drops what is held
        if (this.who !== null && this.who !== now) {
          this.generation++;
          this.settings.set({});
          this.loaded.set(false);
        }
        this.who = now;
        if (this.auth.isLoggedIn()) void this.load();
      });
    });
  }

  async load(): Promise<void> {
    const mine = ++this.generation;
    try {
      const res = await firstValueFrom(this.http.get<{ data: Record<string, unknown> }>(`${environment.apiUrl}/inventory/settings`));
      if (mine !== this.generation) return; // someone else is signed in by now
      const out: Record<string, string> = {};
      for (const [k, v] of Object.entries(res.data ?? {})) out[k] = v == null ? '' : String(v);
      this.settings.set(out);
      this.loaded.set(true);
    } catch {
      // the usual defaults stay until the next try
    }
  }
}
