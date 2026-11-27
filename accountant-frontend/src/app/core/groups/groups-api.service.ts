import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { firstValueFrom } from 'rxjs';

import { environment } from '../../../environments/environment';

/** A record as the server sends it. The Groups pages read fields by name, the way the phone's models do. */
export type Row = Record<string, any>;

/** One page of a list. */
export interface GPage {
  items: Row[];
  page: number;
  total: number;
  hasMore: boolean;
}

type Params = Record<string, string | number | boolean | null | undefined>;

function params(p?: Params): HttpParams {
  let out = new HttpParams();
  for (const [k, v] of Object.entries(p ?? {})) if (v !== null && v !== undefined && String(v).trim() !== '') out = out.set(k, String(v).trim());
  return out;
}

/**
 * The Groups (Vikundi) calls, the same ones the phone makes (groups_api.dart). Every answer is unwrapped to its `data`; a failed call
 * throws the HTTP error, whose message the pages show with serverMessage() in the person's language.
 */
@Injectable({ providedIn: 'root' })
export class GroupsApi {
  private readonly http = inject(HttpClient);

  private url(path: string): string {
    return `${environment.apiUrl}/groups${path}`;
  }

  async get(path: string, query?: Params): Promise<Row> {
    const r = await firstValueFrom(this.http.get<{ data?: Row }>(this.url(path), { params: params(query) }));
    return r?.data ?? {};
  }

  /** A list page: `data.<key>` with `meta.pagination`. */
  async page(path: string, key: string, query?: Params): Promise<GPage> {
    const r = await firstValueFrom(this.http.get<{ data?: Row; meta?: Row }>(this.url(path), { params: params(query) }));
    const p = r?.meta?.['pagination'] ?? {};
    const items = (r?.data?.[key] as Row[] | undefined) ?? [];

    return { items, page: Number(p['page'] ?? 1), total: Number(p['total'] ?? items.length), hasMore: p['has_more'] === true };
  }

  async post(path: string, body: Row = {}): Promise<Row> {
    const r = await firstValueFrom(this.http.post<{ data?: Row }>(this.url(path), body));
    return r?.data ?? {};
  }

  async put(path: string, body: Row = {}): Promise<Row> {
    const r = await firstValueFrom(this.http.put<{ data?: Row }>(this.url(path), body));
    return r?.data ?? {};
  }

  async del(path: string): Promise<Row> {
    const r = await firstValueFrom(this.http.delete<{ data?: Row }>(this.url(path)));
    return r?.data ?? {};
  }

  /** A file the server makes (a CSV), saved on the computer under [name]. */
  async download(path: string, name: string, query?: Params): Promise<void> {
    const blob = await firstValueFrom(this.http.get(this.url(path), { params: params(query), responseType: 'blob' }));
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = name;
    document.body.appendChild(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(link.href), 1000);
  }

  /** The business admin's logo for the group (its own; removing it goes back to the business logo). Not under /groups. */
  async uploadLogo(file: File): Promise<Row> {
    const form = new FormData();
    form.append('logo', file);
    form.append('service', 'groups');
    const r = await firstValueFrom(this.http.post<{ data?: Row }>(`${environment.apiUrl}/business/logo`, form));
    return r?.data ?? {};
  }

  async removeLogo(): Promise<Row> {
    const r = await firstValueFrom(this.http.delete<{ data?: Row }>(`${environment.apiUrl}/business/logo`, { params: params({ service: 'groups' }) }));
    return r?.data ?? {};
  }
}
