-- Changing your phone number.
--
-- The app asks Supabase Auth to change the number, which texts a code to the NEW number.
-- Once that code is verified, auth.users has the new number; this copies it into the
-- profile (and its hash) so friends' contact matching finds the user by their new number.

create function public.sync_profile_phone()
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

    update public.profiles
    set phone = user_phone,
        phone_hash = encode(extensions.digest(user_phone, 'sha256'), 'hex')
    where id = auth.uid()
    returning * into result;

    if result.id is null then
        raise exception 'Create a profile first';
    end if;
    return result;
end
$$;

revoke all on function public.sync_profile_phone() from public, anon;
grant execute on function public.sync_profile_phone() to authenticated;
