// src/lib/supabase/client.ts
import { createBrowserClient } from '@supabase/ssr'

export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  )
}

// ─────────────────────────────────────────────────────
// src/lib/supabase/server.ts
// ─────────────────────────────────────────────────────
// import { createServerClient } from '@supabase/ssr'
// import { cookies } from 'next/headers'
//
// export async function createServerSupabase() {
//   const cookieStore = await cookies()
//   return createServerClient(
//     process.env.NEXT_PUBLIC_SUPABASE_URL!,
//     process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
//     {
//       cookies: {
//         getAll() { return cookieStore.getAll() },
//         setAll(list) {
//           list.forEach(({ name, value, options }) => cookieStore.set(name, value, options))
//         },
//       },
//     }
//   )
// }
