<?php

namespace App\Http\Controllers\API\Inventory;

use App\Support\Ai\Assistant;
use App\Support\Ai\AssistantTools;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;
use OpenApi\Attributes as OA;

/** The AI assistant: questions about the business, answered from the data the signed-in person is allowed to see. */
#[OA\Tag(name: 'Inventory / Assistant', description: 'AI assistant limited to the caller\'s rights')]
class AssistantController extends Controller
{
    public const DAILY_QUESTIONS = 60;

    #[OA\Get(path: '/inventory/assistant', summary: 'Is the assistant on, and what may this person ask it about', security: [['bearerAuth' => []]], tags: ['Inventory / Assistant'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function status(Request $request): JsonResponse
    {
        return response()->json(['data' => [
            'available' => Assistant::available(),
            'topics' => array_keys(AssistantTools::allowedFor($request->user())),
            'questions_left' => max(0, self::DAILY_QUESTIONS - $this->used($request)),
        ]]);
    }

    #[OA\Post(path: '/inventory/assistant', summary: 'Ask the assistant a question about the business', security: [['bearerAuth' => []]], tags: ['Inventory / Assistant'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function ask(Request $request): JsonResponse
    {
        $data = $request->validate([
            'question' => 'required|string|min:2|max:' . Assistant::MAX_QUESTION,
            'lang' => 'sometimes|in:sw,en',
            'history' => 'sometimes|array|max:12',
            'history.*.role' => 'required_with:history|in:user,model',
            'history.*.text' => 'required_with:history|string|max:1500',
        ]);

        if (!Assistant::available()) {
            return response()->json(['message' => 'The assistant is not switched on for this server.', 'code' => 'assistant_off'], 503);
        }
        if ($this->used($request) >= self::DAILY_QUESTIONS) {
            return response()->json(['message' => 'You have reached today\'s limit of questions. Try again tomorrow.', 'code' => 'assistant_daily_limit'], 429);
        }

        try {
            $result = Assistant::ask($request->user(), $data['question'], $data['history'] ?? [], $data['lang'] ?? 'en');
        } catch (\Throwable $e) {
            // The reason goes to the log, never to the screen: it may name the provider or its limits.
            Log::warning('assistant failed', ['user' => $request->user()->id, 'error' => mb_substr($e->getMessage(), 0, 200)]);

            return response()->json(['message' => 'The assistant could not answer now. Please try again in a moment.', 'code' => 'assistant_failed'], 503);
        }

        Cache::put($this->key($request), $this->used($request) + 1, now()->endOfDay());

        return response()->json(['data' => $result + ['questions_left' => max(0, self::DAILY_QUESTIONS - $this->used($request))]]);
    }

    private function key(Request $request): string
    {
        return 'assistant_questions:' . $request->user()->id . ':' . now()->toDateString();
    }

    private function used(Request $request): int
    {
        return (int) Cache::get($this->key($request), 0);
    }
}
