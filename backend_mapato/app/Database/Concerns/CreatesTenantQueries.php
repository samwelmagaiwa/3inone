<?php

namespace App\Database\Concerns;

use App\Database\TenantQueryBuilder;

/** Makes a connection hand out the tenant-aware query builder. */
trait CreatesTenantQueries
{
    public function query()
    {
        return new TenantQueryBuilder($this, $this->getQueryGrammar(), $this->getPostProcessor());
    }
}
