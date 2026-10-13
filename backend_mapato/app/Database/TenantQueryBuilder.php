<?php

namespace App\Database;

use App\Support\Tenancy\TenantContext;
use App\Support\Tenancy\TenantTables;
use Illuminate\Database\Query\Builder;
use LogicException;

/**
 * Query builder that stamps new rows with their business (see TenantTables).
 *
 * The grammar scopes everything that READS or CHANGES existing rows; this class
 * covers INSERTs, where the owner has to be part of the data itself.
 */
class TenantQueryBuilder extends Builder
{
    public function insert(array $values)
    {
        return parent::insert($this->stampOwner($values));
    }

    public function insertGetId(array $values, $sequence = null)
    {
        return parent::insertGetId($this->stampOwner($values), $sequence);
    }

    public function insertOrIgnore(array $values)
    {
        return parent::insertOrIgnore($this->stampOwner($values));
    }

    // The statements below build SQL that cannot be stamped or scoped safely, so a business
    // (or anyone acting as one) may not use them on tenant tables: refuse rather than silently
    // cross businesses. With nothing scoped -- the platform's own tooling inside
    // TenantContext::withoutScope(), such as a system restore, or a super admin -- there is no
    // business to cross, and rows keep the owner they already carry.

    public function upsert(array $values, array|string $uniqueBy, ?array $update = null)
    {
        $this->refuseOnTenantTableUnlessUnscoped(__FUNCTION__);

        return parent::upsert($values, $uniqueBy, $update);
    }

    public function insertUsing(array $columns, $query)
    {
        $this->refuseOnTenantTableUnlessUnscoped(__FUNCTION__);

        return parent::insertUsing($columns, $query);
    }

    public function insertOrIgnoreUsing(array $columns, $query)
    {
        $this->refuseOnTenantTableUnlessUnscoped(__FUNCTION__);

        return parent::insertOrIgnoreUsing($columns, $query);
    }

    public function truncate()
    {
        if (TenantContext::readOwner() !== null) {
            $this->refuseOnTenantTable(__FUNCTION__);
        }

        parent::truncate();
    }

    /**
     * Give each new row to the business doing the insert. A row that already names
     * an owner keeps it, unless a restricted viewer names someone else's.
     */
    protected function stampOwner(array $values): array
    {
        if ($values === [] || !$this->isTenantTable()) {
            return $values;
        }

        $owner = TenantContext::writeOwner();
        if ($owner === null) {
            return $values;
        }

        $restricted = TenantContext::readOwner() !== null;
        $isBatch = is_array(reset($values));
        $rows = $isBatch ? $values : [$values];

        foreach ($rows as $i => $row) {
            $given = $row[TenantTables::OWNER_COLUMN] ?? null;

            if ($given === null) {
                $rows[$i][TenantTables::OWNER_COLUMN] = $owner;
            } elseif ($restricted && (string) $given !== $owner) {
                throw new LogicException("Refusing to write a {$this->from} row for another business.");
            }
        }

        return $isBatch ? $rows : $rows[0];
    }

    private function isTenantTable(): bool
    {
        return is_string($this->from) && TenantTables::has($this->from);
    }

    private function refuseOnTenantTableUnlessUnscoped(string $operation): void
    {
        if (TenantContext::readOwner() !== null) {
            $this->refuseOnTenantTable($operation);
        }
    }

    private function refuseOnTenantTable(string $operation): void
    {
        if ($this->isTenantTable()) {
            throw new LogicException("{$operation}() is not supported on the per-business table {$this->from}.");
        }
    }
}
