import { tsh } from './format';

/** One column of a sheet: what it is called, how it lines up, and how wide it is in Excel (characters). */
export interface SheetColumn {
  label: string;
  /** `money` cells are numbers in Excel (so they add up) and "TSH 1,000" on paper; `number` cells are plain numbers. */
  type?: 'text' | 'money' | 'number';
  align?: 'left' | 'right' | 'center';
  width?: number;
}

/** A list ready to be printed or saved: the business and title on top, a few facts, the table, and a totals row. */
export interface ExportSheet {
  business: string;
  title: string;
  /** Lines under the title: the period, who it is for, the figures that sum it up. */
  facts: string[];
  columns: SheetColumn[];
  rows: (string | number | null)[][];
  /** The last row, in bold: the same columns (null leaves a cell empty). */
  totals?: (string | number | null)[];
  /** Printed on the bottom of the page. */
  footer?: string;
  /** The words for "printed" and the like come from the page so they follow the language. */
  printedLabel?: string;
  printLabel?: string;
}

const esc = (s: unknown): string => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c] as string);

/** A file name that is safe on every computer: letters, digits, dashes. */
export function fileName(title: string, ext: string): string {
  const day = new Date().toISOString().slice(0, 10);
  const base = title.normalize('NFKD').replace(/[^\w]+/g, '-').replace(/^-+|-+$/g, '') || 'export';

  return `${base}-${day}.${ext}`;
}

function save(name: string, blob: Blob): void {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 2000);
}

// ---------------------------------------------------------------------------------------------- paper (print, or "Save as PDF")

const cell = (c: SheetColumn, v: string | number | null): string => {
  if (v === null || v === undefined || v === '') return '';
  return c.type === 'money' && typeof v === 'number' ? tsh(v) : esc(v);
};

/** The sheet as a printable page: a clean table on white, headed by the business. The browser's print window saves it as a PDF. */
export function sheetHtml(sheet: ExportSheet): string {
  const wide = sheet.columns.length > 7;
  const head = sheet.columns.map((c) => `<th class="${c.align ?? 'left'}">${esc(c.label)}</th>`).join('');
  const body = sheet.rows.map((r) => `<tr>${sheet.columns.map((c, i) => `<td class="${c.align ?? (c.type === 'money' || c.type === 'number' ? 'right' : 'left')}">${cell(c, r[i])}</td>`).join('')}</tr>`).join('');
  const total = sheet.totals ? `<tr class="total">${sheet.columns.map((c, i) => `<td class="${c.align ?? (c.type === 'money' || c.type === 'number' ? 'right' : 'left')}">${cell(c, sheet.totals![i])}</td>`).join('')}</tr>` : '';

  return `<!doctype html><html><head><meta charset="utf-8"><title>${esc(sheet.title)}</title>
<style>
@page{size:A4 ${wide ? 'landscape' : 'portrait'};margin:12mm}
*{box-sizing:border-box;-webkit-print-color-adjust:exact;print-color-adjust:exact}
body{font:12.5px/1.45 "Segoe UI",Arial,Helvetica,sans-serif;margin:0 auto;padding:18px;color:#1e293b;background:#fff}
.top{display:flex;justify-content:space-between;align-items:flex-end;gap:20px;padding-bottom:10px;border-bottom:3px solid #1a2f6e}
.top h1{margin:0;font-size:22px;color:#1a2f6e}
.top .t{font-size:18px;font-weight:800;letter-spacing:1px;color:#1a2f6e;text-transform:uppercase;text-align:right}
.facts{display:flex;flex-wrap:wrap;gap:8px 22px;margin:12px 0 4px;color:#334155}
.facts span{padding:3px 12px;border:1px solid #cfd9f3;border-radius:999px;background:#f6f8ff;font-weight:600}
table{width:100%;border-collapse:collapse;margin-top:12px}
th{background:#1a2f6e;color:#fff;font-size:11.5px;letter-spacing:.3px;padding:8px 9px;border:1px solid #1a2f6e;text-align:left}
td{padding:7px 9px;border:1px solid #dbe4f7;vertical-align:top}
tbody tr:nth-child(even){background:#f6f8ff}
.right{text-align:right;white-space:nowrap}
.center{text-align:center}
tr.total td{background:#e8eefc;font-weight:800;color:#1a2f6e;border-top:2px solid #1a2f6e}
.foot{margin-top:16px;padding-top:8px;border-top:1px solid #cbd5e1;color:#94a3b8;font-size:10.5px;display:flex;justify-content:space-between}
thead{display:table-header-group}
tr{page-break-inside:avoid}
.bar{display:flex;justify-content:flex-end;padding-bottom:10px}
.bar button{padding:8px 16px;border:1px solid #1a2f6e;border-radius:8px;background:#1a2f6e;color:#fff;font-weight:700;cursor:pointer}
@media print{.bar{display:none}body{padding:0}}
</style></head><body>
<div class="bar"><button onclick="window.print()">${esc(sheet.printLabel ?? 'Print')}</button></div>
<div class="top"><h1>${esc(sheet.business)}</h1><div class="t">${esc(sheet.title)}</div></div>
${sheet.facts.length ? `<div class="facts">${sheet.facts.map((f) => `<span>${esc(f)}</span>`).join('')}</div>` : ''}
<table><thead><tr>${head}</tr></thead><tbody>${body}${total}</tbody></table>
<div class="foot"><span>${esc(sheet.footer ?? '')}</span><span>${esc(sheet.printedLabel ?? 'Printed')} ${esc(new Date().toLocaleString())}</span></div>
<script>window.onload=function(){setTimeout(function(){window.print()},250)}</script></body></html>`;
}

