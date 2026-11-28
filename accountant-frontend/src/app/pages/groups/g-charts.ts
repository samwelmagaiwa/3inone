import { Component, computed, input } from '@angular/core';

/** One slice of a chart: what it is, how much, and its colour from G_COLORS. */
export interface GSlice {
  label: string;
  value: number;
  color: GColor;
  /** the full figure for the tooltip (the chart itself shows a short one) */
  full?: string;
}

export type GColor = 'purple' | 'blue' | 'green' | 'yellow' | 'red' | 'gray' | 'violet' | 'teal';

/** The charts' eight colours: a soft fill, a stronger edge, and a lighter shade for the words (they sit on the dark Groups cards). */
export const G_COLORS: Record<GColor, { fill: string; edge: string; text: string }> = {
  purple: { fill: '#8576ee', edge: '#6c5ce7', text: '#b3a8ff' },
  blue: { fill: '#74b9ff', edge: '#4a9df8', text: '#9fd0ff' },
  green: { fill: '#6fd08c', edge: '#3fba68', text: '#8ee6a8' },
  yellow: { fill: '#fdd46b', edge: '#f5b82e', text: '#ffe08a' },
  red: { fill: '#ee8585', edge: '#e46262', text: '#ffa3a3' },
  gray: { fill: '#a0a7b4', edge: '#7f8794', text: '#d3d8e0' },
  violet: { fill: '#a987dc', edge: '#8e63d2', text: '#d0b8f5' },
  teal: { fill: '#72e3c2', edge: '#3fcfa6', text: '#9af0d6' },
};

/** A short figure for a chart label: 868K, 1.3M. */
export function shortMoney(v: number): string {
  const a = Math.abs(v);
  if (a >= 1_000_000) return (v / 1_000_000).toFixed(a >= 10_000_000 ? 0 : 1).replace(/\.0$/, '') + 'M';
  if (a >= 1_000) return Math.round(v / 1_000) + 'K';
  return String(Math.round(v));
}

const TAU = Math.PI * 2;
/** The point at [r] and angle [a] (radians, 0 = 12 o'clock, clockwise) around (cx, cy). */
function at(cx: number, cy: number, r: number, a: number): [number, number] {
  return [cx + r * Math.sin(a), cy - r * Math.cos(a)];
}
/** A filled wedge (or a ring piece when [r0] > 0) from angle [a0] to [a1]. */
function wedge(cx: number, cy: number, r: number, a0: number, a1: number, r0 = 0): string {
  if (a1 - a0 >= TAU - 1e-6) {
    // a whole circle cannot be one arc: two halves
    const outer = `M ${cx} ${cy - r} A ${r} ${r} 0 1 1 ${cx} ${cy + r} A ${r} ${r} 0 1 1 ${cx} ${cy - r} Z`;
    return r0 > 0 ? `${outer} M ${cx} ${cy - r0} A ${r0} ${r0} 0 1 0 ${cx} ${cy + r0} A ${r0} ${r0} 0 1 0 ${cx} ${cy - r0} Z` : outer;
  }
  const large = a1 - a0 > Math.PI ? 1 : 0;
  const [x1, y1] = at(cx, cy, r, a0);
  const [x2, y2] = at(cx, cy, r, a1);
  if (r0 <= 0) return `M ${cx} ${cy} L ${x1} ${y1} A ${r} ${r} 0 ${large} 1 ${x2} ${y2} Z`;
  const [x3, y3] = at(cx, cy, r0, a1);
  const [x4, y4] = at(cx, cy, r0, a0);
  return `M ${x1} ${y1} A ${r} ${r} 0 ${large} 1 ${x2} ${y2} L ${x3} ${y3} A ${r0} ${r0} 0 ${large} 0 ${x4} ${y4} Z`;
}
const r1 = (v: number) => Math.round(v * 10) / 10;

/**
 * The flower chart (polar area): every slice has the same angle, its length shows how much. A legend on the left, rings with their
 * figures, and a dotted pointer from each slice to its name and (figure), coloured like the slice.
 */
