<?php

namespace App\Console\Commands;

use App\Console\Concerns\RunsPerBusiness;
use App\Models\Business;
use App\Services\SmsService;
use App\Support\Groups\GroupContributions;
use App\Support\Groups\GroupSettings;
use App\Support\Groups\GroupVotings;
use Illuminate\Console\Command;
use Illuminate\Database\QueryException;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Every morning, for each group (one queued job per group, {@see RunsPerBusiness}):
 *
 *   1. the month's monthly contributions are raised for every active member, if they were not yet (safe to repeat);
 *   2. when the group has switched reminders on, members are texted -- at most once per kind per day:
 *        due_soon   a contribution falls due in 3 days
 *        overdue    a contribution is overdue: the day after it fell due, then once a week
 *        promise    the day they promised to pay has come and it is not yet paid
 *      A text says no amounts unless the group allows it (a shared phone should not show someone's debts). Each text is CLAIMED in
 *      group_reminders before it is sent, and given back if it could not go out, so a rerun never texts twice.
 */
class GroupsDaily extends Command
{
    use RunsPerBusiness;

    protected $signature = 'groups:daily {--dry-run : say what would be raised and texted, change and send nothing}';

    protected $description = "Raise each group's monthly contributions and text members about what is due";

    /** More than this in one day for one group is a mistake, not a day's reminders. */
    private const MAX_PER_GROUP = 500;

    public function handle(): int
    {
        return $this->runPerBusiness('group(s)');
    }

    protected function businessService(): string
    {
        return 'groups';
    }

    protected function businessContext(): array
    {
        return ['today' => now()->toDateString()];
    }

    public function forBusiness(Business $business, array $context, bool $dry): array
    {
        $today = (string) $context['today'];
        $found = 0;
        $sent = 0;

        if (!$dry) {
            $raised = GroupContributions::raiseMonth(substr($today, 0, 7));
            if ($raised > 0) {
                $this->note("{$business->name}: raised {$raised} contribution(s) for " . substr($today, 0, 7));
            }
        }

        if (!$dry) {
            // Votings open and close by their own dates; whoever has not voted is told a day before it closes.
            GroupVotings::syncAll();
            GroupVotings::remindClosing();
        }

        $settings = GroupSettings::all($today);
        if ($settings['sms_reminders'] !== 'on') {
            return ['found' => 0, 'sent' => 0];
        }
        $amounts = $settings['sms_show_amounts'] === 'on';

        foreach ($this->dueTexts($today) as [$kind, $memberId, $phone, $name, $total]) {
            if ($found >= self::MAX_PER_GROUP) {
                $this->note("{$business->name}: stopped at " . self::MAX_PER_GROUP . ' reminders', true);
                break;
            }
            $found++;
            $text = $this->text($kind, (string) $name, (string) $business->name, $amounts ? (float) $total : null);
            if ($dry) {
                $this->note("{$business->name}: would text {$name} ({$kind})");

                continue;
            }
            if (!$this->claim($kind, (int) $memberId, $today)) {
                continue;
            }
            if (SmsService::sendFor($business, $phone, $text)) {
                $sent++;
            } else {
                DB::table('group_reminders')->where('kind', $kind)->where('subject_id', (int) $memberId)->where('sent_on', $today)->delete();
            }
        }

        return ['found' => $found, 'sent' => $sent];
    }

    /**
     * Who is texted today and why: one line per member and kind, with the total they owe for it.
     *
     * @return array<int, array{0: string, 1: int, 2: string, 3: string, 4: float}>
     */
    private function dueTexts(string $today): array
    {
        $soon = Carbon::parse($today)->addDays(3)->toDateString();
        $out = [];
        $owing = GroupContributions::owing(GroupContributions::query())
            ->where('m.status', 'active')
            ->where(fn ($q) => $q->where('o.due_date', $soon)->orWhere('o.due_date', '<', $today))
            ->get();
        $byMember = [];
        foreach ($owing as $o) {
            $kind = (string) $o->due_date === $soon ? 'due_soon' : 'overdue';
            if ($kind === 'overdue') {
                $days = (int) Carbon::parse((string) $o->due_date)->diffInDays(Carbon::parse($today));
                if (($days - 1) % 7 !== 0) {
                    continue;
                }
            }
            $key = $kind . ':' . $o->member_id;
            $byMember[$key] ??= [$kind, (int) $o->member_id, (string) $o->member_phone, (string) $o->member_name, 0.0];
            $byMember[$key][4] += (float) $o->amount_due - (float) $o->paid;
        }
        $out = array_values($byMember);

        $promises = DB::table('group_promises as p')->join('group_members as m', 'm.id', '=', 'p.member_id')
            ->where('p.status', 'open')->where('p.promised_on', $today)->where('m.status', 'active')
            ->get(['p.*', 'm.full_name', 'm.phone']);
        foreach ($promises as $p) {
            if (\App\Support\Groups\GroupPromises::state($p, $today) === 'kept') {
                continue;
            }
            $out[] = ['promise', (int) $p->member_id, (string) $p->phone, (string) $p->full_name, (float) $p->amount];
        }

        return $out;
    }

    private function text(string $kind, string $name, string $group, ?float $amount): string
    {
        $first = trim(explode(' ', trim($name))[0] ?? $name);
        $sum = $amount === null ? '' : ' TSh ' . number_format($amount);

        return match ($kind) {
            'due_soon' => "Habari {$first}, mchango wako{$sum} wa {$group} unakaribia muda wake (siku 3). Fungua programu kuona maelezo. Asante!",
            'overdue' => "Habari {$first}, una mchango{$sum} wa {$group} uliopita muda wake. Fungua programu kuona maelezo au wasiliana na Mweka Hazina. Asante!",
            default => "Habari {$first}, leo ni siku uliyoahidi kulipa{$sum} kwa {$group}. Fungua programu kuona maelezo. Asante!",
        };
    }

    /** Take today's reminder of [kind] for [memberId]; false when it was already taken (a rerun). */
    private function claim(string $kind, int $memberId, string $today): bool
    {
        try {
            return DB::table('group_reminders')->insertOrIgnore(['kind' => $kind, 'subject_id' => $memberId, 'sent_on' => $today, 'created_at' => now()]) === 1;
        } catch (QueryException) {
            return false;
        }
    }
}
