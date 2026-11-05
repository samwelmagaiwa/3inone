import { Component, OnDestroy, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { firstValueFrom } from 'rxjs';

import { AuthService } from '../../core/auth.service';
import { CapabilitiesService } from '../../core/capabilities.service';
import { localizedName, offline, parseAmount, serverMessage, tsh } from '../../core/format';
import { I18nService } from '../../core/i18n.service';
import { Named } from '../../core/products.models';
import { ProductsApi } from '../../core/products-api.service';
import { printReceipt } from '../../core/receipt';
import { ConfirmService } from '../../core/services/confirm.service';
import { ToastService } from '../../core/services/toast.service';
import { activeUnits, CartLine, Customer, PriceOption, Product, SellingUnit } from '../../core/till.models';
import { ClientPackage, CrateType, CreditCheck, ParkedSale, SaleDetail, StaffMember, TillApi } from '../../core/till-api.service';
import { PAYMENT_CHANNELS, PayMode, TillService } from '../../core/till.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';
import { MoneyDirective } from '../../shared/ui/money.directive';

/**
 * The till: find goods, build the cart, say who is buying and how they pay, then save the sale. The same sale, with the same prices and
 * rules, as the mobile app's till (the arithmetic is in core/till-math.ts). Everything here is a plain step with plain words.
 */
/** Starts the note of a sale put aside by this app: what follows is where the sale had got to. */
const PROGRESS = '#wz:';

@Component({
  selector: 'app-till',
  imports: [FormsModule, ModalDialogComponent, MoneyDirective],
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

  // ---- narrowing the goods (opened on demand, so a till that never uses it asks for nothing more)
  private readonly catalogue = inject(ProductsApi);
  protected readonly filtersOpen = signal(false);
  protected readonly categories = signal<Named[]>([]);
  protected readonly brands = signal<Named[]>([]);
  protected fCategory = '';
  protected fBrand = '';
  protected fKind = '';

  // ---- customer
  protected readonly customerQuery = signal('');
  protected readonly customerHits = signal<Customer[]>([]);
  protected readonly credit = signal<CreditCheck | null>(null);
  /** Which way of naming the customer is open: find one who is saved, write a new one, or no name at all. */
  protected readonly custTab = signal<'find' | 'new' | 'walkin'>('find');
  protected newName = '';
  protected newPhone = '';
  protected readonly newError = signal('');
  /** True once Save was pressed and something was missing: the empty required fields are then outlined in red. */
  protected readonly tried = signal(false);

  // ---- the steps of the popup: 1 find the goods, 2 what is bought, 3 who buys, 4 how they pay, 5 check everything and save
  protected readonly steps = [1, 2, 3, 4, 5];
  protected readonly step = signal(1);
  /** Services, goods or both (a salon sells both): chosen in plain sight above the list. */
  protected readonly kinds = [
    { value: '', label: 'till.kind.all' },
    { value: 'service', label: 'till.filter.service' },
    { value: 'goods', label: 'till.filter.goods' },
  ];

  /** The goods used by a service line, worth what they sell for (null when the usual goods are used and not listed here). */
  protected goodsValue(l: CartLine): number | null {
    if (l.materials === null) return null;
    const all = [...this.goodsCache(), ...this.products()];

    return l.materials.reduce((sum, m) => sum + m.qty * (all.find((p) => p.id === m.productId)?.sellingPrice ?? 0), 0) * l.qty;
  }

  protected paidNow(): number {
    return this.till.mode() === 'cash' ? this.till.totals().total : this.till.mode() === 'partial' ? Math.min(this.till.paid(), this.till.totals().total) : 0;
  }

  protected payChannel(): string {
    return this.till.mode() === 'cash' ? this.channelName(this.till.channel()) : this.till.mode() === 'partial' ? this.channelName(this.till.partialChannel()) : '—';
  }

  protected payReference(): string {
    return (this.till.mode() === 'cash' && this.till.channel() !== 'cash' ? this.till.reference() : this.till.mode() === 'partial' && this.till.partialChannel() !== 'cash' ? this.till.partialReference() : '').trim();
  }

  protected setKind(value: string): void {
    this.fKind = value;
    this.setFilters();
  }

  protected stepTitle(n: number): string {
    if (this.till.salon() && n <= 2) return this.i18n.t(n === 1 ? 'till.step1.salon' : 'till.step2.salon');
    return this.i18n.t(['till.step1', 'till.step2', 'till.step3', 'till.step4', 'till.step5'][n - 1]);
  }

  protected stepName(n: number): string {
    if (this.till.salon() && n === 1) return this.i18n.t('till.stepname1.salon');
    return this.i18n.t(['till.stepname1', 'till.stepname2', 'till.stepname3', 'till.stepname4', 'till.stepname5'][n - 1]);
  }

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

  /** A sale paid later (or in part) must be for a saved customer. */
  /** The reason for a typed discount is needed unless a voucher or points explain it. */
  protected readonly reasonNeeded = computed(() => this.till.salon() && this.till.totalDiscount() > 0 && !this.till.voucher().code && this.till.pointsOff() <= 0);
  protected readonly needsCustomer = computed(() => this.till.mode() !== 'cash' && !this.till.customer());
  protected readonly showCrates = computed(() => this.crateTypes().length > 0 && this.caps.useCrates() && this.caps.inventoryType() !== 'retail');
  /** The goods that can be said to have been used for a service: the whole list of goods, whichever tab the list is on. */
  private readonly goodsCache = signal<Product[]>([]);
  protected readonly goodsOnly = computed(() => (this.goodsCache().length ? this.goodsCache() : this.products()).filter((p) => !p.isService && p.active));
  protected readonly balanceDue = computed(() => {
    const t = this.till.totals().total;
    if (this.till.mode() === 'cash') return 0;
    if (this.till.mode() === 'debt') return t;
    return Math.max(0, t - Math.min(Math.max(this.till.paid(), 0), t));
  });

  ngOnInit(): void {
    // A salon starts with its services; the goods used for each one are asked after it is chosen.
    if (this.till.salon()) this.fKind = 'service';
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
      const r = await firstValueFrom(this.api.products(this.query(), 1, { category: this.fCategory, brand: this.fBrand, kind: this.fKind }));
      this.products.set(r.items);
      this.till.reprice(r.items);
    } catch (err) {
      this.productError.set(this.fail(err));
    } finally {
      this.loadingProducts.set(false);
    }
  }

  /** A phone number is needed for every customer: at least nine digits (spaces and dashes do not count). */
  protected phoneOk(): boolean {
    return this.newPhone.replace(/\D/g, '').length >= 9;
  }

  protected async toggleFilters(): Promise<void> {
    this.filtersOpen.update((o) => !o);
    if (this.filtersOpen() && !this.categories().length && !this.brands().length) {
      try {
        const [c, b] = await Promise.all([firstValueFrom(this.catalogue.named('categories')), firstValueFrom(this.catalogue.named('brands'))]);
        this.categories.set(c.filter((n) => n.status === 'active'));
        this.brands.set(b.filter((n) => n.status === 'active'));
      } catch {
        // the filters are a convenience: the search box still works
      }
    }
  }

  protected setFilters(): void {
    void this.loadProducts();
  }

  protected clearFilters(): void {
    this.fCategory = '';
    this.fBrand = '';
    this.fKind = '';
    void this.loadProducts();
  }

  protected get filtered(): boolean {
    return !!(this.fCategory || this.fBrand || this.fKind);
  }

  protected named(name: string): string {
    return localizedName(name, this.i18n.lang());
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

  /** [option] is null for the product's usual price (a product with other prices still has its own). */
  protected chooseOption(p: Product, option: PriceOption | null): void {
    this.optionFor.set(null);
    this.addLine(p, null, option);
  }

  private addLine(p: Product, unit: SellingUnit | null, option: PriceOption | null): void {
    const factor = unit && !unit.isBase ? unit.factor : 1;
    if (!p.isService && this.till.leaving(p.id) + factor > p.quantity) {
      this.toast.warning(this.i18n.t('till.nostock', p.name, String(p.quantity)), this.i18n.t('till.nostock.title'));
      return;
    }
    const before = this.till.lines().length;
    const line = this.till.add(p, { unit, option });
    if (this.till.salon() && p.isService && !line.staffId && this.staff().length === 1) this.till.setStaff(line.key, { id: this.staff()[0].id, name: this.staff()[0].name });
    // A salon sells the service first, then says which goods the client's visit used: asked at once, with the usual ones filled in.
    if (this.till.salon() && p.isService && this.till.lines().length > before) void this.openGoods(line.key);
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

  /** "+ Add" under the search hits: open the new-customer form with what was typed already in the name box. */
  protected addNewCustomer(): void {
    this.newName = this.customerQuery().trim();
    this.newPhone = '';
    this.newError.set('');
    this.custTab.set('new');
  }

  protected openCustTab(tab: 'find' | 'new' | 'walkin'): void {
    this.newError.set('');
    this.custTab.set(tab);
  }

  protected async saveNewCustomer(): Promise<void> {
    const name = this.newName.trim();
    if (!name) return this.newError.set(this.i18n.t('till.cust.needname'));
    if (!this.phoneOk()) return this.newError.set(this.i18n.t('till.cust.needphone'));
    try {
      const c = await firstValueFrom(this.api.createCustomer(name, this.newPhone.trim()));
      this.newName = '';
      this.newPhone = '';
      this.custTab.set('find');
      await this.chooseCustomer(c);
      this.toast.success(this.i18n.t('till.customer.added', c.name), this.i18n.t('common.done'));
    } catch (err) {
      this.newError.set(this.fail(err));
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
    // no name at all is only for a client who pays everything now
    if (m !== 'cash' && this.custTab() === 'walkin') this.custTab.set('find');
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

  /** The list of stylists is a menu that opens under the line it is for (so many stylists never stretch the line). */
  protected readonly staffOpen = signal<string | null>(null);
  protected readonly staffQuery = signal('');
  protected readonly staffShown = computed(() => {
    const q = this.staffQuery().trim().toLowerCase();
    return q ? this.staff().filter((s) => s.name.toLowerCase().includes(q)) : this.staff();
  });

  protected openStaff(key: string): void {
    this.staffQuery.set('');
    this.staffOpen.set(this.staffOpen() === key ? null : key);
  }

  protected closeStaff(): void {
    this.staffOpen.set(null);
  }

  /** Choose a stylist from the menu (the chosen one again clears the choice) and close it. */
  protected toggleStaff(key: string, id: string): void {
    const l = this.till.lines().find((x) => x.key === key);
    this.staffChosen(key, l?.staffId === id ? '' : id);
    this.closeStaff();
  }

  protected initials(name: string): string {
    return name.trim().split(/\s+/).slice(0, 2).map((w) => w.charAt(0)).join('').toUpperCase();
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
    void this.loadGoodsCache();
    if (l.materials) return this.goodsDraft.set(l.materials.map((m) => ({ ...m })));
    try {
      const usual = await firstValueFrom(this.api.usualGoods(l.productId));
      this.goodsDraft.set(usual.map((u) => ({ productId: u.product_id, name: u.name, qty: u.quantity })));
    } catch {
      this.goodsDraft.set([]);
    }
  }

  /** All the goods, once, for the list in the "goods used" card (the till's own list may be showing only services). */
  private async loadGoodsCache(): Promise<void> {
    if (this.goodsCache().length) return;
    try {
      this.goodsCache.set((await firstValueFrom(this.api.products('', 1, { category: '', brand: '', kind: 'goods' }))).items);
    } catch {
      // the list in the card then falls back to what the till already shows
    }
  }

  /** What a service line used, in words: the goods and how many, "the usual goods" until it was changed, or nothing. */
  protected materialsText(l: CartLine): string {
    if (l.materials === null) return this.i18n.t('till.goods.usual');
    const used = l.materials.filter((m) => m.qty > 0).map((m) => `${m.name} ×${m.qty}`);

    return used.length ? used.join(', ') : this.i18n.t('till.goods.none');
  }

  /** The service whose goods are being chosen, for the card's title. */
  protected readonly goodsFor_name = computed(() => this.till.lines().find((l) => l.key === this.goodsFor())?.name ?? '');

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
      await firstValueFrom(this.api.park(this.till.snapshot(), this.till.totals().total, this.till.customer()?.id ?? null, this.progressNote()));
      this.till.clear();
      this.resetForm();
      this.step.set(1);
      this.toast.success(this.i18n.t('till.parked'), this.i18n.t('common.done'));
    } catch (err) {
      this.toast.error(this.fail(err), this.i18n.t('error.title'));
    }
  }

  /** Where the sale had got to, kept in the note of the parked sale so that resuming starts where it stopped. */
  private progressNote(): string {
    const t = this.till;
    return PROGRESS + JSON.stringify({
      step: this.step(),
      mode: t.mode(),
      channel: t.channel(),
      partialChannel: t.partialChannel(),
      reference: t.reference(),
      partialReference: t.partialReference(),
      paid: t.paid(),
      dueDays: t.dueDays(),
      discount: t.discount(),
      discountReason: t.discountReason(),
      manualName: t.manualName(),
      manualPhone: t.manualPhone(),
    });
  }

  /** The step a parked sale stopped at (null for one parked by the phone, which keeps no progress). */
  protected parkedStep(p: ParkedSale): number | null {
    const s = this.readProgress(p.note)?.['step'];
    return typeof s === 'number' && s >= 1 && s <= 5 ? s : null;
  }

  private readProgress(note: string | null): Record<string, unknown> | null {
    if (!note?.startsWith(PROGRESS)) return null;
    try {
      const j: unknown = JSON.parse(note.slice(PROGRESS.length));
      return j && typeof j === 'object' ? (j as Record<string, unknown>) : null;
    } catch {
      return null;
    }
  }

  private applyProgress(note: string | null): void {
    const j = this.readProgress(note);
    this.resetForm();
    if (!j) {
      this.step.set(this.till.lines().length ? 2 : 1);
      return;
    }
    const t = this.till;
    const str = (k: string, d = ''): string => (typeof j[k] === 'string' ? (j[k] as string) : d);
    const num = (k: string, d = 0): number => (typeof j[k] === 'number' && Number.isFinite(j[k]) ? (j[k] as number) : d);
    const mode = str('mode', 'cash');
    t.mode.set(mode === 'debt' || mode === 'partial' ? mode : 'cash');
    t.channel.set(str('channel', 'cash'));
    t.partialChannel.set(str('partialChannel', 'cash'));
    t.reference.set(str('reference'));
    t.partialReference.set(str('partialReference'));
    t.dueDays.set(num('dueDays', 7) || 7);
    t.discountReason.set(str('discountReason'));
    t.manualName.set(str('manualName'));
    t.manualPhone.set(str('manualPhone'));
    if (num('paid') > 0) this.setPaid(String(num('paid')));
    if (num('discount') > 0) this.setDiscount(String(num('discount')));
    const at = num('step', 1);
    this.step.set(this.till.lines().length ? Math.min(Math.max(at, 1), 5) : 1);
  }

  private resetForm(): void {
    this.paidText = '';
    this.discountText = '';
    this.voucherCode = '';
    this.pointsText = '';
    this.voucherMessage.set('');
    this.till.paid.set(0);
    this.till.discount.set(0);
    this.till.discountReason.set('');
    this.till.reference.set('');
    this.till.partialReference.set('');
    this.till.manualName.set('');
    this.till.manualPhone.set('');
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
      this.applyProgress(p.note);
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
    // Crates are listed only for people who may see them (the server answers 403 to the rest) and never in a salon.
    if (this.till.salon() || !this.auth.can('inv_view_crates')) return;
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
  /** The cashier writes the price of one unit; empty or not a number leaves it as it was. */
  protected writePrice(key: string, text: string): void {
    const price = parseAmount(text);
    if (Number.isNaN(price)) return;
    this.till.setPrice(key, price);
  }

  protected listPriceOf(l: CartLine): number | null {
    return this.till.listPriceOf(l, this.products());
  }

  protected useUsualPrice(key: string): void {
    this.till.useListPrice(key, this.products());
  }

  /** Sell at the retail or the wholesale price (for a business that has both): the cart is priced again at once. */
  protected setTier(tier: 'retail' | 'wholesale'): void {
    this.till.tierOverride.set(tier);
    this.till.reprice(this.products());
  }

  /** Empty the cart, after asking: it cannot be undone. */
  protected async clearCart(): Promise<void> {
    if (!this.till.lines().length) return;
    const yes = await this.confirm.ask({
      title: this.i18n.t('till.clear.title'),
      message: this.i18n.t('till.clear.message'),
      confirmLabel: this.i18n.t('till.clear'),
      cancelLabel: this.i18n.t('common.keep'),
      danger: true,
    });
    if (yes) this.till.clear();
  }

  /**
   * What is wrong with the step being left, in words (null when it can be left). The same checks as saving, made one step at a time so
   * the person is told where they are: nothing to sell, a price or quantity that is zero, a service with nobody chosen, a discount without
   * a reason, and (on the last one) the customer, the reference and the credit limit.
   */
  private problemIn(step: number): { message: string; step: number } | null {
    const lines = this.till.lines();
    if (!lines.length) return { message: this.i18n.t('till.err.empty'), step: 1 };
    if (step >= 2) {
      const bad = lines.find((l) => l.packageId === null && (!(l.qty > 0) || !(l.unitPrice > 0)));
      if (bad) return { message: this.i18n.t('till.err.price_required', bad.name), step: 2 };
      const stylist = this.till.missingStylist();
      if (stylist) return { message: this.i18n.t('till.err.stylist_required', stylist.name), step: 2 };
    }
    if (step >= 3 && this.reasonNeeded() && !this.till.discountReason().trim()) return { message: this.i18n.t('till.err.reason_required'), step: 3 };
    if (step >= 4) {
      if (this.till.mode() === 'partial' && !(this.till.paid() > 0 && this.till.paid() < this.till.totals().total)) return { message: this.i18n.t('till.err.paid_required'), step: 4 };
      const built = this.till.buildSale();
      if (built.error) return { message: this.i18n.t(`till.err.${built.error}`, this.till.missingStylist()?.name ?? ''), step: built.error === 'customer_required' ? 3 : built.error === 'stylist_required' ? 2 : 4 };
      const c = this.credit();
      if (this.till.mode() !== 'cash' && c && (c.is_blocked || c.over_limit)) return { message: c.is_blocked ? this.i18n.t('till.err.blocked') : this.i18n.t('till.err.limit', tsh(c.credit_limit)), step: 3 };
    }

    return null;
  }

  protected next(): void {
    const from = this.step();
    const problem = this.problemIn(from);
    if (problem) {
      this.tried.set(true);
      this.formError.set(problem.message);
      this.step.set(problem.step);
      return;
    }
    this.formError.set('');
    this.tried.set(false);
    this.step.set(Math.min(5, from + 1));
  }

  protected back(): void {
    this.formError.set('');
    this.step.update((s) => Math.max(1, s - 1));
  }

  /** Only steps already passed can be gone back to; the way forward is the Next button (it checks what was filled in). */
  protected goStep(n: number): void {
    if (n < this.step()) {
      this.formError.set('');
      this.step.set(n);
    }
  }

  protected closeWizard(): void {
    void this.router.navigateByUrl('/sales');
  }

  protected async charge(): Promise<void> {
    const built = this.till.buildSale();
    if (built.error) {
      this.tried.set(true);
      const stylist = this.till.missingStylist();
      this.formError.set(this.i18n.t(`till.err.${built.error}`, stylist?.name ?? ''));
      this.reveal(built.error === 'customer_required' ? 'till-customer-section' : built.error === 'stylist_required' && stylist ? `line-${stylist.productId}` : null);
      return;
    }
    const c = this.credit();
    if (this.till.mode() !== 'cash' && c && (c.is_blocked || c.over_limit)) {
      this.formError.set(c.is_blocked ? this.i18n.t('till.err.blocked') : this.i18n.t('till.err.limit', tsh(c.credit_limit)));
      return;
    }
    // The preview (step 5) is the check: no second question there.
    const yes = this.step() === 5 || await this.confirm.ask({
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
      this.tried.set(false);
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

  /** "Choose the customer": go to step 3 and put the cursor in the search box. */
  protected goToCustomer(): void {
    this.step.set(3);
    this.custTab.set('find');
    this.reveal('till-customer-section');
    setTimeout(() => (document.querySelector('[data-testid=till-customer-search]') as HTMLInputElement | null)?.focus(), 150);
  }

  /** Bring the part of the till that needs attention into view (the till is long, and a message at the bottom is easy to miss). */
  private reveal(testidOrId: string | null): void {
    if (!testidOrId) return;
    const el = document.getElementById(testidOrId) ?? document.querySelector(`[data-testid="${testidOrId}"]`);
    el?.scrollIntoView?.({ behavior: 'smooth', block: 'center' });
  }

  protected print(sale: SaleDetail): void {
    printReceipt(sale, this.caps.receiptHeader(), (k) => this.i18n.t(k));
  }

  protected newSale(): void {
    this.done.set(null);
    this.step.set(1);
  }

  protected seeSales(): void {
    this.done.set(null);
    void this.router.navigateByUrl('/sales');
  }

  protected channelName(c: string): string {
    return this.i18n.t(`pay.${c}`);
  }
}
