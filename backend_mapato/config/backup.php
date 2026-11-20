<?php

return [
    // How many in-app snapshots of each kind are kept (backups, safety copies before a restore, safety copies before removing a
    // business). Each one is a copy of the whole database, so older ones are deleted as new ones are written.
    'keep' => (int) env('BACKUP_KEEP', 5),
];
