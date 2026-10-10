-- The Shiny Charm, as in the games: whoever holds it finds shiny Pokémon more
-- often. Here it is sold in the shop, once, for what eight regional eggs
-- cost, and it doubles the odds that an egg holds a shiny Pokémon. A request's
-- client is no likelier to be shiny for it.


-- ============================================================
-- The balance of it, beside the rest in coder_settings.
-- ============================================================
alter table public.coder_settings
  -- An egg is shiny one time in this many for someone who holds the charm.
  add column charm_shiny_odds integer not null default 32 check (charm_shiny_odds >= 1);

alter table public.coder_settings
  alter column charm_shiny_odds drop default;


-- ============================================================
-- coder_shop_items.kept: an item that is held rather than used, so a person
-- buys it once. It sits in the bag with the stones, at a quantity of one.
-- ============================================================
alter table public.coder_shop_items
  add column kept boolean not null default false,
  add constraint only_an_item_is_kept check (not kept or item_id is not null);

insert into public.coder_shop_items (id, item_id, egg_kind, price, position, kept)
select 'shiny-charm', 'shiny-charm', null, 200000, max(s.position) + 1, true
  from public.coder_shop_items s;


-- ============================================================
-- Helpers. None is granted to anyone.
-- ============================================================

-- An egg given to this person now is shiny one time in this many.
create function public.egg_shiny_odds(owner uuid)
returns integer
language sql
stable
set search_path = ''
as $$
  select case when exists (select 1 from public.coder_bag b
                            where b.user_id = owner and b.item_id = 'shiny-charm' and b.quantity > 0)
              then g.charm_shiny_odds else g.shiny_odds end
    from public.coder_settings g;
$$;

revoke execute on function public.egg_shiny_odds(uuid) from public;


-- ============================================================
-- roll_egg — as before, at the odds of the person it is for. An egg is drawn
-- shiny or not when it is given, so the charm changes nothing about the eggs
-- already in the box.
-- ============================================================
create or replace function public.roll_egg(owner uuid, egg_kind text)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  settings public.coder_settings;
  drawn integer;
  gender text;
  region text;
  egg uuid;
begin
  select * into settings from public.coder_settings;

  with owned as (
    select distinct public.pokedex_first_form(coalesce(p.form_of, p.id)) as first_form
      from public.coder_companions c
      join public.pokedex_species p on p.id = c.species_id
     where c.user_id = owner
  ),
  weighted as (
    select g.species_id as id,
           r.weight * case when o.first_form is null then settings.unowned_line_weight else 1 end as weight
      from public.coder_egg_species g
      join public.coder_species_rarities sr on sr.species_id = g.species_id
      join public.coder_egg_rarities r on r.id = sr.rarity
      left join owned o on o.first_form = public.pokedex_first_form(g.species_id)
     where g.egg_kind = roll_egg.egg_kind
  ),
  running as (
    select id, sum(weight) over (order by id) as upto, sum(weight) over () as total
      from weighted
  ),
  pick as (
    select random() * max(total) as point from running
  )
  select r.id into drawn
    from running r, pick
   where r.upto > pick.point
   order by r.id
   limit 1;

  if drawn is null then
    raise exception 'no egg of kind % can hold anything', roll_egg.egg_kind;
  end if;

  gender := public.draw_gender(drawn);

  -- The region whose form it hatches as, or null for the default's.
  select r.region into region
    from (select null::text as region
          union
          select rf.egg_kind from public.coder_egg_regional_forms rf
            join public.pokedex_species s on s.id = rf.species_id
           where s.form_of = drawn) r
   where roll_egg.egg_kind = 'national' or r.region is null or r.region = roll_egg.egg_kind
   order by (r.region is not null and r.region = roll_egg.egg_kind) desc, random()
   limit 1;

  select f.id into drawn
    from (select drawn as id
           where region is null
          union all
          select s.id from public.coder_egg_forms ef
            join public.pokedex_species s on s.id = ef.species_id
           where s.form_of = drawn and region is null
          union all
          select s.id from public.coder_egg_kind_forms kf
            join public.pokedex_species s on s.id = kf.species_id
           where s.form_of = drawn and kf.egg_kind = roll_egg.egg_kind and region is null
          union all
          select s.id from public.coder_egg_regional_forms rf
            join public.pokedex_species s on s.id = rf.species_id
           where s.form_of = drawn and rf.egg_kind = region) f
   order by random()
   limit 1;

  if gender = 'female' then
    select coalesce((select s.id from public.pokedex_species s
                      where s.form_of = drawn and s.slug like '%-female'), drawn)
      into drawn;
  end if;

  insert into public.coder_companions (user_id, species_id, egg_kind, is_shiny, gender)
  values (owner, drawn, roll_egg.egg_kind, floor(random() * public.egg_shiny_odds(owner)) = 0, gender)
  returning id into egg;
  return egg;
end;
$$;


-- ============================================================
-- buy — as before, and an item that is kept is sold to a person once.
--
--   → {"outcome": "already_held"}
-- ============================================================
create or replace function public.buy(shop_item_id text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  trainer public.coder_trainers := public.lock_trainer(caller);
  wanted public.coder_shop_items;
  balance bigint;
  egg uuid;
begin
  if trainer.user_id is null then
    return jsonb_build_object('outcome', 'not_started');
  end if;
  select * into wanted from public.coder_shop_items s where s.id = buy.shop_item_id;
  if wanted.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if wanted.kept and exists (select 1 from public.coder_bag b
                              where b.user_id = caller and b.item_id = wanted.item_id and b.quantity > 0) then
    return jsonb_build_object('outcome', 'already_held');
  end if;
  balance := public.point_balance(caller);
  if balance < wanted.price then
    return jsonb_build_object('outcome', 'not_enough_points');
  end if;

  insert into public.coder_point_entries (user_id, points, reason) values (caller, -wanted.price, 'purchase');
  if wanted.item_id is not null then
    insert into public.coder_bag (user_id, item_id, quantity) values (caller, wanted.item_id, 1)
    on conflict (user_id, item_id) do update set quantity = public.coder_bag.quantity + 1;
    return jsonb_build_object('outcome', 'bought', 'points', balance - wanted.price);
  end if;

  egg := public.roll_egg(caller, wanted.egg_kind);
  return jsonb_build_object('outcome', 'bought', 'points', balance - wanted.price, 'companion_id', egg);
end;
$$;
