# Put a semantic layer on your Supabase database, with your coding agent doing the work

> **TL;DR**: Give anfra a read-only login to your Supabase Postgres, then ask your coding agent
> (Claude Code, Codex, Cursor…) to model your tables, define your metrics, answer questions and
> build a dashboard. You stay in charge of the two things an agent shouldn't guess: **access** and
> **what your numbers mean**. No ETL, no copy of your data.
>
> Want to try it on sample data first? The **[demo repo](https://github.com/holistics/anfra-supabase-demo)**
> seeds a small store into Supabase and has everything below already built.

![A Data App running on Supabase](https://raw.githubusercontent.com/holistics/anfra-supabase-demo/main/docs/shop-overview.png)

## Why do this?

Supabase is a great place to *run* your app. Sooner or later someone asks *"what was our net
revenue last quarter, by category?"*. You can ask an AI agent to write the SQL, but each time it
re-guesses which tables to join and what "net revenue" means, and two people asking the same
question get two different numbers.

[anfra](https://anfra.ai) adds a **semantic layer** on top of the same Postgres:

- **Metrics are defined once**, in plain-text files in Git: "net revenue" means one thing, and
  changes to it go through code review.
- **Agents query the definitions, not raw tables.** With anfra's skills, your agent writes AQL
  that names fields and metrics. anfra writes the joins and the SQL.
- **Dashboards are code too.** A Data App is one HTML file in your repo, served by `anfra serve`.

Data stays in Supabase. anfra reads it live, through a login that can't write.

## Who does what

| You | Your agent |
|---|---|
| Create a read-only role and decide which tables it sees | Explore the schema and write the models |
| Put the credentials in a local file | Wire up relationships, validate the repo |
| Say what each metric means for *your* business | Turn that into metric definitions |
| Review the result, check a few numbers | Answer questions, verify them against SQL, build dashboards |

The split is deliberate. The agent never sees your `postgres` admin password, and it never
decides on its own what counts as revenue.

**You need:** a Supabase project with your app's data, a coding agent, and macOS or Linux.
**Time:** about 20 minutes.

---

## Step 1: Install anfra and give your agent the skills

```sh
curl -fsSL https://raw.githubusercontent.com/holistics/anfra/main/install.sh | bash

mkdir my-analytics && cd my-analytics && git init
anfra init           # .anfra/ config, models/, datasets/, apps/, AGENTS.md
anfra agent setup    # installs the anfra skills into the coding agents it finds
```

`anfra agent setup` teaches your agent anfra's languages (AML for models, AQL for queries) and
commands. Restart the agent afterwards so it picks the skills up, and open it in `my-analytics`.

> Keep this repo separate from your app's code, or put it in an `analytics/` folder inside it.
> Either works. It's just files.

## Step 2: Create a read-only role (you do this)

This is the one step you do by hand. It needs your admin login, and that login shouldn't go to an
agent.

Open the **SQL Editor** in the Supabase dashboard and run the following, changing the password and
the schema if your tables aren't in `public`:

```sql
create role anfra_reader login password '<a-strong-password>';

-- Read access to your app's tables. Not auth, storage or other Supabase internals.
grant usage  on schema public to anfra_reader;
grant select on all tables in schema public to anfra_reader;
alter default privileges in schema public grant select on tables to anfra_reader;

-- Guard rails
alter role anfra_reader set default_transaction_read_only = on;
alter role anfra_reader set statement_timeout = '60s';
```

Nothing you or an agent runs through anfra can change your data now. A write fails like this:

```
ERROR: cannot execute INSERT in a read-only transaction (SQLSTATE 25006)
```

Three things to settle before you move on:

**Row Level Security.** Most Supabase tables have RLS turned on, with policies written for your
app's users. `anfra_reader` matches none of them, so it **sees zero rows, without any error**. For
each table you want to analyse, add a read policy for anfra:

```sql
create policy anfra_reader_read on public.orders
  for select to anfra_reader using (true);
```

**Personal data.** If a table holds emails, phone numbers or addresses that analysts don't need,
grant only the columns they do need instead of the whole table:

```sql
revoke select on public.customers from anfra_reader;
grant select (id, country, city, acquisition_channel, created_at) on public.customers to anfra_reader;
```

**Load on production.** A read-only login protects your data, not your database's CPU. To keep
analytics queries off your primary, point anfra at a
[read replica](https://supabase.com/docs/guides/platform/read-replicas) in the next step. Only the
host changes.

## Step 3: Connect (you write the file, the agent checks it)

In the Supabase dashboard, click **Connect** and copy the **Session pooler** details:

- **Use the pooler, not `db.<ref>.supabase.co`.** The direct host is IPv6-only, so many laptops
  and CI runners can't reach it. The Session pooler works over IPv4.
- **On the pooler, the username carries the project ref**: `anfra_reader.<project-ref>`.

Replace the `warehouse` example in `.anfra/data_sources.yml` (it's git-ignored) with:

```yaml
data_sources:
  supabase:
    type: postgresql
    connection:
      host: aws-0-<region>.pooler.supabase.com
      port: 5432                       # a number, not "5432"
      user: anfra_reader.<project-ref>
      password: <a-strong-password>
      dbname: postgres                 # `dbname`, not `database`
    settings:
      require_ssl: true
```

You type the password into that file yourself, so it doesn't go through the chat. anfra reads the
file whenever it runs a query, and the agent doesn't need to open it.

Now hand over to the agent:

> **You:** Check that the `supabase` data source works, then list the tables in the `public`
> schema with their row counts.

You should get back a list of your tables with real counts. If a table you care about shows
**0 rows** but has data in the Supabase table editor, it's RLS: go back to Step 2.

## Step 4: Let the agent model your tables

A **model** describes one table: its fields, their types, and its primary key. A **dataset**
groups models, says how they join, and holds your metrics. You don't need to learn AML to get
started. Tell the agent which tables matter:

> **You:** Model the `customers`, `products`, `orders` and `order_items` tables from the
> `supabase` data source, and put them in a dataset called `shop` with the right relationships.
> Skip anything that looks internal or like a log table. Don't include email or phone columns.
> Run `anfra validate` when you're done.

The agent looks at the columns and sample values, writes one `models/<table>.model.aml` per table
and a `datasets/shop.dataset.aml`, and validates them. A model looks like this:

```aml
Model orders {
  type: 'table'
  label: 'Orders'
  data_source_name: 'supabase'
  table_name: '"public"."orders"'

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

**Review it like a pull request.** `anfra validate` passing only means the files are well
formed. Check these things yourself:

- **Primary keys.** Every model has one, and it really is unique.
- **Relationships point the right way.** `relationship(order_items.order_id > orders.id, true)`
  means many order items to one order. A reversed relationship makes totals double count.
- **Types.** Money columns are `number`, timestamps are `datetime`, and ids that are really codes
  are `text`.
- **Nothing sensitive slipped in.** If it did, ask the agent to remove it, and tighten the grant
  from Step 2.

If something's off, say so in plain words: *"order_items.product_id joins to products.id, not
products.sku"*.

## Step 5: Tell the agent what your metrics mean

This is the step an agent can't do for you. It can see that `orders` has a `status` column. It
can't know whether your finance team counts refunded orders as revenue. Give it the definitions:

> **You:** Add these metrics to the `shop` dataset:
> - **Net revenue**: quantity × (unit price − discount), only for `completed` and `shipped` orders.
> - **AOV**: net revenue per completed or shipped order.
> - **Gross profit**: net revenue minus quantity × product unit cost, same statuses.
> - **Gross margin**: gross profit / net revenue.
> - **Return rate**: share of orders with status `returned`.
> - **Buyers**: distinct customers with at least one order.
>
> Ask me if anything is ambiguous.

The agent writes them as metrics in the dataset, each built on the ones before it:

```aml
  metric net_revenue {
    label: 'Net Revenue'
    type: 'number'
    description: 'Line amounts after discounts, completed and shipped orders only.'
    definition: @aql sum(order_items.net_amount) | where(orders.status in ['completed', 'shipped']) ;;
    format: '[$$]#,###0'
  }

  metric gross_margin {
    label: 'Gross Margin %'
    type: 'number'
    definition: @aql safe_divide(gross_profit, net_revenue) ;;
    format: '#,##0.0%'
  }
```

The "completed and shipped only" rule now lives in exactly one place. Each `description` is
also what the next agent, or the next person, reads before using the metric, so ask for good
ones.

> Write down definitions your team already argues about. Those are the metrics where a
> semantic layer pays off first.

## Step 6: Ask questions, then check a number

Now ask in plain English:

> **You:** Net revenue and gross margin by product category, highest revenue first.

The agent writes AQL against the `shop` dataset and runs it:

```
explore {
  dimensions { category: products.category }
  measures   { net_revenue: net_revenue, gross_margin: gross_margin }
  sorts      { net_revenue desc }
}
```

| category | net_revenue | gross_margin |
|---|---:|---:|
| Footwear | $628,951 | 49.7% |
| Electronics | $468,331 | 54.8% |
| Apparel | $335,390 | 51.8% |
| Outdoor | $269,376 | 52.6% |
| … | | |

*(Results are from the demo store's data. Yours will be your own.)*

The query never mentions `order_items`, `unit_cost` or a join. anfra works those out from the
dataset and sends Supabase plain Postgres SQL. Ask *"show me the SQL"* if you want to read it.

Questions that cross several tables work the same way:

> **You:** Which acquisition channel brings the most buyers, and what's their AOV and return rate?

**Trust, but verify.** For the first few answers, have the agent check its own work outside the
semantic layer:

> **You:** Check total net revenue with a plain SQL query straight against Supabase, without
> using the dataset. Do the numbers match?

If they don't match, the difference usually points at a wrong relationship or metric. Fix the
definition once, and every later answer is fixed too.

## Step 7: Build a dashboard

> **You:** Build a Data App called "Sales overview" on the `shop` dataset: KPI cards for net
> revenue, orders, AOV and gross margin; net revenue over time with a week / month / quarter
> switch; revenue by category and by acquisition channel; top 10 products. Add filters for
> country and order date, and make clicking a category bar filter the rest of the page.

The agent writes `apps/sales_overview.html`, one self-contained HTML file whose queries are AQL
against your metrics. Open it:

```sh
anfra serve
# Data Apps  http://127.0.0.1:7878/apps/
```

Then keep refining it in conversation: *"make the trend a stacked bar by channel"*, *"add a
repeat-buyer KPI"*. The numbers on the page come from the same metric definitions as the answers
in Step 6, so the dashboard and the chat can't disagree.

## Step 8: Commit and share

```sh
git add . && git commit -m "Semantic layer on our Supabase database"
```

Your models, metrics and dashboards are now plain files under review. `.anfra/data_sources.yml`
stays out of Git, and the committed `.anfra/data_sources.yml.example` tells a teammate what to
fill in. When someone changes what "net revenue" means, it shows up as a diff in a pull request
instead of someone quietly editing a query.

Teammates clone the repo, add their own credentials, run `anfra agent setup`, and their agents
use the same definitions.

---

## Prompting tips

- **Name the dataset**: *"using the `shop` dataset…"*. That keeps the agent on your definitions
  instead of raw SQL.
- **Give definitions, not just names.** "Active customer" means something different in every
  company.
- **Ask it to verify.** *"Check that against SQL"* costs one query and catches modelling mistakes
  early.
- **Ask to see the AQL** when a number surprises you. It's short enough to read.
- **Fix the model, not the answer.** If an answer is wrong because a definition is wrong, ask the
  agent to fix the metric, not to patch that one query.

## Doing it by hand

Everything the agent does goes through the `anfra` CLI, which you can also use yourself:

```sh
anfra query --lang sql -s supabase 'select count(*) from public.orders'   # raw SQL, read-only
anfra validate                                                            # check every model and dataset
anfra show shop                                                           # fields and metrics as AQL sees them
anfra query --dataset shop 'explore { measures { net_revenue: net_revenue } }'
anfra serve                                                               # Data Apps and MCP at :7878
```

AML and AQL are documented at [amql.org/docs](https://amql.org/docs). For a complete, working set
of models, metrics and a Data App, see the
[demo repo](https://github.com/holistics/anfra-supabase-demo).

## Troubleshooting

| Symptom | Fix |
|---|---|
| A table shows **0 rows** through anfra, but has data in Supabase | RLS: add a `for select to anfra_reader` policy on that table (Step 2). |
| `could not translate host name db.<ref>.supabase.co` | That host is IPv6-only. Use the Session pooler host. |
| `Tenant or user not found` | Wrong pooler region in the host, or the user is missing `.<project-ref>`. |
| `password authentication failed` right after changing the password | The pooler caches credentials for a short while. Wait a minute and retry. |
| `invalid config for dbtype` | `port` must be a number (`5432`), not `"5432"`. |
| `permission denied for table …` / `for schema …` | Add `grant usage on schema …` / `grant select on …` for `anfra_reader`. Tables in a newly created schema need the grants again. |
| `cannot execute … in a read-only transaction` | Working as intended: the role is read-only. |
| The agent writes raw SQL instead of AQL | Check `anfra agent setup --check`, restart the agent, and name the dataset in your prompt. |

## Links

- Demo repo with sample data: https://github.com/holistics/anfra-supabase-demo
- anfra docs: https://anfra.ai/docs
- AML & AQL docs: https://amql.org/docs
- Supabase connection docs: https://supabase.com/docs/guides/database/connecting-to-postgres
- Supabase Row Level Security: https://supabase.com/docs/guides/database/postgres/row-level-security
