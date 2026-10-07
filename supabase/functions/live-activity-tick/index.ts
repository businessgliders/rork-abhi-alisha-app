// Runs every five minutes (pg_cron). For each celebration:
//   * from an hour before it starts: raises its Live Activity on every registered phone
//   * at its start time: switches every running one to "Happening now"
//   * after it ends: retires them
//
// Secrets (Edge Functions -> Secrets): APNS_KEY (full .p8 contents), APNS_KEY_ID,
// APNS_TEAM_ID, CRON_SECRET. Deploy with:
//   supabase functions deploy live-activity-tick --no-verify-jwt
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const BUNDLE_ID = "com.businessgliders.abhialisha";
const TOPIC = `${BUNDLE_ID}.push-type.liveactivity`;
const SCHEDULE_URL = "https://aawedding.base44.app/api/entities/ScheduleEvent";
const LEAD_MS = 60 * 60 * 1000;
const DEFAULT_LENGTH_MS = 2 * 60 * 60 * 1000;
// Swift's default Date coding counts seconds from 2001-01-01, not 1970.
const APPLE_EPOCH = 978307200;

type Row = { token: string; kind: string; event_id: string | null; device_id: string | null; environment: string };
type Event = {
  id: string; title: string; startsAt: Date; endsAt: Date | null;
  locationName?: string; dressCode?: string; iconKey: string;
};

Deno.serve(async (req) => {
  const secret = Deno.env.get("CRON_SECRET");
  if (!secret || req.headers.get("x-cron-secret") !== secret) {
    return new Response("forbidden", { status: 403 });
  }

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const now = Date.now();
  const events = await loadEvents();
  const { data: rows } = await db.from("live_activity_tokens").select("token, kind, event_id, device_id, environment");
  const tokens = (rows ?? []) as Row[];
  const { data: logRows } = await db.from("live_activity_log").select("event_id, target, stage");
  const sent = new Set((logRows ?? []).map((r) => `${r.event_id}|${r.target}|${r.stage}`));

  const jwt = await providerToken();
  const report = { start: 0, now: 0, end: 0, removed: 0 };

  for (const event of events) {
    const start = event.startsAt.getTime();
    const end = (event.endsAt ?? new Date(start + DEFAULT_LENGTH_MS)).getTime();
    const updates = tokens.filter((t) => t.kind === "update" && t.event_id === event.id);
    const showing = new Set(updates.map((t) => t.device_id).filter(Boolean));

    // 1. Raise it, an hour ahead, on phones not already showing it.
    if (now >= start - LEAD_MS && now < end) {
      for (const t of tokens.filter((t) => t.kind === "start")) {
        const target = t.device_id ?? t.token;
        if (showing.has(t.device_id) || sent.has(`${event.id}|${target}|start`)) continue;
        const ok = await push(jwt, t, startPayload(event, now >= start ? "now" : "soon", end));
        if (ok === "gone") { await remove(db, t.token); report.removed++; continue; }
        if (ok) { await log(db, event.id, target, "start"); report.start++; }
      }
    }

    // 2. Underway: flip to "Happening now".
    if (now >= start && now < end) {
      for (const t of updates) {
        const target = t.device_id ?? t.token;
        if (sent.has(`${event.id}|${target}|now`)) continue;
        const ok = await push(jwt, t, updatePayload("update", "now", end));
        if (ok === "gone") { await remove(db, t.token); report.removed++; continue; }
        if (ok) { await log(db, event.id, target, "now"); report.now++; }
      }
    }

    // 3. Over: retire it.
    if (now >= end) {
      for (const t of updates) {
        const target = t.device_id ?? t.token;
        if (sent.has(`${event.id}|${target}|end`)) continue;
        const ok = await push(jwt, t, updatePayload("end", "now", end));
        if (ok) { await log(db, event.id, target, "end"); report.end++; }
        await remove(db, t.token);
      }
    }
  }

  return new Response(JSON.stringify(report), { headers: { "Content-Type": "application/json" } });
});

// MARK: - Schedule

async function loadEvents(): Promise<Event[]> {
  const res = await fetch(SCHEDULE_URL, { headers: { Accept: "application/json" } });
  if (!res.ok) return [];
  const raw = await res.json() as Record<string, unknown>[];
  const events: Event[] = [];
  for (const r of raw) {
    if (r.is_active === false) continue;
    const title = String(r.title ?? "").trim();
    const time = String(r.time ?? "").toUpperCase();
    if (!title || title.toLowerCase().includes("thank you")) continue;
    if (time.includes("TBA") || time.includes("TBD")) continue;
    const startsAt = r.starts_at ? new Date(String(r.starts_at)) : null;
    if (!startsAt || isNaN(startsAt.getTime())) continue;
    const endsAt = r.ends_at ? new Date(String(r.ends_at)) : null;
    events.push({
      id: String(r.id),
      title,
      startsAt,
      endsAt: endsAt && !isNaN(endsAt.getTime()) ? endsAt : null,
      locationName: clean(r.location_name),
      dressCode: clean(r.dress_code),
      iconKey: iconKey(clean(r.icon_key), title),
    });
  }
  return events;
}

