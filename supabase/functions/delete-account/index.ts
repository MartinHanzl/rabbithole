// Deletes the calling user's account (App Store requirement: deletion inside the app).
//
// Removes the user's avatar files, then the auth user. Every table references
// profiles/auth.users with ON DELETE CASCADE, so profile, topics, friendships, blocks,
// shares, messages and saved articles go with it. Reports filed by the user are kept
// for moderation with reporter_id set to NULL.
//
// The caller is identified from their access token here (verify_jwt is off in
// config.toml), so a request can only ever delete its own account.
import { createClient } from "npm:@supabase/supabase-js@2.117.2";

const json = (body: unknown, status: number) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "unauthorized" }, 401);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const { data: { user }, error: userError } = await admin.auth.getUser(token);
  if (userError || !user) return json({ error: "unauthorized" }, 401);

  const avatars = admin.storage.from("avatars");
  const { data: files, error: listError } = await avatars.list(user.id, { limit: 1000 });
  if (listError) {
    console.error("list avatars failed", listError.message);
    return json({ error: "storage_failed" }, 500);
  }
  if (files.length > 0) {
    const { error: removeError } = await avatars.remove(files.map((file) => `${user.id}/${file.name}`));
    if (removeError) {
      console.error("remove avatars failed", removeError.message);
      return json({ error: "storage_failed" }, 500);
    }
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) {
    console.error("delete user failed", deleteError.message);
    return json({ error: "delete_failed" }, 500);
  }

  return json({ deleted: true }, 200);
});
