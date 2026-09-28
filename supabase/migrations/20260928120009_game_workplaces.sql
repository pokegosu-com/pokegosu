-- Workplaces, points, and a shop that sells evolution stones and regional eggs.
--
-- Tokens raise the partner; time spent coding earns points. A person has five
-- workplaces, each wanting one or two types, and sends a Pokémon of Lv.50 or
-- more to each. What it earns depends on how well its types would hit the
-- workplace's, as a move would, and on its level. The person works too, at a
-- workplace of their own that never changes, so points come in even with no
-- Pokémon sent anywhere.
--
-- Every hour here is an active hour: an hour with usage in usage_rollups, from
-- any machine or agent, counted once. A day away from the keyboard is a day
-- off for everyone. Usage that arrives late still counts, since hours are
-- counted from the ledger each time rather than as they pass.
--
-- As with the rest of the game, nothing happens on its own: settling a shift,
-- rerolling a workplace and collecting the person's own pay are buttons.


-- ============================================================
-- The balance of it, beside the rest in coder_settings.
--
-- A shift pays points_per_hour × shift_hours × aptitude × level factor,
-- rounded down once. The level factor runs from 1 at min_work_level to 2 at
-- Lv.100. At these values five Lv.100 workers with an ordinary box earn about
-- 230 points an active hour between them, so a stone takes a day of
-- coding and a regional egg five; the person alone earns 10 an hour and 1,000
-- more every 24.
-- ============================================================
alter table public.coder_settings
  add column points_per_hour     integer  not null default 10   check (points_per_hour > 0),
  add column shift_hours         smallint not null default 8    check (shift_hours > 0),
  add column workplaces          smallint not null default 5    check (workplaces > 0),
  add column min_work_level      smallint not null default 50   check (min_work_level between 1 and 99),
  add column bonus_every_hours   integer  not null default 24   check (bonus_every_hours > 0),
  add column bonus_points        integer  not null default 1000 check (bonus_points >= 0);

alter table public.coder_settings
  alter column points_per_hour drop default,
  alter column shift_hours drop default,
  alter column workplaces drop default,
  alter column min_work_level drop default,
  alter column bonus_every_hours drop default,
  alter column bonus_points drop default;


-- ============================================================
-- coder_point_entries: the ledger. A balance is the sum of a person's rows,
-- so points are never set, only added and spent, and a row is never changed.
-- ============================================================
create table public.coder_point_entries (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users on delete cascade,
  points     integer not null check (points <> 0),
  reason     text not null check (reason in ('shift', 'trainer', 'bonus', 'purchase')),
  created_at timestamptz not null default now()
);

create index on public.coder_point_entries (user_id);



-- ============================================================
-- coder_request_tasks: what a Pokémon can ask for help with, five for each
-- type. A request is for one of its client's types, so the screen reads
-- 꼬마돌의 터널 파기, or 버터플의 디버깅: half chores, half the work the
-- tokens come from.
-- ============================================================
create table public.coder_request_tasks (
  id      text primary key,
  type    text not null references public.pokedex_types,
  ko_name text,
  en_name text
);

