-- The widget needs each note's sender ID so tapping a note opens Write with that sender
-- selected as the recipient. Adding a column to a function's result means recreating it.

drop function public.widget_notes(text);

create function public.widget_notes(secret text)
returns table (
    note_text text,
    sender_id uuid,
    sender_name text,
    sender_color text,
    sent_at double precision,
    expires_at double precision
)
language sql stable security definer set search_path = ''
as $$
    select n.text, p.id, p.name, p.color, extract(epoch from n.sent_at), extract(epoch from n.expires_at)
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

revoke execute on function public.widget_notes(text) from public, anon, authenticated;
-- The widget calls this without a session; the secret is what identifies the user.
grant execute on function public.widget_notes(text) to anon, authenticated;
