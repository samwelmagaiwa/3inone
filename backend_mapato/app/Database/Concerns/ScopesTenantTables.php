<?php

namespace App\Database\Concerns;

use App\Support\Tenancy\TenantContext;
use App\Support\Tenancy\TenantTables;
use Illuminate\Database\Query\Builder;
use Illuminate\Database\Query\JoinClause;

/**
 * Query-grammar half of the tenant scope (see TenantTables).
 *
 * Every statement the grammar compiles for a registered table gets
 * `<table>.owner_id = '<business>'` ANDed on, so a select, update, delete, join,
 * sub-query, aggregate or `exists:` validation rule can only ever see the
 * signed-in business's rows. The business id is spliced in as a literal -- it is
 * validated as a UUID first -- so it never alters the statement's bindings.
 *
 * The caller's own conditions are wrapped in parentheses first, so an `orWhere`
 * in a controller cannot escape the scope through operator precedence.
 *
 * Use inside a subclass of a Laravel query grammar.
 */
trait ScopesTenantTables
{
    public function compileWheres(Builder $query)
    {
        $sql = parent::compileWheres($query);

        $constraint = $this->tenantConstraint($query);
        if ($constraint === null) {
            return $sql;
        }

        if ($query instanceof JoinClause) {
            // Keep the scope in the ON clause, so a LEFT JOIN stays a left join.
            return $sql === '' ? 'on ' . $constraint : 'on (' . substr($sql, 3) . ') and ' . $constraint;
        }

        return $sql === '' ? 'where ' . $constraint : 'where (' . substr($sql, 6) . ') and ' . $constraint;
    }

    /**
     * `alias.owner_id = '<uuid>'` for a scoped table and a restricted viewer, and `alias.service = '<service>'` for
     * everyone signed in (a super admin sees every business, but one service's books at a time), else null.
     */
    protected function tenantConstraint(Builder $query): ?string
    {
        $table = TenantTables::resolve($query instanceof JoinClause ? $query->table : $query->from);
        if ($table === null) {
            return null;
        }

        $parts = [];
        $owner = TenantContext::readOwner();
        if ($owner !== null) {
            $parts[] = $this->wrap($table[1] . '.' . TenantTables::OWNER_COLUMN) . " = '" . $owner . "'";
        }

        // The service is one of two fixed words, never user text, so it is spliced in like the owner id.
        $service = TenantTables::splitByService() ? TenantContext::service() : null;
        if ($service !== null && in_array($service, TenantTables::SERVICES, true)) {
            $parts[] = $this->wrap($table[1] . '.' . TenantTables::SERVICE_COLUMN) . " = '" . $service . "'";
        }

        return $parts === [] ? null : implode(' and ', $parts);
    }
}
