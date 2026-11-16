-- JewelMatch MVP core schema.
-- User-facing access is closed by default; feature-specific writes go through
-- narrow grants/RLS or trusted RPCs added with their implementation stages.

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create type public.app_role as enum ('customer', 'workshop', 'admin');

create table public.regions (
  id uuid primary key default gen_random_uuid(),
  country_code text not null check (country_code ~ '^[A-Z]{2}$'),
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name text not null check (length(btrim(name)) > 0),
  created_at timestamptz not null default now()
);

create table public.cities (
  id uuid primary key default gen_random_uuid(),
  region_id uuid not null references public.regions(id) on delete restrict,
  slug text not null check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name text not null check (length(btrim(name)) > 0),
  created_at timestamptz not null default now(),
  unique (region_id, slug),
  unique (id, region_id)
);

create table public.service_categories (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid references public.service_categories(id) on delete restrict,
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name text not null check (length(btrim(name)) > 0),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role public.app_role,
  display_name text check (display_name is null or length(btrim(display_name)) <= 160),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references public.profiles(user_id) on delete restrict,
  name text not null check (length(btrim(name)) between 1 and 160),
  city_id uuid not null references public.cities(id) on delete restrict,
  phone_public text not null check (length(btrim(phone_public)) between 3 and 80),
  email_public text check (email_public is null or length(btrim(email_public)) <= 254),
  telegram_public text check (telegram_public is null or length(btrim(telegram_public)) <= 160),
  website_public text check (website_public is null or length(btrim(website_public)) <= 500),
  description text check (description is null or length(description) <= 10000),
  accepts_remote boolean not null default false,
  suspended_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index organizations_owner_user_id_idx on public.organizations(owner_user_id);
create index organizations_city_id_idx on public.organizations(city_id);
create index organizations_active_city_idx on public.organizations(city_id)
  where suspended_at is null;

create table public.organization_services (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  service_category_id uuid not null references public.service_categories(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (organization_id, service_category_id)
);

create index organization_services_category_idx
  on public.organization_services(service_category_id, organization_id);

create table public.organization_service_areas (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  scope_type text not null check (scope_type in ('city', 'region')),
  city_id uuid references public.cities(id) on delete restrict,
  region_id uuid references public.regions(id) on delete restrict,
  created_at timestamptz not null default now(),
  check (
    (scope_type = 'city' and city_id is not null and region_id is null)
    or (scope_type = 'region' and region_id is not null and city_id is null)
  )
);

create unique index organization_service_areas_city_uq
  on public.organization_service_areas(organization_id, city_id)
  where scope_type = 'city';
create unique index organization_service_areas_region_uq
  on public.organization_service_areas(organization_id, region_id)
  where scope_type = 'region';

create table public.organization_portfolio (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  storage_path text not null unique check (length(btrim(storage_path)) > 0),
  caption text check (caption is null or length(caption) <= 500),
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create index organization_portfolio_org_idx
  on public.organization_portfolio(organization_id, sort_order, created_at);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  customer_user_id uuid not null references public.profiles(user_id) on delete restrict,
  source_order_id uuid references public.orders(id) on delete set null,
  category_id uuid not null references public.service_categories(id) on delete restrict,
  title text check (title is null or length(btrim(title)) between 1 and 180),
  description text not null check (length(btrim(description)) between 1 and 20000),
  geography_mode text not null check (geography_mode in ('city', 'region', 'remote')),
  city_id uuid references public.cities(id) on delete restrict,
  region_id uuid references public.regions(id) on delete restrict,
  desired_completion_date date,
  response_window_hours integer default 72,
  status text not null default 'draft'
    check (status in (
      'draft', 'pending_review', 'rejected', 'open', 'in_progress',
      'awaiting_customer_confirmation', 'completed', 'cancelled',
      'relevance_check', 'archived', 'closed_unconfirmed'
    )),
  published_at timestamptz,
  customer_last_activity_at timestamptz,
  relevance_requested_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (geography_mode = 'city' and city_id is not null and region_id is null)
    or (geography_mode = 'region' and region_id is not null and city_id is null)
    or (geography_mode = 'remote' and city_id is null and region_id is null)
  ),
  check (response_window_hours is null or response_window_hours in (24, 72, 168)),
  check (
    (status in ('open', 'in_progress', 'awaiting_customer_confirmation', 'completed')
      and published_at is not null)
    or status not in ('open', 'in_progress', 'awaiting_customer_confirmation', 'completed')
  )
);

create index orders_customer_created_idx
  on public.orders(customer_user_id, created_at desc);
create index orders_open_category_city_idx
  on public.orders(category_id, city_id, published_at desc)
  where status = 'open' and geography_mode = 'city';
create index orders_open_category_region_idx
  on public.orders(category_id, region_id, published_at desc)
  where status = 'open' and geography_mode = 'region';
create index orders_open_remote_idx
  on public.orders(category_id, published_at desc)
  where status = 'open' and geography_mode = 'remote';
create index orders_status_activity_idx
  on public.orders(status, customer_last_activity_at);

create table public.order_revisions (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  author_user_id uuid not null references public.profiles(user_id) on delete restrict,
  revision_no integer not null check (revision_no > 0),
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  moderation_status text not null default 'pending'
    check (moderation_status in ('pending', 'approved', 'rejected')),
  moderated_by uuid references public.profiles(user_id) on delete set null,
  moderated_at timestamptz,
  rejection_reason text check (rejection_reason is null or length(rejection_reason) <= 4000),
  created_at timestamptz not null default now(),
  unique (order_id, revision_no),
  unique (order_id, id),
  check (
    (moderation_status = 'pending' and moderated_by is null and moderated_at is null)
    or (moderation_status <> 'pending' and moderated_by is not null and moderated_at is not null)
  )
);

create index order_revisions_order_created_idx
  on public.order_revisions(order_id, revision_no desc);

create table public.order_attachments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  revision_id uuid,
  storage_path text not null unique check (length(btrim(storage_path)) > 0),
  original_filename text not null check (length(btrim(original_filename)) between 1 and 255),
  mime text not null check (length(btrim(mime)) between 1 and 160),
  size_bytes bigint not null check (size_bytes > 0),
  created_at timestamptz not null default now(),
  foreign key (order_id, revision_id)
    references public.order_revisions(order_id, id) on delete cascade
);

