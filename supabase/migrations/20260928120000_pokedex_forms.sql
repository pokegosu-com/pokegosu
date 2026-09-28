-- The other forms of a species, beside its default: Unown's letters, Burmy's
-- cloaks, Rotom's appliances. pokedex_species already holds one row per form,
-- and a pokedex already lists several forms under one number; what a form
-- lacks is a name of its own, and a way back to the form it is a variant of.
--
-- ko_name and en_name stay the species' names on every form, so a list or a
-- box reads 로토무 whichever Rotom it is. ko_form_name and en_form_name name
-- the form, such as 히트로토무 or 동쪽바다. They are null on a species with
-- one form, which needs no name for it, and on a default form the games name
-- nothing, as plain Pichu beside Spiky-eared Pichu.
--
-- form_of is the default form this row is another form of, and null on a
-- default form, so every form of a species is where coalesce(form_of, id) is
-- the same. It is not an evolution: Gastrodon's East Sea form is a form of
-- Gastrodon, and evolves from Shellos's.
--
-- The rows come from the migration after this one, which
-- apps/pokedex-web/scripts/generate.ts writes.

alter table public.pokedex_species
  add column ko_form_name text,
  add column en_form_name text,
  add column form_of      integer references public.pokedex_species,
  add constraint form_of_another check (form_of <> id);

create index on public.pokedex_species (form_of);
