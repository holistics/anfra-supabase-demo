# Anfra × Supabase demo

Put a semantic layer and live dashboards on top of your **Supabase** Postgres database with
**[Anfra](https://anfra.ai)**, in about 10 minutes, without copying any data out.

```
 Supabase Postgres  ──(read-only role, Session pooler)──▶  Anfra  ──▶  AQL queries · Data Apps · AI agents
 ecommerce schema                                           models/ datasets/ apps/
```

What's in this repo:

| Path | What it is |
|---|---|
| [`supabase/seed.sql`](supabase/seed.sql) | Creates an `ecommerce` schema (customers, products, orders, order_items) with ~14k orders of deterministic sample data. |
| [`supabase/anfra_reader.sql`](supabase/anfra_reader.sql) | A **read-only** Postgres role for Anfra. |
| [`scripts/setup.sh`](scripts/setup.sh) | One command: seeds Supabase, creates the role, writes `.anfra/data_sources.yml`. |
| [`models/`](models) | AML models, one per table. |
| [`datasets/shop.dataset.aml`](datasets/shop.dataset.aml) | The `shop` dataset: relationships plus business metrics (Net Revenue, AOV, Gross Margin, Return Rate…). |
| [`apps/shop_overview.html`](apps/shop_overview.html) | A Data App: KPIs, trend, breakdowns, top products, with filters and cross-filtering. |
| [`TUTORIAL.md`](TUTORIAL.md) | The step-by-step walkthrough. |

![Shop overview Data App](docs/shop-overview.png)

## Quick start

You need a Supabase project, `psql`, and the Anfra CLI.

```sh
# 1. Install Anfra
curl -fsSL https://raw.githubusercontent.com/holistics/anfra/main/install.sh | bash

# 2. Clone this repo
git clone https://github.com/holistics/anfra-supabase-demo.git
cd anfra-supabase-demo

# 3. Point it at your Supabase project (Dashboard → Connect → Session pooler)
export SUPABASE_DB_URL='postgresql://postgres.<project-ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres'

# 4. Seed data, create a read-only role, configure Anfra
./scripts/setup.sh

# 5. Check the models and open the dashboard
anfra validate
anfra serve        # → http://127.0.0.1:7878/apps/shop_overview
```

Ask a question in AQL:

```sh
anfra query --dataset shop '
explore {
  dimensions { category: products.category }
  measures   { net_revenue: net_revenue, gross_margin: gross_margin }
  sorts      { net_revenue desc }
}'
```

Already have your own tables in Supabase? Skip the seed, point the models at your tables, and
follow [TUTORIAL.md](TUTORIAL.md) from step 3.

## Why a read-only role and the pooler?

- **Read-only**: Anfra only reads. `anfra_reader` has `SELECT` on one schema,
  `default_transaction_read_only = on` and a 60s statement timeout, so nothing it runs can change
  or hog your database.
- **Session pooler**: Supabase's direct host (`db.<ref>.supabase.co`) is IPv6-only. The Session
  pooler works over IPv4 everywhere. On the pooler the user is written `<role>.<project-ref>`.
- **Not exposed over the API**: the `ecommerce` schema is not in Supabase's *Exposed schemas*, so
  the demo tables aren't reachable through the auto-generated REST/GraphQL API.

## Learn more

- Anfra docs: https://anfra.ai/docs
- AML & AQL language docs: https://amql.org/docs
- Community: https://community.anfra.ai

## License

MIT