insert into public.coder_request_tasks (id, type, ko_name, en_name) values
  ('errands', 'normal', '심부름', 'Running errands'),
  ('code-review', 'normal', '코드 리뷰', 'Code review'),
  ('tidying-up', 'normal', '대청소', 'A big clean-up'),
  ('shopping', 'normal', '장보기', 'Grocery shopping'),
  ('meeting-notes', 'normal', '회의록 정리', 'Taking meeting notes'),
  ('campfire', 'fire', '캠프파이어 준비', 'Building a campfire'),
  ('baking', 'fire', '빵 굽기', 'Baking bread'),
  ('burning-legacy', 'fire', '레거시 코드 태우기', 'Burning legacy code'),
  ('forge', 'fire', '대장간 일', 'Working the forge'),
  ('hotfix', 'fire', '핫픽스', 'A hotfix'),
  ('watering', 'water', '밭에 물 주기', 'Watering the fields'),
  ('cooling-servers', 'water', '서버 냉각', 'Cooling the servers'),
  ('washing-up', 'water', '설거지', 'Washing up'),
  ('plumbing', 'water', '배관 수리', 'Fixing the plumbing'),
  ('data-lake', 'water', '데이터 레이크 청소', 'Cleaning the data lake'),
  ('power-plant', 'electric', '발전소 점검', 'Checking the power plant'),
  ('powering-servers', 'electric', '서버 전원 공급', 'Powering the servers'),
  ('wiring', 'electric', '배선 정리', 'Tidying the wiring'),
  ('batteries', 'electric', '배터리 충전', 'Charging batteries'),
  ('running-ci', 'electric', 'CI 돌리기', 'Running CI'),
  ('weeding', 'grass', '밭 매기', 'Weeding the fields'),
  ('gardening', 'grass', '정원 가꾸기', 'Tending the garden'),
  ('pruning-dependencies', 'grass', '의존성 가지치기', 'Pruning dependencies'),
  ('picking-fruit', 'grass', '과일 따기', 'Picking fruit'),
  ('tidying-branches', 'grass', '브랜치 정리', 'Tidying branches'),
  ('hauling-ice', 'ice', '얼음 나르기', 'Hauling ice'),
  ('shaved-ice', 'ice', '빙수 만들기', 'Making shaved ice'),
  ('code-freeze', 'ice', '코드 프리즈 지키기', 'Holding the code freeze'),
  ('cold-store', 'ice', '냉동 창고 정리', 'Sorting the cold store'),
  ('clearing-cache', 'ice', '캐시 비우기', 'Clearing the cache'),
  ('moving-house', 'fighting', '이삿짐 나르기', 'Moving house'),
  ('dojo', 'fighting', '도장 청소', 'Cleaning the dojo'),
  ('refactoring', 'fighting', '리팩터링', 'Refactoring'),
  ('bodyguard', 'fighting', '경호', 'Bodyguarding'),
  ('load-testing', 'fighting', '부하 테스트', 'Load testing'),
  ('pest-control', 'poison', '해충 퇴치', 'Pest control'),
  ('brewing-herbs', 'poison', '약초 달이기', 'Brewing herbs'),
  ('reverting', 'poison', '문제 커밋 되돌리기', 'Reverting a bad commit'),
  ('drains', 'poison', '하수구 청소', 'Cleaning the drains'),
  ('vulnerabilities', 'poison', '취약점 찾기', 'Finding vulnerabilities'),
  ('tunnel', 'ground', '터널 파기', 'Digging a tunnel'),
  ('ploughing', 'ground', '밭 갈기', 'Ploughing the fields'),
  ('infrastructure', 'ground', '인프라 공사', 'Laying infrastructure'),
  ('well', 'ground', '우물 파기', 'Digging a well'),
  ('backend', 'ground', '백엔드 다지기', 'Shoring up the backend'),
  ('mail', 'flying', '편지 배달', 'Delivering the mail'),
  ('scouting', 'flying', '하늘 정찰', 'Scouting the skies'),
  ('shipping', 'flying', '배포 나르기', 'Carrying the release'),
  ('parcels', 'flying', '택배 배송', 'Delivering parcels'),
  ('cloud', 'flying', '클라우드 관리', 'Minding the cloud'),
  ('foreseeing-bugs', 'psychic', '버그 예지', 'Foreseeing bugs'),
  ('requirements', 'psychic', '요구사항 읽기', 'Reading the requirements'),
  ('meditation', 'psychic', '명상 지도', 'Guiding meditation'),
  ('fortunes', 'psychic', '점 보기', 'Telling fortunes'),
  ('deciphering-legacy', 'psychic', '레거시 해독', 'Deciphering legacy code'),
  ('debugging', 'bug', '디버깅', 'Debugging'),
  ('spinning-silk', 'bug', '실 잣기', 'Spinning silk'),
  ('pollen', 'bug', '꽃가루 모으기', 'Gathering pollen'),
  ('hive', 'bug', '벌집 짓기', 'Building a hive'),
  ('writing-tests', 'bug', '테스트 작성', 'Writing tests'),
  ('hauling-stones', 'rock', '돌 나르기', 'Hauling stones'),
  ('building-walls', 'rock', '성벽 쌓기', 'Building a wall'),
  ('monolith', 'rock', '모놀리스 지키기', 'Guarding the monolith'),
  ('quarry', 'rock', '채석장 일', 'Quarry work'),
  ('stable-release', 'rock', '안정 버전 지키기', 'Keeping the stable release'),
  ('on-call', 'ghost', '야간 당직', 'Night on-call'),
  ('zombie-processes', 'ghost', '좀비 프로세스 정리', 'Clearing zombie processes'),
  ('haunted-house', 'ghost', '폐가 순찰', 'Patrolling an old house'),
  ('lost-things', 'ghost', '분실물 찾기', 'Finding lost things'),
  ('dead-code', 'ghost', '죽은 코드 치우기', 'Clearing dead code'),
  ('hoard', 'dragon', '보물 지키기', 'Guarding a hoard'),
  ('big-migration', 'dragon', '대규모 마이그레이션', 'A big migration'),
  ('mountain-delivery', 'dragon', '산 넘어 배달', 'Delivering over the mountains'),
  ('sky-road', 'dragon', '하늘길 경비', 'Guarding the sky road'),
  ('architecture', 'dragon', '아키텍처 설계', 'Designing the architecture'),
  ('night-batch', 'dark', '야간 배치 작업', 'A night batch job'),
  ('security-audit', 'dark', '보안 점검', 'A security audit'),
  ('night-patrol', 'dark', '밤길 순찰', 'Night patrol'),
  ('secret-store', 'dark', '비밀 창고 지키기', 'Guarding a secret store'),
  ('digging-logs', 'dark', '로그 뒤지기', 'Digging through logs'),
  ('bridge', 'steel', '다리 보수', 'Mending a bridge'),
  ('server-racks', 'steel', '서버 랙 조립', 'Building server racks'),
  ('hardening-tests', 'steel', '테스트 강화', 'Hardening the tests'),
  ('machines', 'steel', '기계 정비', 'Servicing machines'),
  ('type-checking', 'steel', '타입 검사', 'Type checking'),
  ('docs', 'fairy', '문서 다듬기', 'Polishing the docs'),
  ('flower-beds', 'fairy', '꽃밭 가꾸기', 'Tending the flower beds'),
  ('ui-polish', 'fairy', '화면 꾸미기', 'Dressing up the UI'),
  ('party', 'fairy', '파티 준비', 'Planning a party'),
  ('onboarding', 'fairy', '신입 안내', 'Onboarding a newcomer');


