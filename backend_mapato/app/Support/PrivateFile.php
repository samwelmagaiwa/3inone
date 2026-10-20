<?php

namespace App\Support;

use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\URL;

/**
 * Uploads that must not be readable by whoever happens to know or guess a link: lease documents
 * (signed contracts, ID cards), tenant photos, photos of repair requests, and generated reports.
 *
 * They are stored on the PRIVATE disk (never served by the web server), and the API hands out a
 * short-lived SIGNED link only to a person it already lets see that record (the lists and screens
 * are limited to the signed-in business). The link needs no sign-in header, so the app's image
 * widgets work unchanged, but it stops working after a few hours and cannot be forged or edited.
 *
 * House and property photos and profile pictures stay in the public storage on purpose: they are
 * shown on public listings and everywhere in the app.
 */
final class PrivateFile
{
    /** The private disk (Laravel's "local" disk: storage/app/private, not web-accessible). */
    public const DISK = 'local';

    /** The legacy public disk, where files uploaded before this change still are. */
    public const LEGACY_DISK = 'public';

    /** First path segment of every upload that is private. */
    public const FOLDERS = ['agreements', 'tenant_photos', 'maintenance', 'reports', 'salon_receipts', 'salon_client_photos'];

    public static function isPrivatePath(string $path): bool
    {
        $first = explode('/', ltrim($path, '/'), 2)[0] ?? '';

        return in_array($first, self::FOLDERS, true);
    }

    /** A path that is safe to hand to a disk: no traversal, no odd characters. */
    public static function isCleanPath(string $path): bool
    {
        return $path !== ''
            && !str_contains($path, '..')
            && !str_contains($path, "\0")
            && !str_contains($path, '\\')
            && preg_match('#^[A-Za-z0-9_.\-/]+$#', $path) === 1;
    }

    /** Store an upload privately in $folder (one of FOLDERS, or a sub-folder of one). Returns its path. */
    public static function store(UploadedFile $file, string $folder): string
    {
        return (string) $file->store($folder, self::DISK);
    }

    /**
     * Which disk holds this file: the private one, or (for files uploaded before this change)
     * the legacy public one. Null if neither does.
     */
    public static function diskFor(string $path): ?string
    {
        if (Storage::disk(self::DISK)->exists($path)) {
            return self::DISK;
        }

        return Storage::disk(self::LEGACY_DISK)->exists($path) ? self::LEGACY_DISK : null;
    }

    /**
     * A signed, expiring link for a stored path, to put in an API response. A value that is
     * already a full URL, or is not one of the private folders, is passed on unchanged.
     */
    public static function url(?string $path): ?string
    {
        if ($path === null || $path === '') {
            return null;
        }
        if (preg_match('#^https?://#i', $path) === 1) {
            return $path;
        }

        $path = ltrim(preg_replace('#^/?storage/#', '', $path) ?? $path, '/');

        if (!self::isPrivatePath($path)) {
            return asset('storage/' . $path);
        }

        // Signed over the path only (relative), so it stays valid behind the proxy that turns
        // https into http before the request reaches the app, then made absolute for the client.
        $relative = URL::temporarySignedRoute(
            'files.private',
            now()->addHours(max((int) config('uploads.link_hours', 6), 1)),
            ['path' => $path],
            absolute: false,
        );

        return URL::to($relative);
    }
}
