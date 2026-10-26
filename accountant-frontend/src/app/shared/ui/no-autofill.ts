/**
 * Browsers fill saved usernames into search and filter boxes even when autocomplete is "off".
 * Every text input marked autocomplete="off" starts read-only and becomes editable the moment
 * it is clicked or focused, which leaves the browser nothing to fill.
 */
export function installNoAutofill(): void {
  if (typeof document === 'undefined' || typeof MutationObserver === 'undefined') return;

  const guard = (input: HTMLInputElement) => {
    if (input.dataset['noAutofill'] === '1') return;
    if (input.type !== 'text' && input.type !== 'search') return;
    if (input.getAttribute('autocomplete') !== 'off') return;
    input.dataset['noAutofill'] = '1';
    // a value the user has already typed must stay editable
    if (document.activeElement === input) return;
    input.readOnly = true;
    const release = () => {
      input.readOnly = false;
      input.removeEventListener('focus', release);
      input.removeEventListener('pointerdown', release);
    };
    input.addEventListener('focus', release);
    input.addEventListener('pointerdown', release);
  };

  const scan = (node: ParentNode) => node.querySelectorAll?.('input[autocomplete="off"]').forEach(el => guard(el as HTMLInputElement));

  scan(document);
  new MutationObserver(mutations => {
    for (const m of mutations) {
      m.addedNodes.forEach(n => {
        if (n.nodeType !== 1) return;
        const el = n as Element;
        if (el instanceof HTMLInputElement) guard(el);
        scan(el);
      });
    }
  }).observe(document.body, { childList: true, subtree: true });
}
