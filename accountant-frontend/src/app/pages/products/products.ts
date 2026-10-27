import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { firstValueFrom } from 'rxjs';

import { AuthService } from '../../core/auth.service';
import { offline, parseAmount, serverMessage, tsh } from '../../core/format';
import { I18nService } from '../../core/i18n.service';
import { ProductsApi } from '../../core/products-api.service';
import { Named, NamedKind, PriceOption, Product, ProductBody, ProductFilters, ProductPage, ServiceMaterial, StaffMember } from '../../core/products.models';
import { ConfirmService } from '../../core/services/confirm.service';
import { MotionService } from '../../core/services/motion.service';
import { ToastService } from '../../core/services/toast.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';
import { TableToolbarComponent } from '../../shared/components/table-toolbar/table-toolbar';
import { MoneyDirective } from '../../shared/ui/money.directive';

type Tab = 'products' | 'categories' | 'brands';

/** One line of "price options" in the form (a service priced by hair length, for example). The price stays text while it is typed. */
interface OptionRow {
  label: string;
  price: string;
}

const UNITS = ['pcs', 'kg', 'g', 'litre', 'ml', 'bottle', 'crate', 'carton', 'bag', 'box', 'pack', 'dozen', 'metre'];

/**
 * The goods a business sells and, for a salon, its services: the same screens as the mobile app's "Products" (or "Services & goods")
 * section. Everyone who may see products can search and read them; adding is for those with the add right, and changing, deleting,
 * and the categories and brands tabs are for those who manage the catalogue. The server checks every one of these again.
 */
@Component({
  selector: 'app-products',
  imports: [FormsModule, ModalDialogComponent, TableToolbarComponent, MoneyDirective],
  templateUrl: './products.html',
})
export class ProductsPage implements OnInit {
  private readonly api = inject(ProductsApi);
  private readonly toast = inject(ToastService);
  private readonly confirm = inject(ConfirmService);
  protected readonly auth = inject(AuthService);
  protected readonly i18n = inject(I18nService);
  protected readonly motion = inject(MotionService);

  protected readonly tsh = tsh;
  protected readonly units = UNITS;

  // ---- who may do what (the mobile app's rule, and the server's)
  protected readonly canManage = computed(() => this.auth.can('inv_manage_products'));
  protected readonly canAdd = computed(() => this.canManage() || this.auth.can('inv_create_products'));
  protected readonly salon = computed(() => this.auth.service() === 'salon');

  protected readonly tab = signal<Tab>('products');

  // ---- the list
  protected readonly data = signal<ProductPage | null>(null);
  protected readonly loading = signal(true);
  protected readonly error = signal<string | null>(null);
  protected readonly query = signal('');
  protected readonly status = signal<ProductFilters['status']>('');
  protected readonly kind = signal<ProductFilters['kind']>('');
  protected readonly lowStock = signal(false);
  protected readonly categoryId = signal<number | null>(null);
  protected readonly page = signal(1);
  private searchTimer: ReturnType<typeof setTimeout> | null = null;

  // ---- categories and brands (they also fill the form's choices)
  protected readonly categories = signal<Named[]>([]);
  protected readonly brands = signal<Named[]>([]);

  // ---- the product form
  protected readonly formOpen = signal(false);
  protected readonly editing = signal<Product | null>(null);
  protected readonly saving = signal(false);
  protected readonly formError = signal('');
  protected fName = '';
  protected fSku = '';
  protected fBarcode = '';
  protected fCategory = '';
  protected fBrand = '';
  protected fUnit = 'pcs';
  protected fCost = '';
  protected fPrice = '';
  protected fQty = '';
  protected fMin = '';
  protected fVat = '';
  protected fStatus: 'active' | 'inactive' = 'active';
  protected fDesc = '';
  protected fIsService = false;
  protected fDuration = '';
  protected fRebook = '';
  protected fCommission = '';
  protected fCommissionFixed = '';
  protected fCommissionOn = false;
  protected readonly fOptions = signal<OptionRow[]>([]);
  protected readonly fStaff = signal<string[]>([]);
  protected fIsPackage = false;
  protected fPkgService = '';
  protected fPkgSessions = '';
  protected fPkgDays = '';
  protected readonly staff = signal<StaffMember[]>([]);

  // ---- the goods a service uses up
  protected readonly matFor = signal<Product | null>(null);
  protected readonly materials = signal<ServiceMaterial[]>([]);
  protected readonly matLoading = signal(false);
  protected readonly matSaving = signal(false);
  protected readonly matError = signal('');
  protected readonly matHits = signal<Product[]>([]);
  protected matQuery = '';

