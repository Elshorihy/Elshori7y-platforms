# ELshori7y — ready-to-deploy starter

This package turns the supplied Chat/Calls/Admin module into a standalone web app.
It contains:
- `main-app/`: public React/Vite site with auth, chat, realtime presence and call UI.
- `admin-app/`: separate React/Vite admin dashboard.
- `supabase/`: database migrations and protected Edge Functions.

## Required external accounts
1. Supabase project (database/auth/realtime/functions).
2. LiveKit Cloud project only if voice/video calls are required.

No service-role key or LiveKit secret belongs in the browser.

## Database
Run in Supabase SQL Editor in this order:
1. `supabase/migrations/001_base.sql`
2. `supabase/migrations/002_chat_calls_admin.sql`

Then promote your own confirmed user to admin:
`update public.profiles set role='admin' where id='YOUR-USER-UUID';`

## Edge Functions
Set secrets in Supabase:
- SUPABASE_SERVICE_ROLE_KEY
- LIVEKIT_API_KEY
- LIVEKIT_API_SECRET
- LIVEKIT_URL

Deploy the four folders under `supabase/functions/`.

## Main app
Copy `main-app/.env.example` to `main-app/.env`, fill Supabase URL and anon key, then:
`npm install`
`npm run build`

Deploy the `main-app` directory as a Vite static site. Build command: `npm run build`; output: `dist`.

## Admin
Copy `admin-app/.env.example` to `admin-app/.env`, fill the same Supabase URL and anon key, then:
`npm install`
`npm run build`

Deploy `admin-app` separately. It should not be linked from the public navigation.

## Important
This is a functional standalone chat shell built from the supplied module. It does not contain the original ELshori7y dashboard/study/project screens because those source files were not included in the supplied ZIP.

Before public launch, test RLS, auth email confirmation, abuse/reporting, and call permissions with two separate user accounts.
