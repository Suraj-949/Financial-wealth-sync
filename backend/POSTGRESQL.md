# PostgreSQL setup

WealthSync stores finance records in PostgreSQL as JSONB documents, partitioned
by user and resource. The backend creates the `finance_records` table on
startup. Supported resources are transactions, accounts, budgets, goals, alerts,
and recommendations.

## Start locally

1. Install and start PostgreSQL on the development machine.
2. Create a database and user matching the values in `.env.example`, or set the
   `POSTGRES_*` environment variables to the credentials you created.
3. From the repository root, run `./backend/run_backend.ps1`.
4. Open `/health`; its `database` field should be `connected`.

The example credentials are `wealthsync/wealthsync_dev` and the database
listens on `localhost:5432`. Change these values before exposing the service
outside the development machine. Configure the backend with
`POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_HOST`, and
`POSTGRES_PORT`, or set `DATABASE_URL` (SQLAlchemy `postgresql+psycopg` format).

## API

`GET /api/data/{resource}` lists one user's records.
`PUT /api/data/{resource}/{id}` inserts or replaces one record, and
`DELETE /api/data/{resource}/{id}` removes one.

Pass the namespace as `?user_id=...` or with the `X-User-Id` header (the header
wins when both are present). The Flutter app generates and stores a stable
per-install id (`local-user` by default), exposes it under **More → Settings →
Your data**, and sends it on every request.

## Demo mode vs. user data

- **Demo mode on:** every finance screen renders the in-memory sample data set.
  Nothing is written to PostgreSQL.
- **Demo mode off:** the dashboard, transactions, accounts, budgets, goals,
  alerts, and recommendations all read from the user's PostgreSQL namespace.
  The dashboard summary, category mix, six-month trend, projection, and insights
  are computed from those rows rather than mixed with sample values.
- New transactions can be added from **Dashboard → Add** or the **+** button on
  the Transactions tab; they are written to the active namespace. Deletes are
  supported from the Transactions tab. Other tabs refresh automatically after a
  write.

To start the local PostgreSQL service without opening the backend, run
`./backend/start_database.ps1` from the repository root. Authentication and
multi-device accounts are not implemented yet; the namespace is a prototype
partition key, not a security boundary.

