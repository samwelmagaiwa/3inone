import { ExportSheet, fileName, sheetCsv, sheetHtml, sheetXlsx, sheetXml, zip } from './export';

const sheet: ExportSheet = {
  business: 'Mary\'s Beauty',
  title: 'Expenses',
  facts: ['Month: 01/11/2026 – 05/11/2026', 'Business: TSH 120,000'],
  columns: [
    { label: '#', align: 'center', width: 6 },
    { label: 'What for', width: 30 },
    { label: 'Amount', type: 'money', align: 'right', width: 16 },
  ],
  rows: [
    [1, 'Shop rent, "main"', 100000],
    [2, 'Transport <bus>', 20000],
  ],
  totals: [null, 'Total', 120000],
};

const text = (bytes: Uint8Array): string => new TextDecoder().decode(bytes);

describe('exporting a list', () => {
  it('the printable page has the business, the title, the facts, every row and a totals row, and escapes what people typed', () => {
    const html = sheetHtml(sheet);
    for (const part of ['Mary\'s Beauty', 'Expenses', 'Month: 01/11/2026', 'Shop rent, &quot;main&quot;', 'Transport &lt;bus&gt;', 'TSH 100,000', 'class="total"', 'TSH 120,000']) expect(html).toContain(part);
    expect(html).not.toContain('<bus>');
    expect(html).toContain('size:A4 portrait');
  });

  it('a wide table prints sideways', () => {
    const wide = { ...sheet, columns: Array.from({ length: 9 }, (_, i) => ({ label: `c${i}` })), rows: [], totals: undefined };
    expect(sheetHtml(wide)).toContain('A4 landscape');
  });

  it('the CSV carries the same lines, quotes what needs it, and starts with a mark so Excel reads the letters right', () => {
    const csv = sheetCsv(sheet);
    expect(csv.charCodeAt(0)).toBe(0xfeff);
    expect(csv).toContain('"Shop rent, ""main"""');
    expect(csv).toContain('#,What for,Amount');
    expect(csv).toContain(',Total,120000');
  });

  it('the Excel sheet keeps amounts as numbers (so they add up), with the header and totals styled', () => {
    const xml = sheetXml(sheet);
    expect(xml).toContain('<v>100000</v>');
    expect(xml).toContain('<v>120000</v>');
    expect(xml).toContain('Shop rent, &quot;main&quot;');
    expect(xml).toContain('state="frozen"');
    expect(xml).toContain('<mergeCell ref="A1:C1"/>');
  });

  it('the .xlsx file is a zip with the parts Excel needs', () => {
    const bytes = sheetXlsx(sheet);
    expect(String.fromCharCode(bytes[0], bytes[1])).toBe('PK');
    const all = text(bytes);
    for (const name of ['[Content_Types].xml', '_rels/.rels', 'xl/workbook.xml', 'xl/styles.xml', 'xl/worksheets/sheet1.xml']) expect(all).toContain(name);
    expect(all).toContain('Mary\'s Beauty');
  });

  it('the zip records the right size and checksum of a file', () => {
    const bytes = zip([{ name: 'a.txt', data: 'hello' }]);
    const v = new DataView(bytes.buffer);
    expect(v.getUint32(0, true)).toBe(0x04034b50);
    expect(v.getUint32(14, true)).toBe(0x3610a686); // the CRC-32 of "hello"
    expect(v.getUint32(18, true)).toBe(5);
  });

  it('names the file after the list and the day, with nothing unsafe', () => {
    expect(fileName('Madeni / Debts', 'xlsx')).toMatch(/^Madeni-Debts-\d{4}-\d{2}-\d{2}\.xlsx$/);
  });
});
