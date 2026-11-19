// Permanently deletes the calling user's account and all of their data.
//
// Called from the app (Me → Delete Account) with the user's session, so Supabase verifies
// who is asking. Keep "Verify JWT" ON for this function.
// SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are provided automatically.
//
// Deleting the auth user cascades in the database to: profile, friendships, invites they
// sent, notes, devices and blocks. This function also removes what the cascade can't reach:
// storage files, invites other people sent to their number, and reports about or by them.

import { createClient } from "npm:@supabase/supabase-js@2";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req) => {
  const token = req.headers.get("Authorization")?.replace("Bearer ", "");
  const { data: { user } } = await admin.auth.getUser(token ?? "");
  if (!user) {
    return new Response("Not signed in", { status: 401 });
  }
  const userID = user.id;

  try {
    // Profile photos (every file in their folder).
    const { data: photos } = await admin.storage.from("avatars").list(userID, { limit: 1000 });
    if (photos?.length) {
      await admin.storage.from("avatars").remove(photos.map((file) => `${userID}/${file.name}`));
    }

    // Reports about them, including the evidence photo copies, and reports they filed.
    const { data: reportsAbout } = await admin
      .from("reports").select("evidence_photo_path").eq("reported_id", userID);
    const evidence = (reportsAbout ?? [])
      .map((report) => report.evidence_photo_path)
      .filter((path): path is string => !!path);
    if (evidence.length) {
      await admin.storage.from("report-evidence").remove(evidence);
    }
    await admin.from("reports").delete().or(`reported_id.eq.${userID},reporter_id.eq.${userID}`);

    // Invites other people sent to their phone number.
    const { data: profile } = await admin
      .from("profiles").select("phone_hash").eq("id", userID).maybeSingle();
    if (profile?.phone_hash) {
      await admin.from("pending_invites").delete().eq("invitee_phone_hash", profile.phone_hash);
    }

    // Finally the account itself; the database cascade removes the rest.
    const { error } = await admin.auth.admin.deleteUser(userID);
    if (error) throw error;

    return new Response("Deleted");
  } catch (error) {
    console.error("Account deletion failed", userID, error);
    return new Response("Deletion failed", { status: 500 });
  }
});
