-- Kelmteen initial schema: profiles, friendships, invites, notes and devices.
--
-- Clients only read and write through row level security policies and the RPC functions
-- below. Anything that needs to see other users' rows (contact matching, invites) runs as a
-- security definer function so the tables themselves stay locked down.

-- MARK: Tables

create table public.profiles (
    id uuid primary key references auth.users (id) on delete cascade,
    -- E.164 with a leading '+', copied from the verified auth phone number.
    phone text not null unique,
    -- Hex SHA-256 of `phone`. The app hashes contacts the same way to find friends.
    phone_hash text not null unique,
    name text not null check (char_length(name) between 1 and 60),
    -- Assigned by the server so it's the same on every friend's phone.
    color text not null check (color in ('sky', 'bubblegum', 'sunshine')),
    -- Path inside the `avatars` storage bucket, e.g. "<user id>/avatar.jpg".
    photo_path text,
    -- Permanent code in the user's invite link: https://<domain>/i/<invite_code>
    invite_code text not null unique,
    created_at timestamptz not null default now()
);

-- One row per pair, with the smaller id first, so friendship is always mutual.
create table public.friendships (
    user_a uuid not null references public.profiles (id) on delete cascade,
    user_b uuid not null references public.profiles (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (user_a, user_b),
    check (user_a < user_b)
);
create index friendships_user_b_idx on public.friendships (user_b);

-- Recorded when someone invites a contact over WhatsApp. If that contact signs up with the
-- same number, the app offers the friendship even though the link was lost in the App Store.
create table public.pending_invites (
    inviter_id uuid not null references public.profiles (id) on delete cascade,
    invitee_phone_hash text not null,
    created_at timestamptz not null default now(),
    primary key (inviter_id, invitee_phone_hash)
);
create index pending_invites_invitee_idx on public.pending_invites (invitee_phone_hash);

create table public.notes (
    id uuid primary key default gen_random_uuid(),
    sender_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
    recipient_id uuid not null references public.profiles (id) on delete cascade,
    -- Matches AppModel.maxNoteLength.
    text text not null check (char_length(text) between 1 and 120),
    sent_at timestamptz not null default now(),
    expires_at timestamptz not null default now() + interval '24 hours'
);
create index notes_recipient_idx on public.notes (recipient_id, sent_at desc);
create index notes_sender_idx on public.notes (sender_id, sent_at desc);

-- Push tokens for alerts and WidgetKit push updates, one row per device.
create table public.devices (
    user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
    device_id text not null,
    apns_token text,
    widget_push_token text,
    updated_at timestamptz not null default now(),
    primary key (user_id, device_id)
);

-- MARK: Helpers

create function public.are_friends(a uuid, b uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
    select exists (
        select 1 from public.friendships
        where user_a = least(a, b) and user_b = greatest(a, b)
    )
$$;

-- 8 URL-safe characters (48 random bits).
create function public.generate_invite_code()
returns text
language sql volatile set search_path = ''
as $$
    select translate(encode(extensions.gen_random_bytes(6), 'base64'), '+/', '-_')
$$;

-- MARK: Row level security

alter table public.profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.pending_invites enable row level security;
alter table public.notes enable row level security;
alter table public.devices enable row level security;

revoke all on public.profiles, public.friendships, public.pending_invites,
    public.notes, public.devices from anon;

create policy "Read own and friends' profiles" on public.profiles
    for select to authenticated
    using (id = (select auth.uid()) or public.are_friends(id, (select auth.uid())));

-- Users can only change their name and photo; color, phone and invite code are server-owned.
create policy "Update own profile" on public.profiles
    for update to authenticated
    using (id = (select auth.uid()))
    with check (id = (select auth.uid()));
revoke insert, update, delete on public.profiles from authenticated;
grant update (name, photo_path) on public.profiles to authenticated;

create policy "Read own friendships" on public.friendships
    for select to authenticated
    using ((select auth.uid()) in (user_a, user_b));

create policy "Remove own friendships" on public.friendships
    for delete to authenticated
    using ((select auth.uid()) in (user_a, user_b));
revoke insert, update on public.friendships from authenticated;

create policy "Read own sent invites" on public.pending_invites
    for select to authenticated
    using (inviter_id = (select auth.uid()));
revoke insert, update, delete on public.pending_invites from authenticated;

create policy "Read own notes" on public.notes
    for select to authenticated
    using ((select auth.uid()) in (sender_id, recipient_id));

create policy "Send notes to friends" on public.notes
    for insert to authenticated
    with check (
        sender_id = (select auth.uid())
        and public.are_friends(sender_id, recipient_id)
    );
-- Only the recipient and text come from the client; times and sender use the defaults.
revoke insert, update, delete on public.notes from authenticated;
grant insert (recipient_id, text) on public.notes to authenticated;

create policy "Manage own devices" on public.devices
    for all to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()));

-- MARK: RPC functions

