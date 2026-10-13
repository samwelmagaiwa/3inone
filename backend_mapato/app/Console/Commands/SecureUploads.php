<?php

namespace App\Console\Commands;

use App\Support\PrivateFile;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Storage;

/**
 * Files uploaded before uploads became private (lease documents, tenant photos, repair photos,
 * reports) are still in the public storage folder. This puts a copy of each in private storage.
 *
 *   php artisan files:secure-uploads --dry-run              what would be copied, nothing changes
 *   php artisan files:secure-uploads                        copy them; the originals stay where they are
 *   php artisan files:secure-uploads --remove-originals     copy, then remove each public original
 *                                                           whose private copy is verified to be
 *                                                           the same size
 *
 * Copying alone deletes nothing, and the API keeps working throughout because it finds a file in
 * either place. Only a file that is still in the public folder can be read without a signed link,
 * so --remove-originals is what finally closes the old addresses. Run it after checking a few
 * documents open (via the app) and after taking a backup.
 */
class SecureUploads extends Command
{
    protected $signature = 'files:secure-uploads
                            {--dry-run : Show what would happen and change nothing}
                            {--remove-originals : After copying, remove each public original whose private copy is verified}';

    protected $description = 'Copy old public uploads (lease documents, tenant/repair photos, reports) into private storage';

    public function handle(): int
    {
        $public = Storage::disk(PrivateFile::LEGACY_DISK);
        $private = Storage::disk(PrivateFile::DISK);
        $dry = (bool) $this->option('dry-run');
        $remove = (bool) $this->option('remove-originals');

        $copied = $already = $removed = $failed = 0;
        $keptOriginals = 0;

        foreach (PrivateFile::FOLDERS as $folder) {
            foreach ($public->allFiles($folder) as $path) {
                if (str_ends_with($path, '.gitignore')) {
                    continue;
                }

                $size = $public->size($path);
                $has = $private->exists($path) && $private->size($path) === $size;

                if ($has) {
                    $already++;
                } elseif ($dry) {
                    $this->line("  would copy  {$path}");
                    $copied++;
                } else {
                    $stream = $public->readStream($path);
                    if ($stream === false || !$private->writeStream($path, $stream)) {
                        $this->error("  could not copy {$path}");
                        $failed++;
                        continue;
                    }
                    if (is_resource($stream)) {
                        fclose($stream);
                    }
                    $copied++;
                    $has = $private->exists($path) && $private->size($path) === $size;
                }

                if ($remove) {
                    if (!$dry && $has) {
                        $public->delete($path);
                        $removed++;
                    } elseif ($dry) {
                        $this->line("  would remove the public original of {$path}");
                    } else {
                        $keptOriginals++; // no verified private copy: the original is kept
                    }
                }
            }
        }

        $this->info(($dry ? 'Dry run. ' : '') . "Copied: {$copied}. Already private: {$already}."
            . ($remove ? " Public originals removed: {$removed}." : ' Public originals left in place.')
            . ($failed ? " FAILED: {$failed}." : '')
            . ($keptOriginals ? " Originals kept because their private copy could not be verified: {$keptOriginals}." : ''));

        if (!$remove && !$dry && ($copied + $already) > 0) {
            $this->warn('The public originals are still readable at their old addresses. Once you have checked a few files open, run again with --remove-originals.');
        }

        return $failed > 0 ? self::FAILURE : self::SUCCESS;
    }
}
