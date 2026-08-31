-- ============================================================
-- AGRO KURS — схема базы данных для справочника сотрудников
-- Выполнить целиком в Supabase: Project -> SQL Editor -> New query -> Run
-- ============================================================

-- 1. Разделы справочника
create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

-- 2. Статьи справочника
create table if not exists public.articles (
  id uuid primary key default gen_random_uuid(),
  category_id uuid references public.categories(id) on delete set null,
  title text not null,
  content text not null,
  tags text[] not null default '{}',
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 3. Профили пользователей (роль: employee / admin)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role text not null default 'employee' check (role in ('employee', 'admin')),
  created_at timestamptz not null default now()
);

-- 4. Автосоздание профиля при регистрации нового пользователя
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', new.email), 'employee');
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 5. Включаем защиту на уровне строк (RLS) — это и есть "настоящая защита"
alter table public.categories enable row level security;
alter table public.articles enable row level security;
alter table public.profiles enable row level security;

-- Разделы: читать может любой вошедший сотрудник
drop policy if exists categories_select_auth on public.categories;
create policy categories_select_auth on public.categories
  for select using (auth.role() = 'authenticated');

-- Разделы: изменять может только admin
drop policy if exists categories_admin_write on public.categories;
create policy categories_admin_write on public.categories
  for all using (
    exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
  ) with check (
    exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
  );

-- Статьи: читать может любой вошедший сотрудник
drop policy if exists articles_select_auth on public.articles;
create policy articles_select_auth on public.articles
  for select using (auth.role() = 'authenticated');

-- Статьи: изменять может только admin
drop policy if exists articles_admin_write on public.articles;
create policy articles_admin_write on public.articles
  for all using (
    exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
  ) with check (
    exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
  );

-- Профили: пользователь видит свой профиль; admin видит все
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select using (
    auth.uid() = id
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  );

-- 6. Пример контента (шаблон, чтобы сайт не был пустым) — можно удалить из админки
insert into public.categories (name, sort_order) values
  ('Регламенты и правила', 1),
  ('Инструкции по технике', 2),
  ('Охрана труда', 3),
  ('Контакты и структура', 4)
on conflict do nothing;