@Component({
  selector: 'app-g-rose',
  template: `
    <div class="g-legend-row">
      @for (s of parts(); track s.key) {
        <span class="g-key"><i [style.background]="s.c.fill" [style.border-color]="s.c.edge"></i>{{ s.name }}</span>
      }
    </div>
    <svg class="g-svg" viewBox="0 0 720 575" role="img" [attr.aria-label]="label()">
      <defs>
        @for (s of parts(); track s.key) {
          <marker [attr.id]="'g-arrow-' + s.key" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
            <path d="M 0 0 L 10 5 L 0 10 z" [attr.fill]="s.c.edge" />
          </marker>
        }
      </defs>
      @for (t of ticks(); track t.r) {
        <circle [attr.cx]="cx" [attr.cy]="cy" [attr.r]="t.r" fill="none" stroke="rgba(255,255,255,0.18)" stroke-width="1.2" />
      }
      @for (s of parts(); track s.key) {
        <path [attr.d]="s.d" [attr.fill]="s.c.fill" fill-opacity="0.92" [attr.stroke]="s.c.edge" stroke-width="2"><title>{{ s.name }}: {{ s.full }}</title></path>
      }
      @for (t of ticks(); track t.r) {
        <rect [attr.x]="cx - 24" [attr.y]="cy - t.r - 12" width="48" height="24" rx="4" fill="#0e3a47" fill-opacity="0.95" />
        <text [attr.x]="cx" [attr.y]="cy - t.r + 6" text-anchor="middle" class="g-tick">{{ t.label }}</text>
      }
      @for (s of parts(); track s.key) {
        <line [attr.x1]="s.lx1" [attr.y1]="s.ly1" [attr.x2]="s.lx2" [attr.y2]="s.ly2" [attr.stroke]="s.c.edge" stroke-width="1.4" stroke-dasharray="2 3" [attr.marker-end]="'url(#g-arrow-' + s.key + ')'" />
        <text [attr.x]="s.tx" [attr.y]="s.ty" [attr.text-anchor]="s.anchor" class="g-call" [attr.fill]="s.c.text">
          @if (s.below) {
            <tspan [attr.x]="s.tx" dy="0">({{ s.short }})</tspan><tspan [attr.x]="s.tx" dy="23">{{ s.name }}</tspan>
          } @else {
            <tspan [attr.x]="s.tx" dy="-23">{{ s.name }}</tspan><tspan [attr.x]="s.tx" dy="23">({{ s.short }})</tspan>
          }
        </text>
      }
    </svg>
  `,
  styles: [`
    .g-svg { width: 100%; height: auto; display: block; overflow: visible; margin-top: 4px; }
    .g-legend-row { display: flex; flex-wrap: wrap; justify-content: center; gap: 6px 16px; }
    .g-key { display: inline-flex; align-items: center; gap: 6px; font-size: 14px; font-weight: 700; color: #fff; }
    .g-key i { width: 18px; height: 18px; border-radius: 50%; border: 1.5px solid; display: inline-block; }
    .g-tick { font-size: 15px; font-weight: 800; fill: #fff; }
    .g-call { font-size: 19px; font-weight: 800; }
  `],
})
export class GRoseChart {
  readonly slices = input.required<GSlice[]>();
  readonly label = input('');

  protected readonly cx = 360;
  protected readonly cy = 280;
  private readonly R = 210;

  /** The biggest slice reaches the outer ring, so the chart fills its space. */
  private readonly top = computed(() => Math.max(1, ...this.slices().map((s) => s.value)));

  /** The rings at a quarter, half, three quarters and all of the radius, each with the figure a slice reaching it holds. */
  protected readonly ticks = computed(() => [0.25, 0.5, 0.75, 1].map((f) => ({ r: r1(this.R * f), label: shortMoney(this.top() * f * f) })));

  protected readonly parts = computed(() => {
    const list = this.slices();
    const step = TAU / Math.max(1, list.length);
    return list.map((s, i) => {
      // the AREA shows the amount (radius by the square root), so a small kind stays visible beside a big one
      const r = Math.max(this.R * 0.16, this.R * Math.sqrt(s.value / this.top()));
      const a0 = i * step;
      const a1 = a0 + step;
      const mid = a0 + step / 2;
      const [lx1, ly1] = at(this.cx, this.cy, r * 0.85, mid);
      const [lx2, ly2] = at(this.cx, this.cy, this.R + 22, mid);
      const [tx, ty] = at(this.cx, this.cy, this.R + 36, mid);
      const sin = Math.sin(mid);
      return {
        key: i,
        name: s.label.toUpperCase(),
        short: shortMoney(s.value),
        full: s.full ?? String(s.value),
        c: G_COLORS[s.color],
        d: wedge(this.cx, this.cy, r, a0, a1),
        lx1: r1(lx1), ly1: r1(ly1), lx2: r1(lx2), ly2: r1(ly2),
        tx: r1(tx), ty: r1(ty + (Math.cos(mid) < -0.3 ? 24 : 0)),
        anchor: sin > 0.25 ? 'start' : sin < -0.25 ? 'end' : 'middle',
        below: Math.cos(mid) < 0,
      };
    });
  });
}

