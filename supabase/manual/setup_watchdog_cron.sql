-- Supabase Dashboard SQL editor에서 Vault secret을 먼저 등록하세요.
-- 실제 키는 저장소에 커밋하지 않습니다.
-- select vault.create_secret('https://YOUR_PROJECT.supabase.co', 'watchdog_project_url');
-- select vault.create_secret('YOUR_SERVICE_ROLE_KEY', 'watchdog_service_role_key');
-- select vault.create_secret('YOUR_CRON_SECRET', 'watchdog_cron_secret');

select cron.schedule(
  'mango-watchdog-every-5-minutes',
  '*/5 * * * *',
  $$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'watchdog_project_url') || '/functions/v1/check-watchdog',
      headers := jsonb_build_object(
        'content-type', 'application/json',
        'authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'watchdog_cron_secret')
      ),
      body := jsonb_build_object('source', 'supabase-cron')
    );
  $$
);

-- Database Webhook은 Dashboard > Database > Webhooks에서 설정합니다.
-- 대상: public.watch_availability_events, INSERT
-- URL: https://YOUR_PROJECT.supabase.co/functions/v1/send-watchdog-push
-- Header: x-watchdog-webhook-secret: (Vault에 등록한 WATCHDOG_WEBHOOK_SECRET)
-- Edge Function secrets: WATCHDOG_CRON_SECRET, WATCHDOG_WEBHOOK_SECRET,
-- SUPABASE_SERVICE_ROLE_KEY, FIREBASE_SERVICE_ACCOUNT_JSON_BASE64
