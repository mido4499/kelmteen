-- Lets the widget load notes and receive push updates without the app running.
--
-- The widget can't share the app's login session, so each install gets a random secret
-- (stored in the App Group the app and widget share). The widget sends it to
-- `widget_notes` to read that user's received notes, and nothing else.

alter table public.devices add column widget_secret text unique;
-- Development builds use Apple's sandbox push server; TestFlight and App Store builds don't.
alter table public.devices add column apns_sandbox boolean not null default false;

create function public.widget_notes(secret text)
returns table (note_text text, sender_name text, sender_color text, sent_at double precision, expires_at double precision)
language sql stable security definer set search_path = ''
as $$
    select n.text, p.name, p.color, extract(epoch from n.sent_at), extract(epoch from n.expires_at)
    from public.devices d
    join public.notes n on n.recipient_id = d.user_id
    join public.profiles p on p.id = n.sender_id
    where char_length(secret) >= 32
      and d.widget_secret = secret
      and n.expires_at > now()
      and p.suspended_at is null
      and public.are_friends(n.sender_id, d.user_id)
    order by n.sent_at desc
    limit 10
$$;

-- iOS can change a widget's push token at any time; the widget reports it here directly,
-- so pushes keep working even if the app isn't opened.
create function public.set_widget_push_token(secret text, push_token text)
returns void
language sql security definer set search_path = ''
as $$
    update public.devices
    set widget_push_token = push_token, updated_at = now()
    where char_length(secret) >= 32 and widget_secret = secret
$$;

revoke execute on function public.widget_notes(text), public.set_widget_push_token(text, text)
from public, anon, authenticated;
-- The widget calls these without a session; the secret is what identifies the user.
grant execute on function public.widget_notes(text), public.set_widget_push_token(text, text)
to anon, authenticated;