  // ---- the category / brand form
  protected readonly namedOpen = signal(false);
  protected readonly namedEditing = signal<Named | null>(null);
  protected namedName = '';
  protected namedDesc = '';
  protected namedStatus: 'active' | 'inactive' = 'active';
  protected readonly namedError = signal('');
  protected readonly namedSaving = signal(false);

  /** The services a package can be made of (not packages themselves, not this one). */
  protected readonly packageTargets = computed(() => this.rows().filter((p) => p.is_service && !p.package_sessions && p.status === 'active' && p.id !== this.editing()?.id));
  protected readonly rows = computed(() => this.data()?.items ?? []);
  protected readonly total = computed(() => this.data()?.total ?? 0);
  protected readonly hasFilters = computed(() => !!(this.query() || this.status() || this.kind() || this.lowStock() || this.categoryId()));
  protected readonly noun = computed(() => this.i18n.t(this.total() === 1 ? 'prod.noun.one' : 'prod.noun.many'));
  protected readonly namedList = computed(() => (this.tab() === 'brands' ? this.brands() : this.categories()));
  protected readonly namedKind = computed<NamedKind>(() => (this.tab() === 'brands' ? 'brands' : 'categories'));

  ngOnInit(): void {
    void this.load();
    void this.loadNamed('categories');
    void this.loadNamed('brands');
    if (this.salon()) void this.loadStaff();
  }

  // ------------------------------------------------------------------ loading
  protected async load(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    try {
      this.data.set(await firstValueFrom(this.api.products({ q: this.query(), status: this.status(), kind: this.kind(), lowStock: this.lowStock(), categoryId: this.categoryId(), page: this.page() })));
    } catch (err) {
      this.error.set(this.messageOf(err));
    } finally {
      this.loading.set(false);
    }
  }

  private async loadStaff(): Promise<void> {
    try {
      this.staff.set(await firstValueFrom(this.api.staff()));
    } catch {
      // "done by" is optional: without the list, anyone may do the service
    }
  }

  private async loadNamed(kind: NamedKind): Promise<void> {
    try {
      const list = await firstValueFrom(this.api.named(kind));
      (kind === 'brands' ? this.brands : this.categories).set(list);
    } catch {
      // the lists only fill the choices; the page works without them
    }
  }

  /** A filter changed: go back to the first page and ask again (typing waits a moment, so it does not ask for every letter). */
  protected refilter(wait = 0): void {
    this.page.set(1);
    if (this.searchTimer) clearTimeout(this.searchTimer);
    this.searchTimer = setTimeout(() => void this.load(), wait);
  }

  protected setQuery(q: string): void {
    this.query.set(q);
    this.refilter(300);
  }

  protected clearFilters(): void {
    this.query.set('');
    this.status.set('');
    this.kind.set('');
    this.lowStock.set(false);
    this.categoryId.set(null);
    this.refilter();
  }

  protected goTo(page: number): void {
    const last = this.data()?.lastPage ?? 1;
    if (page < 1 || page > last) return;
    this.page.set(page);
    void this.load();
  }

  /** The words for a status. */
  protected activeKey(status: 'active' | 'inactive'): string {
    return status === 'active' ? 'prod.active' : 'prod.inactive';
  }

  protected setTab(t: Tab): void {
    this.tab.set(t);
  }

  // ------------------------------------------------------------------ reading a row
  protected isLow(p: Product): boolean {
    return !p.is_service && p.quantity < p.min_stock;
  }

  protected subline(p: Product): string {
    if (p.is_service) {
      return [this.i18n.t('prod.service'), p.duration_minutes ? this.i18n.t('prod.minutes', p.duration_minutes) : ''].filter(Boolean).join(' · ');
    }

    return [p.sku, p.category_name, p.brand_name].filter(Boolean).join(' · ');
  }

  // ------------------------------------------------------------------ the product form
  protected openAdd(): void {
    this.editing.set(null);
    this.fill(null);
    // In a salon, a new thing is a service far more often than goods (the mobile app starts there too).
    this.fIsService = this.salon();
    this.formOpen.set(true);
  }

  protected openEdit(p: Product): void {
    this.editing.set(p);
    this.fill(p);
    this.formOpen.set(true);
  }

