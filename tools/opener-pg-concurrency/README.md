# opener 兩段式 · 真 PostgreSQL 並行驗收

PGlite 契約測試（`opener_two_stage_migration_postgres_test.ts`）是單連線；這裡用真 Postgres 多連線驗
同局同時 claim、租約過期接手、結算原子性（失敗回滾／觀察者不見中間狀態）、重播不重扣、跨帳號隔離。

可丟棄叢集（一般使用者、不需 sudo；socket 目錄要短）：

```
PGBIN=/usr/lib/postgresql/16/bin
$PGBIN/initdb -D /path/pgdata -U postgres --auth=trust -E UTF8 --locale=C.UTF-8
mkdir -p ~/.pgsock-opener
$PGBIN/pg_ctl -D /path/pgdata -l /path/postgres.log -o "-p 54329 -k $HOME/.pgsock-opener -c listen_addresses=127.0.0.1" -w start
export PGHOST=127.0.0.1 PGPORT=54329 PGUSER=postgres
psql -Atc "create database opener_acceptance"
psql -d opener_acceptance -v ON_ERROR_STOP=1 -f tools/opener-pg-concurrency/bootstrap.sql
{ echo "SET app.allow_missing_pg_cron = 'pglite-contract-test';"; \
  cat supabase/migrations/20260702120000_increment_usage_atomic_quota.sql \
      supabase/migrations/20260917120000_opener_two_stage_sessions.sql; } \
  | psql -d opener_acceptance -v ON_ERROR_STOP=1
PGDATABASE=opener_acceptance deno run --allow-net=127.0.0.1 --allow-env --allow-read --allow-write \
  tools/opener-pg-concurrency/run.ts --out=<dir>
```

沒有 pg_cron 時 migration 走測試模式（NOTICE 跳過排程），其餘物件與 production 相同。
結束後 `$PGBIN/pg_ctl -D /path/pgdata stop`。這不是 production，也不得指向 production。
