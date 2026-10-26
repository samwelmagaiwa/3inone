import { Injectable, signal } from '@angular/core';

export interface ToastItem {
  id: number;
  title?: string;
  message: string;
  type: 'success' | 'error' | 'warning' | 'info';
  timestamp: string;
}

@Injectable({
  providedIn: 'root',
})
export class ToastService {
  toasts = signal<ToastItem[]>([]);
  private counter = 0;

  show(message: string, type: ToastItem['type'] = 'info', title?: string) {
    const id = ++this.counter;
    const now = new Date().toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
    const item: ToastItem = {
      id,
      title: title || this.getDefaultTitle(type),
      message,
      type,
      timestamp: now,
    };

    this.toasts.update(list => [item, ...list]);

    setTimeout(() => {
      this.dismiss(id);
    }, 4500);
  }

  success(message: string, title: string = 'Success') {
    this.show(message, 'success', title);
  }

  error(message: string, title: string = 'System Alert') {
    this.show(message, 'error', title);
  }

  warning(message: string, title: string = 'Attention') {
    this.show(message, 'warning', title);
  }

  info(message: string, title: string = 'Information') {
    this.show(message, 'info', title);
  }

  dismiss(id: number) {
    this.toasts.update(list => list.filter(t => t.id !== id));
  }

  private getDefaultTitle(type: ToastItem['type']): string {
    switch (type) {
      case 'success': return 'Action Successful';
      case 'error': return 'Error Occurred';
      case 'warning': return 'Warning Alert';
      default: return 'System Notice';
    }
  }
}
