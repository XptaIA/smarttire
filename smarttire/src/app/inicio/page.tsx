'use client'
// src/app/inicio/page.tsx
import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/client'
import type { Profile, Vehicle } from '@/types'

export default function InicioPage() {
  const [profile, setProfile]   = useState<Profile | null>(null)
  const [vehicles, setVehicles] = useState<Vehicle[]>([])
  const [loading, setLoading]   = useState(true)
  const router   = useRouter()
  const supabase = createClient()

  useEffect(() => {
    async function load() {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) { router.push('/login'); return }

      const { data: prof } = await supabase
        .from('profiles').select('*').eq('id', user.id).single()
      setProfile(prof)

      const { data: vehs } = await supabase
        .from('vehicles')
        .select('*, fleet:fleets(name)')
        .eq('is_active', true)
        .limit(10)
      setVehicles(vehs ?? [])
      setLoading(false)
    }
    load()
  }, [])

  async function handleLogout() {
    await supabase.auth.signOut()
    router.push('/login')
  }

  const hour     = new Date().getHours()
  const greeting = hour < 12 ? 'Buenos días' : hour < 18 ? 'Buenas tardes' : 'Buenas noches'

  if (loading) return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="text-sm" style={{ color: '#939188' }}>Cargando...</div>
    </div>
  )

  return (
    <div className="min-h-screen" style={{ background: '#fafaf7' }}>

      {/* Header */}
      <div className="px-4 py-4 flex items-center justify-between border-b"
           style={{ background: '#14130a', borderColor: '#2d2c22' }}>
        <div>
          <div className="text-sm font-bold" style={{ color: '#fff' }}>
            SmartTire <span style={{ color: '#f2c038' }}>IA.Xpta</span>
          </div>
          <div className="text-xs mt-0.5" style={{ color: 'rgba(255,255,255,.5)' }}>
            {profile?.full_name}
          </div>
        </div>
        <button
          onClick={handleLogout}
          className="text-xs px-3 py-1.5 rounded-lg"
          style={{ background: 'rgba(255,255,255,.1)', color: 'rgba(255,255,255,.7)' }}
        >
          Salir
        </button>
      </div>

      <div className="px-4 py-5 max-w-lg mx-auto">

        {/* Saludo */}
        <h2 className="text-lg font-bold mb-4" style={{ color: '#14130a' }}>
          {greeting}, {profile?.full_name?.split(' ')[0]}
        </h2>

        {/* Acciones principales */}
        <div className="grid grid-cols-2 gap-3 mb-6">
          <Link href="/revisiones/nueva"
            className="flex flex-col items-center justify-center py-5 rounded-xl border text-center"
            style={{ background: '#14130a', borderColor: '#14130a', color: '#fff' }}>
            <span className="text-2xl mb-1.5">📋</span>
            <span className="text-sm font-semibold">Registrar</span>
            <span className="text-xs mt-0.5" style={{ color: 'rgba(255,255,255,.6)' }}>revisión</span>
          </Link>

          <Link href="/montajes"
            className="flex flex-col items-center justify-center py-5 rounded-xl border text-center"
            style={{ background: '#d67200', borderColor: '#d67200', color: '#fff' }}>
            <span className="text-2xl mb-1.5">🔧</span>
            <span className="text-sm font-semibold">Registrar</span>
            <span className="text-xs mt-0.5" style={{ color: 'rgba(255,255,255,.7)' }}>montaje</span>
          </Link>
        </div>

        {/* Vehículos de la flota */}
        <div className="mb-2 flex items-center justify-between">
          <span className="text-xs font-semibold uppercase tracking-wide" style={{ color: '#939188' }}>
            Vehículos disponibles
          </span>
          <span className="text-xs" style={{ color: '#939188' }}>{vehicles.length} activos</span>
        </div>

        <div className="space-y-2">
          {vehicles.map(v => (
            <div key={v.id}
              className="flex items-center justify-between px-4 py-3 rounded-xl border"
              style={{ background: '#fff', borderColor: '#e8e5d8' }}>
              <div>
                <div className="text-sm font-bold" style={{ color: '#14130a' }}>{v.plate}</div>
                <div className="text-xs mt-0.5" style={{ color: '#939188' }}>
                  {v.brand} {v.model} · {(v.odometer_current ?? 0).toLocaleString()} km
                </div>
              </div>
              <div className="flex gap-2">
                <Link href={`/revisiones/nueva?vehicleId=${v.id}`}
                  className="text-xs px-2.5 py-1.5 rounded-lg font-semibold"
                  style={{ background: '#e5f1dc', color: '#18580a' }}>
                  Revisar
                </Link>
                <Link href={`/montajes?vehicleId=${v.id}`}
                  className="text-xs px-2.5 py-1.5 rounded-lg font-semibold"
                  style={{ background: '#fef3dd', color: '#935100' }}>
                  Montar
                </Link>
              </div>
            </div>
          ))}
        </div>

        {vehicles.length === 0 && (
          <div className="text-center py-8 text-sm" style={{ color: '#939188' }}>
            No hay vehículos registrados.
          </div>
        )}
      </div>
    </div>
  )
}
