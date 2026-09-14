# ELshori7y deployment

## Cloudflare Pages — main app
- Root directory: `main-app`
- Build command: `npm run build`
- Output directory: `dist`
- Variables: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`

## Cloudflare Pages — admin
Create a second Pages project from the same repository:
- Root directory: `admin-app`
- Build command: `npm run build`
- Output directory: `dist`
- Same two public Supabase variables.

## Supabase
The database has already been created for this project. The repository keeps the original migration files separately when available; the current runtime additions are in `supabase/migrations/003_runtime.sql`.

Run `003_runtime.sql` if the two RPCs are missing. Then create/confirm your first account and promote it manually:
`update public.profiles set role='admin' where id='YOUR_USER_UUID';`

## Edge Functions
Deploy the four folders under `supabase/functions/` and set these Supabase secrets:
- `SUPABASE_SERVICE_ROLE_KEY`
- `LIVEKIT_API_KEY`
- `LIVEKIT_API_SECRET`
- `LIVEKIT_URL`

Never put service-role or LiveKit secrets in Cloudflare/browser environment variables.

## Important
The current public app in `main-app` is the lightweight production chat shell: auth, verified-user search, direct conversations, realtime messages and read receipts. Voice/video is prepared server-side through `mint-call-token` but requires LiveKit configuration.
