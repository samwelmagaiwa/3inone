import { Component, ElementRef, OnInit, computed, inject, signal, viewChild } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { firstValueFrom } from 'rxjs';

import { AccountantApi } from '../../core/accountant-api.service';
import { offline, serverMessage } from '../../core/format';
import { I18nService } from '../../core/i18n.service';
import { AssistantCard, AssistantStatus, AssistantSuggestion, AssistantTurnOut } from '../../core/models';

/** One line of the conversation. A failed answer remembers the question, so "Try again" can ask it once more. */
interface Turn {
  mine: boolean;
  text: string;
  cards: AssistantCard[];
  failed: boolean;
  retry?: { question: string; topic?: string };
}

/**
 * Ask the business a question, or ask how to do something in the app. Made for people new to computers: a short welcome,
 * questions to click (split into "about my business" and "how do I...?"), plain answers, and the records an answer rests on
 * (full names, amounts, days) shown under it exactly as stored, so nothing important depends on the AI's wording.
 * The server decides what this person may read, and which questions to offer, from their rights and their business's services.
 */
@Component({
  selector: 'app-assistant',
  imports: [FormsModule],
  templateUrl: './assistant.html',
})
export class AssistantPage implements OnInit {
  private readonly api = inject(AccountantApi);
  protected readonly i18n = inject(I18nService);

  protected readonly status = signal<AssistantStatus | null>(null);
  protected readonly loading = signal(true);
  protected readonly error = signal<string | null>(null);
  protected readonly turns = signal<Turn[]>([]);
  protected readonly sending = signal(false);
  protected question = '';

  private readonly end = viewChild<ElementRef<HTMLElement>>('end');

  protected readonly suggestions = computed<AssistantSuggestion[]>(() => this.status()?.suggestions ?? []);
  protected readonly about = computed(() => this.suggestions().filter((s) => s.tool !== null));
  protected readonly howTo = computed(() => this.suggestions().filter((s) => s.tool === null));
  protected readonly left = computed(() => this.status()?.questions_left ?? 0);

  ngOnInit(): void {
    void this.loadStatus();
  }

  protected async loadStatus(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    try {
      this.status.set(await firstValueFrom(this.api.assistantStatus()));
    } catch (err) {
      this.error.set(this.messageOf(err));
    } finally {
      this.loading.set(false);
    }
  }

  /** The wording of a suggestion in the language the person uses now. */
  protected text(s: AssistantSuggestion): string {
    return this.i18n.lang() === 'sw' ? s.sw : s.en;
  }

  protected async pick(s: AssistantSuggestion): Promise<void> {
    await this.ask(this.text(s), s.id);
  }

  protected async submit(): Promise<void> {
    const q = this.question.trim();
    if (q.length < 2) return;
    this.question = '';
    await this.ask(q);
  }

  /** Enter sends, Shift+Enter makes a new line. */
  protected onEnter(e: Event): void {
    const k = e as KeyboardEvent;
    if (k.shiftKey) return;
    e.preventDefault();
    void this.submit();
  }

  protected newConversation(): void {
    if (!this.sending()) this.turns.set([]);
  }

  protected async retry(t: Turn): Promise<void> {
    const again = t.retry;
    if (!again || this.sending()) return;
    // The failed answer and the question above it are dropped first, so the conversation stays clean.
    this.turns.update((all) => {
      const rest = all.filter((x) => x !== t);
      return rest.length && rest[rest.length - 1].mine ? rest.slice(0, -1) : rest;
    });
    await this.ask(again.question, again.topic);
  }

  /** Earlier turns for the server (it keeps none itself), without failed ones. */
  private history(): AssistantTurnOut[] {
    return this.turns()
      .filter((t) => !t.failed)
      .map((t) => ({ role: t.mine ? ('user' as const) : ('model' as const), text: t.text }));
  }

  private async ask(question: string, topic?: string): Promise<void> {
    if (this.sending()) return;
    const history = this.history();
    this.turns.update((all) => [...all, { mine: true, text: question, cards: [], failed: false }]);
    this.sending.set(true);
    this.scrollDown();
    try {
      const r = await firstValueFrom(this.api.assistantAsk(question, this.i18n.lang(), history, topic));
      this.turns.update((all) => [...all, { mine: false, text: r.answer, cards: r.cards ?? [], failed: false }]);
      this.status.update((s) => (s ? { ...s, questions_left: r.questions_left } : s));
    } catch (err) {
      this.turns.update((all) => [...all, { mine: false, text: this.messageOf(err), cards: [], failed: true, retry: { question, topic } }]);
    } finally {
      this.sending.set(false);
      this.scrollDown();
    }
  }

  private messageOf(err: unknown): string {
    return offline(err) ? this.i18n.t('error.offline') : (serverMessage(err) ?? this.i18n.t('error.generic'));
  }

  private scrollDown(): void {
    setTimeout(() => this.end()?.nativeElement.scrollIntoView?.({ behavior: 'smooth', block: 'end' }));
  }
}