create index order_attachments_order_idx on public.order_attachments(order_id);

create table public.order_rounds (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  round_no integer not null check (round_no > 0),
  started_at timestamptz not null default now(),
  closed_at timestamptz,
  close_reason text check (close_reason is null or length(close_reason) <= 1000),
  unique (order_id, round_no),
  unique (id, order_id),
  check (closed_at is null or closed_at >= started_at)
);

create index order_rounds_order_idx on public.order_rounds(order_id, round_no desc);

create table public.order_invitations (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references public.order_rounds(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  assigned_at timestamptz not null default now(),
  notification_event_id uuid,
  unique (round_id, organization_id)
);

create index order_invitations_organization_idx
  on public.order_invitations(organization_id, assigned_at desc);

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  customer_user_id uuid not null references public.profiles(user_id) on delete restrict,
  status text not null default 'active'
    check (status in ('active', 'closed_selected', 'closed_cancelled', 'archived_round', 'archived_order')),
  created_at timestamptz not null default now(),
  foreign key (round_id) references public.order_rounds(id) on delete cascade,
  unique (round_id, organization_id)
);

create index conversations_customer_idx
  on public.conversations(customer_user_id, created_at desc);
create index conversations_organization_idx
  on public.conversations(organization_id, created_at desc);
create index conversations_round_idx on public.conversations(round_id);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_user_id uuid not null references public.profiles(user_id) on delete restrict,
  body text check (body is null or length(btrim(body)) <= 10000),
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (body is null or length(btrim(body)) > 0)
);

create index messages_conversation_created_idx
  on public.messages(conversation_id, created_at desc);

create table public.message_attachments (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  storage_path text not null unique check (length(btrim(storage_path)) > 0),
  filename text not null check (length(btrim(filename)) between 1 and 255),
  mime text not null check (length(btrim(mime)) between 1 and 160),
  size_bytes bigint not null check (size_bytes > 0),
  created_at timestamptz not null default now()
);

create index message_attachments_message_idx on public.message_attachments(message_id);

create table public.order_assignments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete restrict,
  round_id uuid not null,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  selected_at timestamptz not null default now(),
  cancelled_at timestamptz,
  cancellation_reason text check (cancellation_reason is null or length(cancellation_reason) <= 4000),
  workshop_completed_at timestamptz,
  customer_confirmed_at timestamptz,
  foreign key (round_id, order_id)
    references public.order_rounds(id, order_id) on delete restrict,
  unique (id, order_id, organization_id),
  check (cancelled_at is null or cancelled_at >= selected_at),
  check (workshop_completed_at is null or workshop_completed_at >= selected_at),
  check (customer_confirmed_at is null or workshop_completed_at is not null),
  check (
    (cancelled_at is null and cancellation_reason is null)
    or (cancelled_at is not null and cancellation_reason is not null)
  )
);

create unique index order_assignments_one_active_per_order_uq
  on public.order_assignments(order_id)
  where cancelled_at is null;
create index order_assignments_organization_idx
  on public.order_assignments(organization_id, selected_at desc);

