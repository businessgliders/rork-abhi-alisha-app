-- Live Activities for every guest, sent from the server.
--
-- The app registers two kinds of ActivityKit token through the
-- `register-live-activity` edge function (no sign-in needed):
--   kind = 'start'  : the phone's push-to-start token (raises a celebration)
--   kind = 'update' : one running activity's own token (moves it to "Happening now",
--                     then retires it)
-- Only the edge functions (service role) read or write these tables.

create table if not exists public.live_activity_tokens (
  token        text primary key,
  kind         text not null check (kind in ('start', 'update')),
  event_id     text,
  device_id    text,
  environment  text not null default 'production' check (environment in ('production', 'sandbox')),
  updated_at   timestamptz not null default now()
);

create index if not exists live_activity_tokens_kind_idx on public.live_activity_tokens (kind);
create index if not exists live_activity_tokens_event_idx on public.live_activity_tokens (event_id);

-- One row per push already sent, so the job never sends the same step twice.
create table if not exists public.live_activity_log (
  event_id  text not null,
  target    text not null,          -- device id (or token when the device is unknown)
  stage     text not null check (stage in ('start', 'now', 'end')),
  sent_at   timestamptz not null default now(),
  primary key (event_id, target, stage)
);

alter table public.live_activity_tokens enable row level security;
alter table public.live_activity_log enable row level security;
-- No policies on purpose: guests can never read or change these rows.

-- Run the job every five minutes. Replace <CRON_SECRET> with the same value you set as
-- the CRON_SECRET function secret. Needs the pg_cron and pg_net extensions
-- (Database -> Extensions in the Supabase dashboard).
--
-- select cron.schedule(
--   'live-activity-tick',
--   '*/5 * * * *',
--   $$
--   select net.http_post(
--     url     := 'https://lrowuakbxuoynlyxlmnr.supabase.co/functions/v1/live-activity-tick',
--     headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', '<CRON_SECRET>'),
--     body    := '{}'::jsonb
--   );
--   $$
-- );
