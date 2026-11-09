-- =============================================================================
-- Anfra x Supabase demo: e-commerce sample data
--
-- Creates an `ecommerce` schema with four tables and fills them with
-- deterministic, realistic-looking data (same rows every run).
--
--   customers    ~2,000 rows
--   products        60 rows
--   orders       ~9,400 rows   (Jan 2025 -> Oct 2026)
--   order_items ~22,000 rows
--
-- Run it in the Supabase SQL Editor, or with psql:
--   psql "$SUPABASE_DB_URL" -f supabase/seed.sql
--
-- Safe to re-run: it drops and recreates the schema.
-- =============================================================================

drop schema if exists ecommerce cascade;
create schema ecommerce;

-- Deterministic randomness
select setseed(0.42);

-- -----------------------------------------------------------------------------
-- products
-- -----------------------------------------------------------------------------
create table ecommerce.products (
  id          integer primary key,
  name        text    not null,
  category    text    not null,
  unit_price  numeric(10,2) not null,
  unit_cost   numeric(10,2) not null,
  created_at  timestamptz not null
);

insert into ecommerce.products (id, name, category, unit_price, unit_cost, created_at)
select
  p.id,
  p.name,
  p.category,
  p.price,
  round(p.price * (0.35 + random() * 0.25)::numeric, 2),
  timestamptz '2024-06-01' + (random() * 200) * interval '1 day'
from (
  values
    ( 1,'Trail Runner Shoes','Footwear',129.00), ( 2,'City Sneakers','Footwear',89.00),
    ( 3,'Leather Boots','Footwear',179.00),      ( 4,'Canvas Slip-ons','Footwear',59.00),
    ( 5,'Hiking Sandals','Footwear',69.00),      ( 6,'Running Socks 3-pack','Footwear',19.00),
    ( 7,'Merino Crew Tee','Apparel',45.00),      ( 8,'Organic Hoodie','Apparel',79.00),
    ( 9,'Rain Shell Jacket','Apparel',149.00),   (10,'Stretch Chinos','Apparel',69.00),
    (11,'Fleece Pullover','Apparel',89.00),      (12,'Linen Shirt','Apparel',59.00),
    (13,'Down Puffer Vest','Apparel',119.00),    (14,'Performance Shorts','Apparel',39.00),
    (15,'Wool Beanie','Accessories',25.00),      (16,'Leather Belt','Accessories',49.00),
    (17,'Canvas Tote','Accessories',29.00),      (18,'Polarized Sunglasses','Accessories',99.00),
    (19,'Everyday Backpack','Accessories',109.00),(20,'Travel Duffel','Accessories',139.00),
    (21,'Insulated Bottle','Accessories',32.00), (22,'Crossbody Bag','Accessories',59.00),
    (23,'Wireless Earbuds','Electronics',129.00),(24,'Smart Watch','Electronics',249.00),
    (25,'Bluetooth Speaker','Electronics',89.00),(26,'Power Bank 20k','Electronics',49.00),
    (27,'Noise-Cancel Headphones','Electronics',299.00),(28,'Action Camera','Electronics',349.00),
    (29,'Fitness Tracker','Electronics',99.00),  (30,'USB-C Charger','Electronics',35.00),
    (31,'Camping Tent 2P','Outdoor',229.00),     (32,'Sleeping Bag','Outdoor',149.00),
    (33,'Trekking Poles','Outdoor',79.00),       (34,'Headlamp','Outdoor',39.00),
    (35,'Camp Stove','Outdoor',89.00),           (36,'Hammock','Outdoor',59.00),
    (37,'Cooler Box','Outdoor',129.00),          (38,'Folding Chair','Outdoor',49.00),
    (39,'Yoga Mat','Fitness',45.00),             (40,'Adjustable Dumbbells','Fitness',299.00),
    (41,'Resistance Bands','Fitness',25.00),     (42,'Foam Roller','Fitness',29.00),
    (43,'Jump Rope','Fitness',15.00),            (44,'Kettlebell 12kg','Fitness',59.00),
    (45,'Gym Bag','Fitness',55.00),              (46,'Protein Shaker','Fitness',12.00),
    (47,'Ceramic Mug Set','Home',35.00),         (48,'Pour-over Coffee Kit','Home',65.00),
    (49,'Scented Candle','Home',24.00),          (50,'Throw Blanket','Home',79.00),
    (51,'Desk Lamp','Home',69.00),               (52,'Plant Pot Trio','Home',39.00),
    (53,'Linen Napkins','Home',29.00),           (54,'Cast Iron Skillet','Home',55.00),
    (55,'Notebook Set','Stationery',18.00),      (56,'Fountain Pen','Stationery',79.00),
    (57,'Desk Organizer','Stationery',34.00),    (58,'Weekly Planner','Stationery',22.00),
    (59,'Sticky Notes Pack','Stationery',9.00),  (60,'Sketchbook','Stationery',16.00)
) as p(id, name, category, price);