-- Called once after phone verification, from the onboarding name step.
create function public.create_profile(display_name text)
returns public.profiles
language plpgsql security definer set search_path = ''
as $$
declare
    user_phone text;
    result public.profiles;
begin
    -- auth.users stores phone numbers without the leading '+'.
    select '+' || ltrim(phone, '+') into user_phone
    from auth.users where id = auth.uid();
    if user_phone is null then
        raise exception 'Sign in with a phone number first';
    end if;

    insert into public.profiles (id, phone, phone_hash, name, color, invite_code)
    values (
        auth.uid(),
        user_phone,
        encode(extensions.digest(user_phone, 'sha256'), 'hex'),
        trim(display_name),
        (array['sky', 'bubblegum', 'sunshine'])[1 + floor(random() * 3)::int],
        public.generate_invite_code()
    )
    -- Re-running sign-up only updates the name; the color and invite code stay put.
    on conflict (id) do update set name = excluded.name
    returning * into result;

    return result;
end
$$;

-- Returns which of the given contact hashes belong to Kelmteen users.
create function public.match_contacts(phone_hashes text[])
returns table (phone_hash text, id uuid, name text, color text, photo_path text)
language sql stable security definer set search_path = ''
as $$
    select p.phone_hash, p.id, p.name, p.color, p.photo_path
    from public.profiles p
    where p.phone_hash = any (phone_hashes[1:5000])
      and p.id <> auth.uid()
$$;

-- Records that the current user invited a contact and returns the user's invite code.
create function public.create_invite(contact_phone_hash text)
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

    insert into public.pending_invites (inviter_id, invitee_phone_hash)
    values (auth.uid(), contact_phone_hash)
    on conflict (inviter_id, invitee_phone_hash) do update set created_at = now();

    return code;
end
$$;

-- Who an invite link belongs to, for the "Add <name> as your friend" screen and the web
-- landing page (which is why signed-out visitors can call it too).
create function public.invite_preview(code text)
returns table (id uuid, name text, color text, photo_path text)
language sql stable security definer set search_path = ''
as $$
    select p.id, p.name, p.color, p.photo_path
    from public.profiles p
    where p.invite_code = code
$$;

-- Makes the current user and the link's owner friends. Returns the new friend's id.
create function public.accept_invite(code text)
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
    if inviter is null then
        raise exception 'Invite not found';
    end if;
    if inviter = me then
        raise exception 'You can''t add yourself';
    end if;

    select phone_hash into my_hash from public.profiles where id = me;
    if my_hash is null then
        raise exception 'Create a profile first';
    end if;

    insert into public.friendships (user_a, user_b)
    values (least(me, inviter), greatest(me, inviter))
    on conflict do nothing;

    -- Clear invites in either direction now that they're friends.
    delete from public.pending_invites
    where (inviter_id = inviter and invitee_phone_hash = my_hash)
       or (inviter_id = me and invitee_phone_hash = inviter_hash);

    return inviter;
end
$$;

-- Invites sent to the current user's number before they had the app.
create function public.my_pending_invites()
returns table (invite_code text, id uuid, name text, color text, photo_path text)
language sql stable security definer set search_path = ''
as $$
    select p.invite_code, p.id, p.name, p.color, p.photo_path
    from public.pending_invites i
    join public.profiles me on me.id = auth.uid()
    join public.profiles p on p.id = i.inviter_id
    where i.invitee_phone_hash = me.phone_hash
      and not public.are_friends(p.id, me.id)
    order by i.created_at desc
$$;

-- Hides a pending invite the user chose not to accept.
create function public.dismiss_invite(code text)
returns void
language sql security definer set search_path = ''
as $$
    delete from public.pending_invites i
    using public.profiles p, public.profiles me
    where p.invite_code = code
      and i.inviter_id = p.id
      and me.id = auth.uid()
      and i.invitee_phone_hash = me.phone_hash
$$;

-- Postgres lets everyone execute new functions by default; limit them to signed-in users.
revoke execute on function
    public.are_friends(uuid, uuid),
    public.generate_invite_code(),
    public.create_profile(text),
    public.match_contacts(text[]),
    public.create_invite(text),
    public.invite_preview(text),
    public.accept_invite(text),
    public.my_pending_invites(),
    public.dismiss_invite(text)
from public, anon, authenticated;

grant execute on function
    public.are_friends(uuid, uuid),
    public.create_profile(text),
    public.match_contacts(text[]),
    public.create_invite(text),
    public.invite_preview(text),
    public.accept_invite(text),
    public.my_pending_invites(),
    public.dismiss_invite(text)
to authenticated;

grant execute on function public.invite_preview(text) to anon;

-- MARK: Profile photos

-- Public bucket: photos are served by URL. Each user can only write inside their own folder.
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

create policy "Read avatars" on storage.objects
    for select to authenticated
    using (bucket_id = 'avatars');

create policy "Upload own avatar" on storage.objects
    for insert to authenticated
    with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "Replace own avatar" on storage.objects
    for update to authenticated
    using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "Delete own avatar" on storage.objects
    for delete to authenticated
    using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