-- ============================================================
-- coder_workplaces: a person's workplaces, one row per slot for good. Settling
-- or rerolling one changes the row into the next workplace rather than
-- adding one; what it paid is in the ledger.
--
-- The screen calls each one a request (의뢰): a Pokémon drawn from the
-- pokedex, client_id, asks for help with task_id, and the work wants its
-- types.
--
-- opened_at starts the clock for a reroll, assigned_at the worker's shift. A
-- Pokémon works at one workplace at a time.
-- ============================================================
create table public.coder_workplaces (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users on delete cascade,
  slot         smallint not null check (slot > 0),
  client_id    integer not null references public.pokedex_species,
  task_id      text not null references public.coder_request_tasks,
  opened_at    timestamptz not null default now(),
  companion_id uuid unique,
  assigned_at  timestamptz,
  unique (user_id, slot),
  foreign key (companion_id, user_id) references public.coder_companions (id, user_id),
  constraint a_worker_has_a_shift check ((companion_id is null) = (assigned_at is null))
);


-- The person's own workplace: when it opened, and how many of the active
-- hours since then have been paid. Trainers from before this migration start
-- now, so nobody is paid for hours from before there was anything to earn.
alter table public.coder_trainers
  add column work_started_at timestamptz not null default now(),
  add column work_hours_paid integer not null default 0 check (work_hours_paid >= 0);


-- ============================================================
-- The shop, and what a person holds.
--
-- It sells every evolution stone and every regional egg. A national egg is
-- still what Lv.50 earns, and is not sold.
-- ============================================================
create table public.coder_shop_items (
  id       text primary key,
  item_id  text references public.pokedex_items,
  egg_kind text references public.coder_egg_kinds,
  price    integer not null check (price > 0),
  position smallint not null,
  constraint one_thing check ((item_id is null) <> (egg_kind is null))
);

insert into public.coder_shop_items (id, item_id, egg_kind, price, position) values
  ('fire-stone',    'fire-stone',    null, 5000,  1),
  ('water-stone',   'water-stone',   null, 5000,  2),
  ('thunder-stone', 'thunder-stone', null, 5000,  3),
  ('leaf-stone',    'leaf-stone',    null, 5000,  4),
  ('moon-stone',    'moon-stone',    null, 5000,  5),
  ('sun-stone',     'sun-stone',     null, 5000,  6),
  ('shiny-stone',   'shiny-stone',   null, 5000,  7),
  ('dusk-stone',    'dusk-stone',    null, 5000,  8),
  ('dawn-stone',    'dawn-stone',    null, 5000,  9),
  ('kanto-egg',     null, 'kanto',         25000, 10),
  ('johto-egg',     null, 'johto',         25000, 11),
  ('hoenn-egg',     null, 'hoenn',         25000, 12),
  ('sinnoh-egg',    null, 'sinnoh',        25000, 13);

create table public.coder_bag (
  user_id  uuid not null references auth.users on delete cascade,
  item_id  text not null references public.pokedex_items,
  quantity integer not null check (quantity >= 0),
  primary key (user_id, item_id)
);


-- ============================================================
-- Access: the shop is readable by anyone signed in, like the other game
-- tables; a person's own rows are read through work() and box().
-- ============================================================
revoke all on public.coder_point_entries, public.coder_workplaces, public.coder_shop_items,
  public.coder_bag, public.coder_request_tasks
  from anon, authenticated;

alter table public.coder_point_entries enable row level security;
alter table public.coder_workplaces    enable row level security;
alter table public.coder_shop_items    enable row level security;
alter table public.coder_bag           enable row level security;
alter table public.coder_request_tasks enable row level security;

grant select on public.coder_shop_items, public.coder_request_tasks to authenticated;

create policy "anyone signed in can read the shop" on public.coder_shop_items
  for select to authenticated using (true);
create policy "anyone signed in can read what a request can be" on public.coder_request_tasks
  for select to authenticated using (true);


-- ============================================================
-- Helpers. None is granted to anyone.
-- ============================================================

