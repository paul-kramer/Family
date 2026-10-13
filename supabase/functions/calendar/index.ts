// Familienzeit: holt den iCloud-Kalender auf Anfrage frisch ab.
// Nur wer den Familien-Schlüssel aus dem App-Link kennt, bekommt Termine.
// Benötigtes Secret: ICAL_URL (öffentlicher iCloud-Link, webcal://… oder https://…)
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

// Alte Einzeltermine weglassen, damit die Antwort klein bleibt.
// Wiederkehrende Termine (RRULE) bleiben immer drin.
function trimIcs(ics: string, keepFromYmd: string): string {
  const parts = ics.split(/(?=BEGIN:VEVENT)/);
  const out: string[] = [];
  for (const p of parts) {
    if (!p.startsWith("BEGIN:VEVENT")) { out.push(p); continue; }
    const end = p.indexOf("END:VEVENT");
    const ev = end >= 0 ? p.slice(0, end + "END:VEVENT".length) : p;
    const rest = end >= 0 ? p.slice(end + "END:VEVENT".length) : "";
    const isRecurring = /\nRRULE[:;]/.test(ev);
    const m = ev.match(/\nDTSTART[^:\n]*:(\d{8})/);
    if (isRecurring || !m || m[1] >= keepFromYmd) out.push(ev);
    out.push(rest);
  }
  return out.join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Nur POST" }, 405);

  let key = "";
  try {
    key = String((await req.json()).key || "");
  } catch {
    return json({ error: "Ungültige Anfrage" }, 400);
  }
  if (key.length < 16) return json({ error: "Schlüssel fehlt" }, 401);

  // Familie prüfen: fz_load liefert nur mit gültigem Schlüssel etwas zurück.
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!);
  const today = new Date().toISOString().slice(0, 10);
  const { data, error } = await sb.rpc("fz_load", { p_key: key, p_from: today, p_to: today });
  if (error) return json({ error: "Datenbank nicht erreichbar" }, 502);
  if (data === null) return json({ error: "Unbekannte Familie" }, 401);

  const raw = (Deno.env.get("ICAL_URL") || "").trim();
  if (!raw) return json({ error: "ICAL_URL ist nicht eingerichtet" }, 500);
  const url = raw.replace(/^webcal:\/\//i, "https://");

  const res = await fetch(url, { headers: { "User-Agent": "familienzeit-calendar" } });
  if (!res.ok) return json({ error: `iCloud antwortet mit ${res.status}` }, 502);
  const ics = await res.text();
  if (!ics.includes("BEGIN:VCALENDAR")) return json({ error: "Antwort ist kein Kalender" }, 502);

  const from = new Date(Date.now() - 30 * 864e5).toISOString().slice(0, 10).replace(/-/g, "");
  return json({ ics: trimIcs(ics, from), fetched: new Date().toISOString() });
});
