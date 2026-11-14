import { Component } from '@angular/core';
import { RouterOutlet } from '@angular/router';

import { installNoAutofill } from './shared/ui/no-autofill';
import { installTableLabels } from './shared/ui/table-labels';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet],
  template: `<router-outlet />`,
  styles: [':host { display: block; height: 100dvh; }'],
})
export class App {
  constructor() {
    installNoAutofill();
    installTableLabels();
  }
}
