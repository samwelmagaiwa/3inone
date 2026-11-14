import { describe, expect, it } from 'vitest';

import { labelTable } from './table-labels';

describe('labelTable', () => {
  it('labels each cell from its column heading, ignoring the sort arrow', () => {
    const t = document.createElement('table');
    t.innerHTML =
      '<thead><tr><th>Name <span class="arrow">▲</span></th><th>Price</th></tr></thead><tbody><tr><td>Braids</td><td>25,000</td></tr><tr><td colspan="2">Empty</td></tr></tbody>';
    labelTable(t);
    const cells = t.querySelectorAll('td');
    expect(cells[0].getAttribute('data-label')).toBe('Name');
    expect(cells[1].getAttribute('data-label')).toBe('Price');
    expect(cells[2].hasAttribute('data-label')).toBe(false);
  });
});
