// Tells the recipient's widgets to reload when they get a new note (WidgetKit push).
//
// Triggered by a Supabase Database Webhook on INSERT into public.notes.
// Secrets (Edge Functions → Secrets):
//   APNS_KEY_ID           Key ID of the APNs key (.p8) from developer.apple.com
//   APNS_PRIVATE_KEY      full contents of the .p8 file, including the BEGIN/END lines
//   NOTE_WEBHOOK_SECRET   any long random string; the webhook sends it in `x-webhook-secret`
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided automatically.

import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

const TEAM_ID = "D4BJD4NM7F";
// WidgetKit pushes use the app's bundle ID with this suffix as the topic.
const TOPIC = "com.ahmedshaheen.kelmteen.push-type.widgets";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// Apple accepts a signed token for up to an hour; reuse it to avoid re-signing every push.
let cachedToken: { value: string; createdAt: number } | null = null;

async function apnsToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && now - cachedToken.createdAt < 50 * 60) return cachedToken.value;
  const key = await importPKCS8(Deno.env.get("APNS_PRIVATE_KEY")!, "ES256");
  const value = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: Deno.env.get("APNS_KEY_ID")! })
    .setIssuer(TEAM_ID)
    .setIssuedAt(now)
    .sign(key);
  cachedToken = { value, createdAt: now };
  return value;
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("NOTE_WEBHOOK_SECRET");
  if (!secret || req.headers.get("x-webhook-secret") !== secret) {
    return new Response("Forbidden", { status: 403 });
  }

  const payload = await req.json();
  const note = payload?.record;
  if (payload?.type !== "INSERT" || !note) {
    return new Response("Ignored");
  }

  const { data: devices } = await supabase
    .from("devices")
    .select("user_id, device_id, widget_push_token, apns_sandbox")
    .eq("user_id", note.recipient_id)
    .not("widget_push_token", "is", null);

  const token = await apnsToken();
  const results = await Promise.all((devices ?? []).map(async (device) => {
    const host = device.apns_sandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com";
    const response = await fetch(`https://${host}/3/device/${device.widget_push_token}`, {
      method: "POST",
      headers: {
        "authorization": `bearer ${token}`,
        "apns-push-type": "widgets",
        "apns-topic": TOPIC,
      },
      body: JSON.stringify({ aps: { "content-changed": true } }),
    });

    // The widget was removed or the app deleted; stop pushing to this token.
    if (response.status === 410 || response.status === 400) {
      const reason = await response.text();
      if (response.status === 410 || reason.includes("BadDeviceToken")) {
        await supabase.from("devices")
          .update({ widget_push_token: null })
          .eq("user_id", device.user_id)
          .eq("device_id", device.device_id);
      }
      return `${response.status} ${reason}`;
    }
    return `${response.status}`;
  }));

  return new Response(JSON.stringify(results));
});