-- The active hours a person has had since a moment: the hours with any usage
-- from the one it falls in on. That hour counts even if the usage in it came
-- first, so an hour can count for both the shift that ends in it and the one
-- that starts: better than a person seeing work they did go unpaid.
create function public.active_hours(owner uuid, since timestamptz)
returns integer
language sql
stable
set search_path = ''
as $$
  select count(distinct r.hour_bucket)::integer
    from public.usage_rollups r
   where r.user_id = owner and r.hour_bucket >= date_trunc('hour', since, 'UTC') and r.tokens > 0;
$$;

create function public.point_balance(owner uuid)
returns bigint
language sql
stable
set search_path = ''
as $$
  select coalesce(sum(p.points), 0)::bigint from public.coder_point_entries p where p.user_id = owner;
$$;

-- How well a species would do at a workplace: the best of its types used as
-- a move against the workplace's, as a multiplier from 0 to 4.
create function public.aptitude(species_id integer, type1 text, type2 text)
returns numeric
language sql
stable
set search_path = ''
as $$
  select round(max(e1.damage_factor * coalesce(e2.damage_factor, 100)) / 10000.0, 2)
    from public.pokedex_species s
   cross join lateral (values (s.type1), (s.type2)) mine (t)
    join public.pokedex_type_efficacy e1
      on e1.attacking_type = mine.t and e1.defending_type = aptitude.type1
    left join public.pokedex_type_efficacy e2
      on e2.attacking_type = mine.t and e2.defending_type = aptitude.type2
   where s.id = aptitude.species_id and mine.t is not null;
$$;

-- What a shift pays a Pokémon of this species and level at this workplace.
create function public.shift_pay(species_id integer, level smallint, type1 text, type2 text)
returns integer
language sql
stable
set search_path = ''
as $$
  select floor(g.points_per_hour * g.shift_hours
               * public.aptitude(shift_pay.species_id, shift_pay.type1, shift_pay.type2)
               * (1 + (shift_pay.level - g.min_work_level)::numeric / (100 - g.min_work_level)))::integer
    from public.coder_settings g;
$$;

-- The Pokémon a new workplace is for, drawn from the national pokedex, every
-- species in its default form as likely as the next, so the types common
-- among Pokémon are common among workplaces too.
create function public.roll_client()
returns integer
language sql
volatile
set search_path = ''
as $$
  select s.id
    from public.pokedex_entries e
    join public.pokedex_species s on s.id = e.species_id
   where e.dex = 'national' and e.is_default
   order by random()
   limit 1;
$$;

-- A task for one of the client's types, every task as likely as the next.
create function public.roll_task(client_id integer)
returns text
language sql
volatile
set search_path = ''
as $$
  select t.id
    from public.coder_request_tasks t
    join public.pokedex_species s on t.type in (s.type1, s.type2)
   where s.id = roll_task.client_id
   order by random()
   limit 1;
$$;

-- Fills a person's slots up to the number of workplaces there are.
create function public.open_workplaces(owner uuid)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  n smallint;
  client integer;
begin
  for n in select generate_series(1, g.workplaces) from public.coder_settings g loop
    if not exists (select 1 from public.coder_workplaces w where w.user_id = owner and w.slot = n) then
      client := public.roll_client();
      insert into public.coder_workplaces (user_id, slot, client_id, task_id)
      values (owner, n, client, public.roll_task(client));
    end if;
  end loop;
end;
$$;

-- Turns a workplace into the next one, with nobody at it.
create function public.replace_workplace(workplace_id uuid)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  client integer := public.roll_client();
begin
  update public.coder_workplaces w
     set client_id = client, task_id = public.roll_task(client), opened_at = now(),
         companion_id = null, assigned_at = null
   where w.id = replace_workplace.workplace_id;
end;
$$;

-- The caller's trainer row, locked, as every change here starts: two tabs
-- settling at once would otherwise both be paid.
create function public.lock_trainer(owner uuid)
returns public.coder_trainers
language plpgsql
volatile
set search_path = ''
as $$
declare
  found public.coder_trainers;
begin
  if owner is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;
  select * into found from public.coder_trainers t where t.user_id = owner for update;
  return found;
end;
$$;

-- The next forms a form becomes with an item, and which: Eevee has three. An
-- item with nothing else asked, or a gender the companion has: a male Kirlia
-- and a female Snorunt take the Dawn Stone.
create function public.item_evolutions(from_id integer, gender text)
returns table (id integer, item text)
language sql
stable
set search_path = ''
as $$
  select p.id, m.item
    from public.pokedex_species p
    join public.pokedex_evolution_methods m on m.id = p.evolution_method
   where p.evolves_from_id = from_id
     and m.trigger = 'use-item' and m.item is not null
     and (m.gender is null or m.gender = item_evolutions.gender)
     and m.time_of_day is null and m.held_item is null
     and m.location is null and m.known_move is null and m.party_species_id is null
   order by p.id;
$$;


-- Everyone playing already gets their workplaces.
select public.open_workplaces(t.user_id) from public.coder_trainers t;