create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id) on delete restrict,
  assignment_id uuid not null unique references public.order_assignments(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  customer_user_id uuid not null references public.profiles(user_id) on delete restrict,
  rating smallint not null check (rating between 1 and 5),
  body text check (body is null or length(body) <= 5000),
  created_at timestamptz not null default now(),
  foreign key (assignment_id, order_id, organization_id)
    references public.order_assignments(id, order_id, organization_id) on delete restrict
);

create index reviews_organization_created_idx
  on public.reviews(organization_id, created_at desc);

create table public.subscription_plans (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (length(btrim(name)) between 1 and 120),
  monthly_price numeric(12, 2) check (monthly_price is null or monthly_price > 0),
  currency text check (currency is null or currency ~ '^[A-Z]{3}$'),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.organization_entitlements (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  trial_started_at timestamptz,
  trial_ends_at timestamptz,
  trial_trigger_order_id uuid references public.orders(id) on delete set null,
  paid_until timestamptz,
  suspended_at timestamptz,
  updated_at timestamptz not null default now(),
  check (
    (trial_started_at is null and trial_ends_at is null and trial_trigger_order_id is null)
    or (trial_started_at is not null and trial_ends_at > trial_started_at and trial_trigger_order_id is not null)
  )
);

create table public.subscription_payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  amount numeric(12, 2) not null check (amount > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  period_start timestamptz not null,
  period_end timestamptz not null,
  approved_by uuid not null references public.profiles(user_id) on delete restrict,
  approved_at timestamptz not null default now(),
  reference text check (reference is null or length(reference) <= 1000),
  created_at timestamptz not null default now(),
  check (period_end > period_start)
);

create index subscription_payments_organization_idx
  on public.subscription_payments(organization_id, period_end desc);

create table public.telegram_accounts (
  user_id uuid primary key references public.profiles(user_id) on delete cascade,
  telegram_user_id text not null unique check (length(btrim(telegram_user_id)) > 0),
  chat_id text unique check (chat_id is null or length(btrim(chat_id)) > 0),
  bot_connected_at timestamptz,
  created_at timestamptz not null default now(),
  check ((chat_id is null and bot_connected_at is null) or (chat_id is not null and bot_connected_at is not null))
);

create table public.notification_preferences (
  user_id uuid primary key references public.profiles(user_id) on delete cascade,
  email_enabled boolean not null default true,
  telegram_enabled boolean not null default true,
  message_digest_mode text not null default 'immediate'
    check (message_digest_mode in ('immediate', 'hourly', 'daily')),
  updated_at timestamptz not null default now()
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  event_type text not null check (length(btrim(event_type)) between 1 and 120),
  entity_type text,
  entity_id uuid,
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload) = 'object'),
  dedupe_key text not null unique check (length(btrim(dedupe_key)) between 1 and 500),
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index notifications_user_created_idx
  on public.notifications(user_id, created_at desc);

create table public.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.notifications(id) on delete cascade,
  channel text not null check (channel in ('email', 'telegram')),
  attempts integer not null default 0 check (attempts >= 0),
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'delivered', 'failed')),
  last_error text check (last_error is null or length(last_error) <= 4000),
  delivered_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (notification_id, channel),
  check (
    (status = 'delivered' and delivered_at is not null)
    or (status <> 'delivered' and delivered_at is null)
  )
);

create index notification_deliveries_retry_idx
  on public.notification_deliveries(status, updated_at)
  where status in ('pending', 'failed');

create table public.admin_audit_log (
  id uuid primary key default gen_random_uuid(),
  admin_user_id uuid not null references public.profiles(user_id) on delete restrict,
  action text not null check (length(btrim(action)) between 1 and 120),
  entity_type text not null check (length(btrim(entity_type)) between 1 and 120),
  entity_id uuid,
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload) = 'object'),
  created_at timestamptz not null default now()
);

create index admin_audit_log_entity_idx
  on public.admin_audit_log(entity_type, entity_id, created_at desc);

create function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

create function private.create_profile_for_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (user_id, display_name)
  values (
    new.id,
    nullif(pg_catalog.btrim(new.raw_user_meta_data ->> 'name'), '')
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.create_profile_for_auth_user();

insert into public.profiles (user_id, display_name)
select
  u.id,
  nullif(pg_catalog.btrim(u.raw_user_meta_data ->> 'name'), '')
from auth.users as u
on conflict (user_id) do nothing;

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function private.set_updated_at();
create trigger organizations_set_updated_at
  before update on public.organizations
  for each row execute function private.set_updated_at();
create trigger orders_set_updated_at
  before update on public.orders
  for each row execute function private.set_updated_at();
create trigger entitlements_set_updated_at
  before update on public.organization_entitlements
  for each row execute function private.set_updated_at();
create trigger notification_preferences_set_updated_at
  before update on public.notification_preferences
  for each row execute function private.set_updated_at();
create trigger notification_deliveries_set_updated_at
  before update on public.notification_deliveries
  for each row execute function private.set_updated_at();

create function private.current_profile_role()
returns public.app_role
language sql
stable
security definer
set search_path = ''
as $$
  select p.role
  from public.profiles as p
  where p.user_id = (select auth.uid())
$$;

create function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles as p
    where p.user_id = (select auth.uid())
      and p.role = 'admin'::public.app_role
  )
