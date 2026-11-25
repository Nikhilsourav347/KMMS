import { createClient } from "npm:@supabase/supabase-js@2.89.0";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Content-Type": "application/json",
};

const respond = (status: number, body: object) =>
  new Response(JSON.stringify(body), { status, headers });

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers });
  if (request.method !== "POST") return respond(405, { message: "Use POST." });

  const token = request.headers.get("authorization")?.match(/^Bearer (.+)$/i)?.[1];
  const url = Deno.env.get("SUPABASE_URL");
  const projectKeys = Deno.env.get("SUPABASE_SECRET_KEYS");
  const secret = (projectKeys ? JSON.parse(projectKeys).default : undefined) ||
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !secret) return respond(503, { message: "Staff provisioning is unavailable." });
  if (!token) return respond(401, { message: "Sign in again." });

  const service = createClient(url, secret, { auth: { persistSession: false, autoRefreshToken: false } });
  // Never use an unverified request claim to grant access to the admin client.
  const { data: { user }, error: tokenError } = await service.auth.getUser(token);
  if (tokenError || !user) return respond(401, { message: "Sign in again." });
  const { data: profile, error: profileError } = await service
    .from("profiles").select("role, disabled_at").eq("id", user.id).maybeSingle();
  if (profileError || profile?.role !== "admin" || profile.disabled_at !== null) {
    return respond(403, { message: "Administrator access is required." });
  }

  let input: Record<string, unknown>;
  try {
    const body = await request.text();
    if (body.length > 2048) return respond(413, { message: "Account details are too long." });
    input = JSON.parse(body);
    if (!input || typeof input !== "object" || Array.isArray(input)) throw new Error();
  } catch {
    return respond(400, { message: "Invalid account details." });
  }

  const { role, password } = input;
  const name = typeof input.name === "string" ? input.name.trim() : "";
  const email = typeof input.email === "string" ? input.email.trim().toLowerCase() : "";
  const phone = typeof input.phone === "string" ? input.phone.trim() : "";
  if ((role !== "admin" && role !== "manager") || !name || name.length > 120 ||
      !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || email.length > 254 ||
      typeof password !== "string" || password.length < 12 || password.length > 72 ||
      phone.length > 40) {
    return respond(400, { message: "Enter a valid name, email, role and password of 12–72 characters." });
  }

  const { data: account, error: creationError } = await service.auth.admin.createUser({
    email, password, email_confirm: true,
  });
  if (creationError || !account.user) return respond(400, { message: "Could not create the account. Check the email and password." });
  const { error: insertError } = await service.from("profiles").insert({
    id: account.user.id, full_name: name, role, phone,
  });
  if (insertError) {
    await service.auth.admin.deleteUser(account.user.id);
    return respond(500, { message: "Could not create the staff profile." });
  }
  return respond(201, { created: true });
});
