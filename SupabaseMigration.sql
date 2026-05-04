-- INGRIA Supabase starter schema
-- Paste this into Supabase SQL Editor.
-- Uses anon-safe policies for the current prototype. Tighten admin/update policies before public launch.

create extension if not exists pgcrypto;

create table if not exists public.products (
    barcode text primary key,
    product_name text not null default '',
    brand text not null default '',
    brand_key text not null default '',
    category text not null default 'unknown',
    category_key text not null default '',
    image_url text,
    ingredients_image_url text,
    ingredients_text text not null default '',
    cleaned_ingredients_text text not null default '',
    result text not null default 'INGREDIENT_DATA_NEEDED'
        check (result in ('CLEAN', 'REVIEW', 'AVOID', 'INGREDIENT_DATA_NEEDED')),
    summary_line text not null default '',
    source text not null default 'INGRIA',
    source_status text not null default 'pendingReview',
    review_status text not null default 'pending',
    admin_review_status text not null default 'waiting',
    flagged_ingredients text[] not null default '{}',
    created_from_ios_scan boolean not null default false,
    approved_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.scan_logs (
    id uuid primary key default gen_random_uuid(),
    barcode text not null default '',
    product_name text not null default '',
    brand text not null default '',
    result text not null default 'INGREDIENT_DATA_NEEDED'
        check (result in ('CLEAN', 'REVIEW', 'AVOID', 'INGREDIENT_DATA_NEEDED')),
    review_status text not null default 'pending',
    source_status text not null default 'pendingReview',
    scan_source text not null default 'unknown',
    summary_line text not null default '',
    ingredient_count integer not null default 0,
    avoid_count integer not null default 0,
    review_count integer not null default 0,
    clean_count integer not null default 0,
    category text not null default 'unknown',
    created_at timestamptz not null default now()
);

create table if not exists public.missing_product_submissions (
    barcode text primary key,
    product_name text not null default '',
    brand text not null default '',
    category text not null default 'unknown',
    ingredients_text text not null default '',
    cleaned_ingredients_text text not null default '',
    result text not null default 'INGREDIENT_DATA_NEEDED'
        check (result in ('CLEAN', 'REVIEW', 'AVOID', 'INGREDIENT_DATA_NEEDED')),
    summary_line text not null default '',
    source_status text not null default 'userSubmitted',
    review_status text not null default 'missingIngredients',
    admin_review_status text not null default 'waiting',
    note text not null default '',
    flagged_ingredients text[] not null default '{}',
    front_image_url text,
    front_image_storage_path text,
    front_image_pending_upload boolean,
    front_image_content_type text,
    front_image_size_bytes integer,
    front_image_uploaded_at timestamptz,
    ingredients_image_url text,
    ingredients_image_storage_path text,
    ingredients_image_pending_upload boolean,
    ingredients_image_content_type text,
    ingredients_image_size_bytes integer,
    ingredients_image_uploaded_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.ingredient_rules (
    id uuid primary key default gen_random_uuid(),
    normalized_key text not null unique,
    display_name_de text not null default '',
    display_name_en text not null default '',
    aliases text[] not null default '{}',
    category text not null default 'food',
    result text not null default 'REVIEW'
        check (result in ('CLEAN', 'REVIEW', 'AVOID', 'INGREDIENT_DATA_NEEDED')),
    reason_de text not null default '',
    reason_en text not null default '',
    source text not null default 'INGRIA',
    review_status text not null default 'adminReviewed',
    updated_at timestamptz not null default now()
);

create table if not exists public.product_store_availability (
    id uuid primary key default gen_random_uuid(),
    barcode text not null references public.products(barcode) on delete cascade,
    store_name text not null,
    availability_status text not null default 'availability_not_confirmed',
    source_label text not null default 'INGRIA',
    is_online boolean not null default false,
    updated_at timestamptz not null default now()
);

create index if not exists products_brand_key_idx on public.products (brand_key);
create index if not exists products_category_key_idx on public.products (category_key);
create index if not exists products_result_idx on public.products (result);
create index if not exists products_review_status_idx on public.products (review_status);
create index if not exists scan_logs_barcode_idx on public.scan_logs (barcode);
create index if not exists missing_product_submissions_admin_status_idx on public.missing_product_submissions (admin_review_status);
create index if not exists ingredient_rules_result_idx on public.ingredient_rules (result);
create index if not exists product_store_availability_barcode_idx on public.product_store_availability (barcode);

alter table public.products enable row level security;
alter table public.scan_logs enable row level security;
alter table public.missing_product_submissions enable row level security;
alter table public.ingredient_rules enable row level security;
alter table public.product_store_availability enable row level security;

drop policy if exists "anon read reviewed products" on public.products;
create policy "anon read reviewed products"
on public.products for select
to anon
using (review_status in ('approved', 'adminReviewed') or admin_review_status = 'approved');

drop policy if exists "anon insert scan logs" on public.scan_logs;
create policy "anon insert scan logs"
on public.scan_logs for insert
to anon
with check (true);

drop policy if exists "anon upsert product drafts" on public.products;
create policy "anon upsert product drafts"
on public.products for insert
to anon
with check (true);

drop policy if exists "anon update product drafts" on public.products;
create policy "anon update product drafts"
on public.products for update
to anon
using (review_status not in ('approved', 'adminReviewed'))
with check (review_status not in ('approved', 'adminReviewed'));

drop policy if exists "anon submit missing products" on public.missing_product_submissions;
create policy "anon submit missing products"
on public.missing_product_submissions for insert
to anon
with check (true);

drop policy if exists "anon update own missing product barcode rows" on public.missing_product_submissions;
create policy "anon update own missing product barcode rows"
on public.missing_product_submissions for update
to anon
using (admin_review_status not in ('approved', 'rejected'))
with check (admin_review_status not in ('approved', 'rejected'));

drop policy if exists "anon read ingredient rules" on public.ingredient_rules;
create policy "anon read ingredient rules"
on public.ingredient_rules for select
to anon
using (true);

drop policy if exists "anon read store availability" on public.product_store_availability;
create policy "anon read store availability"
on public.product_store_availability for select
to anon
using (true);

insert into storage.buckets (id, name, public)
values ('product-submissions', 'product-submissions', true)
on conflict (id) do update set public = excluded.public;

drop policy if exists "anon upload product submission images" on storage.objects;
create policy "anon upload product submission images"
on storage.objects for insert
to anon
with check (bucket_id = 'product-submissions');

drop policy if exists "anon update product submission images" on storage.objects;
create policy "anon update product submission images"
on storage.objects for update
to anon
using (bucket_id = 'product-submissions')
with check (bucket_id = 'product-submissions');

drop policy if exists "public read product submission images" on storage.objects;
create policy "public read product submission images"
on storage.objects for select
to anon
using (bucket_id = 'product-submissions');
