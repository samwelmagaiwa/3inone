import { TestBed } from '@angular/core/testing';

import { environment } from '../../../environments/environment';
import { byTestId, configure, settle, text, type } from '../../testing';
import { AssistantPage } from './assistant';

const URL = `${environment.apiUrl}/assistant`;

const suggestions = [
  { id: 'sg_owe', en: 'Who owes me?', sw: 'Nani ananidai?', tool: 'customers_who_owe' },
  { id: 'hg_sale', en: 'How do I record a sale?', sw: 'Ninarekodije mauzo?', tool: null },
];

const answer = {
  answer: 'Mama Neema Joseph owes the most.',
  cards: [{ type: 'rows', title: 'Owe the business', rows: [{ title: 'Mama Neema Joseph', value: 'TSh 350,000', note: '120 days' }] }],
  tools: ['customers_who_owe'],
  questions_left: 19,
};

async function open(status: Record<string, unknown> = {}, who = {}) {
  const h = configure(who);
  const fixture = TestBed.createComponent(AssistantPage);
  fixture.detectChanges();
  h.http.expectOne({ method: 'GET', url: URL }).flush({ data: { available: true, topics: ['customers_who_owe'], suggestions, services: ['inventory'], questions_left: 20, ...status } });
  await settle(fixture);

  return { h, fixture, el: fixture.nativeElement as HTMLElement };
}

const click = (el: HTMLElement, id: string) => (byTestId(el, id) as HTMLButtonElement).click();

describe('the AI assistant page', () => {
  it('welcomes a new person and groups the questions: about the business, and how to use the app', async () => {
    const { el } = await open();

    expect(byTestId(el, 'assistant-welcome')).not.toBeNull();
    expect(text(el)).toContain('About my business');
    expect(text(el)).toContain('How do I...?');
    expect(text(byTestId(el, 'sg_owe')!)).toBe('Who owes me?');
    expect(text(byTestId(el, 'hg_sale')!)).toBe('How do I record a sale?');
  });

  it('shows the questions in Swahili when the app is in Swahili', async () => {
    const { h, fixture, el } = await open();
    h.i18n.setLang('sw');
    await settle(fixture);

    expect(text(byTestId(el, 'sg_owe')!)).toBe('Nani ananidai?');
    expect(text(el)).toContain('Jinsi ya kutumia programu');
  });

  it('a clicked question goes with its id, and the answer shows the full name, amount and days from the records', async () => {
    const { h, fixture, el } = await open();

    click(el, 'sg_owe');
    const req = h.http.expectOne({ method: 'POST', url: URL });
    expect(req.request.body).toEqual({ question: 'Who owes me?', lang: 'en', history: [], topic: 'sg_owe' });
    req.flush({ data: answer });
    await settle(fixture);

    const all = text(el);
    expect(all).toContain('Mama Neema Joseph owes the most.');
    expect(all).toContain('Mama Neema Joseph');
    expect(all).toContain('TSh 350,000');
    expect(all).toContain('120 days');
    expect(all).toContain('Questions left today: 19');
    expect(byTestId(el, 'assistant-quick')).not.toBeNull();
  });

  it('a typed question is free-form and carries the earlier turns', async () => {
    const { h, fixture, el } = await open();
    click(el, 'sg_owe');
    h.http.expectOne({ method: 'POST', url: URL }).flush({ data: answer });
    await settle(fixture);

    type(el, '[data-testid="assistant-input"]', 'And the second one?');
    await settle(fixture);
    click(el, 'assistant-send');
    const req = h.http.expectOne({ method: 'POST', url: URL });

    expect(req.request.body.topic).toBeUndefined();
    expect(req.request.body.history).toEqual([
      { role: 'user', text: 'Who owes me?' },
      { role: 'model', text: 'Mama Neema Joseph owes the most.' },
    ]);
    req.flush({ data: answer });
    await settle(fixture);
  });

  it('a failed question shows a plain message, and Try again asks it again without a duplicate', async () => {
    const { h, fixture, el } = await open();

    click(el, 'sg_owe');
    h.http.expectOne({ method: 'POST', url: URL }).flush({ message: 'The assistant could not answer now.' }, { status: 503, statusText: 'x' });
    await settle(fixture);
    expect(text(el)).toContain('could not answer now');

    click(el, 'assistant-retry');
    const req = h.http.expectOne({ method: 'POST', url: URL });
    expect(req.request.body.topic).toBe('sg_owe');
    req.flush({ data: answer });
    await settle(fixture);

    expect(text(el)).not.toContain('could not answer now');
    expect(byTestId(el, 'turn-0')).not.toBeNull();
    expect(byTestId(el, 'turn-1')).not.toBeNull();
    expect(byTestId(el, 'turn-2')).toBeNull();
  });

  it('a new conversation clears the chat', async () => {
    const { h, fixture, el } = await open();
    click(el, 'sg_owe');
    h.http.expectOne({ method: 'POST', url: URL }).flush({ data: answer });
    await settle(fixture);

    click(el, 'assistant-new');
    await settle(fixture);

    expect(byTestId(el, 'turn-0')).toBeNull();
    expect(byTestId(el, 'assistant-welcome')).not.toBeNull();
  });

  it('says plainly when the assistant is switched off on the server', async () => {
    const { el } = await open({ available: false, suggestions: [] });

    expect(byTestId(el, 'assistant-off')).not.toBeNull();
    expect(byTestId(el, 'assistant-input')).toBeNull();
  });

  it('a person with no right to business data is still offered how-to help', async () => {
    const { el } = await open({ suggestions: [{ id: 'hg_start', en: 'What can I do in this app?', sw: 'x', tool: null }] }, { permissions: [] });

    expect(text(byTestId(el, 'assistant-welcome')!)).toContain('cannot view business data');
    expect(text(el)).not.toContain('About my business');
    expect(byTestId(el, 'hg_start')).not.toBeNull();
    expect(byTestId(el, 'assistant-input')).not.toBeNull();
  });

  it('stops asking when the day\'s questions are used', async () => {
    const { el } = await open({ questions_left: 0 });

    expect((byTestId(el, 'assistant-input') as HTMLTextAreaElement).disabled).toBe(true);
    expect(text(el)).toContain('You have used today\'s questions');
  });
});
