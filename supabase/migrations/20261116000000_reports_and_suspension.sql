-- Reporting and account suspension.
--
-- Users can file reports but never read them (not even their own), so nobody can learn who
-- reported them. Moderation happens from the Supabase dashboard; see supabase/moderation.sql.

-- MARK: Suspension

-- Set by a moderator. Suspended users can still sign in (to see why), but can't reach anyone.
alter table public.profiles add column suspended_at timestamptz;

create function public.is_suspended(user_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
    select coalesce((select suspended_at is not null from public.profiles where id = user_id), false)
$$;

-- Suspended users disappear from their friends' lists.
drop policy "Read own and friends' profiles" on public.profiles;
create policy "Read own and friends' profiles" on public.profiles
    for select to authenticated
    using (
        id = (select auth.uid())
        or (suspended_at is null and public.are_friends(id, (select auth.uid())))
    );

-- Suspended users can't send notes, and notes can't be sent to them.
drop policy "Send notes to friends" on public.notes;
create policy "Send notes to friends" on public.notes
    for insert to authenticated
    with check (
        sender_id = (select auth.uid())
        and public.are_friends(sender_id, recipient_id)
        and not public.is_suspended(sender_id)
        and not public.is_suspended(recipient_id)
    );

-- Suspended users don't show up as "On Kelmteen" in anyone's contacts.
create or replace function public.match_contacts(phone_hashes text[])
returns table (phone_hash text, id uuid, name text, color text, photo_path text)
language sql stable security definer set search_path = ''
as $$
    select p.phone_hash, p.id, p.name, p.color, p.photo_path
    from public.profiles p
    where p.phone_hash = any (phone_hashes[1:5000])
      and p.id <> auth.uid()
      and p.suspended_at is null
$$;

create or replace function public.create_invite(contact_phone_hash text)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
    code text;
begin
    select invite_code into code from public.profiles where id = auth.uid();
    if code is null then
        raise exception 'Create a profile first';
    end if;
    if public.is_suspended(auth.uid()) then
        raise exception 'Your account is suspended';
    end if;

    insert into public.pending_invites (inviter_id, invitee_phone_hash)
    values (auth.uid(), contact_phone_hash)
    on conflict (inviter_id, invitee_phone_hash) do update set created_at = now();

    return code;
end
$$;

-- A suspended user's invite link looks like it doesn't exist, in the app and on the website.
create or replace function public.invite_preview(code text)
returns table (id uuid, name text, color text, photo_path text, blocked_by_me boolean)
language sql stable security definer set search_path = ''
as $$
    select p.id, p.name, p.color, p.photo_path,
           exists (select 1 from public.blocks b where b.blocker_id = auth.uid() and b.blocked_id = p.id)
    from public.profiles p
    where p.invite_code = code
      and p.suspended_at is null
      and not exists (select 1 from public.blocks b where b.blocker_id = p.id and b.blocked_id = auth.uid())
$$;

create or replace function public.accept_invite(code text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
    me uuid := auth.uid();
    inviter uuid;
    inviter_hash text;
    my_hash text;
begin
    select id, phone_hash into inviter, inviter_hash
    from public.profiles where invite_code = code;
    if inviter is null
       or public.is_suspended(inviter)
       or exists (select 1 from public.blocks where blocker_id = inviter and blocked_id = me) then
        raise exception 'This invite isn''t available';
    end if;
    if inviter = me then
        raise exception 'You can''t add yourself';
    end if;
    if public.is_suspended(me) then
        raise exception 'Your account is suspended';
    end if;
    if exists (select 1 from public.blocks where blocker_id = me and blocked_id = inviter) then
        raise exception 'Unblock this person to accept their invite';
    end if;

    select phone_hash into my_hash from public.profiles where id = me;
    if my_hash is null then
        raise exception 'Create a profile first';
    end if;

    insert into public.friendships (user_a, user_b)
    values (least(me, inviter), greatest(me, inviter))
    on conflict do nothing;

    delete from public.pending_invites
    where (inviter_id = inviter and invitee_phone_hash = my_hash)
       or (inviter_id = me and invitee_phone_hash = inviter_hash);

    return inviter;
end
$$;

create or replace function public.my_pending_invites()
returns table (invite_code text, id uuid, name text, color text, photo_path text)
language sql stable security definer set search_path = ''
as $$
    select p.invite_code, p.id, p.name, p.color, p.photo_path
    from public.pending_invites i
    join public.profiles me on me.id = auth.uid()
    join public.profiles p on p.id = i.inviter_id
    where i.invitee_phone_hash = me.phone_hash
      and p.suspended_at is null
      and not public.are_friends(p.id, me.id)
      and not public.is_blocked_either_way(p.id, me.id)
    order by i.created_at desc
$$;

-- MARK: Reports

create table public.reports (
    id uuid primary key default gen_random_uuid(),
    -- Kept even if either account is later deleted.
    reporter_id uuid references public.profiles (id) on delete set null,
    reported_id uuid references public.profiles (id) on delete set null,
    reason text not null check (reason in ('inappropriate_photo', 'harassment', 'spam', 'other')),
    details text check (char_length(details) <= 500),
    -- Evidence as it was when reported, in case the person changes it afterwards.
    reported_name text not null,
    reported_phone text not null,
    reported_photo_path text,
    -- Copy of the photo in the private report-evidence bucket, made by the notify function.
    evidence_photo_path text,
    status text not null default 'open' check (status in ('open', 'actioned', 'dismissed')),
    moderator_note text,
    created_at timestamptz not null default now(),
    reviewed_at timestamptz
);
create index reports_status_idx on public.reports (status, created_at desc);
-- One open report per person per reporter; reporting again updates it.
create unique index reports_one_open_idx on public.reports (reporter_id, reported_id) where status = 'open';

alter table public.reports enable row level security;
revoke all on public.reports from anon, authenticated;

create function public.report_user(target uuid, reason text, details text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
    me uuid := auth.uid();
    reported public.profiles;
begin
    if target = me then
        raise exception 'You can''t report yourself';
    end if;
    select * into reported from public.profiles where id = target;
    if reported.id is null then
        raise exception 'This person isn''t on Kelmteen';
    end if;
    if (select count(*) from public.reports
        where reporter_id = me and created_at > now() - interval '1 day') >= 10 then
        raise exception 'You''ve sent a lot of reports today. Please try again tomorrow.';
    end if;

    insert into public.reports
        (reporter_id, reported_id, reason, details, reported_name, reported_phone, reported_photo_path)
    values
        (me, target, reason, nullif(trim(details), ''), reported.name, reported.phone, reported.photo_path)
    on conflict (reporter_id, reported_id) where status = 'open' do update
        set reason = excluded.reason,
            details = coalesce(excluded.details, public.reports.details),
            reported_photo_path = excluded.reported_photo_path,
            created_at = now();
end
$$;

-- Private bucket for evidence photos; only the service role (dashboard, functions) can read it.
insert into storage.buckets (id, name, public)
values ('report-evidence', 'report-evidence', false)
on conflict (id) do nothing;

-- MARK: Permissions

revoke execute on function
    public.is_suspended(uuid),
    public.report_user(uuid, text, text),
    public.invite_preview(text)
from public, anon, authenticated;

grant execute on function public.is_suspended(uuid) to authenticated;
grant execute on function public.report_user(uuid, text, text) to authenticated;
grant execute on function public.invite_preview(text) to anon, authenticated;
