<?php

namespace App\Http\Controllers\API;

use App\Http\Controllers\Controller;
use App\Support\PrivateFile;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\HttpFoundation\StreamedResponse;
use OpenApi\Attributes as OA;

class MediaController extends Controller
{
    /**
     * Serve public disk files (e.g., avatars) with CORS headers for web clients.
     */
    #[OA\Get(
        path: '/files/public/{path}',
        summary: 'Public file',
        tags: ['Admin / Media'],
        parameters: [
            new OA\Parameter(name: 'path', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function publicFile(Request $request, string $path): StreamedResponse
    {
        // Normalize the path to avoid leading slashes or directory traversal
        $path = ltrim($path, '/');

        // Lease documents, tenant and repair photos and reports are NOT public: they are only
        // served through a signed link the API gives to people allowed to see them (privateFile).
        // This route stays for house and property photos and profile pictures.
        if (str_contains($path, '..') || PrivateFile::isPrivatePath($path)) {
            abort(404);
        }

        // Only serve real files; directory requests should 404 (prevents Flysystem file_size error)
        if ($path === '' || !Storage::disk('public')->fileExists($path)) {
            abort(404);
        }

        // Stream the file with CORS headers so mobile/web can fetch it WITHOUT relying on file_size
        $disk = Storage::disk('public');
        $stream = $disk->readStream($path);
        if ($stream === false) {
            abort(404);
        }
        $mime = 'application/octet-stream';
        try {
            $mime = $disk->mimeType($path) ?? $mime;
        } catch (\Throwable $e) {
            // ignore and keep default
        }

        return response()->stream(function () use ($stream) {
            fpassthru($stream);
            if (is_resource($stream)) {
                fclose($stream);
            }
        }, 200, [
            'Content-Type' => $mime,
            'Cache-Control' => 'public, max-age=86400',
            'Access-Control-Allow-Origin' => '*',
            'Access-Control-Allow-Methods' => 'GET, OPTIONS',
            'Access-Control-Allow-Headers' => 'Origin, X-Requested-With, Content-Type, Accept, Authorization',
        ]);
    }

    /**
     * Serve a private upload (lease document, tenant photo, repair photo, report) -- but only
     * to someone holding a valid signed link, which the API issues to people allowed to see
     * the record and which expires after a few hours (config/uploads.php). Files uploaded before
     * uploads became private are found in the old public folder and served the same way.
     */
    public function privateFile(Request $request, string $path): StreamedResponse
    {
        $path = ltrim($path, '/');

        if (!PrivateFile::isCleanPath($path) || !PrivateFile::isPrivatePath($path)) {
            abort(404);
        }

        $diskName = PrivateFile::diskFor($path);
        if ($diskName === null) {
            abort(404);
        }

        $disk = Storage::disk($diskName);
        $stream = $disk->readStream($path);
        if ($stream === false) {
            abort(404);
        }

        $mime = 'application/octet-stream';
        try {
            $mime = $disk->mimeType($path) ?: $mime;
        } catch (\Throwable $e) {
            // keep the default
        }

        return response()->stream(function () use ($stream) {
            fpassthru($stream);
            if (is_resource($stream)) {
                fclose($stream);
            }
        }, 200, [
            'Content-Type' => $mime,
            'Cache-Control' => 'private, max-age=3600',
            'X-Content-Type-Options' => 'nosniff',
            // A report is an HTML page: never let it run anything in this site's origin.
            'Content-Security-Policy' => "default-src 'none'; img-src 'self' data:; style-src 'unsafe-inline'; sandbox",
        ]);
    }
}