-- ============================================================
-- start_game — as before, and the workplaces open with the first egg.
-- ============================================================
create or replace function public.start_game()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  egg uuid;
begin
  if caller is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;
  if exists (select 1 from public.coder_trainers t where t.user_id = caller) then
    return jsonb_build_object('outcome', 'already_started');
  end if;

  begin
    egg := public.roll_egg(caller, 'national');
    insert into public.coder_trainers (user_id, main_companion_id) values (caller, egg);
    perform public.open_workplaces(caller);
  exception when unique_violation then
    -- Another tab started at the same moment. Its egg stands, and this one
    -- goes back with the rest of the block.
    return jsonb_build_object('outcome', 'already_started');
  end;

  return jsonb_build_object('outcome', 'started', 'companion_id', egg);
end;
$$;


-- ============================================================
-- work — the caller's points, their own workplace, and the five others.
--
--   → {"started": true, "points": 1234,
--      "rules": {"points_per_hour", "shift_hours", "min_work_level",
--                "bonus_every_hours", "bonus_points"},
--      "trainer": {"hours", "hours_paid", "points_waiting", "hours_to_bonus"},
--      "workplaces": [{"id", "slot", "client": {"species_id", "ko_name", "en_name", "sprites"},
--                      "task": {"id", "ko_name", "en_name"},
--                      "types": [{"id", "ko_name", "en_name"}],
--                      "hours_open", "can_reroll",
--                      "worker": null | {"companion_id", "hours", "aptitude", "points", "can_settle"}}],
--      "pokemon": [{"id", "species_id", "ko_name", "en_name", "sprites", "is_shiny", "gender", "level",
--                   "types", "workplace_id",
--                   "offers": [{"workplace_id", "aptitude", "points"}]}]}
--   → {"started": false}
--
-- pokemon is every Pokémon that may work, with what each workplace would pay
-- it for a shift, so the screen can say how well it suits one before it goes.
-- A worker's hours stop counting at a shift's length; the rest wait for the
-- next one.
-- ============================================================
create function public.work()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  trainer public.coder_trainers;
  g public.coder_settings;
  hours integer;
  unpaid integer;
begin
  if caller is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;
  select * into trainer from public.coder_trainers t where t.user_id = caller;
  if not found then
    return jsonb_build_object('started', false);
  end if;
  select * into g from public.coder_settings;

  hours := public.active_hours(caller, trainer.work_started_at);
  unpaid := greatest(0, hours - trainer.work_hours_paid);

  return jsonb_build_object(
    'started', true,
    'points', public.point_balance(caller),
    'rules', jsonb_build_object(
      'points_per_hour', g.points_per_hour,
      'shift_hours', g.shift_hours,
      'min_work_level', g.min_work_level,
      'bonus_every_hours', g.bonus_every_hours,
      'bonus_points', g.bonus_points),
    'trainer', jsonb_build_object(
      'hours', hours,
      'hours_paid', trainer.work_hours_paid,
      'points_waiting', unpaid * g.points_per_hour
        + (hours / g.bonus_every_hours - trainer.work_hours_paid / g.bonus_every_hours) * g.bonus_points,
      'hours_to_bonus', g.bonus_every_hours - hours % g.bonus_every_hours),
    'workplaces', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', w.id,
               'slot', w.slot,
               'client', jsonb_build_object('species_id', k.id, 'ko_name', k.ko_name, 'en_name', k.en_name,
                                            'sprites', k.sprites),
               'task', (select jsonb_build_object('id', t.id, 'ko_name', t.ko_name, 'en_name', t.en_name)
                          from public.coder_request_tasks t where t.id = w.task_id),
               'types', (select jsonb_agg(jsonb_build_object('id', t.id, 'ko_name', t.ko_name, 'en_name', t.en_name)
                                          order by t.id = k.type2)
                           from public.pokedex_types t where t.id in (k.type1, k.type2)),
               'hours_open', open.hours,
               'can_reroll', w.companion_id is null and open.hours >= g.shift_hours,
               'worker', case when w.companion_id is not null then jsonb_build_object(
                   'companion_id', w.companion_id,
                   'hours', least(shift.hours, g.shift_hours),
                   'aptitude', public.aptitude(c.species_id, k.type1, k.type2),
                   'points', public.shift_pay(c.species_id, c.level, k.type1, k.type2),
                   'can_settle', shift.hours >= g.shift_hours) end)
             order by w.slot)
        from public.coder_workplaces w
        join public.pokedex_species k on k.id = w.client_id
        left join public.coder_companions c on c.id = w.companion_id
        cross join lateral (select public.active_hours(caller, w.opened_at) as hours) open
        cross join lateral (select public.active_hours(caller, w.assigned_at) as hours) shift
       where w.user_id = caller), '[]'::jsonb),
    'pokemon', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.id,
               'species_id', p.id,
               'ko_name', p.ko_name,
               'en_name', p.en_name,
               'sprites', p.sprites,
               'is_shiny', c.is_shiny,
               'gender', c.gender,
               'level', c.level,
               'types', (select jsonb_agg(jsonb_build_object('id', t.id, 'ko_name', t.ko_name, 'en_name', t.en_name)
                                          order by t.id = p.type2)
                           from public.pokedex_types t where t.id in (p.type1, p.type2)),
               'workplace_id', (select w.id from public.coder_workplaces w where w.companion_id = c.id),
               'offers', (select jsonb_agg(jsonb_build_object(
                                   'workplace_id', w.id,
                                   'aptitude', public.aptitude(p.id, k.type1, k.type2),
                                   'points', public.shift_pay(p.id, c.level, k.type1, k.type2))
                                 order by w.slot)
                            from public.coder_workplaces w
                            join public.pokedex_species k on k.id = w.client_id
                           where w.user_id = caller))
             order by c.level desc, c.hatched_at)
        from public.coder_companions c
        join public.pokedex_species p on p.id = c.species_id
       where c.user_id = caller and c.hatched_at is not null and c.level >= g.min_work_level), '[]'::jsonb));
