import { HttpClient } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { firstValueFrom } from 'rxjs';

import { environment } from '../../../environments/environment';
import { AuthService } from '../../core/auth.service';
import { serverMessage } from '../../core/format';
import { I18nService } from '../../core/i18n.service';

const API = environment.apiUrl;

const text = (v: unknown): string => (v === null || v === undefined ? '' : String(v));
const obj = (v: unknown): Record<string, unknown> => (v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : {});

export interface BusinessView {
  name: string;
  tin: string;
  phone: string;
  email: string;
  address: string;
  logoUrl: string | null;
}

export function readBusiness(j: Record<string, unknown>): BusinessView {
  return {
    name: text(j['name']),
    tin: text(j['tin']),
    phone: text(j['phone']),
    email: text(j['email']),
    address: text(j['address']),
    logoUrl: typeof j['logo_url'] === 'string' && j['logo_url'] ? (j['logo_url'] as string) : null,
  };
}

/** What is wrong with the business details, as translation keys (the same rules as the phone's form); an empty list means all is well. */
export function businessProblems(b: { name: string; tin: string; phone: string; email: string }): { field: string; key: string }[] {
  const out: { field: string; key: string }[] = [];
  if (!b.name.trim()) out.push({ field: 'name', key: 'bp.err.name' });
  const tin = b.tin.trim();
  if (tin && !/^\d{3}[-\s]?\d{3}[-\s]?\d{3}$/.test(tin)) out.push({ field: 'tin', key: 'bp.err.tin' });
  const phone = b.phone.trim();
  if (phone && !/^(0\d{9}|\+\d{9,15})$/.test(phone)) out.push({ field: 'phone', key: 'bp.err.phone' });
  const email = b.email.trim();
  if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) out.push({ field: 'email', key: 'bp.err.email' });

  return out;
}

@Component({
  selector: 'app-business',
  imports: [FormsModule],
  template: `
    <div class="ad ph-page" data-testid="business-page">
      @if (error() && !loaded()) {
        <section class="ph-card"><p data-testid="bp-error">{{ error() }}</p><button type="button" class="btn-outline ph-btn" (click)="load()">{{ i18n.t('pl.retry') }}</button></section>
      } @else if (!loaded()) {
        <section class="ph-card"><p class="ph-muted">{{ i18n.t('pl.loading') }}</p></section>
      } @else {
        <section class="ph-card ph-row">
          <div class="ph-row" style="gap: 12px">
            @if (logo()) { <img [src]="logo()" alt="" style="width: 64px; height: 64px; border-radius: 14px; object-fit: cover; background: #fff" data-testid="bp-logo" /> }
            @else { <span class="ph-badge" style="padding: 18px 20px">{{ i18n.t('bp.no.logo') }}</span> }
          </div>
          @if (edit()) {
            <div class="ph-row" style="gap: 6px; flex-wrap: wrap">
              <label class="btn-outline ph-btn" style="cursor: pointer">{{ logo() ? i18n.t('bp.logo.change') : i18n.t('bp.logo.add') }}<input type="file" accept="image/*" hidden (change)="pickLogo($event)" data-testid="bp-logo-input" /></label>
              @if (logo()) { <button type="button" class="btn-outline ph-btn" (click)="removeLogo()" data-testid="bp-logo-remove">{{ i18n.t('bp.logo.remove') }}</button> }
            </div>
          }
        </section>

        <section class="ph-card" style="display: grid; gap: 12px">
          <label class="ph-field">{{ i18n.t('bp.name') }}<input class="modal-input" [disabled]="!edit()" [ngModel]="name()" (ngModelChange)="name.set($event)" data-testid="bp-name" name="bpName" /></label>
          <label class="ph-field">TIN<input class="modal-input" inputmode="numeric" [disabled]="!edit()" [ngModel]="tin()" (ngModelChange)="tin.set($event)" data-testid="bp-tin" name="bpTin" /></label>
          <label class="ph-field">{{ i18n.t('bp.phone') }}<input class="modal-input" type="tel" [disabled]="!edit()" [ngModel]="phone()" (ngModelChange)="phone.set($event)" data-testid="bp-phone" name="bpPhone" /></label>
          <label class="ph-field">{{ i18n.t('bp.email') }}<input class="modal-input" type="email" [disabled]="!edit()" [ngModel]="email()" (ngModelChange)="email.set($event)" data-testid="bp-email" name="bpEmail" /></label>
          <label class="ph-field">{{ i18n.t('bp.address') }}<textarea class="modal-input" rows="3" [disabled]="!edit()" [ngModel]="address()" (ngModelChange)="address.set($event)" data-testid="bp-address" name="bpAddress"></textarea></label>
          @for (p of problems(); track p.field) { <p class="ph-bad" [attr.data-testid]="'bp-problem-' + p.field">{{ i18n.t(p.key) }}</p> }
          @if (error()) { <p class="ph-bad">{{ error() }}</p> }
          @if (saved()) { <p class="ph-good" data-testid="bp-saved">{{ i18n.t('set.saved') }}</p> }
          @if (edit()) { <button type="button" class="btn-primary ph-btn" [disabled]="busy()" (click)="save()" data-testid="bp-save">{{ busy() ? i18n.t('common.saving') : i18n.t('common.save') }}</button> }
          @else { <p class="ph-muted">{{ i18n.t('bp.read.only') }}</p> }
        </section>
        <p class="ph-muted">{{ i18n.t('bp.phone.only') }}</p>
      }
    </div>
  `,
})
export class BusinessPage implements OnInit {
  private readonly http = inject(HttpClient);
  private readonly auth = inject(AuthService);
  protected readonly i18n = inject(I18nService);