/** Open the printable page; the person prints it or chooses "Save as PDF" as the printer. */
export function printSheet(sheet: ExportSheet): void {
  const w = window.open('', '_blank', 'width=1100,height=850');
  if (!w) return;
  w.document.write(sheetHtml(sheet));
  w.document.close();
}

// ---------------------------------------------------------------------------------------------- CSV

/** The sheet as CSV, which Excel opens (with a byte-order mark so Swahili and other letters stay right). */
export function sheetCsv(sheet: ExportSheet): string {
  const q = (v: unknown): string => {
    const s = String(v ?? '');
    return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const lines: string[] = [[sheet.business].map(q).join(','), [sheet.title].map(q).join(',')];
  for (const f of sheet.facts) lines.push(q(f));
  lines.push('');
  lines.push(sheet.columns.map((c) => q(c.label)).join(','));
  for (const r of sheet.rows) lines.push(r.map(q).join(','));
  if (sheet.totals) lines.push(sheet.totals.map(q).join(','));

  return '﻿' + lines.join('\r\n') + '\r\n';
}

export function downloadCsv(sheet: ExportSheet): void {
  save(fileName(sheet.title, 'csv'), new Blob([sheetCsv(sheet)], { type: 'text/csv;charset=utf-8' }));
}

// ---------------------------------------------------------------------------------------------- Excel (.xlsx), written by hand

const enc = new TextEncoder();

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }

  return t;
})();

function crc32(bytes: Uint8Array): number {
  let c = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);

  return (c ^ 0xffffffff) >>> 0;
}

/** A ZIP with the files stored as they are (no compression): the .xlsx container. */
export function zip(files: { name: string; data: string }[]): Uint8Array {
  const parts: Uint8Array[] = [];
  const central: Uint8Array[] = [];
  let offset = 0;
  const u16 = (v: number) => new Uint8Array([v & 255, (v >>> 8) & 255]);
  const u32 = (v: number) => new Uint8Array([v & 255, (v >>> 8) & 255, (v >>> 16) & 255, (v >>> 24) & 255]);
  const join = (...a: Uint8Array[]): Uint8Array => {
    const out = new Uint8Array(a.reduce((n, x) => n + x.length, 0));
    let p = 0;
    for (const x of a) {
      out.set(x, p);
      p += x.length;
    }

    return out;
  };
  const dosTime = 0;
  const dosDate = ((2026 - 1980) << 9) | (1 << 5) | 1;

  for (const f of files) {
    const name = enc.encode(f.name);
    const data = enc.encode(f.data);
    const crc = crc32(data);
    const local = join(u32(0x04034b50), u16(20), u16(0x0800), u16(0), u16(dosTime), u16(dosDate), u32(crc), u32(data.length), u32(data.length), u16(name.length), u16(0), name, data);
    parts.push(local);
    central.push(join(u32(0x02014b50), u16(20), u16(20), u16(0x0800), u16(0), u16(dosTime), u16(dosDate), u32(crc), u32(data.length), u32(data.length), u16(name.length), u16(0), u16(0), u16(0), u16(0), u32(0), u32(offset), name));
    offset += local.length;
  }
  const dir = join(...central);
  const end = join(u32(0x06054b50), u16(0), u16(0), u16(files.length), u16(files.length), u32(dir.length), u32(offset), u16(0));

  return join(...parts, dir, end);
}

