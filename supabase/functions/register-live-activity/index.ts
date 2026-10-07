// Stores a phone's Live Activity token. Called by the app with no sign-in, so deploy
// with: supabase functions deploy register-live-activity --no-verify-jwt
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const HEX = /^[0-9a-f]{32,400}$/;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method" }, 405);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "body" }, 400);
  }

  const token = String(body.token ?? "").toLowerCase();
  const kind = String(body.kind ?? "");
  const eventID = body.event_id ? String(body.event_id).slice(0, 120) : null;
  const deviceID = body.device_id ? String(body.device_id).slice(0, 80) : null;
  const environment = body.environment === "sandbox" ? "sandbox" : "production";

  if (!HEX.test(token) || (kind !== "start" && kind !== "update")) {
    return json({ error: "invalid" }, 400);
  }
  if (kind === "update" && !eventID) return json({ error: "event_id" }, 400);

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // A phone has one push-to-start token at a time: retire the old one.
  if (kind === "start" && deviceID) {
    await db.from("live_activity_tokens").delete()
      .eq("kind", "start").eq("device_id", deviceID).neq("token", token);
  }

  const { error } = await db.from("live_activity_tokens").upsert({
    token,
    kind,
    event_id: eventID,
    device_id: deviceID,
    environment,
    updated_at: new Date().toISOString(),
  });
  if (error) return json({ error: "store" }, 500);
  return json({ ok: true });
});

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
