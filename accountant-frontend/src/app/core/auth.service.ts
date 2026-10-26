import { Injectable, computed, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Router } from '@angular/router';
import { firstValueFrom } from 'rxjs';

import { environment } from '../../environments/environment';
import { ApiEnvelope, ServiceName, SessionUser } from './models';

const TOKEN_KEY = 'accountant_token';
const USER_KEY = 'accountant_user';
const SERVICE_KEY = 'accountant_service';

/** localStorage can be missing or blocked (private windows): the app then simply asks for the sign-in each time. */
function read(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function write(key: string, value: string | null): void {
  try {
    if (value === null) localStorage.removeItem(key);
    else localStorage.setItem(key, value);
  } catch {
    // nothing to do: the session just does not survive a reload
  }
}

function readUser(): SessionUser | null {
  try {
    const raw = read(USER_KEY);
    return raw ? (JSON.parse(raw) as SessionUser) : null;
  } catch {
    return null;
  }
}

const SUPPORTED: ServiceName[] = ['inventory', 'salon'];

/** What the server sends at sign-in, as far as this app reads it. */
interface LoginPayload {
  token: string;
  role?: string;
  role_display?: string;
  user: {
    id: string | number;
    name: string;
    email: string;
    role: string;
    phone_number?: string;
    services?: { service_type: string }[];
    effective_permissions?: string[];
    business?: { name?: string } | null;
  };
}

/** Turn the server's user into what the app needs; the rights are the server's own resolved list, never guessed here. */
export function toSessionUser(p: LoginPayload): SessionUser {
  const u = p.user;
  const services = (u.services ?? []).map((s) => s.service_type).filter((s): s is ServiceName => SUPPORTED.includes(s as ServiceName));
  return {
    id: String(u.id),
    name: u.name,
    email: u.email,
    role: u.role,
    roleLabel: p.role_display ?? u.role,
    phone: u.phone_number,
    services: services.filter((s, i) => services.indexOf(s) === i),
    permissions: u.effective_permissions ?? [],
    business: u.business?.name ?? undefined,
  };
}

/** Who is signed in: the token the API gave, the person it belongs to, what they may do, and the service they are working in. */
@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly http = inject(HttpClient);
  private readonly router = inject(Router);

  readonly token = signal<string | null>(read(TOKEN_KEY));
  readonly user = signal<SessionUser | null>(readUser());
  readonly isLoggedIn = computed(() => !!this.token());

  /** The service the pages work in (the server answers from that service's books). */
  readonly service = signal<ServiceName>(this.initialService());

  private initialService(): ServiceName {
    const wanted = read(SERVICE_KEY) as ServiceName | null;
    const mine = readUser()?.services ?? [];
    return wanted && mine.includes(wanted) ? wanted : (mine[0] ?? environment.defaultService);
  }

  async login(email: string, phone: string, password: string): Promise<void> {
    const res = await firstValueFrom(
      this.http.post<ApiEnvelope<LoginPayload>>(`${environment.apiUrl}/auth/login`, { email, phone_number: phone, password }),
    );
    const user = toSessionUser(res.data);
    this.token.set(res.data.token);
    this.user.set(user);
    this.service.set(user.services[0] ?? environment.defaultService);
    write(TOKEN_KEY, res.data.token);
    write(USER_KEY, JSON.stringify(user));
    write(SERVICE_KEY, this.service());
  }

  /** Does the signed-in person have this right? (`__all__` is the owner's "everything".) */
  can(permission: string): boolean {
    const p = this.user()?.permissions ?? [];
    return p.includes('__all__') || p.includes(permission);
  }

  canAny(...permissions: string[]): boolean {
    return permissions.some((p) => this.can(p));
  }

  /** Does the person work in this service? */
  works(service: ServiceName): boolean {
    return (this.user()?.services ?? []).includes(service);
  }

  switchService(service: ServiceName): void {
    if (!this.works(service)) return;
    this.service.set(service);
    write(SERVICE_KEY, service);
  }

  /** Sign out here at once; tell the server too (so the token stops working), but never wait on it. */
  logout(goToLogin = true): void {
    if (this.token()) {
      this.http.post(`${environment.apiUrl}/auth/logout`, {}).subscribe({ error: () => undefined });
    }
    this.clear();
    if (goToLogin) void this.router.navigate(['/login']);
  }

  /** Forget the session without telling the server (it already said the token is no good). */
  clear(): void {
    this.token.set(null);
    this.user.set(null);
    write(TOKEN_KEY, null);
    write(USER_KEY, null);
    write(SERVICE_KEY, null);
  }
}
