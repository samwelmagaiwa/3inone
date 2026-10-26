/**
 * Tiny positioning helper for the calendar and dropdown popovers.
 * The popover is appended to <body> (so tables and cards with overflow:hidden never clip it),
 * placed under its anchor (or above when there is no room), and closed on outside click,
 * Escape, scroll or resize.
 */
export function openPopover(
  anchor: HTMLElement,
  pop: HTMLElement,
  options: { matchWidth?: boolean; onClose?: () => void } = {},
): () => void {
  pop.classList.add('bs-popover');
  document.body.appendChild(pop);

  const place = () => {
    const a = anchor.getBoundingClientRect();
    if (options.matchWidth) {
      pop.style.minWidth = `${a.width}px`;
    }
    const p = pop.getBoundingClientRect();
    const gap = 6;
    const spaceBelow = window.innerHeight - a.bottom;
    const openUp = spaceBelow < p.height + gap && a.top > spaceBelow;
    const top = openUp ? Math.max(8, a.top - p.height - gap) : a.bottom + gap;
    const left = Math.min(Math.max(8, a.left), Math.max(8, window.innerWidth - p.width - 8));
    pop.style.top = `${top}px`;
    pop.style.left = `${left}px`;
  };
  place();

  let closed = false;
  const close = () => {
    if (closed) return;
    closed = true;
    document.removeEventListener('mousedown', onDown, true);
    document.removeEventListener('keydown', onKey, true);
    window.removeEventListener('scroll', onScroll, true);
    window.removeEventListener('resize', close);
    pop.remove();
    options.onClose?.();
  };
  const onDown = (e: MouseEvent) => {
    const t = e.target as Node;
    if (!pop.contains(t) && !anchor.contains(t)) close();
  };
  const onKey = (e: KeyboardEvent) => {
    if (e.key === 'Escape') {
      e.stopPropagation();
      close();
      anchor.focus();
    }
  };
  const onScroll = (e: Event) => {
    if (!pop.contains(e.target as Node)) close();
  };

  document.addEventListener('mousedown', onDown, true);
  document.addEventListener('keydown', onKey, true);
  window.addEventListener('scroll', onScroll, true);
  window.addEventListener('resize', close);

  // re-place once the content has its final size
  requestAnimationFrame(place);
  return close;
}

export const CHEVRON =
  '<svg class="bs-trigger-icon is-chevron" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7"/></svg>';
export const CALENDAR_ICON =
  '<svg class="bs-trigger-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M8 7V3m8 4V3M4 11h16M5 5h14a1 1 0 011 1v13a1 1 0 01-1 1H5a1 1 0 01-1-1V6a1 1 0 011-1z"/></svg>';
export const CHECK =
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3"><path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7"/></svg>';
