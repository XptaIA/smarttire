// src/app/page.tsx — Redirect root to /inicio
import { redirect } from 'next/navigation'
export default function RootPage() {
  redirect('/inicio')
}
