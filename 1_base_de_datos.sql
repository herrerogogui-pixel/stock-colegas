-- =====================================================================
--  STOCK COLEGAS - Base de datos para Supabase
--  Pegá TODO este archivo en Supabase > SQL Editor > New query > Run
--  Se puede correr más de una vez sin romper nada.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------- USUARIOS (perfil de cada colega) ----------
create table if not exists public.profiles (
  id          uuid primary key references auth.users on delete cascade,
  username    text unique,
  role        text not null default 'pendiente' check (role in ('admin','colega','pendiente')),
  agency      text,      -- nombre de la agencia
  contact     text,      -- nombre de contacto
  phone       text,      -- WhatsApp con código de país
  zone        text,
  created_at  timestamptz not null default now()
);

-- ---------- AUTOS ----------
create table if not exists public.cars (
  id               uuid primary key default gen_random_uuid(),
  owner            uuid not null references public.profiles(id) on delete cascade,
  brand            text not null,
  model            text not null,
  version          text,
  year             int  not null,
  km               int  not null default 0,
  currency         text not null default 'USD' check (currency in ('USD','ARS')),
  price            numeric not null default 0,
  color            text,
  fuel             text,
  gearbox          text,
  status           text not null default 'Disponible' check (status in ('Disponible','Reservado')),
  notes            text,
  photos           text[] not null default '{}',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  price_updated_at timestamptz not null default now()
);
create index if not exists cars_owner_idx on public.cars(owner);

-- ---------- FUNCIONES DE PERMISOS ----------
create or replace function public.is_admin() returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'admin');
$$;

create or replace function public.is_member() returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role in ('admin','colega'));
$$;

-- Cada usuario nuevo recibe un perfil. El PRIMERO que se registra queda como admin;
-- los demás quedan "pendiente" (sin acceso) hasta que el admin los habilite.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, username, role)
  values (
    new.id,
    lower(split_part(new.email, '@', 1)),
    case when exists (select 1 from profiles where role = 'admin') then 'pendiente' else 'admin' end
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Un colega solo puede cambiar PRECIO, MONEDA y FOTOS de sus autos.
-- Cualquier otro cambio que intente se descarta acá, en el servidor.
create or replace function public.cars_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then
    new.id         := old.id;
    new.owner      := old.owner;
    new.brand      := old.brand;
    new.model      := old.model;
    new.version    := old.version;
    new.year       := old.year;
    new.km         := old.km;
    new.color      := old.color;
    new.fuel       := old.fuel;
    new.gearbox    := old.gearbox;
    new.status     := old.status;
    new.notes      := old.notes;
    new.created_at := old.created_at;
  end if;
  new.updated_at := now();
  if new.price is distinct from old.price or new.currency is distinct from old.currency then
    new.price_updated_at := now();
  elsif new.price_updated_at is distinct from old.price_updated_at then
    new.price_updated_at := now();   -- "precio confirmado": siempre con la hora del servidor
  end if;
  return new;
end $$;

drop trigger if exists cars_guard on public.cars;
create trigger cars_guard before update on public.cars
  for each row execute function public.cars_guard();

-- El admin puede cambiarle la clave a un colega.
create or replace function public.admin_set_password(target uuid, new_password text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not is_admin() then raise exception 'Solo el admin puede cambiar claves'; end if;
  if length(new_password) < 6 then raise exception 'La clave debe tener al menos 6 caracteres'; end if;
  update auth.users
     set encrypted_password = extensions.crypt(new_password, extensions.gen_salt('bf')),
         updated_at = now()
   where id = target;
end $$;

-- El admin puede borrar un usuario (y sus autos).
create or replace function public.admin_delete_user(target uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'Solo el admin puede borrar usuarios'; end if;
  if target = auth.uid() then raise exception 'No podés borrarte a vos mismo'; end if;
  delete from auth.users where id = target;
end $$;

revoke all on function public.admin_set_password(uuid, text) from public, anon;
revoke all on function public.admin_delete_user(uuid) from public, anon;
grant execute on function public.admin_set_password(uuid, text) to authenticated;
grant execute on function public.admin_delete_user(uuid) to authenticated;

-- ---------- ACCESO DE LA APP A LAS TABLAS ----------
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on public.profiles, public.cars to authenticated;
grant execute on function public.is_admin(), public.is_member() to authenticated;

-- ---------- REGLAS DE ACCESO (RLS) ----------
alter table public.profiles enable row level security;
alter table public.cars     enable row level security;

drop policy if exists "ver perfiles"      on public.profiles;
drop policy if exists "admin edita perfiles" on public.profiles;
create policy "ver perfiles" on public.profiles
  for select to authenticated using (public.is_member() or id = auth.uid());
create policy "admin edita perfiles" on public.profiles
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "ver autos"          on public.cars;
drop policy if exists "admin agrega autos" on public.cars;
drop policy if exists "admin borra autos"  on public.cars;
drop policy if exists "editar autos"       on public.cars;
create policy "ver autos" on public.cars
  for select to authenticated using (public.is_member());
create policy "admin agrega autos" on public.cars
  for insert to authenticated with check (public.is_admin());
create policy "admin borra autos" on public.cars
  for delete to authenticated using (public.is_admin());
create policy "editar autos" on public.cars
  for update to authenticated
  using (public.is_admin() or (owner = auth.uid() and public.is_member()))
  with check (public.is_admin() or (owner = auth.uid() and public.is_member()));

-- ---------- FOTOS (Storage) ----------
insert into storage.buckets (id, name, public)
values ('fotos', 'fotos', true)
on conflict (id) do update set public = true;

drop policy if exists "subir fotos"  on storage.objects;
drop policy if exists "borrar fotos" on storage.objects;
create policy "subir fotos" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'fotos' and (public.is_admin()
    or (public.is_member() and (storage.foldername(name))[1] = auth.uid()::text)));
create policy "borrar fotos" on storage.objects
  for delete to authenticated
  using (bucket_id = 'fotos' and (public.is_admin()
    or (public.is_member() and (storage.foldername(name))[1] = auth.uid()::text)));

-- Listo ✔