  private fill(p: Product | null): void {
    this.formError.set('');
    this.fName = p?.name ?? '';
    this.fSku = p?.sku ?? '';
    this.fBarcode = p?.barcode ?? '';
    this.fCategory = p?.category_id ? String(p.category_id) : '';
    this.fBrand = p?.brand_id ? String(p.brand_id) : '';
    this.fUnit = p?.unit ?? 'pcs';
    this.fCost = p ? String(p.cost_price) : '';
    this.fPrice = p ? String(p.selling_price) : '';
    this.fQty = p ? String(p.quantity) : '0';
    this.fMin = p ? String(p.min_stock) : '0';
    this.fVat = p?.tax_percent === null || p?.tax_percent === undefined ? '' : String(p.tax_percent);
    this.fStatus = p?.status ?? 'active';
    this.fDesc = p?.description ?? '';
    this.fIsService = p?.is_service ?? false;
    this.fDuration = p?.duration_minutes ? String(p.duration_minutes) : '';
    this.fRebook = p?.rebook_after_weeks ? String(p.rebook_after_weeks) : '';
    this.fCommission = p?.commission_percent === null || p?.commission_percent === undefined ? '' : String(p.commission_percent);
    this.fCommissionFixed = p?.commission_fixed ? String(p.commission_fixed) : '';
    this.fCommissionOn = !!(p?.commission_percent || p?.commission_fixed);
    this.fStaff.set(p?.staff_ids ?? []);
    this.fIsPackage = !!p?.package_sessions;
    this.fPkgService = p?.package_service_id ? String(p.package_service_id) : '';
    this.fPkgSessions = p?.package_sessions ? String(p.package_sessions) : '';
    this.fPkgDays = p?.package_valid_days ? String(p.package_valid_days) : '';
    this.fOptions.set((p?.price_options ?? []).map((o) => ({ label: o.label, price: String(o.price) })));
  }

  protected isStaffPicked(id: string): boolean {
    return this.fStaff().includes(id);
  }

  protected toggleStaff(id: string): void {
    this.fStaff.update((all) => (all.includes(id) ? all.filter((x) => x !== id) : [...all, id]));
  }

  protected addOption(): void {
    if (this.fOptions().length < 10) this.fOptions.update((o) => [...o, { label: '', price: '' }]);
  }

  protected removeOption(i: number): void {
    this.fOptions.update((o) => o.filter((_, k) => k !== i));
  }

  protected setOption(i: number, field: keyof OptionRow, value: string): void {
    this.fOptions.update((o) => o.map((row, k) => (k === i ? { ...row, [field]: value } : row)));
  }

  protected async save(): Promise<void> {
    const body = this.bodyOrError();
    if (!body) return;
    this.saving.set(true);
    this.formError.set('');
    try {
      const current = this.editing();
      await firstValueFrom(current ? this.api.updateProduct(current.id, body) : this.api.createProduct(body));
      this.toast.success(this.i18n.t(current ? 'prod.saved' : 'prod.created'), this.i18n.t('common.done'));
      this.formOpen.set(false);
      await this.load();
    } catch (err) {
      this.formError.set(this.messageOf(err));
    } finally {
      this.saving.set(false);
    }
  }