-- -----------------------------------------------------------------------------
-- customers
-- -----------------------------------------------------------------------------
create table ecommerce.customers (
  id              integer primary key,
  full_name       text not null,
  email           text not null unique,
  country         text not null,
  city            text not null,
  acquisition_channel text not null,
  created_at      timestamptz not null
);

with
first_names as (
  select array['Olivia','Liam','Emma','Noah','Ava','Lucas','Mia','Ethan','Sofia','Mason',
               'Linh','Minh','Hana','Kenji','Priya','Arjun','Chloe','Leo','Zoe','Mateo',
               'Isla','Hugo','Nora','Felix','Aria','Kai','Lena','Omar','Yuki','Ana'] as a
),
last_names as (
  select array['Nguyen','Smith','Tran','Garcia','Kim','Müller','Rossi','Silva','Tanaka','Patel',
               'Johnson','Le','Brown','Lopez','Wang','Dubois','Novak','Andersen','Costa','Lee'] as a
),
geo as (
  -- country, city, weight
  select * from (values
    ('United States','New York',14),('United States','San Francisco',9),('United States','Austin',6),
    ('United Kingdom','London',9),('United Kingdom','Manchester',3),
    ('Germany','Berlin',6),('Germany','Munich',3),
    ('France','Paris',6),
    ('Vietnam','Ho Chi Minh City',7),('Vietnam','Hanoi',5),
    ('Singapore','Singapore',6),
    ('Japan','Tokyo',6),
    ('Australia','Sydney',5),('Australia','Melbourne',3),
    ('Canada','Toronto',5),
    ('Brazil','São Paulo',4),
    ('India','Bangalore',3)
  ) as g(country, city, w)
),
geo_cum as (
  select country, city,
         sum(w) over (order by country, city) - w as lo,
         sum(w) over (order by country, city)     as hi,
         sum(w) over ()                           as total
  from geo
),
base as (
  select
    gs as id,
    random() as r_geo,
    random() as r_chan,
    random() as r_date,
    (floor(random() * 30) + 1)::int as fi,
    (floor(random() * 20) + 1)::int as li
  from generate_series(1, 2000) gs
)
insert into ecommerce.customers (id, full_name, email, country, city, acquisition_channel, created_at)
select
  b.id,
  f.a[b.fi] || ' ' || l.a[b.li],
  lower(f.a[b.fi]) || '.' || lower(replace(l.a[b.li], 'ü', 'u')) || b.id || '@example.com',
  g.country,
  g.city,
  case
    when b.r_chan < 0.32 then 'Organic Search'
    when b.r_chan < 0.55 then 'Paid Social'
    when b.r_chan < 0.72 then 'Referral'
    when b.r_chan < 0.86 then 'Email'
    else 'Direct'
  end,
  -- signups ramp up over time (the power skews toward later dates)
  timestamptz '2025-01-01' + (power(b.r_date, 0.7) * 660) * interval '1 day'
from base b
cross join first_names f
cross join last_names l
join geo_cum g on b.r_geo * g.total >= g.lo and b.r_geo * g.total < g.hi;