$$;

create function private.owns_organization(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.organizations as o
    where o.id = p_organization_id
      and o.owner_user_id = (select auth.uid())
  )
$$;

create function private.workshop_can_read_order(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.orders as o
    join public.organizations as org
      on org.owner_user_id = (select auth.uid())
    join public.profiles as p
      on p.user_id = org.owner_user_id
    where o.id = p_order_id
      and p.role = 'workshop'::public.app_role
      and org.suspended_at is null
      and (
        exists (
          select 1
          from public.order_invitations as oi
          join public.order_rounds as r on r.id = oi.round_id
          where oi.organization_id = org.id and r.order_id = o.id
        )
        or exists (
          select 1
          from public.conversations as c
          join public.order_rounds as r on r.id = c.round_id
          where c.organization_id = org.id and r.order_id = o.id
        )
        or exists (
          select 1 from public.order_assignments as a
          where a.organization_id = org.id and a.order_id = o.id
        )
        or (
          o.status = 'open'
          and o.published_at is not null
          and length(btrim(org.name)) > 0
          and org.city_id is not null
          and length(btrim(org.phone_public)) > 0
          and exists (
            select 1
            from public.organization_services as os
            join public.service_categories as sc
              on sc.id = os.service_category_id and sc.is_active
            where os.organization_id = org.id and os.service_category_id = o.category_id
          )
          and not exists (
            select 1
            from public.organization_entitlements as e
            where e.organization_id = org.id
              and (
                e.suspended_at is not null
                or not (
                  e.trial_started_at is null
                  or e.trial_ends_at > pg_catalog.now()
                  or e.paid_until > pg_catalog.now()
                )
              )
          )
          and (
            (o.geography_mode = 'remote' and org.accepts_remote)
            or (
              o.geography_mode = 'city'
              and exists (
                select 1
                from public.cities as target_city
                join public.organization_service_areas as area
                  on area.organization_id = org.id
                where target_city.id = o.city_id
                  and (
                    (area.scope_type = 'city' and area.city_id = target_city.id)
                    or (area.scope_type = 'region' and area.region_id = target_city.region_id)
                  )
              )
            )
            or (
              o.geography_mode = 'region'
              and exists (
                select 1 from public.organization_service_areas as area
                where area.organization_id = org.id
                  and area.scope_type = 'region'
                  and area.region_id = o.region_id
              )
            )
          )
        )
      )
  )
$$;

create function private.can_read_order(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.orders as o
    where o.id = p_order_id
      and (
        o.customer_user_id = (select auth.uid())
        or private.is_admin()
        or private.workshop_can_read_order(o.id)
      )
  )
$$;

create function private.can_view_conversation(p_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.conversations as c
    where c.id = p_conversation_id
      and (
        c.customer_user_id = (select auth.uid())
        or exists (
          select 1 from public.organizations as o
          where o.id = c.organization_id and o.owner_user_id = (select auth.uid())
        )
      )
  )
$$;

create function private.can_start_conversation(p_round_id uuid, p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.order_rounds as r
    join public.orders as o on o.id = r.order_id
    join public.organizations as org on org.id = p_organization_id
    where r.id = p_round_id
      and r.closed_at is null
      and o.status = 'open'
      and r.round_no = (
        select pg_catalog.max(r2.round_no)
        from public.order_rounds as r2
        where r2.order_id = r.order_id
      )
      and org.owner_user_id = (select auth.uid())
      and private.workshop_can_read_order(o.id)
      and exists (
        select 1 from public.order_invitations as oi
        where oi.round_id = r.id and oi.organization_id = org.id
      )
      and not exists (
        select 1 from public.order_assignments as a
        where a.order_id = o.id
          and a.organization_id = org.id
          and a.cancelled_at is not null
      )
  )
$$;

create function private.can_send_message(p_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.conversations as c
    where c.id = p_conversation_id
      and c.status = 'active'
      and (
        c.customer_user_id = (select auth.uid())
        or exists (
          select 1
          from public.organizations as org
          join public.profiles as p on p.user_id = org.owner_user_id
          join public.organization_entitlements as e on e.organization_id = org.id
          where org.id = c.organization_id
            and org.owner_user_id = (select auth.uid())
            and p.role = 'workshop'::public.app_role
            and org.suspended_at is null
            and e.suspended_at is null
            and (e.trial_ends_at > pg_catalog.now() or e.paid_until > pg_catalog.now())
        )
      )
  )
$$;

