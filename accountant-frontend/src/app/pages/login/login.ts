import { Component, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { Router } from '@angular/router';

import { environment } from '../../../environments/environment';
import { AuthService } from '../../core/auth.service';
import { errorMessage } from '../../core/format';

@Component({
  selector: 'app-login',
  imports: [ReactiveFormsModule],
  templateUrl: './login.html',
})
export class LoginPage {
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);

  protected readonly appName = environment.appName;
  protected readonly busy = signal(false);
  protected readonly error = signal<string | null>(null);

  protected readonly form = inject(FormBuilder).nonNullable.group({
    email: ['', [Validators.required, Validators.email]],
    // Only a sanity check (some digits); which numbers are valid is decided by the server, in one place.
    phone: ['', [Validators.required, Validators.pattern(/^\+?[\d\s-]{9,20}$/)]],
    password: ['', Validators.required],
  });

  protected async submit(): Promise<void> {
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }
    const { email, phone, password } = this.form.getRawValue();
    this.busy.set(true);
    this.error.set(null);
    try {
      // spaces and dashes typed for readability are dropped; the server checks the number itself
      await this.auth.login(email.trim(), phone.replace(/[\s-]/g, ''), password);
      await this.router.navigate(['/']);
    } catch (err) {
      this.error.set(errorMessage(err));
    } finally {
      this.busy.set(false);
    }
  }
}
