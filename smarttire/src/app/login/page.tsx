'use client'
// src/app/login/page.tsx
import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'

export default function LoginPage() {
  const [email, setEmail]       = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading]   = useState(false)
  const [error, setError]       = useState<string | null>(null)
  const router   = useRouter()
  const supabase = createClient()

  async function handleLogin(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    setError(null)
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) {
      setError('Correo o contraseña incorrectos.')
      setLoading(false)
    } else {
      router.push('/inicio')
      router.refresh()
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center px-4"
         style={{ background: '#fefcf5' }}>
      <div className="w-full max-w-sm">

        {/* Logo */}
        <div className="text-center mb-8">
          <h1 className="text-2xl font-bold tracking-tight" style={{ color: '#14130a' }}>
            SmartTire <span style={{ color: '#d67200' }}>IA.Xpta</span>
          </h1>
          <p className="text-sm mt-1" style={{ color: '#939188' }}>Gestión técnica de llantas</p>
        </div>

        {/* Card */}
        <div className="rounded-2xl p-6 border"
             style={{ background: '#fff', borderColor: '#ccc8b4' }}>
          <form onSubmit={handleLogin} className="space-y-4">

            <div>
              <label className="block text-xs font-semibold mb-1.5" style={{ color: '#2d2c22' }}>
                Correo electrónico
              </label>
              <input
                type="email"
                value={email}
                onChange={e => setEmail(e.target.value)}
                required
                placeholder="usuario@empresa.com"
                className="w-full px-3 py-3 rounded-lg border text-sm outline-none transition-colors"
                style={{ borderColor: '#ccc8b4', background: '#fefcf5' }}
              />
            </div>

            <div>
              <label className="block text-xs font-semibold mb-1.5" style={{ color: '#2d2c22' }}>
                Contraseña
              </label>
              <input
                type="password"
                value={password}
                onChange={e => setPassword(e.target.value)}
                required
                placeholder="••••••••"
                className="w-full px-3 py-3 rounded-lg border text-sm outline-none"
                style={{ borderColor: '#ccc8b4', background: '#fefcf5' }}
              />
            </div>

            {error && (
              <div className="px-3 py-2.5 rounded-lg text-xs"
                   style={{ background: '#fce5e5', color: '#881616', border: '1px solid #e49090' }}>
                {error}
              </div>
            )}

            <button
              type="submit"
              disabled={loading}
              className="w-full py-3 rounded-lg text-sm font-semibold text-white transition-opacity"
              style={{ background: loading ? '#939188' : '#14130a' }}
            >
              {loading ? 'Ingresando...' : 'Ingresar'}
            </button>
          </form>

          {/* Nota de prueba */}
          <div className="mt-4 px-3 py-2.5 rounded-lg text-xs"
               style={{ background: '#e2f3e8', color: '#18580a', border: '1px solid #7ec852' }}>
            <strong>Datos de prueba:</strong><br />
            inspector@demo.com / Demo2024!<br />
            analista@demo.com / Demo2024!
          </div>
        </div>
      </div>
    </div>
  )
}