/**
 * The full pie, or the ring (donut) when [ring] is set: the figure and its share written on each slice, the legend above as round dots.
 */
@Component({
  selector: 'app-g-pie',
  template: `
    <div class="g-legend-row">
      @for (s of slices(); track s.label) {
        <span class="g-key"><i [style.background]="g(s).fill" [style.border-color]="g(s).edge"></i>{{ s.label }}</span>
      }
    </div>
    <svg class="g-svg" viewBox="0 0 320 320" role="img" [attr.aria-label]="label()">
      @if (total() <= 0) {
        <circle cx="160" cy="160" [attr.r]="ring() ? 130 : 140" fill="none" stroke="rgba(255,255,255,0.18)" [attr.stroke-width]="ring() ? 30 : 2" />
        <text x="160" y="166" text-anchor="middle" class="g-empty">{{ empty() }}</text>
      } @else {
        @for (p of parts(); track p.key) {
          <path [attr.d]="p.d" [attr.fill]="p.c.fill" [attr.stroke]="p.c.edge" stroke-width="1.5" fill-rule="evenodd"><title>{{ p.name }}: {{ p.full }}</title></path>
        }
        @for (p of parts(); track p.key) {
          @if (p.share >= 0.06) {
            <text [attr.x]="p.x" [attr.y]="p.y" text-anchor="middle" class="g-val" [class.g-ring-val]="ring()">{{ p.short }}</text>
            <text [attr.x]="p.x" [attr.y]="p.y + (ring() ? 19 : 26)" text-anchor="middle" class="g-pct" [class.g-ring-val]="ring()">{{ p.pct }}%</text>
          }
        }
      }
    </svg>
  `,
  styles: [`
    .g-svg { width: 100%; max-width: 380px; height: auto; display: block; margin: 8px auto 0; overflow: visible; }
    .g-legend-row { display: flex; flex-wrap: wrap; justify-content: center; gap: 6px 14px; }
    .g-key { display: inline-flex; align-items: center; gap: 6px; font-size: 15px; font-weight: 700; color: #fff; }
    .g-key i { width: 20px; height: 20px; border-radius: 50%; border: 1.5px solid; display: inline-block; }
    /* dark ink on the light slice colours: it reads on every one of them */
    .g-val { font-size: 27px; font-weight: 900; fill: #0d1b2a; }
    .g-pct { font-size: 18px; font-weight: 700; fill: #0d1b2a; fill-opacity: 0.85; }
    .g-ring-val { font-size: 20px; }
    .g-pct.g-ring-val { font-size: 14px; }
    .g-empty { font-size: 15px; fill: rgba(255, 255, 255, 0.6); }
  `],
})
export class GPieChart {
  readonly slices = input.required<GSlice[]>();
  readonly ring = input(false);
  readonly label = input('');
  readonly empty = input('—');

  protected readonly total = computed(() => this.slices().reduce((a, s) => a + Math.max(0, s.value), 0));

  protected g(s: GSlice) {
    return G_COLORS[s.color];
  }

  protected readonly parts = computed(() => {
    const total = this.total();
    const outer = this.ring() ? 152 : 146;
    const inner = this.ring() ? 96 : 0;
    let a = 0;
    return this.slices().filter((s) => s.value > 0).map((s, i) => {
      const share = s.value / total;
      const a0 = a;
      a += share * TAU;
      const mid = (a0 + a) / 2;
      const [x, y] = at(160, 160, this.ring() ? (outer + inner) / 2 : outer * 0.58, mid);
      return {
        key: i, name: s.label, full: s.full ?? String(s.value), c: G_COLORS[s.color], share,
        d: wedge(160, 160, outer, a0, a, inner),
        x: r1(x), y: r1(y - (this.ring() ? 2 : 4)),
        short: shortMoney(s.value),
        pct: (share * 100).toFixed(1),
      };
    });
  });
}
