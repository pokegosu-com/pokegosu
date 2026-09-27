-- ============================================================
-- providers — Codex joins Claude Code.
--
-- A client can only send what the server knows: ingest names an unknown
-- provider and refuses the whole batch, so this row has to ship before any
-- client that reads Codex's logs.
-- ============================================================
insert into public.providers (id, display_name) values
  ('codex', 'Codex');
