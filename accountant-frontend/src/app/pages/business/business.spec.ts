import { describe, expect, it } from 'vitest';

import { businessProblems, readBusiness } from './business';

describe('business profile page', () => {
  it('reads the details and the logo', () => {
    const b = readBusiness({ name: "Mary's Beauty", tin: '123-456-789', phone: '0743519100', email: null, address: 'Kariakoo', logo_url: 'https://x/logo.png' });
    expect(b).toEqual({ name: "Mary's Beauty", tin: '123-456-789', phone: '0743519100', email: '', address: 'Kariakoo', logoUrl: 'https://x/logo.png' });
    expect(readBusiness({}).logoUrl).toBeNull();
  });

  it('checks the details as the phone does', () => {
    expect(businessProblems({ name: 'A', tin: '', phone: '', email: '' })).toEqual([]);
    expect(businessProblems({ name: 'A', tin: '123 456 789', phone: '+255743519100', email: 'a@b.co' })).toEqual([]);
    const bad = businessProblems({ name: ' ', tin: '12', phone: '123', email: 'nope' });
    expect(bad.map((p) => p.field)).toEqual(['name', 'tin', 'phone', 'email']);
  });
});