  protected readonly loaded = signal(false);
  protected readonly error = signal('');
  protected readonly saved = signal(false);
  protected readonly busy = signal(false);
  protected readonly logo = signal<string | null>(null);
  protected readonly name = signal('');
  protected readonly tin = signal('');
  protected readonly phone = signal('');
  protected readonly email = signal('');
  protected readonly address = signal('');
  protected readonly problems = signal<{ field: string; key: string }[]>([]);

  /** The owner edits; everyone else reads. */
  protected edit(): boolean {
    return this.auth.isBusinessAdmin();
  }

  ngOnInit(): void {
    void this.load();
  }

  private fill(b: BusinessView): void {
    this.name.set(b.name);
    this.tin.set(b.tin);
    this.phone.set(b.phone);
    this.email.set(b.email);
    this.address.set(b.address);
    this.logo.set(b.logoUrl);
  }

  async load(): Promise<void> {
    this.error.set('');
    try {
      const r = await firstValueFrom(this.http.get<{ data: Record<string, unknown> }>(`${API}/business`));
      this.fill(readBusiness(obj(r.data)));
      this.loaded.set(true);
    } catch (e) {
      this.error.set(serverMessage(e) || this.i18n.t('pl.error'));
    }
  }

  protected async save(): Promise<void> {
    this.saved.set(false);
    this.error.set('');
    const found = businessProblems({ name: this.name(), tin: this.tin(), phone: this.phone(), email: this.email() });
    this.problems.set(found);
    if (found.length) return;
    this.busy.set(true);
    try {
      const r = await firstValueFrom(
        this.http.put<{ data: Record<string, unknown> }>(`${API}/business`, {
          name: this.name().trim(),
          address: this.address().trim(),
          tin: this.tin().trim(),
          phone: this.phone().trim(),
          email: this.email().trim(),
        }),
      );
      this.fill(readBusiness(obj(r.data)));
      this.saved.set(true);
    } catch (e) {
      this.error.set(serverMessage(e) || this.i18n.t('pl.error'));
    }
    this.busy.set(false);
  }

  protected async pickLogo(ev: Event): Promise<void> {
    const input = ev.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;
    const body = new FormData();
    body.append('logo', file, file.name);
    this.error.set('');
    try {
      const r = await firstValueFrom(this.http.post<{ data: Record<string, unknown> }>(`${API}/business/logo`, body));
      this.logo.set(readBusiness(obj(r.data)).logoUrl);
    } catch (e) {
      this.error.set(serverMessage(e) || this.i18n.t('pl.error'));
    }
    input.value = '';
  }

  protected async removeLogo(): Promise<void> {
    this.error.set('');
    try {
      const r = await firstValueFrom(this.http.delete<{ data: Record<string, unknown> }>(`${API}/business/logo`));
      this.logo.set(readBusiness(obj(r.data)).logoUrl);
    } catch (e) {
      this.error.set(serverMessage(e) || this.i18n.t('pl.error'));
    }
  }
}