create function public.choose_app_role(p_role public.app_role)
returns public.app_role
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role public.app_role;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_role not in ('customer'::public.app_role, 'workshop'::public.app_role) then
    raise exception 'Role is not selectable' using errcode = '22023';
  end if;

  update public.profiles as p
  set role = p_role
  where p.user_id = (select auth.uid())
    and p.role is null
  returning p.role into v_role;

  if v_role is not null then
    return v_role;
  end if;

  select p.role into v_role
  from public.profiles as p
  where p.user_id = (select auth.uid());

  if v_role is null then
    raise exception 'Profile does not exist' using errcode = 'P0002';
  end if;
  if v_role <> p_role then
    raise exception 'Role has already been selected' using errcode = '23514';
  end if;
  return v_role;
end;
$$;

revoke all on function private.set_updated_at() from public, anon, authenticated;
revoke all on function private.create_profile_for_auth_user() from public, anon, authenticated;
revoke all on function private.current_profile_role() from public, anon, authenticated;
revoke all on function private.is_admin() from public, anon, authenticated;
revoke all on function private.owns_organization(uuid) from public, anon, authenticated;
revoke all on function private.workshop_can_read_order(uuid) from public, anon, authenticated;
revoke all on function private.can_read_order(uuid) from public, anon, authenticated;
revoke all on function private.can_view_conversation(uuid) from public, anon, authenticated;
revoke all on function private.can_start_conversation(uuid, uuid) from public, anon, authenticated;
revoke all on function private.can_send_message(uuid) from public, anon, authenticated;
revoke all on function public.choose_app_role(public.app_role) from public, anon, authenticated;
grant execute on function private.current_profile_role() to authenticated;
grant execute on function private.is_admin() to authenticated;
grant execute on function private.owns_organization(uuid) to authenticated;
grant execute on function private.workshop_can_read_order(uuid) to authenticated;
grant execute on function private.can_read_order(uuid) to authenticated;
grant execute on function private.can_view_conversation(uuid) to authenticated;
grant execute on function private.can_start_conversation(uuid, uuid) to authenticated;
grant execute on function private.can_send_message(uuid) to authenticated;
grant execute on function public.choose_app_role(public.app_role) to authenticated;

alter table public.regions enable row level security;
alter table public.cities enable row level security;
alter table public.service_categories enable row level security;
alter table public.profiles enable row level security;
alter table public.organizations enable row level security;
alter table public.organization_services enable row level security;
alter table public.organization_service_areas enable row level security;
alter table public.organization_portfolio enable row level security;
alter table public.orders enable row level security;
alter table public.order_revisions enable row level security;
alter table public.order_attachments enable row level security;
alter table public.order_rounds enable row level security;
alter table public.order_invitations enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.message_attachments enable row level security;
alter table public.order_assignments enable row level security;
alter table public.reviews enable row level security;
alter table public.subscription_plans enable row level security;
alter table public.organization_entitlements enable row level security;
alter table public.subscription_payments enable row level security;
alter table public.telegram_accounts enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.notifications enable row level security;
alter table public.notification_deliveries enable row level security;
alter table public.admin_audit_log enable row level security;

revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
grant usage on schema public to anon, authenticated;
grant all on all tables in schema public to service_role;
grant all on all sequences in schema public to service_role;
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public
  grant all on tables to service_role;
alter default privileges for role postgres in schema public
  grant all on sequences to service_role;
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;
alter default privileges for role postgres in schema private
  revoke execute on functions from public, anon, authenticated;

create policy regions_read_all on public.regions
  for select to anon, authenticated using (true);
create policy cities_read_all on public.cities
  for select to anon, authenticated using (true);
create policy service_categories_read_active on public.service_categories
  for select to anon using (is_active);
create policy service_categories_read_active_or_admin on public.service_categories
  for select to authenticated using (is_active or (select private.is_admin()));
grant select on public.regions, public.cities, public.service_categories to anon, authenticated;
grant insert, update, delete on public.regions, public.cities, public.service_categories to authenticated;
create policy regions_admin_insert on public.regions
  for insert to authenticated with check ((select private.is_admin()));
create policy regions_admin_update on public.regions
  for update to authenticated using ((select private.is_admin()))
  with check ((select private.is_admin()));
create policy regions_admin_delete on public.regions
  for delete to authenticated using ((select private.is_admin()));
create policy cities_admin_insert on public.cities
  for insert to authenticated with check ((select private.is_admin()));
create policy cities_admin_update on public.cities
  for update to authenticated using ((select private.is_admin()))
  with check ((select private.is_admin()));
create policy cities_admin_delete on public.cities
  for delete to authenticated using ((select private.is_admin()));
create policy service_categories_admin_insert on public.service_categories
  for insert to authenticated with check ((select private.is_admin()));