  /** The body to send, or null after showing what is wrong (in the person's own words, next to the form). */
  private bodyOrError(): ProductBody | null {
    const t = (k: string) => this.i18n.t(k);
    const fail = (key: string): null => {
      this.formError.set(t(key));
      return null;
    };
    const money = (s: string): number => (s.trim() === '' ? 0 : parseAmount(s));
    const whole = (s: string): number => (s.trim() === '' ? 0 : /^\d+$/.test(s.trim()) ? Number(s.trim()) : NaN);

    if (!this.fName.trim()) return fail('prod.err.name');
    // A service has no buying price (it is not bought): the same as on the mobile app.
    const cost = this.fIsService ? 0 : money(this.fCost);
    const price = money(this.fPrice);
    if (Number.isNaN(cost)) return fail('prod.err.cost');
    if (Number.isNaN(price) || (!this.fIsService && this.fPrice.trim() === '')) return fail('prod.err.price');
    const qty = this.fIsService ? 0 : whole(this.fQty);
    const min = this.fIsService ? 0 : whole(this.fMin);
    if (Number.isNaN(qty)) return fail('prod.err.qty');
    if (Number.isNaN(min)) return fail('prod.err.min');

    let vat: number | null = null;
    if (!this.fIsService && this.fVat.trim() !== '') {
      vat = parseAmount(this.fVat);
      if (Number.isNaN(vat) || vat > 100) return fail('prod.err.vat');
    }

    let options: PriceOption[] = [];
    let duration: number | null = null;
    let rebook: number | null = null;
    let commission: number | null = null;
    let commissionFixed: number | null = null;
    let pkgSessions: number | null = null;
    let pkgService: number | null = null;
    let pkgDays: number | null = null;
    if (this.fIsService) {
      for (const o of this.fOptions()) {
        const p = parseAmount(o.price);
        if (!o.label.trim() || Number.isNaN(p)) return fail('prod.err.option');
        options = [...options, { label: o.label.trim(), price: p }];
      }
      if (this.fDuration.trim() !== '') {
        duration = whole(this.fDuration);
        if (Number.isNaN(duration) || duration < 1 || duration > 1440) return fail('prod.err.duration');
      }
      if (this.fRebook.trim() !== '') {
        rebook = whole(this.fRebook);
        if (Number.isNaN(rebook) || rebook < 1 || rebook > 52) return fail('prod.err.rebook');
      }
      if (this.fCommissionOn) {
        if (this.fCommission.trim() !== '') {
          commission = parseAmount(this.fCommission);
          if (Number.isNaN(commission) || commission > 100) return fail('prod.err.commission');
        }
        if (this.fCommissionFixed.trim() !== '') {
          commissionFixed = parseAmount(this.fCommissionFixed);
          if (Number.isNaN(commissionFixed)) return fail('prod.err.commission.fixed');
        }
      }
      if (this.fIsPackage) {
        pkgService = this.fPkgService ? Number(this.fPkgService) : null;
        pkgSessions = whole(this.fPkgSessions);
        if (!pkgService) return fail('prod.err.pkg.service');
        if (Number.isNaN(pkgSessions) || pkgSessions < 2 || pkgSessions > 100) return fail('prod.err.pkg.sessions');
        if (this.fPkgDays.trim() !== '') {
          pkgDays = whole(this.fPkgDays);
          if (Number.isNaN(pkgDays) || pkgDays < 1 || pkgDays > 730) return fail('prod.err.pkg.days');
        }
      }
    }

    return {
      name: this.fName.trim(),
      description: this.fDesc.trim() || null,
      // Leave the code blank when adding and the server makes one; when editing the code is kept.
      ...(this.fSku.trim() ? { sku: this.fSku.trim() } : {}),
      barcode: this.fBarcode.trim() || null,
      category_id: this.fCategory ? Number(this.fCategory) : null,
      brand_id: this.fBrand ? Number(this.fBrand) : null,
      unit: this.fUnit.trim() || 'pcs',
      cost_price: cost,
      selling_price: price,
      quantity: qty,
      min_stock: min,
      status: this.fStatus,
      tax_percent: vat,
      is_service: this.fIsService,
      duration_minutes: duration,
      rebook_after_weeks: rebook,
      commission_percent: commission,
      commission_fixed: commissionFixed,
      package_sessions: pkgSessions,
      package_service_id: pkgService,
      package_valid_days: pkgDays,
      staff_ids: this.fIsService ? this.fStaff() : [],
      price_options: options,
    };
  }

  // ------------------------------------------------------------------ the goods a service uses up
  protected async openMaterials(p: Product): Promise<void> {
    this.matFor.set(p);
    this.materials.set([]);
    this.matHits.set([]);
    this.matQuery = '';
    this.matError.set('');
    this.matLoading.set(true);
    try {
      this.materials.set(await firstValueFrom(this.api.materials(p.id)));
    } catch (err) {
      this.matError.set(this.messageOf(err));
    } finally {
      this.matLoading.set(false);
    }
  }

  protected async searchGoods(q: string): Promise<void> {
    this.matQuery = q;
    if (q.trim().length < 2) return this.matHits.set([]);
    try {
      const have = new Set(this.materials().map((m) => m.material_product_id));
      this.matHits.set((await firstValueFrom(this.api.findGoods(q.trim()))).filter((g) => !have.has(g.id)).slice(0, 8));
    } catch {
      this.matHits.set([]);
    }
  }

  protected addMaterial(g: Product): void {
    this.materials.update((all) => [...all, { material_product_id: g.id, name: g.name, quantity: 1, in_stock: g.quantity }]);
    this.matHits.set([]);
    this.matQuery = '';
  }

  protected setMaterialQty(i: number, value: string): void {
    const q = Math.max(1, Math.min(1000, Math.floor(Number(value)) || 1));
    this.materials.update((all) => all.map((m, k) => (k === i ? { ...m, quantity: q } : m)));
  }

