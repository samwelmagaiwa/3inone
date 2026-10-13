<?php

namespace App\Database;

use App\Database\Concerns\CreatesTenantQueries;
use Illuminate\Database\MySqlConnection;
use PDOException;

class MySqlConnection57 extends MySqlConnection
{
    // Per-business data isolation for the raw-SQL (Inventory) tables: see
    // App\Support\Tenancy\TenantTables. Everything else behaves exactly as before.
    use CreatesTenantQueries;

    protected function getDefaultQueryGrammar()
    {
        return new TenantMySqlGrammar($this);
    }

    /**
     * Get the number of active connections.
     * Override to work with MySQL 5.7 which doesn't have performance_schema.session_status
     *
     * @return int|null
     */
    public function threadCount(): ?int
    {
        try {
            // Try the original method first (for MySQL 8+)
            return parent::threadCount();
        } catch (PDOException $e) {
            // If it fails due to performance_schema issue, use fallback
            if (str_contains($e->getMessage(), 'performance_schema.session_status')) {
                try {
                    // Fallback for MySQL 5.7: use SHOW STATUS instead
                    $result = $this->selectOne("SHOW STATUS LIKE 'Threads_connected'");
                    return $result ? (int) $result->Value : null;
                } catch (PDOException $fallbackException) {
                    // If even the fallback fails, return null gracefully
                    return null;
                }
            }
            
            // Re-throw other exceptions
            throw $e;
        } catch (\Exception $e) {
            // Handle any other exceptions
            if (str_contains($e->getMessage(), 'performance_schema.session_status')) {
                try {
                    $result = $this->selectOne("SHOW STATUS LIKE 'Threads_connected'");
                    return $result ? (int) $result->Value : null;
                } catch (\Exception $fallbackException) {
                    return null;
                }
            }
            
            throw $e;
        }
    }

    /**
     * Get server version in a MySQL 5.7 compatible way
     *
     * @return string
     */
    public function getServerVersion(): string
    {
        try {
            return parent::getServerVersion();
        } catch (\Exception $e) {
            // Fallback method for MySQL 5.7
            try {
                $result = $this->selectOne('SELECT VERSION() as version');
                return $result->version ?? 'MySQL 5.7 (Compatible)';
            } catch (\Exception $fallbackException) {
                return 'MySQL 5.7 (Compatible)';
            }
        }
    }

    /**
     * Get database size in a MySQL 5.7 compatible way
     *
     * @return float|null
     */
    public function getSize(): ?float
    {
        try {
            // Try to get database size using information_schema
            $result = $this->selectOne("
                SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS size_mb
                FROM information_schema.tables 
                WHERE table_schema = ?
            ", [$this->getDatabaseName()]);
            
            return $result ? (float) $result->size_mb : null;
        } catch (\Exception $e) {
            // Return null if we can't get the size
            return null;
        }
    }
}