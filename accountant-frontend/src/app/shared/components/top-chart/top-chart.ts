import { Component, Input, computed, signal } from '@angular/core';

export interface ChartItem {
  name: string;
  value: number;
}

/** The colours of the bars, in order (blue, teal, green, mint, yellow, orange, red, pink), and of the trend line through their tops. */
export const BAR_COLORS = ['#007bff', '#17a2b8', '#28a745', '#20c997', '#ffc107', '#fd7e14', '#dc3545', '#e83e8c'];
export const TREND_COLOR = '#003580';

const W = 760;
const H = 380;
const M = { left: 64, right: 16, top: 34, bottom: 112 };

/** 11.5M, 120K, 950 */
export function shortAmount(v: number): string {
  const a = Math.abs(v);
  if (a >= 1_000_000) return `${(v / 1_000_000).toFixed(1)}M`;
  if (a >= 1_000) return `${(v / 1_000).toFixed(a >= 100_000 ? 0 : 1)}K`;

  return String(Math.round(v));
}

function niceCeil(v: number): number {
  if (v <= 0) return 1;
  const p = Math.pow(10, Math.floor(Math.log10(v)));
  for (const m of [1, 2, 2.5, 5, 10]) if (v <= m * p) return m * p;

  return 10 * p;
}

/**
 * Coloured bars with their figure above in the same colour and a smooth trend line through their tops (white-ringed dots) on a light
 * grid: what earned most, one bar each. Drawn as SVG, so it needs no library and scales to its box.
 */
@Component({
  selector: 'app-top-chart',
  standalone: true,
  template: `
    @if (items.length) {
      <div class="tc" data-testid="top-chart">
        <div class="tc-legend">
          <span><i class="dot" [style.background]="trend"></i>{{ trendLabel }}</span>
          <span><i class="dot" [style.background]="colors[0]"></i>{{ legend }}</span>
        </div>
        <svg [attr.viewBox]="'0 0 ' + w + ' ' + h" role="img" [attr.aria-label]="legend">
          @for (g of grid(); track g.y) {
            <line [attr.x1]="m.left" [attr.x2]="w - m.right" [attr.y1]="g.y" [attr.y2]="g.y" stroke="#e5e7eb" stroke-width="1" />
            <text [attr.x]="m.left - 8" [attr.y]="g.y + 4" text-anchor="end" class="tc-axis">{{ g.label }}</text>
          }
          <text [attr.x]="14" [attr.y]="(m.top + h - m.bottom) / 2" text-anchor="middle" class="tc-title" [attr.transform]="'rotate(-90 14 ' + (m.top + h - m.bottom) / 2 + ')'">{{ legend }}</text>
          @for (b of bars(); track $index) {
            <path [attr.d]="b.path" [attr.fill]="b.color" data-testid="top-chart-bar" />
          }
          <path [attr.d]="curve()" fill="none" [attr.stroke]="trend" stroke-width="3.5" stroke-linecap="round" />
          @for (b of bars(); track $index) {
            <circle [attr.cx]="b.cx" [attr.cy]="b.top" r="7" fill="#fff" [attr.stroke]="trend" stroke-width="4" />
            <text [attr.x]="b.cx" [attr.y]="b.top - 14" text-anchor="middle" class="tc-value" [attr.fill]="b.color">{{ b.label }}</text>
            <text [attr.x]="b.cx + 6" [attr.y]="h - m.bottom + 18" text-anchor="end" class="tc-name" [attr.transform]="'rotate(-45 ' + (b.cx + 6) + ' ' + (h - m.bottom + 18) + ')'">{{ b.name }}</text>
          }
        </svg>
      </div>
    }
  `,
  styles: [`
    :host { display: block; }
    .tc-legend { display: flex; justify-content: center; flex-wrap: wrap; gap: 6px 22px; font-size: 13px; font-weight: 800; color: #555; margin-bottom: 4px; }
    .tc-legend .dot { display: inline-block; width: 14px; height: 14px; border-radius: 50%; margin-right: 7px; vertical-align: -2px; }
    svg { width: 100%; height: auto; display: block; }
    .tc-axis { font: 600 12px 'Segoe UI', Arial, sans-serif; fill: #555; }
    .tc-title { font: 800 13px 'Segoe UI', Arial, sans-serif; fill: #222; }
    .tc-value { font: 900 17px 'Segoe UI', Arial, sans-serif; paint-order: stroke; stroke: #fff; stroke-width: 3px; }
    .tc-name { font: 800 11.5px 'Segoe UI', Arial, sans-serif; fill: #333; text-transform: uppercase; }
  `],
})
export class TopChartComponent {
  protected readonly w = W;
  protected readonly h = H;
  protected readonly m = M;
  protected readonly colors = BAR_COLORS;
  protected readonly trend = TREND_COLOR;

  private readonly data = signal<ChartItem[]>([]);

  @Input() set items(value: ChartItem[]) {
    this.data.set(value ?? []);
  }
  get items(): ChartItem[] {
    return this.data();
  }

  /** What the bars are ("Profit (TSH)"), and the name of the line. */
  @Input() legend = '';
  @Input() trendLabel = 'Trend line';

  private readonly max = computed(() => niceCeil(Math.max(...this.data().map((i) => i.value), 0) * 1.12));

  protected readonly grid = computed(() => {
    const top = M.top;
    const bottom = H - M.bottom;
    const max = this.max();

    return Array.from({ length: 6 }, (_, i) => ({ y: bottom - ((bottom - top) * i) / 5, label: shortAmount((max / 5) * i) }));
  });

  protected readonly bars = computed(() => {
    const n = this.data().length;
    const plotW = W - M.left - M.right;
    const plotH = H - M.top - M.bottom;
    const slot = plotW / Math.max(n, 1);
    const bw = Math.min(slot * 0.56, 72);
    const max = this.max();

    return this.data().map((it, i) => {
      const cx = M.left + slot * i + slot / 2;
      const bh = plotH * (it.value / max);
      const top = M.top + plotH - bh;
      const x = cx - bw / 2;
      const r = 4;
      const path = `M${x},${top + bh} V${top + r} Q${x},${top} ${x + r},${top} H${x + bw - r} Q${x + bw},${top} ${x + bw},${top + r} V${top + bh} Z`;
      const name = it.name.length > 18 ? `${it.name.slice(0, 17)}…` : it.name;

      return { cx, top, path, color: BAR_COLORS[i % BAR_COLORS.length], label: shortAmount(it.value), name };
    });
  });

  /** A smooth curve through the tops of the bars. */
  protected readonly curve = computed(() => {
    const p = this.bars().map((b) => ({ x: b.cx, y: b.top }));
    if (p.length < 2) return '';
    let d = `M${p[0].x},${p[0].y}`;
    for (let i = 0; i < p.length - 1; i++) {
      const p0 = p[i - 1] ?? p[i];
      const p1 = p[i];
      const p2 = p[i + 1];
      const p3 = p[i + 2] ?? p2;
      d += ` C${p1.x + (p2.x - p0.x) / 6},${p1.y + (p2.y - p0.y) / 6} ${p2.x - (p3.x - p1.x) / 6},${p2.y - (p3.y - p1.y) / 6} ${p2.x},${p2.y}`;
    }

    return d;
  });
}