create policy service_categories_admin_update on public.service_categories
  for update to authenticated using ((select private.is_admin()))
  with check ((select private.is_admin()));
create policy service_categories_admin_delete on public.service_categories
  for delete to authenticated using ((select private.is_admin()));

create policy profiles_read_self_or_admin on public.profiles
  for select to authenticated
  using (user_id = (select auth.uid()) or (select private.is_admin()));
create policy profiles_update_self on public.profiles
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
grant select on public.profiles to authenticated;
grant update (display_name) on public.profiles to authenticated;

create policy organizations_read_owner_or_admin on public.organizations
  for select to authenticated
  using (owner_user_id = (select auth.uid()) or (select private.is_admin()));
create policy organizations_insert_workshop_owner on public.organizations
  for insert to authenticated
  with check (
    owner_user_id = (select auth.uid())
    and (select private.current_profile_role()) = 'workshop'::public.app_role
  );
create policy organizations_update_owner on public.organizations
  for update to authenticated
  using (
    owner_user_id = (select auth.uid())
    and (select private.current_profile_role()) = 'workshop'::public.app_role
  )
  with check (
    owner_user_id = (select auth.uid())
    and (select private.current_profile_role()) = 'workshop'::public.app_role
  );
grant select on public.organizations to authenticated;
grant insert (
  owner_user_id, name, city_id, phone_public, email_public, telegram_public,
  website_public, description, accepts_remote
) on public.organizations to authenticated;
grant update (
  name, city_id, phone_public, email_public, telegram_public,
  website_public, description, accepts_remote
) on public.organizations to authenticated;

create policy organization_services_owner_select on public.organization_services
  for select to authenticated
  using ((select private.owns_organization(organization_id)));
create policy organization_services_owner_insert on public.organization_services
  for insert to authenticated
  with check (
    (select private.owns_organization(organization_id))
    and (select private.current_profile_role()) = 'workshop'::public.app_role
    and exists (
      select 1 from public.service_categories as category
      where category.id = service_category_id and category.is_active
    )
  );
create policy organization_services_owner_update on public.organization_services
  for update to authenticated
  using ((select private.owns_organization(organization_id)))
  with check (
    (select private.owns_organization(organization_id))
    and (select private.current_profile_role()) = 'workshop'::public.app_role
    and exists (
      select 1 from public.service_categories as category
      where category.id = service_category_id and category.is_active
    )
  );
create policy organization_services_owner_delete on public.organization_services
  for delete to authenticated
  using (
    (select private.owns_organization(organization_id))
    and (select private.current_profile_role()) = 'workshop'::public.app_role
  );
grant select, insert, update, delete on public.organization_services to authenticated;

create policy organization_service_areas_owner_select on public.organization_service_areas
  for select to authenticated
  using ((select private.owns_organization(organization_id)));
create policy organization_service_areas_owner_insert on public.organization_service_areas
  for insert to authenticated
  with check (
    (select private.owns_organization(organization_id))
    and (select private.current_profile_role()) = 'workshop'::public.app_role
  );
create policy organization_service_areas_owner_update on public.organization_service_areas
  for update to authenticated
  using ((select private.owns_organization(organization_id)))
  with check (
    (select private.owns_organization(organization_id))
    and (select private.current_profile_role()) = 'workshop'::public.app_role
  );
create policy organization_service_areas_owner_delete on public.organization_service_areas
  for delete to authenticated
  using (
    (select private.owns_organization(organization_id))
    and (select private.current_profile_role()) = 'workshop'::public.app_role
  );
grant select, insert, update, delete on public.organization_service_areas to authenticated;

create policy organization_portfolio_owner_select on public.organization_portfolio
  for select to authenticated
  using ((select private.owns_organization(organization_id)));
create policy organization_portfolio_owner_insert on public.organization_portfolio
  for insert to authenticated
  with check (
    (select private.owns_organization(organization_id))
    and (select private.current_profile_role()) = 'workshop'::public.app_role
  );
create policy organization_portfolio_owner_update on public.organization_portfolio
  for update to authenticated
  using ((select private.owns_organization(organization_id)))
  with check (
    (select private.owns_organization(organization_id))
    and (select private.current_profile_role()) = 'workshop'::public.app_role
  );
create policy organization_portfolio_owner_delete on public.organization_portfolio
  for delete to authenticated
  using (
    (select private.owns_organization(organization_id))
    and (select private.current_profile_role()) = 'workshop'::public.app_role
  );
grant select, insert, update, delete on public.organization_portfolio to authenticated;

create policy orders_read_participant on public.orders
  for select to authenticated
  using ((select private.can_read_order(id)));
create policy orders_insert_customer_draft on public.orders
  for insert to authenticated
  with check (
    customer_user_id = (select auth.uid())
    and (select private.current_profile_role()) = 'customer'::public.app_role
    and status = 'draft'
    and exists (
      select 1 from public.service_categories as category
      where category.id = category_id and category.is_active
    )
  );
