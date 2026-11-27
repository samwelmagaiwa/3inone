import { Injectable } from '@angular/core';
import Swal from 'sweetalert2';

export interface ConfirmOptions {
  title: string;
  message: string;
  confirmLabel?: string;
  cancelLabel?: string;
  /** Destructive actions (delete, remove) use the red button. */
  danger?: boolean;
}

/**
 * Replaces window.confirm() and window.alert() with SweetAlert2 dialogs styled like the rest of
 * the application (see the .swal-bs classes in styles.css).
 *
 *   if (!(await this.confirm.ask({ title: 'Delete submission', message: '…', danger: true }))) return;
 */
@Injectable({ providedIn: 'root' })
export class ConfirmService {
  private readonly classes = {
    popup: 'swal-bs-popup',
    title: 'swal-bs-title',
    htmlContainer: 'swal-bs-text',
    actions: 'swal-bs-actions',
    cancelButton: 'swal-bs-cancel',
  };

  /** A yes/no question; resolves true only when the user confirms. */
  async ask(options: ConfirmOptions): Promise<boolean> {
    const result = await Swal.fire({
      title: options.title,
      text: options.message,
      icon: options.danger ? 'warning' : 'question',
      showCancelButton: true,
      confirmButtonText: options.confirmLabel || 'Confirm',
      cancelButtonText: options.cancelLabel || 'Cancel',
      reverseButtons: true,
      focusCancel: !!options.danger,
      buttonsStyling: false,
      customClass: { ...this.classes, confirmButton: options.danger ? 'swal-bs-confirm swal-bs-danger' : 'swal-bs-confirm' },
    });
    return result.isConfirmed;
  }

  /**
   * A question that needs a few words written (why a payment is turned down, why a member is suspended). Resolves the text, or null when
   * the person cancels. The confirm button stays off until at least [minLength] letters are written.
   */
  async askText(options: ConfirmOptions & { placeholder?: string; minLength?: number; initial?: string }): Promise<string | null> {
    const min = options.minLength ?? 3;
    const result = await Swal.fire({
      title: options.title,
      text: options.message,
      input: 'textarea',
      inputValue: options.initial ?? '',
      inputPlaceholder: options.placeholder ?? '',
      inputAttributes: { maxlength: '255' },
      showCancelButton: true,
      confirmButtonText: options.confirmLabel || 'Confirm',
      cancelButtonText: options.cancelLabel || 'Cancel',
      reverseButtons: true,
      buttonsStyling: false,
      inputValidator: (v) => ((v ?? '').trim().length < min ? options.placeholder || ' ' : null),
      customClass: { ...this.classes, input: 'swal-bs-pre', confirmButton: options.danger ? 'swal-bs-confirm swal-bs-danger' : 'swal-bs-confirm' },
    });
    return result.isConfirmed ? String(result.value ?? '').trim() : null;
  }

  /** A message the user has to acknowledge. */
  async notify(title: string, message: string, type: 'info' | 'success' | 'warning' | 'error' = 'info'): Promise<void> {
    await Swal.fire({
      title,
      text: message,
      icon: type,
      confirmButtonText: 'OK',
      buttonsStyling: false,
      customClass: { ...this.classes, confirmButton: 'swal-bs-confirm' },
    });
  }
}
