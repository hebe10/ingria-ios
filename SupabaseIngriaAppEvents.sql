-- INGRIA iOS app event tables
-- Run in Supabase SQL Editor for project zzneaciygbazcybbsxdy.

create extension if not exists pgcrypto;

create table if not exists public.scan_history (
    id uuid primary key default gen_random_uuid(),
    barcode text not null default '',
    product_name text not null default '',
    brand text not null default '',
    verdict text not null default 'Review'
        check (verdict in ('Clean', 'Review', 'Avoid')),
    score integer
        check (score is null or (score >= 0 and score <= 100)),
    total_ingredients integer not null default 0,
    recognized_ingredients integer not null default 0,
    unknown_ingredients integer not null default 0,
    coverage_ratio double precision not null default 0,
    unknown_ingredient_list text[] not null default '{}',
    raw_ingredients text not null default '',
    source text not null default 'ios_app',
    created_at timestamptz not null default now()
);

create table if not exists public.saved_products (
    id uuid primary key default gen_random_uuid(),
    barcode text not null default '',
    product_name text not null default '',
    brand text not null default '',
    verdict text not null default 'Review'
        check (verdict in ('Clean', 'Review', 'Avoid')),
    score integer
        check (score is null or (score >= 0 and score <= 100)),
    raw_ingredients text not null default '',
    source text not null default 'ios_app',
    created_at timestamptz not null default now()
);

create table if not exists public.ingredient_corrections (
    id uuid primary key default gen_random_uuid(),
    barcode text not null default '',
    product_name text not null default '',
    brand text not null default '',
    raw_ingredients text not null default '',
    unknown_ingredient_list text[] not null default '{}',
    issue_type text not null default 'ingredient_issue',
    note text not null default '',
    source text not null default 'ios_app',
    created_at timestamptz not null default now()
);

create index if not exists scan_history_created_at_idx on public.scan_history (created_at desc);
create index if not exists scan_history_barcode_idx on public.scan_history (barcode);
create index if not exists saved_products_created_at_idx on public.saved_products (created_at desc);
create index if not exists saved_products_barcode_idx on public.saved_products (barcode);
create index if not exists ingredient_corrections_created_at_idx on public.ingredient_corrections (created_at desc);
create index if not exists ingredient_corrections_barcode_idx on public.ingredient_corrections (barcode);

alter table public.scan_history enable row level security;
alter table public.saved_products enable row level security;
alter table public.ingredient_corrections enable row level security;

drop policy if exists "anon insert scan history" on public.scan_history;
create policy "anon insert scan history"
on public.scan_history for insert
to anon
with check (source = 'ios_app');

drop policy if exists "anon insert saved products" on public.saved_products;
create policy "anon insert saved products"
on public.saved_products for insert
to anon
with check (source = 'ios_app');

drop policy if exists "anon insert ingredient corrections" on public.ingredient_corrections;
create policy "anon insert ingredient corrections"
on public.ingredient_corrections for insert
to anon
with check (source = 'ios_app');

-- Prototype verification policy. Remove these public read policies before storing private user data.
drop policy if exists "anon read scan history" on public.scan_history;
create policy "anon read scan history"
on public.scan_history for select
to anon
using (true);

drop policy if exists "anon read saved products" on public.saved_products;
create policy "anon read saved products"
on public.saved_products for select
to anon
using (true);

drop policy if exists "anon read ingredient corrections" on public.ingredient_corrections;
create policy "anon read ingredient corrections"
on public.ingredient_corrections for select
to anon
using (true);

notify pgrst, 'reload schema';
