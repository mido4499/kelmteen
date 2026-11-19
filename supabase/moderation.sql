-- Kelmteen moderation commands. Run these one at a time in Supabase → SQL Editor.
-- Replace the placeholder IDs ('REPORT_ID', 'USER_ID') before running.
--
-- Apple expects reports to be handled promptly (aim for within 24 hours).


-- 1. Open reports, newest first. `evidence_photo_path` is in the private
--    `report-evidence` bucket (Storage → report-evidence) if the person had a photo.
select r.id, r.created_at, r.reason, r.details,
       r.reported_id, r.reported_name, r.reported_phone, r.evidence_photo_path,
       reporter.name as reporter_name,
       (select count(*) from public.reports o where o.reported_id = r.reported_id) as total_reports_against
from public.reports r
left join public.profiles reporter on reporter.id = r.reporter_id
where r.status = 'open'
order by r.created_at desc;


-- 2. Everything reported about one person.
select created_at, reason, details, status, moderator_note
from public.reports
where reported_id = 'USER_ID'
order by created_at desc;


-- 3a. Remove someone's profile photo (they can upload a new one).
--     Afterwards, delete the old file in Storage → avatars → <their USER_ID folder>.
update public.profiles set photo_path = null where id = 'USER_ID';


-- 3b. Suspend an account. They vanish from friends' lists, contacts and invites, and can't
--     send notes or add anyone. The app shows them a "suspended" screen with the contact email.
update public.profiles set suspended_at = now() where id = 'USER_ID';

-- 3c. Lift a suspension.
update public.profiles set suspended_at = null where id = 'USER_ID';

-- 3d. Delete an account permanently (profile, friendships, invites, notes, blocks).
--     Also delete their folder in Storage → avatars.
delete from auth.users where id = 'USER_ID';


-- 4. Close a report once handled.
update public.reports
set status = 'actioned',          -- or 'dismissed' if no action was needed
    moderator_note = 'Suspended for offensive photo',
    reviewed_at = now()
where id = 'REPORT_ID';