const colName = (i: number): string => {
  let n = i + 1;
  let s = '';
  while (n > 0) {
    const r = (n - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    n = Math.floor((n - 1) / 26);
  }

  return s;
};

const STYLES = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<numFmts count="1"><numFmt numFmtId="164" formatCode="#,##0"/></numFmts>
<fonts count="5">
<font><sz val="11"/><name val="Calibri"/></font>
<font><b/><sz val="11"/><name val="Calibri"/></font>
<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>
<font><b/><sz val="16"/><color rgb="FF1A2F6E"/><name val="Calibri"/></font>
<font><b/><sz val="13"/><color rgb="FF1A2F6E"/><name val="Calibri"/></font>
</fonts>
<fills count="4">
<fill><patternFill patternType="none"/></fill>
<fill><patternFill patternType="gray125"/></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FF1A2F6E"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFE8EEFC"/></patternFill></fill>
</fills>
<borders count="2">
<border><left/><right/><top/><bottom/><diagonal/></border>
<border><left style="thin"><color rgb="FFCFD9F3"/></left><right style="thin"><color rgb="FFCFD9F3"/></right><top style="thin"><color rgb="FFCFD9F3"/></top><bottom style="thin"><color rgb="FFCFD9F3"/></bottom><diagonal/></border>
</borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="12">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="0" fontId="4" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="0" fontId="2" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="center" wrapText="1"/></xf>
<xf numFmtId="0" fontId="2" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="center" wrapText="1"/></xf>
<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="top" wrapText="1"/></xf>
<xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="top"/></xf>
<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="top"/></xf>
<xf numFmtId="0" fontId="1" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>
<xf numFmtId="164" fontId="1" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right"/></xf>
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment horizontal="left"/></xf>
<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="left"/></xf>
</cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>`;

/** The sheet as the XML of an Excel worksheet: business and title on top, the facts, a header row, the data, and a totals row. */
export function sheetXml(sheet: ExportSheet): string {
  const cols = sheet.columns.length;
  const last = colName(cols - 1);
  const rows: string[] = [];
  let r = 1;
  const text = (ref: string, s: number, v: string) => `<c r="${ref}" s="${s}" t="inlineStr"><is><t xml:space="preserve">${esc(v)}</t></is></c>`;
  const merges: string[] = [];

  rows.push(`<row r="${r}" ht="24" customHeight="1">${text(`A${r}`, 1, sheet.business)}</row>`);
  merges.push(`A${r}:${last}${r}`);
  r++;
  rows.push(`<row r="${r}" ht="20" customHeight="1">${text(`A${r}`, 2, sheet.title)}</row>`);
  merges.push(`A${r}:${last}${r}`);
  r++;
  for (const f of sheet.facts) {
    rows.push(`<row r="${r}">${text(`A${r}`, 10, f)}</row>`);
    merges.push(`A${r}:${last}${r}`);
    r++;
  }
  r++; // a blank row before the table
  const headerRow = r;
  rows.push(`<row r="${r}" ht="22" customHeight="1">${sheet.columns.map((c, i) => text(`${colName(i)}${r}`, c.align === 'right' ? 4 : 3, c.label)).join('')}</row>`);
  r++;
  for (const row of sheet.rows) {
    rows.push(
      `<row r="${r}">${sheet.columns
        .map((c, i) => {
          const v = row[i];
          const ref = `${colName(i)}${r}`;
          if (v === null || v === undefined || v === '') return `<c r="${ref}" s="${c.type === 'money' ? 6 : 5}"/>`;
          if ((c.type === 'money' || c.type === 'number') && typeof v === 'number') return `<c r="${ref}" s="${c.type === 'money' ? 6 : 7}"><v>${v}</v></c>`;

          return text(ref, c.align === 'center' ? 7 : 5, String(v));
        })
        .join('')}</row>`,
    );
    r++;
  }
  if (sheet.totals) {
    rows.push(
      `<row r="${r}">${sheet.columns
        .map((c, i) => {
          const v = sheet.totals![i];
          const ref = `${colName(i)}${r}`;
          if (v === null || v === undefined || v === '') return `<c r="${ref}" s="8"/>`;
          if (c.type === 'money' && typeof v === 'number') return `<c r="${ref}" s="9"><v>${v}</v></c>`;

          return text(ref, 8, String(v));
        })
        .join('')}</row>`,
    );
  }

  const widths = sheet.columns.map((c, i) => `<col min="${i + 1}" max="${i + 1}" width="${c.width ?? 16}" customWidth="1"/>`).join('');

  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0" showGridLines="0"><pane ySplit="${headerRow}" topLeftCell="A${headerRow + 1}" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols>${widths}</cols><sheetData>${rows.join('')}</sheetData><mergeCells count="${merges.length}">${merges.map((m) => `<mergeCell ref="${m}"/>`).join('')}</mergeCells><pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" header="0.3" footer="0.3"/><pageSetup orientation="${cols > 7 ? 'landscape' : 'portrait'}" fitToWidth="1" fitToHeight="0"/></worksheet>`;
}

/** The whole .xlsx file as bytes. */
export function sheetXlsx(sheet: ExportSheet): Uint8Array {
  const name = esc(sheet.title.replace(/[\\/?*[\]:]/g, ' ').slice(0, 31) || 'Sheet1');

  return zip([
    { name: '[Content_Types].xml', data: '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>' },
    { name: '_rels/.rels', data: '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>' },
    { name: 'xl/workbook.xml', data: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="${name}" sheetId="1" r:id="rId1"/></sheets></workbook>` },
    { name: 'xl/_rels/workbook.xml.rels', data: '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>' },
    { name: 'xl/styles.xml', data: STYLES },
    { name: 'xl/worksheets/sheet1.xml', data: sheetXml(sheet) },
  ]);
}

export function downloadXlsx(sheet: ExportSheet): void {
  const bytes = sheetXlsx(sheet);
  save(fileName(sheet.title, 'xlsx'), new Blob([bytes as BlobPart], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }));
}
