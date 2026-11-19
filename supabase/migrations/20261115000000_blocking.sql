-- Blocking: a blocked person stops being a friend, can't add the blocker, and isn't told.

create table public.blocks (
    blocker_id uuid not null references public.profiles (id) on delete cascade,
    blocked_id uuid not null references public.profiles (id) on delete cascade,
    -- Whether they were friends when the block happened, so unblocking can restore it.
    was_friend boolean not null default false,
    created_at timestamptz not null default now(),
    primary key (blocker_id, blocked_id),
    check (blocker_id <> blocked_id)
);
create index blocks_blocked_idx on public.blocks (blocked_id);

alter table public.blocks enable row level security;
revoke all on public.blocks from anon;
revoke insert, update, delete on public.blocks from authenticated;

-- Users only ever see who they blocked, never who blocked them.
create policy "Read own blocks" on public.blocks
    for select to authenticated
    using (blocker_id = (select auth.uid()));

-- MARK: Block and unblock

create function public.block_user(target uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
    me uuid := auth.uid();
begin
    if target = me then
        raise exception 'You can''t block yourself';
    end if;

    insert into public.blocks (blocker_id, blocked_id, was_friend)
    values (me, target, public.are_friends(me, target))
    on conflict do nothing;

    delete from public.friendships
    where user_a = least(me, target) and user_b = greatest(me, target);

    -- Drop invites in either direction.
    delete from public.pending_invites
    where (inviter_id = me and invitee_phone_hash = (select phone_hash from public.profiles where id = target))
       or (inviter_id = target and invitee_phone_hash = (select phone_hash from public.profiles where id = me));
end
$$;

create function public.unblock_user(target uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
    me uuid := auth.uid();
    restore boolean;
begin
    delete from public.blocks
    where blocker_id = me and blocked_id = target
    returning was_friend into restore;

    if not coalesce(restore, false) then
        return;
    end if;

    if exists (select 1 from public.blocks where blocker_id = target and blocked_id = me) then
        -- They've blocked this user too; restore the friendship once they unblock.
        update public.blocks set was_friend = true
        where blocker_id = target and blocked_id = me;
    else
        insert into public.friendships (user_a, user_b)
        values (least(me, target), greatest(me, target))
        on conflict do nothing;
    end if;
end
$$;

-- People the user has blocked. Their profiles aren't otherwise visible once they're not friends.
create function public.my_blocked_users()
returns table (id uuid, name text, color text, photo_path text)
language sql stable security definer set search_path = ''
as $$
    select p.id, p.name, p.color, p.photo_path
    from public.blocks b
    join public.profiles p on p.id = b.blocked_id
    where b.blocker_id = auth.uid()
    order by p.name
$$;

create function public.is_blocked_either_way(a uuid, b uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
    select exists (
        select 1 from public.blocks
        where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a)
    )
$$;

-- MARK: Invites respect blocks

-- Adds `blocked_by_me` so the app can offer to unblock. If the link's owner blocked the
-- viewer, the invite looks like it doesn't exist.
drop function public.invite_preview(text);
create function public.invite_preview(code text)
returns table (id uuid, name text, color text, photo_path text, blocked_by_me boolean)
language sql stable security definer set search_path = ''
as $$
    select p.id, p.name, p.color, p.photo_path,
           exists (select 1 from public.blocks b where b.blocker_id = auth.uid() and b.blocked_id = p.id)
    from public.profiles p
    where p.invite_code = code
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
    if inviter is null or exists (select 1 from public.blocks where blocker_id = inviter and blocked_id = me) then
        raise exception 'This invite isn''t available';
    end if;
    if inviter = me then
        raise exception 'You can''t add yourself';
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
      and not public.are_friends(p.id, me.id)
      and not public.is_blocked_either_way(p.id, me.id)
    order by i.created_at desc
$$;

-- MARK: Permissions

revoke execute on function
    public.block_user(uuid),
    public.unblock_user(uuid),
    public.my_blocked_users(),
    public.is_blocked_either_way(uuid, uuid),
    public.invite_preview(text)
from public, anon, authenticated;

grant execute on function
    public.block_user(uuid),
    public.unblock_user(uuid),
    public.my_blocked_users(),
    public.invite_preview(text)
to authenticated;

-- The invite web page looks up inviters while signed out.
grant execute on function public.invite_preview(text) to anon;
