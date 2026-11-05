import { Component, Input, computed, inject } from '@angular/core';

import { ExportSheet, downloadCsv, downloadXlsx, printSheet } from '../../../core/export';
import { I18nService } from '../../../core/i18n.service';
import { MenuItem, RowMenuComponent } from '../row-menu/row-menu';

/**
 * "Export": print the list or save it as a PDF, save it as an Excel workbook, or as a CSV sheet. The page gives a function that builds the
 * sheet (so it is made from what is on the page at the moment of the click: the filtered list, with its totals).
 */
@Component({
  selector: 'app-export-menu',
  standalone: true,
  imports: [RowMenuComponent],
  template: `<app-row-menu [label]="i18n.t('export.button')" [items]="items()" testid="export-menu" (picked)="run($event)" />`,
})
export class ExportMenuComponent {
  protected readonly i18n = inject(I18nService);

  @Input({ required: true }) build!: () => ExportSheet;

  protected readonly items = computed<MenuItem[]>(() => [
    { id: 'print', label: this.i18n.t('export.print'), testid: 'export-print' },
    { id: 'xlsx', label: this.i18n.t('export.excel'), testid: 'export-excel' },
    { id: 'csv', label: this.i18n.t('export.csv'), testid: 'export-csv' },
  ]);

  protected run(id: string): void {
    const sheet = this.build();
    sheet.printLabel = this.i18n.t('export.printbtn');
    sheet.printedLabel = this.i18n.t('receipt.printed');
    if (id === 'print') printSheet(sheet);
    else if (id === 'xlsx') downloadXlsx(sheet);
    else downloadCsv(sheet);
  }
}
