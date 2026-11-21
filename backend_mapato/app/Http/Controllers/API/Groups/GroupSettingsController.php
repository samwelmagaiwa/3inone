<?php

namespace App\Http\Controllers\API\Groups;

use App\Support\Groups\GroupAudit;
use App\Support\Groups\GroupSettings;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Validation\Rule;
use InvalidArgumentException;

/**
 * The group's own values (fees, shares, rules) and the record of every change. A change starts on a day (today unless said) and never
 * rewrites the past: the value that applied before stays readable for old calculations.
 */
class GroupSettingsController extends Controller
{
    public function show(): JsonResponse
    {
        return response()->json(['success' => true, 'data' => [
            'settings' => GroupSettings::all(),
            'keys' => GroupSettings::KEYS,
            'history' => GroupSettings::history(),
        ]]);
    }

    public function update(Request $request): JsonResponse
    {
        $data = $request->validate([
            'values' => 'required|array|min:1',
            'values.*' => 'nullable',
            'reason' => 'required|string|min:3|max:255',
            'effective_from' => 'nullable|date|after_or_equal:today',
        ]);
        foreach (array_keys($data['values']) as $key) {
            if (!array_key_exists((string) $key, GroupSettings::KEYS)) {
                return response()->json(['success' => false, 'code' => 'unknown_setting', 'message' => "Unknown setting {$key}."], 422);
            }
        }
        try {
            $changed = GroupSettings::change($data['values'], (string) $request->user()->id, trim($data['reason']), $data['effective_from'] ?? null);
        } catch (InvalidArgumentException $e) {
            return response()->json(['success' => false, 'code' => 'bad_value', 'message' => $e->getMessage()], 422);
        }
        if ($changed !== []) {
            GroupAudit::record((string) $request->user()->id, 'settings_changed', collect($changed)->map(fn ($c, $k) => "{$k}: {$c['from']} -> {$c['to']}")->implode('; ') . ' (' . trim($data['reason']) . ')');
        }

        return response()->json(['success' => true, 'data' => ['changed' => $changed] + $this->show()->getData(true)['data']]);
    }

    /** The group's activity log, newest first; [before] continues from an id. */
    public function audit(Request $request): JsonResponse
    {
        $request->validate(['before' => 'nullable|integer']);

        return response()->json(['success' => true, 'data' => ['entries' => GroupAudit::recent(50, $request->query('before'))]]);
    }
}
