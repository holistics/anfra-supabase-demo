# Turn your Supabase database into a governed analytics layer with Anfra

> **TL;DR**: Connect Anfra to Supabase Postgres with a read-only role, describe your tables
> once in AML, and you get consistent business metrics you can query in AQL, put on a live
> dashboard (a Data App), or hand to your AI coding agent. No ETL and no copy of your data.
> Full demo repo: **https://github.com/holistics/anfra-supabase-demo**

![Shop overview Data App, running on Supabase](https://raw.githubusercontent.com/holistics/anfra-supabase-demo/main/docs/shop-overview.png)

## Why do this?

Supabase is a great place to *run* your app: Postgres, auth, storage, all in one. Sooner or
later someone asks *"what was our net revenue last quarter, by category?"*, and the answer turns
into a pile of hand-written SQL that each person writes a bit differently.

[Anfra](https://anfra.ai) adds a **semantic layer** on top of the same Postgres:

- **Define metrics once.** "Net revenue" means one thing, written in one file, reviewed in Git.
- **Query by meaning, not joins.** AQL knows how `orders`, `order_items` and `products` relate,
  so a query names fields and metrics and Anfra writes the SQL.
- **Ship dashboards as code.** A Data App is one HTML file in your repo, served by `anfra serve`.
- **Give your AI agent guardrails.** Anfra ships skills and an MCP server, so Claude Code, Cursor
  and friends query your *defined* metrics instead of guessing at SQL.

Data stays in Supabase. Anfra reads it live, through a read-only login.

## What we'll build

```
 Supabase Postgres                                  Anfra repo (Git)
 ┌───────────────────────┐   read-only role    ┌──────────────────────────────┐
 │ ecommerce.customers   │   via Session       │ models/    one per table     │
 │ ecommerce.products    │ ◀──── pooler ────── │ datasets/  joins + metrics   │──▶ AQL / Data Apps / MCP
 │ ecommerce.orders      │   (IPv4, TLS)       │ apps/      dashboards        │
 │ ecommerce.order_items │                     └──────────────────────────────┘
 └───────────────────────┘
```

A small online store: 2,000 customers, 60 products, ~9,400 orders and ~22,000 order lines from
Jan 2025 to Oct 2026. By the end you'll have:

1. Sample data in your Supabase project
2. A read-only `anfra_reader` role
3. An Anfra repo with 4 models and a `shop` dataset with 11 metrics
4. AQL queries checked against plain SQL
5. A live dashboard with filters and cross-filtering

**Time:** ~10 minutes. **You need:** a Supabase project, `psql`, macOS/Linux.

---

## Step 0: Get the Anfra CLI and the demo repo

```sh
curl -fsSL https://raw.githubusercontent.com/holistics/anfra/main/install.sh | bash
anfra version

git clone https://github.com/holistics/anfra-supabase-demo.git
cd anfra-supabase-demo
```

> Starting from scratch instead? `anfra init` in any folder creates the same layout:
> `.anfra/data_sources.yml`, `models/`, `datasets/`, `apps/`.

## Step 1: Get your Supabase connection string

In the Supabase dashboard, click **Connect** at the top of your project, then copy the
**Session pooler** URI:

```
postgresql://postgres.<project-ref>:[YOUR-PASSWORD]@aws-0-<region>.pooler.supabase.com:5432/postgres
```

Two Supabase details worth knowing:

- **Use the pooler, not `db.<ref>.supabase.co`.** The direct host is IPv6-only, so many laptops,
  CI runners and cloud VMs can't reach it. The Session pooler works over IPv4.
- **Pooler usernames carry the project ref**: `postgres.<project-ref>`. The same goes for any
  role you create: `anfra_reader.<project-ref>`.

Keep it out of Git:

```sh
echo 'postgresql://postgres.<project-ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres' > .env.local
```

(`.env.local` is already git-ignored in the demo repo.)

## Step 2: Seed data and create a read-only role

One script does both and writes Anfra's connection config:

```sh
./scripts/setup.sh
```

```
→ Seeding the ecommerce schema on aws-0-<region>.pooler.supabase.com
 table_name  | count
-------------+-------
 customers   |  2000
 products    |    60
 orders      |  9357
 order_items | 22210
→ Creating the read-only role anfra_reader
→ Writing .anfra/data_sources.yml (git-ignored)
→ Checking the connection through Anfra
  orders visible to anfra_reader: 9357
✓ Done. Next: anfra validate && anfra serve
```

What it ran:

**`supabase/seed.sql`** creates an `ecommerce` schema with deterministic data, so everyone
following along gets the same numbers. The schema is *not* in Supabase's **Exposed schemas**, so
these tables aren't reachable through the auto-generated REST/GraphQL API.

**`supabase/anfra_reader.sql`** creates the role Anfra logs in as. If you prefer the SQL Editor,
this is the whole thing:

```sql
create role anfra_reader login password '<a-strong-password>';

grant usage  on schema ecommerce to anfra_reader;
grant select on all tables in schema ecommerce to anfra_reader;
alter default privileges in schema ecommerce grant select on tables to anfra_reader;

alter role anfra_reader set statement_timeout = '60s';
alter role anfra_reader set default_transaction_read_only = on;
```

Anfra only ever reads. With a role that *can't* write, nothing you or an AI agent runs through
Anfra can change your production data:

```sh
$ anfra query --lang sql -s supabase "insert into ecommerce.products values (999,'x','x',1,1,now())"
error: 'run query: ERROR: cannot execute INSERT in a read-only transaction (SQLSTATE 25006)'
```

**`.anfra/data_sources.yml`** (git-ignored) ends up like this:

```yaml
data_sources:
  supabase:
    type: postgresql
    connection:
      host: aws-0-<region>.pooler.supabase.com
      port: 5432                       # a number, not a string
      user: anfra_reader.<project-ref> # pooler format
      password: <password>
      dbname: postgres                 # `dbname`, not `database`
    settings:
      require_ssl: true
```

Check it:

```sh
anfra query --lang sql -s supabase 'select count(*) from ecommerce.orders'
```

## Step 3: Model the tables (AML)

A **model** maps one table and declares its fields. Here's `models/orders.model.aml`, shortened:

```aml
Model orders {
  type: 'table'
  label: 'Orders'
  data_source_name: 'supabase'
  table_name: '"ecommerce"."orders"'

  dimension id {
    type: 'number'
    primary_key: true
    definition: @sql {{ #SOURCE.id }};;
  }
  dimension status {
    type: 'text'
    description: 'completed / shipped / returned / cancelled'
    definition: @sql {{ #SOURCE.status }};;
  }
  dimension created_at {
    label: 'Ordered At'
    type: 'datetime'
    definition: @sql {{ #SOURCE.created_at }};;
  }
  // customer_id, channel …
}
```

Derived columns live in the model too, so nobody re-derives them differently.
From `models/order_items.model.aml`:

```aml
  dimension net_amount {
    label: 'Net Amount'
    type: 'number'
    description: 'quantity x (unit_price - discount)'
    definition: @sql {{ #SOURCE.quantity }} * ({{ #SOURCE.unit_price }} - {{ #SOURCE.discount }});;
  }
```

## Step 4: Define relationships and metrics once (the dataset)

A **dataset** bundles models, says how they join, and defines the business metrics.
From `datasets/shop.dataset.aml`:

```aml
Dataset shop {
  label: 'Shop (Supabase)'
  data_source_name: 'supabase'

  models: [customers, products, orders, order_items]

  relationships: [
    relationship(order_items.order_id   > orders.id,    true),
    relationship(order_items.product_id > products.id,  true),
    relationship(orders.customer_id     > customers.id, true),
  ]

  metric net_revenue {
    label: 'Net Revenue'
    type: 'number'
    description: 'Line amounts after discounts, completed and shipped orders only.'
    definition: @aql sum(order_items.net_amount) | where(orders.status in ['completed', 'shipped']) ;;
    format: '[$$]#,###0'
  }

  metric cogs {
    label: 'Cost of Goods Sold'
    type: 'number'
    definition: @aql sum(order_items, order_items.quantity * products.unit_cost)
                     | where(orders.status in ['completed', 'shipped']) ;;
  }

  metric gross_profit { type: 'number'  definition: @aql net_revenue - cogs ;; }
  metric gross_margin { type: 'number'  definition: @aql safe_divide(gross_profit, net_revenue) ;; }

  metric aov {
    label: 'AOV (Average Order Value)'
    type: 'number'
    definition: @aql safe_divide(net_revenue, total_orders | where(orders.status in ['completed', 'shipped'])) ;;
  }
  // total_orders, buyers, gross_sales, total_discount, units_sold, return_rate …
}
```

Metrics build on metrics (`gross_margin` → `gross_profit` → `net_revenue`, `cogs`), and the
"completed and shipped only" rule lives in exactly one place.

Validate the repo:

```sh
$ anfra validate
diagnostics: []
valid: true

$ anfra show shop     # models, fields and metrics as AQL sees them
```

## Step 5: Ask questions in AQL

AQL names *what* you want. Anfra works out the joins:

```sh
anfra query --dataset shop '
explore {
  dimensions { category: products.category }
  measures   { net_revenue: net_revenue, gross_margin: gross_margin }
  sorts      { net_revenue desc }
}'
```

| category | net_revenue | gross_margin |
|---|---:|---:|
| Footwear | $628,951 | 49.7% |
| Electronics | $468,331 | 54.8% |
| Apparel | $335,390 | 51.8% |
| Outdoor | $269,376 | 52.6% |
| Accessories | $219,933 | 50.2% |
| Fitness | $169,691 | 54.4% |
| Home | $112,559 | 51.1% |
| Stationery | $47,071 | 41.7% |

The query never mentions `order_items`, `unit_cost` or a join. Anfra sends Supabase plain
Postgres SQL, which you can read:

```sql
WITH "aql__t2" AS (
  SELECT
    "products"."category" AS "products->category",
    SUM(("order_items"."quantity" * ("order_items"."unit_price" - "order_items"."discount"))) AS "sum_order_items->net_amount",
    SUM(("order_items"."quantity" * "products"."unit_cost")) AS "sum_2c0c2fd4038a3b77"
  FROM "ecommerce"."order_items" "order_items"
    LEFT JOIN "ecommerce"."orders"   "orders"   ON "order_items"."order_id"   = "orders"."id"
    LEFT JOIN "ecommerce"."products" "products" ON "order_items"."product_id" = "products"."id"
  WHERE "orders"."status" IN ('completed', 'shipped')
  GROUP BY 1
)
SELECT "products->category" AS "category",
       "sum_order_items->net_amount" AS "net_revenue",
       (("sum_order_items->net_amount" - "sum_2c0c2fd4038a3b77") * 1.0)
         / NULLIF("sum_order_items->net_amount", 0) AS "gross_margin"
FROM "aql__t2" "aql__t1"
ORDER BY 2 DESC
```

Another one, crossing three tables, with no join written:

```sh
anfra query --dataset shop '
explore {
  dimensions { channel: customers.acquisition_channel }
  measures   { buyers: buyers, aov: aov, return_rate: return_rate }
  sorts      { buyers desc }
}'
```

| channel | buyers | aov | return_rate |
|---|---:|---:|---:|
| Organic Search | 485 | $260.12 | 3.6% |
| Paid Social | 340 | $257.35 | 4.4% |
| Referral | 261 | $261.38 | 3.7% |
| Email | 242 | $250.27 | 3.6% |
| Direct | 237 | $266.29 | 3.2% |

**Trust, but verify.** We checked the headline numbers with plain SQL against Supabase:

```sql
select sum(i.quantity * (i.unit_price - i.discount)) filter (where o.status in ('completed','shipped')) as net_revenue,
       count(distinct o.id) as orders, count(distinct o.customer_id) as buyers
from ecommerce.order_items i join ecommerce.orders o on o.id = i.order_id;
-- 2251299.80 | 9357 | 1565   ← identical to the AQL metrics
```

## Step 6: A live dashboard with a Data App

`apps/shop_overview.html` is a single HTML file. It declares its queries with the Anfra SDK, and
`anfra serve` runs them against Supabase:

```sh
anfra serve
# Data Apps  http://127.0.0.1:7878/apps/
```

Open **Shop Overview (Supabase)**: five KPIs, revenue and gross profit over time (week / month /
quarter), revenue by category and acquisition channel, and top products, with category, country
and date filters. **Click a bar** to cross-filter the whole page.

The SDK wiring is short. Each query is AQL that uses the dataset's metrics:

```js
const app = Anfra.createApp({ title: 'Shop Overview' });

const trend = app.createQuery('trend', {
  dataset: 'shop',
  aql: `explore {
    dimensions { period: orders.created_at | month() }
    measures   { net_revenue: net_revenue, gross_profit: gross_profit }
    sorts      { period asc }
  }`,
});
const byCategory = app.createQuery('byCategory', {
  dataset: 'shop',
  aql: `explore {
    dimensions { category: products.category }
    measures   { net_revenue: net_revenue }
    sorts      { net_revenue desc }
  }`,
});

// Controls are explicit: a filter only affects the queries you map it to
const country = app.createFilter('country', { dataset: 'shop', field: 'customers.country' });
app.mapControl(country, trend,      { field: 'customers.country' });
app.mapControl(country, byCategory, { field: 'customers.country' });

const grain = app.createDateDrill('grain', { default: 'month' });
app.mapControl(grain, trend, { field: 'orders.created_at' });

// Clicking a category filters the trend
app.mapCrossFilter(byCategory, trend);

app.subscribe(render);   // your rendering: ECharts here, anything you like
app.execute();
```

Filtering to *Singapore* in the app shows **$107,098** net revenue, the same number as a direct
SQL query with `where c.country = 'Singapore'`.

## Step 7 (bonus): Let your AI agent use the same metrics

`anfra serve` also exposes your repo as **MCP tools** at `http://127.0.0.1:7878/mcp`, and Anfra
ships skills for coding agents:

```sh
anfra agent setup
```

Now ask Claude Code / Cursor *"Which acquisition channel brings the highest AOV in 2026?"*. The
agent writes AQL against `shop` and uses *your* definition of AOV, not one it made up, through a
login that can't write.

---

## Using your own Supabase tables

1. Skip the seed. Grant `anfra_reader` `SELECT` on your schema (often `public`).
2. Write one `models/<table>.model.aml` per table, with a `primary_key`.
3. Add a dataset with relationships and the metrics your team argues about.
4. `anfra validate`, then check one number against SQL.

**Tip:** the Anfra skills make step 2 fast. Ask your agent to *"model the tables in the public
schema of the supabase data source"* and review the AML it writes.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `could not translate host name db.<ref>.supabase.co` | That host is IPv6-only. Use the Session pooler host. |
| `Tenant or user not found` | Wrong pooler region in the host, or the user is missing `.<project-ref>`. |
| `invalid config for dbtype` | `port` must be a number (`5432`), not `"5432"`. |
| `permission denied for schema …` | `grant usage on schema … to anfra_reader` (re-run after dropping/recreating a schema). |
| `cannot execute … in a read-only transaction` | Working as intended: the role is read-only. |

## Links

- Demo repo: https://github.com/holistics/anfra-supabase-demo
- Anfra docs: https://anfra.ai/docs
- AML & AQL docs: https://amql.org/docs
- Supabase connection docs: https://supabase.com/docs/guides/database/connecting-to-postgres
