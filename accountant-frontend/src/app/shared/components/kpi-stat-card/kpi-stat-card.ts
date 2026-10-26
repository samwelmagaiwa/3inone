import { Component, Input } from '@angular/core';

@Component({
  selector: 'app-kpi-stat-card',
  standalone: true,
  template: `
    <div class="kpi-card kpi-primary">
      <div class="flex justify-between items-start">
        <div>
          <p class="label-eyebrow">{{ label }}</p>
          <h3 class="text-3xl font-black text-[#1a2f6e] tracking-tight mt-2">{{ value }}</h3>
        </div>
        <div class="w-11 h-11 flex items-center justify-center rounded-lg shadow-xs shrink-0" [class]="iconBgClass">
          <ng-content select="[slot=icon]"></ng-content>
        </div>
      </div>
      @if (sublabel) {
        <div class="mt-4 pt-3 border-t border-slate-100">
          <span class="text-[11px] font-bold text-slate-400 uppercase tracking-wide">{{ sublabel }}</span>
        </div>
      }
    </div>
  `,
})
export class KpiStatCardComponent {
  @Input({ required: true }) label: string = '';
  @Input({ required: true }) value: string | number = 0;
  @Input() sublabel?: string;
  @Input() variant: 'primary' | 'success' | 'warning' | 'danger' | 'purple' = 'primary';

  get iconBgClass(): string {
    switch (this.variant) {
      case 'success': return 'kpi-icon-success';
      case 'warning': return 'kpi-icon-warning';
      case 'danger':  return 'kpi-icon-danger';
      case 'purple':  return 'kpi-icon-purple';
      default:        return 'kpi-icon-primary';
    }
  }
}