-- -----------------------------------------------------------------------------
-- orders
-- -----------------------------------------------------------------------------
create table ecommerce.orders (
  id           integer primary key,
  customer_id  integer not null references ecommerce.customers(id),
  status       text not null,
  channel      text not null,
  created_at   timestamptz not null
);

with
cust as (
  -- each customer places 0..21 orders, skewed so most place few
  select id, created_at,
         floor(power(random(), 2.0) * 22)::int as n_orders
  from ecommerce.customers
),
exploded as (
  select c.id as customer_id, c.created_at as signup_at, gs as nth,
         random() as r_gap, random() as r_status, random() as r_channel
  from cust c
  cross join lateral generate_series(1, c.n_orders) gs
),
dated as (
  select *,
         -- first order soon after signup, later ones spread out
         signup_at + (case when nth = 1 then random() * 7 else random() * 400 end) * interval '1 day'
           + (random() * 24) * interval '1 hour' as created_at
  from exploded
)
insert into ecommerce.orders (id, customer_id, status, channel, created_at)
select
  row_number() over (order by created_at, customer_id, nth),
  customer_id,
  case
    when r_status < 0.86 then 'completed'
    when r_status < 0.93 then 'shipped'
    when r_status < 0.97 then 'returned'
    else 'cancelled'
  end,
  case when r_channel < 0.62 then 'web' when r_channel < 0.92 then 'mobile_app' else 'marketplace' end,
  created_at
from dated
where created_at < timestamptz '2026-11-01';

-- -----------------------------------------------------------------------------
-- order_items
-- -----------------------------------------------------------------------------
create table ecommerce.order_items (
  id          integer primary key,
  order_id    integer not null references ecommerce.orders(id),
  product_id  integer not null references ecommerce.products(id),
  quantity    integer not null,
  unit_price  numeric(10,2) not null,
  discount    numeric(10,2) not null default 0
);

with lines as (
  select o.id as order_id, o.created_at, gs as line_no,
         -- popular products appear more often (power skew on product id)
         (floor(power(random(), 1.6) * 60) + 1)::int as product_id,
         random() as r_qty, random() as r_disc
  from ecommerce.orders o
  -- 1..5 lines per order. `o.id * 0` ties random() to each order row; without it
  -- Postgres evaluates the lateral call once and every order gets the same count.
  cross join lateral generate_series(1, 1 + floor(power(random() + o.id * 0, 1.8) * 5)::int) gs
)
insert into ecommerce.order_items (id, order_id, product_id, quantity, unit_price, discount)
select
  row_number() over (order by l.order_id, l.line_no),
  l.order_id,
  l.product_id,
  case when l.r_qty < 0.78 then 1 when l.r_qty < 0.94 then 2 else 3 end,
  p.unit_price,
  -- November/December promos get bigger discounts
  case
    when extract(month from l.created_at) in (11, 12) and l.r_disc < 0.55 then round(p.unit_price * 0.20, 2)
    when l.r_disc < 0.15 then round(p.unit_price * 0.10, 2)
    else 0
  end
from lines l
join ecommerce.products p on p.id = l.product_id;

create index on ecommerce.orders (customer_id);
create index on ecommerce.orders (created_at);
create index on ecommerce.order_items (order_id);
create index on ecommerce.order_items (product_id);

-- Note: the `ecommerce` schema is not in Supabase's "Exposed schemas" list, so
-- these tables are NOT reachable through the auto-generated REST/GraphQL API,
-- and the anon/authenticated roles have no privileges on it.

-- Re-running this file drops the schema and its grants: restore them for
-- Anfra's read-only role if it already exists (see anfra_reader.sql).
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anfra_reader') then
    grant usage  on schema ecommerce to anfra_reader;
    grant select on all tables in schema ecommerce to anfra_reader;
  end if;
end
$$;

analyze ecommerce.customers, ecommerce.products, ecommerce.orders, ecommerce.order_items;

select 'customers'   as table_name, count(*) from ecommerce.customers
union all select 'products',    count(*) from ecommerce.products
union all select 'orders',      count(*) from ecommerce.orders
union all select 'order_items', count(*) from ecommerce.order_items;