end;
$$;


-- ============================================================
-- assign — send a Pokémon to a workplace.
--
--   {"workplace_id", "companion_id"}
--   → {"outcome": "assigned"}
--   → {"outcome": "too_low"}     under min_work_level, or still an egg
--   → {"outcome": "occupied"}    someone is already there
--   → {"outcome": "working"}     it is at another workplace
--   → {"outcome": "not_found"}
--
-- Once sent, it stays until its shift is settled: there is no calling it
-- back, and no sending it elsewhere halfway.
-- ============================================================
create function public.assign(workplace_id uuid, companion_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  pokemon public.coder_companions := public.lock_companion(caller, assign.companion_id);
  place public.coder_workplaces;
begin
  select * into place from public.coder_workplaces w
   where w.id = assign.workplace_id and w.user_id = caller for update;
  if pokemon.id is null or place.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if place.companion_id is not null then
    return jsonb_build_object('outcome', 'occupied');
  end if;
  if exists (select 1 from public.coder_workplaces w where w.companion_id = pokemon.id) then
    return jsonb_build_object('outcome', 'working');
  end if;
  if pokemon.level is null or pokemon.level < (select g.min_work_level from public.coder_settings g) then
    return jsonb_build_object('outcome', 'too_low');
  end if;

  update public.coder_workplaces w set companion_id = pokemon.id, assigned_at = now()
   where w.id = place.id;
  return jsonb_build_object('outcome', 'assigned');
end;
$$;


-- ============================================================
-- settle and reroll — the two ways a workplace becomes the next one.
--
--   settle {"workplace_id"}: its worker's shift is done; pay it.
--   → {"outcome": "settled", "points": 172}
--   → {"outcome": "not_ready"} | {"outcome": "empty"} | {"outcome": "not_found"}
--
--   reroll {"workplace_id"}: nobody is there, and it has stood a shift's
--   length; swap it for another.
--   → {"outcome": "rerolled"}
--   → {"outcome": "not_ready"} | {"outcome": "occupied"} | {"outcome": "not_found"}
--
-- Pay is worked out now, so a Pokémon that levelled or evolved during its
-- shift is paid as it is. A shift that pays nothing, at a workplace its types
-- cannot touch, still ends and leaves no row in the ledger.
-- ============================================================
create function public.settle(workplace_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  place public.coder_workplaces;
  pokemon public.coder_companions;
  pay integer;
begin
  perform public.lock_trainer(caller);
  select * into place from public.coder_workplaces w
   where w.id = settle.workplace_id and w.user_id = caller for update;
  if place.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if place.companion_id is null then
    return jsonb_build_object('outcome', 'empty');
  end if;
  if public.active_hours(caller, place.assigned_at) < (select g.shift_hours from public.coder_settings g) then
    return jsonb_build_object('outcome', 'not_ready');
  end if;

  select * into pokemon from public.coder_companions c where c.id = place.companion_id;
  select public.shift_pay(pokemon.species_id, pokemon.level, k.type1, k.type2) into pay
    from public.pokedex_species k where k.id = place.client_id;
  if pay > 0 then
    insert into public.coder_point_entries (user_id, points, reason) values (caller, pay, 'shift');
  end if;
  perform public.replace_workplace(place.id);
  return jsonb_build_object('outcome', 'settled', 'points', pay);
end;
$$;

create function public.reroll(workplace_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  place public.coder_workplaces;
begin
  perform public.lock_trainer(caller);
  select * into place from public.coder_workplaces w
   where w.id = reroll.workplace_id and w.user_id = caller for update;
  if place.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if place.companion_id is not null then
    return jsonb_build_object('outcome', 'occupied');
  end if;
  if public.active_hours(caller, place.opened_at) < (select g.shift_hours from public.coder_settings g) then
    return jsonb_build_object('outcome', 'not_ready');
  end if;

  perform public.replace_workplace(place.id);
  return jsonb_build_object('outcome', 'rerolled');
end;
$$;


-- ============================================================
-- settle_trainer — the person's own pay: every active hour not yet paid, and
-- a bonus for every bonus_every_hours reached since the last time.
--
--   → {"outcome": "settled", "hours": 5, "points": 50, "bonus": 1000}
--   → {"outcome": "nothing"} | {"outcome": "not_started"}
-- ============================================================
create function public.settle_trainer()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  trainer public.coder_trainers := public.lock_trainer(caller);
  g public.coder_settings;
  hours integer;
  pay integer;
  bonus integer;
begin
  if trainer.user_id is null then
    return jsonb_build_object('outcome', 'not_started');
  end if;
  select * into g from public.coder_settings;

  hours := public.active_hours(caller, trainer.work_started_at);
  if hours <= trainer.work_hours_paid then
    return jsonb_build_object('outcome', 'nothing');
  end if;

  pay := (hours - trainer.work_hours_paid) * g.points_per_hour;
  bonus := (hours / g.bonus_every_hours - trainer.work_hours_paid / g.bonus_every_hours) * g.bonus_points;
  insert into public.coder_point_entries (user_id, points, reason) values (caller, pay, 'trainer');
  if bonus > 0 then
    insert into public.coder_point_entries (user_id, points, reason) values (caller, bonus, 'bonus');
  end if;
  update public.coder_trainers t set work_hours_paid = hours where t.user_id = caller;
  return jsonb_build_object('outcome', 'settled', 'hours', hours - trainer.work_hours_paid,
                            'points', pay, 'bonus', bonus);
end;
$$;


-- ============================================================
-- buy — spend points on something from the shop. A stone goes in the bag; an
-- egg goes in the box, drawn as any other egg of its kind is.
--
--   {"shop_item_id": "fire-stone"}
--   → {"outcome": "bought", "points": 3200}                  what is left
--   → {"outcome": "bought", "points": 3200, "companion_id"}  for an egg
--   → {"outcome": "not_enough_points"} | {"outcome": "not_found"} | {"outcome": "not_started"}
-- ============================================================
create function public.buy(shop_item_id text)
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


-- ============================================================
-- use_item — use an item from the bag on a Pokémon. Today every item is a
-- stone, and a stone either evolves it or is kept, as in the games.
--
--   {"companion_id", "item_id": "fire-stone"}
--   → {"outcome": "evolved", "from": 37, "to": 38}
--   → {"outcome": "no_effect"}     nothing it evolves into takes this item
--   → {"outcome": "not_in_bag"} | {"outcome": "not_found"}
-- ============================================================
create function public.use_item(companion_id uuid, item_id text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  pokemon public.coder_companions := public.lock_companion(caller, use_item.companion_id);
  next_form integer;
begin
  if pokemon.id is null or pokemon.hatched_at is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if not exists (select 1 from public.coder_bag b
                  where b.user_id = caller and b.item_id = use_item.item_id and b.quantity > 0) then
    return jsonb_build_object('outcome', 'not_in_bag');
  end if;

  select e.id into next_form from public.item_evolutions(pokemon.species_id, pokemon.gender) e
   where e.item = use_item.item_id;
  if next_form is null then
    return jsonb_build_object('outcome', 'no_effect');
  end if;

  update public.coder_bag b set quantity = b.quantity - 1
   where b.user_id = caller and b.item_id = use_item.item_id;
  update public.coder_companions c set species_id = next_form where c.id = pokemon.id;
  return jsonb_build_object('outcome', 'evolved', 'from', pokemon.species_id, 'to', next_form);
end;
$$;


-- ============================================================
-- box — as before, with the bag, the points, and for each Pokémon the stones
-- that evolve it, by its gender too, and the workplace it is at.
--
--   → {..., "points": 1234, "bag": [{"id", "ko_name", "en_name", "sprite", "quantity"}],
--      "pokemon": [{..., "item_evolutions": [{"species_id", "ko_name", "en_name",
--                                             "item": {"id", "ko_name", "en_name", "sprite"}}],
--                   "workplace_id": "..." | null}]}
-- ============================================================
create or replace function public.box()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  main uuid;
  balance bigint;
begin
  if caller is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;

  balance := (select coalesce(sum(r.tokens), 0) from public.usage_rollups r where r.user_id = caller)
           - (select coalesce(sum(c.invested_tokens), 0) from public.coder_companions c where c.user_id = caller);

  select t.main_companion_id into main from public.coder_trainers t where t.user_id = caller;
  if not found then
    return jsonb_build_object('started', false, 'balance', balance::text);
  end if;

  return jsonb_build_object(
    'started', true,
    'main_companion_id', main,
    'balance', balance::text,
    'points', public.point_balance(caller),
    'bag', coalesce((
      select jsonb_agg(jsonb_build_object('id', i.id, 'ko_name', i.ko_name, 'en_name', i.en_name,
                                          'sprite', i.sprite, 'quantity', b.quantity)
                       order by s.position, i.id)
        from public.coder_bag b
        join public.pokedex_items i on i.id = b.item_id
        left join public.coder_shop_items s on s.item_id = b.item_id
       where b.user_id = caller and b.quantity > 0), '[]'::jsonb),
    'eggs', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.id,
               'created_at', c.created_at,
               'tokens', c.egg_tokens,
               'tokens_needed', p.hatch_counter::bigint * g.tokens_per_cycle,
               'is_main', c.id = main,
               'markings', c.markings)
             order by c.created_at)
        from public.coder_companions c
        join public.pokedex_species p on p.id = c.species_id
        cross join public.coder_settings g
       where c.user_id = caller and c.hatched_at is null), '[]'::jsonb),
    'pokemon', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.id,
               'species_id', p.id,
               'form_slug', case when p.form_of is not null then p.slug end,
               'dex_no', dex.number,
               'ko_name', p.ko_name,
               'en_name', p.en_name,
               'sprites', p.sprites,
               'growth_rate', p.growth_rate,
               'types', (select jsonb_agg(jsonb_build_object('id', t.id, 'ko_name', t.ko_name, 'en_name', t.en_name)
                                          order by t.id = p.type2)
                           from public.pokedex_types t where t.id in (p.type1, p.type2)),
               'is_shiny', c.is_shiny,
               'gender', c.gender,
               'level', c.level,
               'tokens', c.exp,
               'level_tokens', here.tokens,
               'next_level_tokens', above.tokens,
               'max_tokens', top.tokens,
               'evolves_to', case when nxt.id is not null then
                   jsonb_build_object('species_id', nxt.id, 'ko_name', target.ko_name, 'en_name', target.en_name,
                                      'level', nxt.min_level) end,
               'can_evolve', coalesce(c.level >= nxt.min_level, false),
               'item_evolutions', coalesce((
                   select jsonb_agg(jsonb_build_object(
                            'species_id', e.id, 'ko_name', s.ko_name, 'en_name', s.en_name,
                            'item', jsonb_build_object('id', i.id, 'ko_name', i.ko_name, 'en_name', i.en_name,
                                                       'sprite', i.sprite))
                          order by e.id)
                     from public.item_evolutions(c.species_id, c.gender) e
                     join public.pokedex_species s on s.id = e.id
                     join public.pokedex_items i on i.id = e.item), '[]'::jsonb),
               'workplace_id', (select w.id from public.coder_workplaces w where w.companion_id = c.id),
               'can_receive_egg', c.level >= 50 and c.egg_received_at is null,
               'ribbons', coalesce((
                   select jsonb_agg(jsonb_build_object('id', r.id, 'ko_name', r.ko_name, 'en_name', r.en_name,
                                                       'received_at', cr.received_at)
                                    order by cr.received_at)
                     from public.coder_companion_ribbons cr
                     join public.coder_ribbons r on r.id = cr.ribbon_id
                    where cr.companion_id = c.id), '[]'::jsonb),
               'ribbons_waiting', coalesce((
                   select jsonb_agg(jsonb_build_object('id', r.id, 'ko_name', r.ko_name, 'en_name', r.en_name) order by r.id)
                     from public.coder_ribbons r
                    where r.id = any (public.eligible_ribbons(c))), '[]'::jsonb),
               'created_at', c.created_at,
               'hatched_at', c.hatched_at,
               'is_main', c.id = main,
               'markings', c.markings)
             order by c.hatched_at)
        from public.coder_companions c
        join public.pokedex_species p on p.id = c.species_id
        cross join public.coder_settings g
        join public.coder_experience_levels here on here.growth_rate = p.growth_rate and here.level = c.level
        join public.coder_experience_levels top on top.growth_rate = p.growth_rate and top.level = 100
        left join public.coder_experience_levels above
          on above.growth_rate = p.growth_rate and above.level = c.level + 1
        left join lateral public.level_up_evolution(c.species_id, c.gender) nxt on true
        left join public.pokedex_species target on target.id = nxt.id
        left join public.pokedex_entries dex on dex.dex = 'national' and dex.species_id = p.id
       where c.user_id = caller and c.hatched_at is not null), '[]'::jsonb));
end;
$$;


-- ============================================================
-- Who may call what. See the note in the account migration.
-- ============================================================
revoke execute on function
  public.active_hours(uuid, timestamptz),
  public.point_balance(uuid),
  public.aptitude(integer, text, text),
  public.shift_pay(integer, smallint, text, text),
  public.roll_client(),
  public.roll_task(integer),
  public.open_workplaces(uuid),
  public.replace_workplace(uuid),
  public.lock_trainer(uuid),
  public.item_evolutions(integer, text),
  public.work(),
  public.assign(uuid, uuid),
  public.settle(uuid),
  public.reroll(uuid),
  public.settle_trainer(),
  public.buy(text),
  public.use_item(uuid, text)
  from public;

grant execute on function
  public.work(),
  public.assign(uuid, uuid),
  public.settle(uuid),
  public.reroll(uuid),
  public.settle_trainer(),
  public.buy(text),
  public.use_item(uuid, text)
  to authenticated;
