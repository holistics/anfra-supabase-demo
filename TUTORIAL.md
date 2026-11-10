# Build trusted analytics on Supabase, for free, with your coding agent

> **TL;DR**: Give anfra a read-only login to your Supabase Postgres, then ask your coding agent
> (Claude Code, Codex, Cursor…) to model your tables, define your metrics, answer questions,
> build a dashboard and publish it to your team. You stay in charge of what an agent shouldn't
> decide alone: **access** and **what your numbers mean**. After installing anfra, a
> [single prompt](#the-prompt-steps-2-to-8-in-one-go) does Steps 2 to 8 and stops each time
> it needs you. No ETL, no copy of your data, and anfra is open source (Apache 2.0).
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

**Your agent does most of the work:**

- writes the SQL for a read-only database role
- explores your schema and writes the models and relationships
- turns your metric definitions into code and validates the repo
- answers questions, then checks its answers against plain SQL
- builds and refines dashboards

**You make the decisions:**

- which tables and columns anfra may read, and approving the role before it's created
- the database password, which you type into a local file yourself, never into the chat
- what each metric means for *your* business
- reviewing the models, checking a few numbers, and publishing to your team

The split is deliberate. An agent can draft everything, but it shouldn't decide on its own what
it's allowed to read or what counts as revenue. That's how the post works: after installing,
you paste [**one prompt**](#the-prompt-steps-2-to-8-in-one-go) that covers Steps 2 to 8, and
the agent pauses at each of these decisions.

**You need:** a Supabase project with your app's data, a coding agent, and macOS or Linux.
**Time:** about 20 minutes.

---

## Step 1: Install anfra and give your agent the skills

Open your agent in an empty folder (say `my-analytics`) and ask:

> **You:** Install the anfra CLI (https://anfra.ai/docs), then in this folder run `git init`,
> `anfra init` and `anfra agent setup`.

Or run it yourself:

```sh
curl -fsSL https://raw.githubusercontent.com/holistics/anfra/main/install.sh | bash

mkdir my-analytics && cd my-analytics && git init
anfra init           # .anfra/ config, models/, datasets/, apps/, AGENTS.md
anfra agent setup    # installs the anfra skills into the coding agents it finds
```

`anfra agent setup` teaches your agent anfra's languages (AML for models, AQL for queries) and
commands. **Then restart the agent**, still in `my-analytics`. An agent loads its skills when it
starts, so without a restart it would do the rest from memory, and guess.

> Keep this repo separate from your app's code, or put it in an `analytics/` folder inside it.
> Either works. It's just files.

## The prompt: Steps 2 to 8 in one go

After the restart, one prompt takes the agent through Steps 2 to 8. It stops wherever you have
to decide something. Fill in the brackets and paste it:

> **You:** Set up anfra on my Supabase database so we can analyse our [sales] data. Go step by
> step, and stop where I've written **STOP**.
>
> - **Step 2.** Write the SQL for a read-only role `anfra_reader`. It should read the app
>   tables in `public` (nothing in `auth` or `storage`), be read-only with a 60s statement
>   timeout, and have a select policy on every table with Row Level Security turned on. Leave
>   out personal data like email, phone and address columns. Use `<password>` as the password. **STOP** so I can review
>   and run it.
> - **Step 3.** Connect anfra as the data source `supabase`, logging in as `anfra_reader`
>   through this Session pooler string: `[paste it from Supabase → Connect]`. Leave
>   `<password>` as a placeholder. **STOP** so I can fill in the password. Then list the tables
>   with row counts, and point out any table that shows 0 rows.
> - **Step 4.** Model the tables that matter for [sales], and put them in a dataset called
>   `[shop]` with their relationships. Run `anfra validate`. Show me the primary keys and
>   relationships. **STOP** for my review.
> - **Step 5.** Propose definitions for these metrics: [net revenue, AOV, gross margin, return
>   rate]. Point out anything ambiguous, like which order statuses count. **STOP** for me to
>   confirm them, then add them to the dataset.
> - **Step 6.** Answer "[net revenue and gross margin by product category]" with AQL, and
>   check the total against a plain SQL query.
> - **Step 7.** Build a Data App called "[Sales overview]" with KPIs, a trend over time, the
>   main breakdowns and a date filter. Tell me how to open it.
> - **Step 8.** Commit the repo. Don't publish; I'll do that.

Paste the Session pooler string from Supabase's **Connect** button. It shows `[YOUR-PASSWORD]`
instead of your password, so it's safe to share. You can also be more specific than the
brackets suggest: name the tables to model, or describe the dashboard you want. The rest of
this post uses the names above, the `shop` dataset and a "Sales overview" app. Read your own
names in their place.

You don't need to run Steps 2 to 8 separately; this prompt does them. Read them alongside
it: each one covers what the agent does, what to check when it stops, and what to say back.

## Step 2: Create a read-only role (the agent drafts it, you approve it)

anfra should log in with its own role, one that can read your app's tables and nothing else.
The agent starts by writing the SQL for it, then stops.

How the agent finds your tables, RLS settings and columns depends on what it can see:

- **Opened in your app's repo**, it reads your `supabase/migrations`. You review the SQL and
  paste it into the Supabase **SQL Editor**, replacing `<password>` with a strong one.
- **Connected to Supabase** (for example through the
  [Supabase MCP server](https://supabase.com/docs/guides/getting-started/mcp)), it can look at
  the live schema and run the SQL itself. Approve each statement before it runs, and set the
  password yourself afterwards in the SQL Editor
  (`alter role anfra_reader password '…'`) so it never passes through the chat. The pooler
  caches passwords for a short while, so if the first login fails, wait a minute and retry.

Either way, the result should look like this (the demo repo has a complete version in
[`supabase/anfra_reader.sql`](https://github.com/holistics/anfra-supabase-demo/blob/main/supabase/anfra_reader.sql)):

```sql
create role anfra_reader login password '<password>';

-- Read access to your app's tables. Not auth, storage or other Supabase internals.
grant usage  on schema public to anfra_reader;
grant select on all tables in schema public to anfra_reader;
-- Optional: also make tables created later readable. Leave this out if you'd
-- rather grant each new table yourself.
alter default privileges in schema public grant select on tables to anfra_reader;

-- Guard rails
alter role anfra_reader set default_transaction_read_only = on;
alter role anfra_reader set statement_timeout = '60s';
```

The role has no `insert`, `update` or `delete` grants, so it can't change your tables. That's
what protects your data. The read-only default is a second layer on top of it, and makes a
write fail straight away:

```
ERROR: cannot execute INSERT in a read-only transaction (SQLSTATE 25006)
```

One gap to check: Postgres lets every role run functions by default. If `public` has
`security definer` functions that write data, the agent should list them, and you decide
whether to revoke `execute` on them.

What to check before you approve it:

**Row Level Security.** Most Supabase tables have RLS turned on, with policies written for your
app's users. `anfra_reader` matches none of them, so without its own policy it **sees zero rows,
without any error**. Check there's a read policy like this one for each table you want to
analyse:

```sql
create policy anfra_reader_read on public.orders
  for select to anfra_reader using (true);
```

**Personal data.** If a table holds emails, phone numbers or addresses that analysts don't need,
the grant should list only the columns they do need, not the whole table:

```sql
revoke select on public.customers from anfra_reader;
grant select (id, country, city, acquisition_channel, created_at) on public.customers to anfra_reader;
```

Check your **views** too. `grant select on all tables` covers views as well, and a Supabase
view runs as its owner unless it's created `with (security_invoker = on)`. Such a view skips
both RLS and the column grant above, so a view that shows `customers.email` would still expose
it. Revoke `select` on views like that, or leave them out of the grant.

**Load on production.** A read-only login protects your data, not your database's CPU. To keep
analytics queries off your primary, point anfra at a
[read replica](https://supabase.com/docs/guides/platform/read-replicas) in the next step. Only the
host changes.

## Step 3: Connect (the agent writes the config, you add the password)

Next the agent configures anfra's connection from the Session pooler string in your prompt.
Two Supabase details the agent needs to get right, and you should check:

- **The pooler, not `db.<ref>.supabase.co`.** The direct host is IPv6-only, so many laptops
  and CI runners can't reach it. The Session pooler works over IPv4.
- **On the pooler, the username carries the project ref**: `anfra_reader.<project-ref>`, not
  `anfra_reader`.
- **Copy the host exactly as Connect shows it.** Depending on the project it starts with
  `aws-0-` or `aws-1-`, followed by your region.

The agent replaces the `warehouse` example in `.anfra/data_sources.yml` (git-ignored) with
something like this, and mirrors it without secrets in the committed
`.anfra/data_sources.yml.example`:

```yaml
data_sources:
  supabase:
    type: postgresql
    connection:
      host: aws-0-<region>.pooler.supabase.com
      port: 5432                       # a number, not "5432"
      user: anfra_reader.<project-ref>
      password: <password>             # you replace this
      dbname: postgres                 # `dbname`, not `database`
    settings:
      require_ssl: true
```

Now open `.anfra/data_sources.yml` in your editor and replace `<password>` with the password you
set for `anfra_reader` in Step 2. That's the only thing you type yourself, and it never goes
through the chat. This login is the only one anfra ever uses, from your laptop or (after Step 9)
from anfra Cloud, and it can't write.

Then tell the agent to carry on:

> **You:** Password's in, go on.

It checks the connection and lists your tables with their row counts. If a table you care about shows
**0 rows** but has data in the Supabase table editor, it's RLS: go back to Step 2.

## Step 4: Let the agent model your tables

A **model** describes one table: its fields, their types, and its primary key. A **dataset**
groups models, says how they join, and holds your metrics. You don't need to learn AML to get
started.

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

If something's off, say so in plain words and let the agent fix it:

> **You:** `order_items.product_id` joins to `products.id`, not `products.sku`. And drop the
> `audit_log` table, we don't need it.

## Step 5: Tell the agent what your metrics mean

This is the step an agent can't do for you. It can see that `orders` has a `status` column. It
can't know whether your finance team counts refunded orders as revenue. So it proposes
definitions, points out what's ambiguous, and stops. Answer with the definitions your business
actually uses:

> **You:** Use these:
> - **Net revenue**: quantity × (unit price − discount), only for `completed` and `shipped` orders.
> - **AOV**: net revenue per completed or shipped order.
> - **Gross profit**: net revenue minus quantity × product unit cost, same statuses.
> - **Gross margin**: gross profit / net revenue.
> - **Return rate**: share of all orders, cancelled ones included, with status `returned`.
> - **Buyers**: distinct customers with at least one order.

The agent writes them as metrics in the dataset, each built on the ones before it:

```aml
  metric net_revenue {
    label: 'Net Revenue'
    type: 'number'
    description: 'Line amounts after discounts, completed and shipped orders only.'
    definition: @aql sum(order_items.net_amount) | where(orders.status in ['completed', 'shipped']) ;;
    format: '[$$]#,###0'
  }

  // cogs, gross_profit …

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

With metrics in place, the agent answers the question from your prompt. Say it was:

> Net revenue and gross margin by product category, highest revenue first.

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

From here on, just keep asking. Questions that cross several tables work the same way:

> **You:** Which acquisition channel brings the most buyers, and what's their AOV and return rate?

**Trust, but verify.** The prompt has the agent check its first answer against plain SQL. Keep
doing that for the first few questions:

> **You:** Check total net revenue with a plain SQL query straight against Supabase, without
> using the dataset. Do the numbers match?

If they don't match, the difference usually points at a wrong relationship or metric. Fix the
definition once, and every later answer is fixed too.

## Step 7: Build a dashboard

The agent writes `apps/sales_overview.html`, one self-contained HTML file whose queries are AQL
against your metrics. Open it:

```sh
anfra serve
# Data Apps  http://127.0.0.1:7878/apps/
```

The first version follows the short brief in the prompt. Then shape it in conversation, as
specifically as you like:

> **You:** Add a week / month / quarter switch to the trend, revenue by acquisition channel,
> and the top 10 products. Add a country filter, and make clicking a category bar filter the
> rest of the page.

The numbers on the page come from the same metric definitions as the answers
in Step 6, so the dashboard and the chat can't disagree.

## Step 8: Commit

The prompt ends with the agent committing the repo. Doing it yourself is just:

```sh
git add . && git commit -m "Semantic layer on our Supabase database"
```

Your models, metrics and dashboards are now plain files under review. `.anfra/data_sources.yml`
stays out of Git, and the committed `.anfra/data_sources.yml.example` tells a teammate what to
fill in. When someone changes what "net revenue" means, it shows up as a diff in a pull request
instead of someone quietly editing a query.

Teammates who code can clone the repo, add their own credentials, run `anfra agent setup`, and
their agents use the same definitions.

## Step 9: Publish to your team

Everyone else shouldn't need a terminal to see the dashboard. `anfra publish` uploads the repo to
an org on [anfra Cloud](https://anfra.ai/cloud/), which is free during its beta. Your team then
signs in and opens the Data Apps in the browser, and their agents can connect to the same metrics
through anfra Cloud's MCP server.

First see what would go up:

```sh
anfra publish --dry-run
```

It lists only your `.aml` files and everything under `apps/`. `.anfra/` stays local, `.env`
files and notes don't go, and `.gitignore` doesn't affect it. Then publish:

```sh
anfra publish
```

The first time, it opens your browser to sign in and choose or create an org. It saves the org's
address in `.anfra/config.yml`. Commit that file so everyone on the team publishes to the same
org.

Things to know:

- **The `supabase` data source is created in the org on the first publish**, from your
  `.anfra/data_sources.yml`, after you confirm. Its credentials are stored encrypted on anfra
  Cloud. This is the `anfra_reader` login from Step 2, so the hosted copy can't write either.
- **Queries still run on Supabase.** Results pass through anfra Cloud on the way to the page; no
  copy of your tables is kept.
- **A publish replaces what's there.** Files you deleted locally are deleted in the org too.
  Validation runs locally and again on the server, and nothing is published if either fails.
- **Each publish is kept as a version**, with who published it and when. The message defaults to
  your latest commit, or set one with `-m "…"`.

Then invite your team in anfra Cloud and give each person a role.

> Publish from `main` after the pull request is reviewed, and you get a simple release process:
> the metric definitions your team sees are always the reviewed ones.

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
anfra publish --dry-run                                                   # what would go to your org
```

AML and AQL are documented at [amql.org/docs](https://amql.org/docs). For a complete, working set
of models, metrics and a Data App, see the
[demo repo](https://github.com/holistics/anfra-supabase-demo).

## Troubleshooting

| Symptom | Fix |
|---|---|
| A table shows **0 rows** through anfra, but has data in Supabase | RLS: add a `for select to anfra_reader` policy on that table (Step 2). |
| `could not translate host name db.<ref>.supabase.co` | That host is IPv6-only. Use the Session pooler host. |
| `Tenant or user not found` | The pooler host doesn't match Connect (region, or `aws-0` vs `aws-1`), or the user is missing `.<project-ref>`. |
| `password authentication failed` right after changing the password | The pooler caches credentials for a short while. Wait a minute and retry. |
| `invalid config for dbtype` | `port` must be a number (`5432`), not `"5432"`. |
| `permission denied for table …` / `for schema …` | Add `grant usage on schema …` / `grant select on …` for `anfra_reader`. Tables in a newly created schema need the grants again. |
| `cannot execute … in a read-only transaction` | Working as intended: the role is read-only. |
| Everything stopped working after a quiet week | Free-tier Supabase projects pause after a week without activity. Restore the project from the Supabase dashboard. |
| Works locally, but published apps can't reach the database | If you turned on Supabase **Network Restrictions**, anfra Cloud's addresses must be allowed too. |
| The agent writes raw SQL instead of AQL | Check `anfra agent setup --check`, restart the agent, and name the dataset in your prompt. |

## Links

- Demo repo with sample data: https://github.com/holistics/anfra-supabase-demo
- anfra docs: https://anfra.ai/docs
- anfra Cloud: https://anfra.ai/cloud/
- AML & AQL docs: https://amql.org/docs
- Supabase connection docs: https://supabase.com/docs/guides/database/connecting-to-postgres
- Supabase Row Level Security: https://supabase.com/docs/guides/database/postgres/row-level-security