create policy orders_update_own_draft on public.orders
  for update to authenticated
  using (
    customer_user_id = (select auth.uid())
    and status in ('draft', 'rejected')
  )
  with check (
    customer_user_id = (select auth.uid())
    and status in ('draft', 'rejected')
    and exists (
      select 1 from public.service_categories as category
      where category.id = category_id and category.is_active
    )
  );
grant select on public.orders to authenticated;
grant insert (
  customer_user_id, source_order_id, category_id, title, description,
  geography_mode, city_id, region_id, desired_completion_date, response_window_hours
) on public.orders to authenticated;
grant update (
  source_order_id, category_id, title, description, geography_mode, city_id,
  region_id, desired_completion_date, response_window_hours
) on public.orders to authenticated;

create policy order_revisions_read_authorized on public.order_revisions
  for select to authenticated
  using (
    author_user_id = (select auth.uid())
    or (select private.is_admin())
    or (
      moderation_status = 'approved'
      and (select private.can_read_order(order_id))
    )
  );
create policy order_revisions_insert_draft_owner on public.order_revisions
  for insert to authenticated
  with check (
    author_user_id = (select auth.uid())
    and moderation_status = 'pending'
    and exists (
      select 1 from public.orders as o
      where o.id = order_id
        and o.customer_user_id = (select auth.uid())
        and o.status in ('draft', 'rejected')
    )
  );
grant select, insert on public.order_revisions to authenticated;

create policy order_attachments_read_authorized on public.order_attachments
  for select to authenticated
  using ((select private.can_read_order(order_id)));
create policy order_attachments_insert_owner_draft on public.order_attachments
  for insert to authenticated
  with check (
    exists (
      select 1 from public.orders as o
      where o.id = order_id
        and o.customer_user_id = (select auth.uid())
        and o.status in ('draft', 'rejected')
    )
  );
grant select, insert on public.order_attachments to authenticated;

create policy order_rounds_read_participant on public.order_rounds
  for select to authenticated
  using ((select private.can_read_order(order_id)));
grant select on public.order_rounds to authenticated;

create policy order_invitations_read_participant on public.order_invitations
  for select to authenticated
  using (
    (select private.owns_organization(organization_id))
    or exists (
      select 1
      from public.order_rounds as r
      join public.orders as o on o.id = r.order_id
      where r.id = round_id and o.customer_user_id = (select auth.uid())
    )
  );
grant select on public.order_invitations to authenticated;

create policy conversations_read_participants on public.conversations
  for select to authenticated
  using ((select private.can_view_conversation(id)));
create policy conversations_insert_eligible_workshop on public.conversations
  for insert to authenticated
  with check (
    customer_user_id = (
      select o.customer_user_id
      from public.order_rounds as r
      join public.orders as o on o.id = r.order_id
      where r.id = round_id
    )
    and status = 'active'
    and (select private.can_start_conversation(round_id, organization_id))
  );
grant select, insert on public.conversations to authenticated;

create policy messages_read_participants on public.messages
  for select to authenticated
  using ((select private.can_view_conversation(conversation_id)));
create policy messages_insert_participants on public.messages
  for insert to authenticated
  with check (
    sender_user_id = (select auth.uid())
    and (select private.can_send_message(conversation_id))
  );
grant select, insert on public.messages to authenticated;

create policy message_attachments_read_participants on public.message_attachments
  for select to authenticated
  using (
    exists (
      select 1 from public.messages as m
      where m.id = message_id
        and (select private.can_view_conversation(m.conversation_id))
    )
  );
create policy message_attachments_insert_active_participant on public.message_attachments
  for insert to authenticated
  with check (
    exists (
      select 1 from public.messages as m
      where m.id = message_id
        and m.sender_user_id = (select auth.uid())
        and (select private.can_send_message(m.conversation_id))
    )
  );
grant select, insert on public.message_attachments to authenticated;

create policy order_assignments_read_participants on public.order_assignments
  for select to authenticated
  using (
    exists (
      select 1 from public.orders as o
      where o.id = order_id and o.customer_user_id = (select auth.uid())
    )
    or (select private.owns_organization(organization_id))
  );
grant select on public.order_assignments to authenticated;

create policy reviews_read_parties on public.reviews
  for select to authenticated
  using (
    customer_user_id = (select auth.uid())
    or (select private.owns_organization(organization_id))
    or (select private.is_admin())
  );