function clean(value: unknown): string | undefined {
  const text = typeof value === "string" ? value.trim() : "";
  return text ? text : undefined;
}

/** Mirrors the app's EventIconKey.inferred(fromTitle:). */
function iconKey(stored: string | undefined, title: string): string {
  const keys = ["flutes", "paisley", "arch", "mandap", "sparkle", "sun"];
  if (stored && keys.includes(stored.toLowerCase())) return stored.toLowerCase();
  const t = title.toLowerCase();
  const rules: [string[], string][] = [
    [["mehndi", "sangeet", "haldi"], "paisley"],
    [["anand karaj", "sikh", "gurdwara"], "arch"],
    [["phera", "mandap", "hindu", "baraat"], "mandap"],
    [["reception"], "sparkle"],
    [["welcome", "cocktail", "party"], "flutes"],
    [["brunch", "farewell", "thank you", "rest"], "sun"],
  ];
  for (const [words, key] of rules) if (words.some((w) => t.includes(w))) return key;
  return "sparkle";
}

// MARK: - Payloads

const appleTime = (ms: number) => ms / 1000 - APPLE_EPOCH;
const unix = (ms: number) => Math.floor(ms / 1000);

function startPayload(event: Event, phase: "soon" | "now", endMs: number) {
  const attributes: Record<string, unknown> = {
    eventID: event.id,
    title: event.title,
    startsAt: appleTime(event.startsAt.getTime()),
    iconKeyRaw: event.iconKey,
  };
  if (event.endsAt) attributes.endsAt = appleTime(event.endsAt.getTime());
  if (event.locationName) attributes.locationName = event.locationName;
  if (event.dressCode) attributes.dressCode = event.dressCode;

  return {
    aps: {
      timestamp: unix(Date.now()),
      event: "start",
      "attributes-type": "EventFollowAttributes",
      attributes,
      "content-state": { phase },
      "stale-date": unix(endMs),
      alert: {
        title: event.title,
        body: phase === "now" ? "Happening now" : `Begins at ${timeLabel(event.startsAt)}`,
      },
    },
  };
}

function updatePayload(kind: "update" | "end", phase: "soon" | "now", endMs: number) {
  const aps: Record<string, unknown> = {
    timestamp: unix(Date.now()),
    event: kind,
    "content-state": { phase },
    "stale-date": unix(endMs),
  };
  if (kind === "end") aps["dismissal-date"] = unix(Date.now());
  return { aps };
}

function timeLabel(date: Date): string {
  return date.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit", timeZone: "America/Cancun" });
}

// MARK: - APNs

async function push(jwt: string, t: Row, payload: unknown): Promise<boolean | "gone"> {
  const host = t.environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  try {
    const res = await fetch(`https://${host}/3/device/${t.token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-push-type": "liveactivity",
        "apns-topic": TOPIC,
        "apns-priority": "10",
        "content-type": "application/json",
      },
      body: JSON.stringify(payload),
    });
    if (res.ok) return true;
    const reason = (await res.json().catch(() => ({}))).reason ?? "";
    if (res.status === 410 || reason === "BadDeviceToken" || reason === "Unregistered") return "gone";
    console.log("apns", res.status, reason);
    return false;
  } catch (error) {
    console.log("apns unreachable", String(error));
    return false;
  }
}

async function providerToken(): Promise<string> {
  const pem = Deno.env.get("APNS_KEY")!;
  const der = Uint8Array.from(
    atob(pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "")),
    (c) => c.charCodeAt(0),
  );
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const header = b64url(JSON.stringify({ alg: "ES256", kid: Deno.env.get("APNS_KEY_ID") }));
  const claims = b64url(JSON.stringify({ iss: Deno.env.get("APNS_TEAM_ID"), iat: unix(Date.now()) }));
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  return `${header}.${claims}.${b64url(new Uint8Array(signature))}`;
}

function b64url(input: string | Uint8Array): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let text = "";
  bytes.forEach((b) => (text += String.fromCharCode(b)));
  return btoa(text).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// MARK: - Bookkeeping

// deno-lint-ignore no-explicit-any
async function log(db: any, eventID: string, target: string, stage: string) {
  await db.from("live_activity_log").upsert({ event_id: eventID, target, stage });
}

// deno-lint-ignore no-explicit-any
async function remove(db: any, token: string) {
  await db.from("live_activity_tokens").delete().eq("token", token);
}
