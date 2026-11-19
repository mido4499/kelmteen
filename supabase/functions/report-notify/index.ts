// Emails the moderator about each new report and saves a private copy of the reported
// person's photo as evidence (so it survives them changing or deleting it).
//
// Triggered by a Supabase Database Webhook on INSERT into public.reports.
// Secrets (Edge Functions → Secrets):
//   RESEND_API_KEY         API key from resend.com
//   REPORT_WEBHOOK_SECRET  any long random string; the webhook sends it in `x-webhook-secret`
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided automatically.

import { createClient } from "npm:@supabase/supabase-js@2";

const NOTIFY_EMAIL = "ahmedwael4499@gmail.com";
// Resend's shared test sender only delivers to the email that owns the Resend account.
// Once a domain is verified in Resend, switch to e.g. "Kelmteen <reports@ahmedshaheen.com>".
const FROM = "Kelmteen Reports <onboarding@resend.dev>";

const REASONS: Record<string, string> = {
  inappropriate_photo: "Inappropriate photo",
  harassment: "Harassment or offensive notes",
  spam: "Spam or fake account",
  other: "Something else",
};

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req) => {
  const secret = Deno.env.get("REPORT_WEBHOOK_SECRET");
  if (!secret || req.headers.get("x-webhook-secret") !== secret) {
    return new Response("Forbidden", { status: 403 });
  }

  const payload = await req.json();
  const report = payload?.record;
  if (payload?.type !== "INSERT" || !report) {
    return new Response("Ignored");
  }

  // Keep the reported photo as evidence in the private bucket.
  let evidenceLink = "No photo";
  if (report.reported_photo_path) {
    const evidencePath = `${report.id}.jpg`;
    const { data: photo } = await supabase.storage.from("avatars").download(report.reported_photo_path);
    if (photo) {
      const { error } = await supabase.storage
        .from("report-evidence")
        .upload(evidencePath, photo, { contentType: "image/jpeg", upsert: true });
      if (!error) {
        await supabase.from("reports").update({ evidence_photo_path: evidencePath }).eq("id", report.id);
        const { data: signed } = await supabase.storage
          .from("report-evidence")
          .createSignedUrl(evidencePath, 60 * 60 * 24 * 7);
        evidenceLink = signed?.signedUrl ?? `Storage → report-evidence → ${evidencePath}`;
      }
    }
  }

  const { data: reporter } = await supabase
    .from("profiles").select("name").eq("id", report.reporter_id).maybeSingle();
  const { count } = await supabase
    .from("reports").select("id", { count: "exact", head: true }).eq("reported_id", report.reported_id);

  const text = [
    `New report: ${REASONS[report.reason] ?? report.reason}`,
    "",
    `Reported: ${report.reported_name} (${report.reported_phone})`,
    `User ID: ${report.reported_id}`,
    `Reports against them so far: ${count ?? "?"}`,
    `Reported by: ${reporter?.name ?? "Unknown"}`,
    "",
    `Details: ${report.details ?? "(none)"}`,
    `Photo (link valid 7 days): ${evidenceLink}`,
    "",
    `Report ID: ${report.id}`,
    "Act on it with the commands in supabase/moderation.sql.",
  ].join("\n");

  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${Deno.env.get("RESEND_API_KEY")}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: FROM,
      to: [NOTIFY_EMAIL],
      subject: `Kelmteen report: ${report.reported_name} (${REASONS[report.reason] ?? report.reason})`,
      text,
    }),
  });

  if (!response.ok) {
    console.error("Resend error", response.status, await response.text());
    return new Response("Email failed", { status: 502 });
  }
  return new Response("OK");
});
