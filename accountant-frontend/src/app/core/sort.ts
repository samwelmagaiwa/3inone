export type SortDir = 'asc' | 'desc';
export interface SortState {
  key: string;
  dir: SortDir;
}

/** The next sort when a header is clicked: a new column starts ascending, the same column flips. */
export function nextSort(current: SortState | null, key: string): SortState {
  return current?.key === key ? { key, dir: current.dir === 'asc' ? 'desc' : 'asc' } : { key, dir: 'asc' };
}

/** A sorted copy (numbers by value, text by the language's own order, empty last); the original is left as it is. */
export function sorted<T>(rows: readonly T[], state: SortState | null, value: (row: T, key: string) => string | number | null | undefined): T[] {
  if (!state) return [...rows];
  const sign = state.dir === 'asc' ? 1 : -1;

  return [...rows].sort((a, b) => {
    const x = value(a, state.key);
    const y = value(b, state.key);
    if (x === null || x === undefined) return y === null || y === undefined ? 0 : 1;
    if (y === null || y === undefined) return -1;
    if (typeof x === 'number' && typeof y === 'number') return (x - y) * sign;

    return String(x).localeCompare(String(y), undefined, { numeric: true, sensitivity: 'base' }) * sign;
  });
}

/** The arrow shown in a header: both arrows while unsorted, one once sorted. */
export function sortArrow(state: SortState | null, key: string): string {
  return state?.key !== key ? '⇅' : state.dir === 'asc' ? '▲' : '▼';
}
