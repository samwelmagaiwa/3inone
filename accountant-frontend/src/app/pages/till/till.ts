import { Component, OnDestroy, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { firstValueFrom } from 'rxjs';

import { AuthService } from '../../core/auth.service';
import { CapabilitiesService } from '../../core/capabilities.service';
import { offline, parseAmount, serverMessage, tsh } from '../../core/format';
import { I18nService } from '../../core/i18n.service';
import { printReceipt } from '../../core/receipt';
import { ConfirmService } from '../../core/services/confirm.service';
import { ToastService } from '../../core/services/toast.service';
import { activeUnits, Customer, PriceOption, Product, SellingUnit } from '../../core/till.models';
import { ClientPackage, CrateType, CreditCheck, ParkedSale, SaleDetail, StaffMember, TillApi } from '../../core/till-api.service';
import { PAYMENT_CHANNELS, PayMode, TillService } from '../../core/till.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';

/**
 * The till: find goods, build the cart, say who is buying and how they pay, then save the sale. The same sale, with the same prices and
 * rules, as the mobile app's till (the arithmetic is in core/till-math.ts). Everything here is a plain step with plain words.
 */
@Component({
  selector: 'app-till',
  imports: [FormsModule, ModalDialogComponent],
  templateUrl: './till.html',
})
export class TillPage implements OnInit, OnDestroy {
  private readonly api = inject(TillApi);
  private readonly toast = inject(ToastService);
  private readonly confirm = inject(ConfirmService);
  private readonly router = inject(Router);
  protected readonly till = inject(TillService);
  protected readonly caps = inject(CapabilitiesService);
  protected readonly auth = inject(AuthService);
  protected readonly i18n = inject(I18nService);

  protected readonly tsh = tsh;
  protected readonly channels = PAYMENT_CHANNELS;

  // ---- goods
  protected readonly query = signal('');
  protected readonly products = signal<Product[]>([]);
  protected readonly loadingProducts = signal(true);
  protected readonly productError = signal<string | null>(null);
  private timer: ReturnType<typeof setTimeout> | null = null;

  // ---- customer
  protected readonly customerQuery = signal('');
  protected readonly customerHits = signal<Customer[]>([]);
  protected readonly credit = signal<CreditCheck | null>(null);

  // ---- salon
  protected readonly staff = signal<StaffMember[]>([]);
  protected readonly packages = signal<ClientPackage[]>([]);
  protected readonly loyaltyBalance = signal(0);
  protected voucherCode = '';
  protected readonly voucherMessage = signal('');
  protected pointsText = '';

  // ---- depot
  protected readonly crateTypes = signal<CrateType[]>([]);

  // ---- choosing a price option / the goods used
  protected readonly optionFor = signal<Product | null>(null);
  protected readonly goodsFor = signal<string | null>(null); // line key
  protected readonly goodsDraft = signal<{ productId: number; name: string; qty: number }[]>([]);
  protected addGoodId = '';

  // ---- paying
  protected paidText = '';
  protected discountText = '';
  protected readonly saving = signal(false);
  protected readonly formError = signal('');
  protected readonly done = signal<SaleDetail | null>(null);
  protected readonly parkedOpen = signal(false);
  protected readonly parked = signal<ParkedSale[]>([]);

  protected readonly showCrates = computed(() => this.crateTypes().length > 0 && this.caps.useCrates() && this.caps.inventoryType() !== 'retail');
  protected readonly goodsOnly = computed(() => this.products().filter((p) => !p.isService && p.active));
  protected readonly balanceDue = computed(() => {
    const t = this.till.totals().total;
    if (this.till.mode() === 'cash') return 0;
    if (this.till.mode() === 'debt') return t;
    return Math.max(0, t - Math.min(Math.max(this.till.paid(), 0), t));
  });

  ngOnInit(): void {
    void this.loadProducts();
    if (this.till.salon()) void this.loadSalon();
    void this.loadCrates();
  }

  ngOnDestroy(): void {
    if (this.timer) clearTimeout(this.timer);
  }

  private fail(err: unknown): string {
    return offline(err) ? this.i18n.t('error.offline') : (serverMessage(err) ?? this.i18n.t('error.generic'));
  }

  // ------------------------------------------------------------------ goods
  protected async loadProducts(): Promise<void> {
    this.loadingProducts.set(true);
    this.productError.set(null);
    try {
      const r = await firstValueFrom(this.api.products(this.query()));
      this.products.set(r.items);
      this.till.reprice(r.items);
    } catch (err) {
      this.productError.set(this.fail(err));
    } finally {
      this.loadingProducts.set(false);
    }
  }

  protected setQuery(q: string): void {
    this.query.set(q);
    if (this.timer) clearTimeout(this.timer);
    this.timer = setTimeout(() => void this.loadProducts(), 300);
  }

  /** Enter in the search box: a barcode or code that matches exactly goes straight into the cart (a scanner types it and presses Enter). */
  protected onEnter(): void {
    const q = this.query().trim().toLowerCase();
    if (!q) return;
    const hit = this.products().find((p) => p.barcode.toLowerCase() === q || p.sku.toLowerCase() === q);
    const only = this.products().length === 1 ? this.products()[0] : undefined;
    const p = hit ?? only;
    if (p) {
      this.pick(p);
      this.query.set('');
      void this.loadProducts();
    }
  }

  protected inCart(p: Product): number {
    return this.till.leaving(p.id);
  }

  protected soldOut(p: Product): boolean {
    return !p.isService && p.quantity - this.till.leaving(p.id) <= 0;
  }

  protected pick(p: Product): void {
    if (p.priceOptions.length) {
      this.optionFor.set(p);
      return;
    }
    this.addLine(p, null, null);
  }

  protected chooseOption(p: Product, option: PriceOption): void {
    this.optionFor.set(null);
    this.addLine(p, null, option);
  }

  private addLine(p: Product, unit: SellingUnit | null, option: PriceOption | null): void {
    const factor = unit && !unit.isBase ? unit.factor : 1;
    if (!p.isService && this.till.leaving(p.id) + factor > p.quantity) {
      this.toast.warning(this.i18n.t('till.nostock', p.name, String(p.quantity)), this.i18n.t('till.nostock.title'));
      return;
    }
    const line = this.till.add(p, { unit, option });
    if (this.till.salon() && p.isService && !line.staffId && this.staff().length === 1) this.till.setStaff(line.key, { id: this.staff()[0].id, name: this.staff()[0].name });
  }

  protected productOf(id: number): Product | undefined {
    return this.products().find((p) => p.id === id);
  }

  protected unitsOf(id: number): SellingUnit[] {
    const p = this.productOf(id);
    return p ? activeUnits(p) : [];
  }

  protected changeUnit(key: string, productId: number, unitId: string): void {
    const p = this.productOf(productId);
    if (!p) return;
    this.till.changeUnit(key, p, p.units.find((u) => String(u.id) === unitId) ?? null);
  }

  protected setQty(key: string, productId: number, text: string): void {
    const n = Math.floor(Number(text));
    if (!Number.isFinite(n) || n < 1) return this.till.setQty(key, 1);
    const l = this.till.lines().find((x) => x.key === key);
    const p = this.productOf(productId);
    if (l && p && !p.isService) {
      const others = this.till.leaving(p.id) - l.qty * (l.unitFactor < 1 ? 1 : l.unitFactor);
      const room = Math.floor((p.quantity - others) / (l.unitFactor < 1 ? 1 : l.unitFactor));
      if (n > room) {
        this.toast.warning(this.i18n.t('till.nostock', p.name, String(p.quantity)), this.i18n.t('till.nostock.title'));
        return this.till.setQty(key, Math.max(1, room));
      }
    }
    this.till.setQty(key, n);
  }

  // ------------------------------------------------------------------ customer
  protected async searchCustomers(q: string): Promise<void> {
    this.customerQuery.set(q);
    if (q.trim().length < 2) return this.customerHits.set([]);
    try {
      this.customerHits.set(await firstValueFrom(this.api.customers(q)));
    } catch {
      this.customerHits.set([]);
    }
  }

  protected async chooseCustomer(c: Customer | null): Promise<void> {
    this.till.customer.set(c);
    this.customerQuery.set('');
    this.customerHits.set([]);
    this.credit.set(null);
    this.packages.set([]);
    this.loyaltyBalance.set(0);
    this.till.reprice(this.products());
    if (c && this.till.salon()) {
      try {
        this.packages.set(await firstValueFrom(this.api.clientPackages(c.id)));
        const l = await firstValueFrom(this.api.loyalty(c.id));
        this.loyaltyBalance.set(l.on ? l.balance : 0);
      } catch {
        // perks are optional
      }
    }
    await this.checkCredit();
  }

  protected async addNewCustomer(): Promise<void> {
    const name = this.customerQuery().trim();
    if (!name) return;
    try {
      const c = await firstValueFrom(this.api.createCustomer(name, this.till.manualPhone().trim()));
      await this.chooseCustomer(c);
      this.toast.success(this.i18n.t('till.customer.added', c.name), this.i18n.t('common.done'));
    } catch (err) {
      this.toast.error(this.fail(err), this.i18n.t('error.title'));
    }
  }

  /** On credit: is the customer blocked or over their limit? Asked of the server, which keeps the figures. */
  protected async checkCredit(): Promise<void> {
    const c = this.till.customer();
    if (!c || this.till.mode() === 'cash') return this.credit.set(null);
    try {
      this.credit.set(await firstValueFrom(this.api.creditCheck(c.id, this.balanceDue())));
    } catch {
      this.credit.set(null);
    }
  }

  protected setMode(m: PayMode): void {
    this.till.mode.set(m);
    this.formError.set('');
    void this.checkCredit();
  }

  protected setPaid(text: string): void {
    this.paidText = text;
    const n = parseAmount(text);
    this.till.paid.set(Number.isNaN(n) ? 0 : n);
    void this.checkCredit();
  }

  // ------------------------------------------------------------------ salon
  private async loadSalon(): Promise<void> {
    try {
      this.staff.set(await firstValueFrom(this.api.salonStaff()));
    } catch {
      // the stylist box then stays empty and the till says so
    }
    try {
      const s = await firstValueFrom(this.api.loyaltySettings());
      this.till.pointValue.set(s.on ? s.value : 0);
    } catch {
      // no loyalty
    }
  }

  protected staffChosen(key: string, id: string): void {
    const s = this.staff().find((x) => x.id === id);
    this.till.setStaff(key, s ? { id: s.id, name: s.name } : null);
  }

  protected setDiscount(text: string): void {
    this.discountText = text;
    const n = parseAmount(text);
    this.till.discount.set(Number.isNaN(n) ? 0 : n);
  }

  protected async applyVoucher(): Promise<void> {
    const code = this.voucherCode.trim();
    if (!code) return this.till.voucher.set({ code: '', off: 0 });
    try {
      const r = await firstValueFrom(this.api.voucher(code, this.till.subtotal()));
      this.till.voucher.set({ code, off: r.discount });
      this.voucherMessage.set(this.i18n.t('till.voucher.ok', tsh(r.discount)));
    } catch (err) {
      this.till.voucher.set({ code: '', off: 0 });
      this.voucherMessage.set(serverMessage(err) ?? this.i18n.t('till.voucher.bad'));
    }
  }

  protected setPoints(text: string): void {
    this.pointsText = text;
    const n = Math.floor(Number(text));
    this.till.pointsUsed.set(Number.isFinite(n) && n > 0 ? Math.min(n, this.loyaltyBalance()) : 0);
  }

  protected packagesFor(productId: number): ClientPackage[] {
    return this.packages().filter((p) => p.service_product_id === productId && p.usable);
  }

  protected usePackage(key: string, id: string): void {
    this.till.setPackage(key, id ? Number(id) : null);
  }

  protected async openGoods(key: string): Promise<void> {
    const l = this.till.lines().find((x) => x.key === key);
    if (!l) return;
    this.goodsFor.set(key);
    this.addGoodId = '';
    if (l.materials) return this.goodsDraft.set(l.materials.map((m) => ({ ...m })));
    try {
      const usual = await firstValueFrom(this.api.usualGoods(l.productId));
      this.goodsDraft.set(usual.map((u) => ({ productId: u.product_id, name: u.name, qty: u.quantity })));
    } catch {
      this.goodsDraft.set([]);
    }
  }

  protected draftQty(i: number, text: string): void {
    const n = Math.max(0, Math.floor(Number(text)) || 0);
    this.goodsDraft.update((d) => d.map((g, x) => (x === i ? { ...g, qty: n } : g)));
  }

  protected draftRemove(i: number): void {
    this.goodsDraft.update((d) => d.filter((_, x) => x !== i));
  }

  protected draftAdd(): void {
    const p = this.goodsOnly().find((x) => String(x.id) === this.addGoodId);
    if (!p) return;
    this.goodsDraft.update((d) => (d.some((g) => g.productId === p.id) ? d : [...d, { productId: p.id, name: p.name, qty: 1 }]));
    this.addGoodId = '';
  }

  protected saveGoods(): void {
    const key = this.goodsFor();
    if (key) this.till.setMaterials(key, this.goodsDraft());
    this.goodsFor.set(null);
  }

  // ------------------------------------------------------------------ parking
  protected async park(): Promise<void> {
    if (!this.till.lines().length) return;
    try {
      await firstValueFrom(this.api.park(this.till.snapshot(), this.till.totals().total, this.till.customer()?.id ?? null, ''));
      this.till.clear();
      this.toast.success(this.i18n.t('till.parked'), this.i18n.t('common.done'));
    } catch (err) {
      this.toast.error(this.fail(err), this.i18n.t('error.title'));
    }
  }

  protected async openParked(): Promise<void> {
    this.parkedOpen.set(true);
    try {
      this.parked.set(await firstValueFrom(this.api.parked()));
    } catch (err) {
      this.parked.set([]);
      this.toast.error(this.fail(err), this.i18n.t('error.title'));
    }
  }

  protected async resume(p: ParkedSale): Promise<void> {
    try {
      const r = await firstValueFrom(this.api.resume(p.id));
      const c = r.customer_id ? ({ id: r.customer_id, name: p.customer_name ?? '', phone: '' } as Customer) : null;
      this.till.restore(r.cart, c);
      this.parkedOpen.set(false);
    } catch (err) {
      this.toast.error(this.fail(err), this.i18n.t('error.title'));
    }
  }

  protected async discard(p: ParkedSale): Promise<void> {
    const yes = await this.confirm.ask({
      title: this.i18n.t('till.discard.title'),
      message: this.i18n.t('till.discard.message', p.reference),
      confirmLabel: this.i18n.t('common.delete'),
      cancelLabel: this.i18n.t('common.keep'),
      danger: true,
    });
    if (!yes) return;
    try {
      await firstValueFrom(this.api.discard(p.id));
      this.parked.update((l) => l.filter((x) => x.id !== p.id));
    } catch (err) {
      this.toast.error(this.fail(err), this.i18n.t('error.title'));
    }
  }

  // ------------------------------------------------------------------ crates
  private async loadCrates(): Promise<void> {
    try {
      this.crateTypes.set((await firstValueFrom(this.api.crateTypes())).filter((c) => c.active !== false));
    } catch {
      // no crates for this business
    }
  }

  protected setCrate(typeId: string, qty: string, direction: string): void {
    const id = typeId ? Number(typeId) : null;
    this.till.crate.set(id ? { typeId: id, qty: Math.max(0, Math.floor(Number(qty)) || 0), direction: direction === 'returned' ? 'returned' : 'issued' } : null);
  }

  // ------------------------------------------------------------------ the sale
  protected async charge(): Promise<void> {
    const built = this.till.buildSale();
    if (built.error) {
      const stylist = this.till.missingStylist();
      this.formError.set(this.i18n.t(`till.err.${built.error}`, stylist?.name ?? ''));
      return;
    }
    const c = this.credit();
    if (this.till.mode() !== 'cash' && c && (c.is_blocked || c.over_limit)) {
      this.formError.set(c.is_blocked ? this.i18n.t('till.err.blocked') : this.i18n.t('till.err.limit', tsh(c.credit_limit)));
      return;
    }
    const yes = await this.confirm.ask({
      title: this.i18n.t('till.confirm.title'),
      message: this.i18n.t('till.confirm.message', tsh(this.till.totals().total), this.till.customer()?.name ?? (this.till.manualName().trim() || this.i18n.t('sales.walkin'))),
      confirmLabel: this.i18n.t('till.confirm.yes'),
      cancelLabel: this.i18n.t('till.confirm.no'),
    });
    if (!yes) return;

    this.saving.set(true);
    this.formError.set('');
    try {
      const made = await firstValueFrom(this.api.createSale(built.payload!));
      const sale = await firstValueFrom(this.api.sale(made.id));
      this.done.set(sale);
      this.till.clear();
      this.paidText = '';
      this.discountText = '';
      this.voucherCode = '';
      this.pointsText = '';
      this.voucherMessage.set('');
      void this.loadProducts();
    } catch (err) {
      this.formError.set(this.fail(err));
    } finally {
      this.saving.set(false);
    }
  }

  protected print(sale: SaleDetail): void {
    printReceipt(sale, this.auth.user()?.business ?? '', (k) => this.i18n.t(k));
  }

  protected newSale(): void {
    this.done.set(null);
  }

  protected seeSales(): void {
    this.done.set(null);
    void this.router.navigateByUrl('/sales');
  }

  protected channelName(c: string): string {
    return this.i18n.t(`pay.${c}`);
  }
}
