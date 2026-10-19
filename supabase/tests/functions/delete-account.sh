#!/bin/bash
# Integration test for the delete-account Edge Function against the LOCAL stack.
# Uses only throwaway local dev keys from `supabase status`.
#
#   npx supabase start
#   npx supabase functions serve --no-verify-jwt   (in another terminal)
#   bash supabase/tests/functions/delete-account.sh
set -euo pipefail
cd "$(dirname "$0")/../../.."

API=http://127.0.0.1:54321
STATUS=$(npx --yes supabase@2.121.0 status -o json 2>/dev/null)
SECRET=$(echo "$STATUS" | python3 -c "import json,sys;print(json.load(sys.stdin)['SECRET_KEY'])")
PUBLISHABLE=$(echo "$STATUS" | python3 -c "import json,sys;print(json.load(sys.stdin)['PUBLISHABLE_KEY'])")
PSQL="psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -tAc"
EMAIL="delete$RANDOM@test.local"
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (expected $3, got $2)"; fail=1; fi; }

USER_ID=$(curl -s -X POST "$API/auth/v1/admin/users" -H "apikey: $SECRET" -H "Authorization: Bearer $SECRET" \
  -H "Content-Type: application/json" -d "{\"email\":\"$EMAIL\",\"password\":\"Test-pass-123\",\"email_confirm\":true}" \
  | python3 -c "import json,sys;print(json.load(sys.stdin)['id'])")
JWT=$(curl -s -X POST "$API/auth/v1/token?grant_type=password" -H "apikey: $PUBLISHABLE" \
  -H "Content-Type: application/json" -d "{\"email\":\"$EMAIL\",\"password\":\"Test-pass-123\"}" \
  | python3 -c "import json,sys;print(json.load(sys.stdin)['access_token'])")
AUTH="Authorization: Bearer $JWT"

code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/rest/v1/profiles" -H "apikey: $PUBLISHABLE" -H "$AUTH" \
  -H "Content-Type: application/json" -d "{\"id\":\"$USER_ID\",\"nickname\":\"del$RANDOM\"}")
check "user creates own profile" "$code" 201
code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/storage/v1/object/avatars/$USER_ID/avatar.jpg" \
  -H "apikey: $PUBLISHABLE" -H "$AUTH" -H "Content-Type: image/jpeg" --data-binary "fake")
check "user uploads avatar into own folder" "$code" 200
code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/storage/v1/object/avatars/00000000-0000-0000-0000-000000000000/x.jpg" \
  -H "apikey: $PUBLISHABLE" -H "$AUTH" -H "Content-Type: image/jpeg" --data-binary "fake")
check "user cannot upload into a foreign folder" "$code" 400

check "missing credentials rejected" "$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/functions/v1/delete-account")" 401
check "garbage credentials rejected" "$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/functions/v1/delete-account" -H "Authorization: Bearer nonsense")" 401
check "GET rejected" "$(curl -s -o /dev/null -w "%{http_code}" "$API/functions/v1/delete-account" -H "$AUTH")" 405
check "valid request deletes" "$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/functions/v1/delete-account" -H "$AUTH")" 200

check "auth user removed" "$($PSQL "select count(*) from auth.users where id='$USER_ID'")" 0
check "profile removed" "$($PSQL "select count(*) from public.profiles where id='$USER_ID'")" 0
check "avatar removed" "$($PSQL "select count(*) from storage.objects where name like '$USER_ID/%'")" 0
exit $fail
