<?php

namespace App\Logging;

use Illuminate\Log\Logger;

/**
 * Log-channel "tap" (see config/logging.php): puts BusinessContextProcessor on the channel.
 */
class AddBusinessContext
{
    public function __invoke(Logger $logger): void
    {
        foreach ($logger->getLogger()->getHandlers() as $handler) {
            if (method_exists($handler, 'pushProcessor')) {
                $handler->pushProcessor(new BusinessContextProcessor());
            }
        }
    }
}
