<?php

namespace App\Jobs;

use App\Models\Business;
use App\Models\User;
use App\Services\SmsService;
use App\Support\Tenancy\TenantContext;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Support\Facades\DB;

/**
 * Sends a group's text to its recipients, in the queue (a text to 300 members never holds up a request). Each recipient is marked as it goes,
 * under the group's own sender name and SMS limit (SmsService::sendFor: the group's switch and limit apply). Tried once: a recipient already
 * marked is never texted again.
 */
class SendGroupMessageJob implements ShouldQueue
{
    use Queueable;

    public int $tries = 1;

    public int $timeout = 600;

    public function __construct(public string $actorId, public int $messageId)
    {
    }

    public function handle(): void
    {
        $actor = User::query()->withoutGlobalScopes()->find($this->actorId);
        if ($actor === null) {
            return;
        }
        TenantContext::runAs($actor, function () use ($actor) {
            $message = DB::table('group_messages')->where('id', $this->messageId)->first();
            if ($message === null) {
                return;
            }
            $business = Business::forUser($actor);
            $sent = 0;
            foreach (DB::table('group_message_recipients')->where('message_id', $message->id)->where('status', 'waiting')->get() as $r) {
                // Claimed before sending, so a second run never texts the same person.
                $claimed = DB::table('group_message_recipients')->where('id', $r->id)->where('status', 'waiting')->update(['status' => 'sending']);
                if ($claimed === 0) {
                    continue;
                }
                $ok = SmsService::sendFor($business, $r->phone, $message->body);
                DB::table('group_message_recipients')->where('id', $r->id)->update(['status' => $ok ? 'sent' : 'failed']);
                $sent += $ok ? 1 : 0;
            }
            DB::table('group_messages')->where('id', $message->id)->update([
                'sent' => DB::table('group_message_recipients')->where('message_id', $message->id)->where('status', 'sent')->count(),
                'status' => 'done',
                'updated_at' => now(),
            ]);
        });
    }
}
