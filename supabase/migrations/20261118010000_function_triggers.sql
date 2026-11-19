-- Calls the Edge Functions when notes and reports are created (the same thing the dashboard's
-- "Database Webhooks" does, written as SQL).
--
-- The shared secrets each function checks live in Supabase Vault, not in this file:
--   select vault.create_secret('<secret>', 'note_webhook_secret');
--   select vault.create_secret('<secret>', 'report_webhook_secret');
-- The same values are set as NOTE_WEBHOOK_SECRET / REPORT_WEBHOOK_SECRET on the functions.

create extension if not exists pg_net with schema extensions;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- Trigger arguments: the function name and the Vault secret it expects.
create function private.call_edge_function()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
    function_name text := tg_argv[0];
    secret_name text := tg_argv[1];
    secret text;
begin
    select decrypted_secret into secret from vault.decrypted_secrets where name = secret_name;

    perform net.http_post(
        url := 'https://slwarapujtjzjtlhdciw.supabase.co/functions/v1/' || function_name,
        body := jsonb_build_object(
            'type', tg_op,
            'table', tg_table_name,
            'schema', tg_table_schema,
            'record', to_jsonb(new),
            'old_record', null
        ),
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'x-webhook-secret', coalesce(secret, '')
        )
    );
    return new;
end
$$;

create trigger notes_push_widgets
    after insert on public.notes
    for each row execute function private.call_edge_function('note-push', 'note_webhook_secret');

create trigger reports_notify_moderator
    after insert on public.reports
    for each row execute function private.call_edge_function('report-notify', 'report_webhook_secret');
