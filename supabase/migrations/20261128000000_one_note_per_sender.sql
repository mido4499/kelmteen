-- Each person has at most one note to each friend: sending a new one replaces the previous
-- one, so a chat between two friends holds at most two notes (one from each). Both still
-- expire 24 hours after they were sent.

-- Keep only the newest note from each sender to each recipient.
delete from public.notes n
using public.notes newer
where newer.sender_id = n.sender_id
  and newer.recipient_id = n.recipient_id
  and (newer.sent_at, newer.id) > (n.sent_at, n.id);

-- Clients can't delete notes, so the replacement happens on the server, as the note is sent.
create function private.replace_previous_note()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
    delete from public.notes
    where sender_id = new.sender_id
      and recipient_id = new.recipient_id;
    return new;
end;
$$;

create trigger notes_replace_previous
    before insert on public.notes
    for each row execute function private.replace_previous_note();