create policy reviews_insert_completed_customer on public.reviews
  for insert to authenticated
  with check (
    customer_user_id = (select auth.uid())
    and exists (
      select 1
      from public.orders as o
      join public.order_assignments as a on a.order_id = o.id
      where o.id = reviews.order_id
        and o.customer_user_id = (select auth.uid())
        and o.status = 'completed'
        and a.id = reviews.assignment_id
        and a.organization_id = reviews.organization_id
        and a.cancelled_at is null
        and a.workshop_completed_at is not null
        and a.customer_confirmed_at is not null
    )
  );
grant select, insert on public.reviews to authenticated;

create policy subscription_plans_read_active on public.subscription_plans
  for select to anon, authenticated using (active);
grant select on public.subscription_plans to anon, authenticated;

create policy organization_entitlements_read_owner on public.organization_entitlements
  for select to authenticated
  using ((select private.owns_organization(organization_id)) or (select private.is_admin()));
grant select on public.organization_entitlements to authenticated;

create policy subscription_payments_read_owner on public.subscription_payments
  for select to authenticated
  using ((select private.owns_organization(organization_id)) or (select private.is_admin()));
grant select on public.subscription_payments to authenticated;

create policy telegram_accounts_read_self on public.telegram_accounts
  for select to authenticated using (user_id = (select auth.uid()));
grant select on public.telegram_accounts to authenticated;

create policy notification_preferences_read_self on public.notification_preferences
  for select to authenticated using (user_id = (select auth.uid()));
create policy notification_preferences_insert_self on public.notification_preferences
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy notification_preferences_update_self on public.notification_preferences
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
grant select, insert, update on public.notification_preferences to authenticated;

create policy notifications_read_self on public.notifications
  for select to authenticated using (user_id = (select auth.uid()));
create policy notifications_mark_read_self on public.notifications
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
grant select on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;

create view public.public_workshop_directory
with (security_invoker = false)
as
select
  org.id,
  org.name,
  city.name as city_name,
  region.name as region_name,
  org.phone_public,
  org.email_public,
  org.telegram_public,
  org.website_public,
  org.description,
  org.accepts_remote,
  coalesce(
    (
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object('slug', category.slug, 'name', category.name)
        order by category.sort_order, category.name
      )
      from public.organization_services as os
      join public.service_categories as category
        on category.id = os.service_category_id and category.is_active
      where os.organization_id = org.id
    ),
    '[]'::jsonb
  ) as services,
  org.created_at
from public.organizations as org
join public.cities as city on city.id = org.city_id
join public.regions as region on region.id = city.region_id
where org.suspended_at is null
  and length(btrim(org.name)) > 0
  and length(btrim(org.phone_public)) > 0
  and exists (
    select 1 from public.organization_services as os
    join public.service_categories as category
      on category.id = os.service_category_id and category.is_active
    where os.organization_id = org.id
  );

grant select on public.public_workshop_directory to anon, authenticated;

create view public.public_workshop_reviews
with (security_invoker = false)
as
select
  id,
  order_id,
  organization_id,
  rating,
  body,
  created_at
from public.reviews;

grant select on public.public_workshop_reviews to anon, authenticated;

insert into public.regions (country_code, slug, name)
values ('MD', 'transnistria', 'Приднестровье')
on conflict (slug) do update
set country_code = excluded.country_code, name = excluded.name;

insert into public.cities (region_id, slug, name)
select r.id, seed.slug, seed.name
from public.regions as r
cross join (
  values
    ('tiraspol', 'Тирасполь'),
    ('bender', 'Бендеры'),
    ('rybnita', 'Рыбница'),
    ('dubasari', 'Дубоссары'),
    ('grigoriopol', 'Григориополь'),
    ('slobozia', 'Слободзея'),
    ('camenca', 'Каменка'),
    ('dnestrovsk', 'Днестровск')
) as seed(slug, name)
where r.slug = 'transnistria'
on conflict (region_id, slug) do update set name = excluded.name;

insert into public.service_categories (slug, name, sort_order)
values
  ('manufacturing', 'Изготовление украшений', 10),
  ('repair', 'Ремонт украшений', 20),
  ('engraving', 'Гравировка', 30),
  ('3d-modeling', '3D-моделирование', 40),
  ('casting', 'Литьё', 50),
  ('stone-setting', 'Закрепка камней', 60),
  ('plating-polishing', 'Покрытия и полировка', 70),
  ('other-jewelry-services', 'Другие ювелирные услуги', 80)
on conflict (slug) do update
set name = excluded.name, sort_order = excluded.sort_order;

insert into public.subscription_plans (name, monthly_price, currency, active)
values ('Единый тариф', null, null, true)
on conflict (name) do nothing;

comment on view public.public_workshop_directory is
  'Intentionally owner-executed safe public projection; only public workshop profile fields are selected.';
comment on view public.public_workshop_reviews is
  'Public review projection; excludes customer_user_id and assignment_id.';
comment on function public.choose_app_role(public.app_role) is
  'A user may choose customer or workshop once; admin is assigned only through a trusted operation.';