  protected removeMaterial(i: number): void {
    this.materials.update((all) => all.filter((_, k) => k !== i));
  }

  protected async saveMaterials(): Promise<void> {
    const service = this.matFor();
    if (!service) return;
    this.matSaving.set(true);
    this.matError.set('');
    try {
      await firstValueFrom(this.api.saveMaterials(service.id, this.materials().map((m) => ({ material_product_id: m.material_product_id, quantity: m.quantity }))));
      this.toast.success(this.i18n.t('prod.mat.saved'), this.i18n.t('common.done'));
      this.matFor.set(null);
    } catch (err) {
      this.matError.set(this.messageOf(err));
    } finally {
      this.matSaving.set(false);
    }
  }

  // ------------------------------------------------------------------ deleting
  protected async remove(p: Product): Promise<void> {
    const yes = await this.confirm.ask({
      title: this.i18n.t('prod.delete.title'),
      message: this.i18n.t('prod.delete.message', p.name),
      confirmLabel: this.i18n.t('common.delete'),
      cancelLabel: this.i18n.t('common.keep'),
      danger: true,
    });
    if (!yes) return;
    try {
      await firstValueFrom(this.api.deleteProduct(p.id));
      this.toast.success(this.i18n.t('prod.deleted'), this.i18n.t('common.done'));
      await this.load();
    } catch (err) {
      // A product that was sold cannot be deleted without losing the sales history: offer to archive it (set it to inactive) instead.
      if ((err as { status?: number }).status === 422 && (serverMessage(err) ?? '').toLowerCase().includes('sales history')) {
        await this.archive(p);
        return;
      }
      this.toast.error(this.messageOf(err), this.i18n.t('error.title'));
    }
  }

  private async archive(p: Product): Promise<void> {
    const yes = await this.confirm.ask({
      title: this.i18n.t('prod.archive.title'),
      message: this.i18n.t('prod.archive.message', p.name),
      confirmLabel: this.i18n.t('prod.archive.confirm'),
      cancelLabel: this.i18n.t('common.keep'),
    });
    if (!yes) return;
    try {
      await firstValueFrom(this.api.deleteProduct(p.id, true));
      this.toast.success(this.i18n.t('prod.archived'), this.i18n.t('common.done'));
      await this.load();
    } catch (err) {
      this.toast.error(this.messageOf(err), this.i18n.t('error.title'));
    }
  }

  // ------------------------------------------------------------------ categories and brands
  protected openNamed(n: Named | null): void {
    this.namedEditing.set(n);
    this.namedName = n?.name ?? '';
    this.namedDesc = n?.description ?? '';
    this.namedStatus = n?.status ?? 'active';
    this.namedError.set('');
    this.namedOpen.set(true);
  }

  protected async saveNamed(): Promise<void> {
    if (!this.namedName.trim()) return this.namedError.set(this.i18n.t('prod.err.name'));
    this.namedSaving.set(true);
    this.namedError.set('');
    const kind = this.namedKind();
    try {
      await firstValueFrom(this.api.saveNamed(kind, this.namedEditing()?.id ?? null, { name: this.namedName.trim(), description: this.namedDesc.trim() || null, status: this.namedStatus }));
      this.toast.success(this.i18n.t('prod.saved'), this.i18n.t('common.done'));
      this.namedOpen.set(false);
      await this.loadNamed(kind);
    } catch (err) {
      this.namedError.set(this.messageOf(err));
    } finally {
      this.namedSaving.set(false);
    }
  }

  protected async removeNamed(n: Named): Promise<void> {
    const kind = this.namedKind();
    const yes = await this.confirm.ask({
      title: this.i18n.t('prod.delete.title'),
      message: this.i18n.t('prod.delete.message', n.name),
      confirmLabel: this.i18n.t('common.delete'),
      cancelLabel: this.i18n.t('common.keep'),
      danger: true,
    });
    if (!yes) return;
    try {
      await firstValueFrom(this.api.deleteNamed(kind, n.id));
      this.toast.success(this.i18n.t('prod.deleted'), this.i18n.t('common.done'));
      await this.loadNamed(kind);
    } catch (err) {
      this.toast.error(this.messageOf(err), this.i18n.t('error.title'));
    }
  }

  private messageOf(err: unknown): string {
    return offline(err) ? this.i18n.t('error.offline') : (serverMessage(err) ?? this.i18n.t('error.generic'));
  }
}
