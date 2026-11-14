/**
 * Gives every table cell a `data-label` taken from its column heading, so a phone can show each table row as a small card ("Price: 25,000")
 * in place of a wide table that scrolls sideways. Runs on the page as it changes; cells already labelled are left alone.
 */
export function labelTable(table: HTMLTableElement): void {
  const heads = Array.from(table.querySelectorAll('thead th')).map((th) => {
    const clone = th.cloneNode(true) as HTMLElement;
    clone.querySelectorAll('.arrow').forEach((a) => a.remove());

    return (clone.textContent ?? '').replace(/\s+/g, ' ').trim();
  });
  if (!heads.length) return;

  table.querySelectorAll('tbody tr').forEach((tr) => {
    let col = 0;
    Array.from(tr.children).forEach((cell) => {
      if (!(cell instanceof HTMLElement) || cell.tagName !== 'TD') return;
      const span = Math.max(1, Number(cell.getAttribute('colspan') ?? 1));
      if (!cell.hasAttribute('data-label') && span === 1 && heads[col]) cell.setAttribute('data-label', heads[col]);
      col += span;
    });
  });
}

export function labelAllTables(root: ParentNode = document): void {
  root.querySelectorAll('table.grid-table, table.premium-table').forEach((t) => labelTable(t as HTMLTableElement));
}

export function installTableLabels(): void {
  if (typeof document === 'undefined' || typeof MutationObserver === 'undefined') return;

  let queued = false;
  const run = () => {
    queued = false;
    labelAllTables();
  };
  new MutationObserver(() => {
    if (queued) return;
    queued = true;
    requestAnimationFrame(run);
  }).observe(document.body, { childList: true, subtree: true });
}
