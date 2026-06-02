'use client'
// src/app/montajes/page.tsx
// M-MON: Flujo completo de registro de montaje

import { useEffect, useState } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import type { Vehicle, AxlePosition, Tire, TreadAnalysis } from '@/types'

type Step = 'select_vehicle' | 'select_position' | 'select_tire' | 'analysis' | 'confirm'

const WARNING_STYLES = {
  none:     { bg: '#e2ecf9', color: '#0b4674', border: '#7ab0e4', label: 'Sin diferencia notable' },
  advisory: { bg: '#e2ecf9', color: '#0b4674', border: '#7ab0e4', label: 'Diferencia leve' },
  warning:  { bg: '#fef3dd', color: '#935100', border: '#f2c038', label: 'Advertencia técnica' },
  critical: { bg: '#fce5e5', color: '#881616', border: '#e49090', label: 'Advertencia crítica' },
}

export default function MontajesPage() {
  const supabase     = createClient()
  const router       = useRouter()
  const searchParams = useSearchParams()

  const [step, setStep]         = useState<Step>('select_vehicle')
  const [vehicles, setVehicles] = useState<Vehicle[]>([])
  const [selVehicle, setSelVehicle] = useState<Vehicle | null>(null)
  const [positions, setPositions] = useState<AxlePosition[]>([])
  const [occupiedIds, setOccupiedIds] = useState<Set<string>>(new Set())
  const [selPosition, setSelPosition] = useState<AxlePosition | null>(null)
  const [availTires, setAvailTires] = useState<Tire[]>([])
  const [selTire, setSelTire]     = useState<Tire | null>(null)
  const [odometer, setOdometer]   = useState('')
  const [analysis, setAnalysis]   = useState<TreadAnalysis | null>(null)
  const [analysisLoading, setAnalysisLoading] = useState(false)
  const [saving, setSaving]       = useState(false)
  const [currentUser, setCurrentUser] = useState<string | null>(null)
  const [tenantId, setTenantId]   = useState<string | null>(null)

  useEffect(() => {
    async function init() {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) { router.push('/login'); return }
      setCurrentUser(user.id)

      const { data: prof } = await supabase.from('profiles').select('tenant_id').eq('id', user.id).single()
      setTenantId(prof?.tenant_id ?? null)

      const { data: vehs } = await supabase
        .from('vehicles').select('*, fleet:fleets(name)')
        .eq('is_active', true).order('plate')
      setVehicles(vehs ?? [])

      const preVehicleId = searchParams.get('vehicleId')
      if (preVehicleId && vehs) {
        const found = vehs.find((v: Vehicle) => v.id === preVehicleId)
        if (found) { await selectVehicle(found) }
      }
    }
    init()
  }, [])

  async function selectVehicle(v: Vehicle) {
    setSelVehicle(v)
    setOdometer(String(v.odometer_current))

    const { data: pos } = await supabase
      .from('axle_positions').select('*').eq('vehicle_id', v.id).order('sort_order')

    // Posiciones ocupadas
    const { data: activeMountings } = await supabase
      .from('mountings').select('position_id').eq('vehicle_id', v.id).eq('is_active', true)

    setOccupiedIds(new Set(activeMountings?.map((m: {position_id: string}) => m.position_id) ?? []))
    setPositions(pos ?? [])
    setStep('select_position')
  }

  async function selectPosition(p: AxlePosition) {
    setSelPosition(p)
    // Cargar llantas en bodega
    const { data: tires } = await supabase
      .from('tires')
      .select('*, brand:brands(name), model:tire_models(*)')
      .eq('tenant_id', tenantId!)
      .eq('status', 'warehouse')
      .order('serial_number')

    setAvailTires(tires ?? [])
    setStep('select_tire')
  }

  async function selectTire(t: Tire) {
    setSelTire(t)
    setAnalysisLoading(true)
    setStep('analysis')

    // Análisis de diferencia de labrado
    try {
      const res = await fetch('/api/tread-analysis', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          tireId:     t.id,
          positionId: selPosition!.id,
          vehicleId:  selVehicle!.id,
        }),
      })
      const data = await res.json()
      setAnalysis(data)
    } catch {
      setAnalysis({
        warningLevel: 'none', differencesMm: null, mountingTreadMm: null,
        companionTreadMm: null, companionTireId: null, companionSerialNumber: null,
        impactText: null, requiresApproval: false,
      })
    } finally {
      setAnalysisLoading(false)
    }
  }

  async function confirmMount() {
    if (!selVehicle || !selPosition || !selTire || !currentUser || !tenantId) return
    setSaving(true)
    try {
      // Crear mounting
      await supabase.from('mountings').insert({
        tenant_id:          tenantId,
        tire_id:            selTire.id,
        vehicle_id:         selVehicle.id,
        position_id:        selPosition.id,
        mount_date:         new Date().toISOString().split('T')[0],
        mount_odometer:     parseInt(odometer),
        mount_depth_mm:     selTire.current_depth_min_mm,
        mounted_by:         currentUser,
        tread_warning_level: analysis?.warningLevel ?? 'none',
        tread_difference_mm: analysis?.differencesMm ?? null,
      })

      // Evento de ciclo de vida
      await supabase.from('tire_events').insert({
        tenant_id:   tenantId,
        tire_id:     selTire.id,
        vehicle_id:  selVehicle.id,
        position_id: selPosition.id,
        event_type:  'mount',
        event_date:  new Date().toISOString().split('T')[0],
        odometer:    parseInt(odometer),
        performed_by: currentUser,
        metadata: { tread_warning: analysis?.warningLevel ?? 'none' },
      })

      // Actualizar odómetro
      await supabase.from('vehicles')
        .update({ odometer_current: parseInt(odometer) })
        .eq('id', selVehicle.id)

      router.push('/inicio?mounted=1')
    } catch (e) {
      console.error(e)
      alert('Error al registrar el montaje.')
    } finally {
      setSaving(false)
    }
  }

  // ═══════════════════════════════════════════
  // PANTALLAS
  // ═══════════════════════════════════════════

  // P1: Seleccionar vehículo
  if (step === 'select_vehicle') return (
    <Screen title="Registrar montaje" subtitle="Seleccionar vehículo"
            onBack={() => router.push('/inicio')}>
      <div className="space-y-2">
        {vehicles.map(v => (
          <button key={v.id} onClick={() => selectVehicle(v)}
            className="w-full flex items-center justify-between px-4 py-3 rounded-xl border text-left"
            style={{ background: '#fff', borderColor: '#e8e5d8' }}>
            <div>
              <div className="text-sm font-bold" style={{ color: '#14130a' }}>{v.plate}</div>
              <div className="text-xs mt-0.5" style={{ color: '#939188' }}>
                {v.brand} {v.model} · {(v.odometer_current ?? 0).toLocaleString()} km
              </div>
            </div>
            <span style={{ color: '#939188' }}>→</span>
          </button>
        ))}
      </div>
    </Screen>
  )

  // P2: Seleccionar posición
  if (step === 'select_position') return (
    <Screen title="Diagrama de posiciones" subtitle={selVehicle?.plate}
            onBack={() => setStep('select_vehicle')}>
      <p className="text-xs mb-3" style={{ color: '#939188' }}>
        Toca la posición donde vas a montar la llanta. Solo las posiciones vacías están disponibles.
      </p>
      <div className="space-y-2">
        {positions.map(p => {
          const occupied = occupiedIds.has(p.id)
          return (
            <button key={p.id}
              onClick={() => !occupied && selectPosition(p)}
              className="w-full flex items-center gap-3 px-4 py-3 rounded-xl border text-left"
              style={{
                background: occupied ? '#f3f0e4' : '#fff',
                borderColor: occupied ? '#ccc8b4' : '#e8e5d8',
                opacity: occupied ? 0.6 : 1,
                cursor: occupied ? 'not-allowed' : 'pointer',
              }}>
              <span className="text-sm">{occupied ? '🟡' : '🟢'}</span>
              <div>
                <div className="text-sm font-semibold" style={{ color: '#14130a' }}>{p.label}</div>
                <div className="text-xs mt-0.5" style={{ color: '#939188' }}>
                  {occupied ? 'Posición ocupada' : 'Disponible para montaje'}
                </div>
              </div>
            </button>
          )
        })}
      </div>
    </Screen>
  )

  // P3: Seleccionar llanta de bodega
  if (step === 'select_tire') return (
    <Screen title="Seleccionar llanta" subtitle={`Posición: ${selPosition?.label}`}
            onBack={() => setStep('select_position')}>
      {availTires.length === 0 ? (
        <div className="text-center py-8 text-sm" style={{ color: '#939188' }}>
          No hay llantas disponibles en bodega.
        </div>
      ) : (
        <div className="space-y-2">
          {availTires.map(t => {
            const m = t.model as { name: string; size: string; original_depth_mm: number } | undefined
            return (
              <button key={t.id} onClick={() => selectTire(t)}
                className="w-full flex items-center gap-3 px-4 py-3 rounded-xl border text-left"
                style={{ background: '#fff', borderColor: '#e8e5d8' }}>
                <div className="flex-1">
                  <div className="text-sm font-bold" style={{ color: '#14130a' }}>{t.serial_number}</div>
                  <div className="text-xs mt-0.5" style={{ color: '#939188' }}>
                    {t.brand?.name} {m?.name} · {m?.size}
                  </div>
                  <div className="text-xs mt-0.5" style={{ color: '#626059' }}>
                    Labrado: {t.current_depth_min_mm ?? m?.original_depth_mm ?? '—'}mm ·{' '}
                    {t.condition === 'new' ? 'Nueva' : `Reencauchada (${t.retread_count}° ciclo)`}
                  </div>
                </div>
                <span style={{ color: '#939188' }}>→</span>
              </button>
            )
          })}
        </div>
      )}
    </Screen>
  )

  // P4: Análisis de labrado + kilómetros
  if (step === 'analysis') {
    const warn = analysis ? WARNING_STYLES[analysis.warningLevel] : WARNING_STYLES.none
    return (
      <Screen title="Análisis del conjunto"
              subtitle={`${selTire?.serial_number} → ${selPosition?.label}`}
              onBack={() => setStep('select_tire')}>

        {analysisLoading ? (
          <div className="text-center py-6 text-sm" style={{ color: '#939188' }}>
            Analizando diferencia de labrado...
          </div>
        ) : analysis && (
          <div className="mb-4 px-4 py-3 rounded-xl border"
               style={{ background: warn.bg, borderColor: warn.border }}>
            <div className="text-xs font-bold mb-1" style={{ color: warn.color }}>{warn.label}</div>
            {analysis.differencesMm !== null && (
              <div className="text-sm font-bold mb-1" style={{ color: warn.color }}>
                Diferencia: {analysis.differencesMm.toFixed(1)}mm
              </div>
            )}
            {analysis.companionSerialNumber && (
              <div className="text-xs mb-2" style={{ color: '#626059' }}>
                Llanta a montar: {analysis.mountingTreadMm}mm ·
                Compañera ({analysis.companionSerialNumber}): {analysis.companionTreadMm}mm
              </div>
            )}
            {analysis.impactText && (
              <div className="text-xs italic" style={{ color: '#626059' }}>
                {analysis.impactText}
              </div>
            )}
          </div>
        )}

        {/* Kilómetros */}
        <div className="mb-4">
          <label className="block text-xs font-semibold mb-2" style={{ color: '#2d2c22' }}>
            Kilómetros del vehículo al montar *
          </label>
          <input
            type="number" inputMode="numeric"
            value={odometer}
            onChange={e => setOdometer(e.target.value)}
            className="w-full px-4 py-4 rounded-xl border text-2xl font-bold text-center outline-none"
            style={{ borderColor: '#ccc8b4', background: '#fff', color: '#14130a' }}
          />
          <p className="text-xs mt-1" style={{ color: '#939188' }}>
            Último registrado: {selVehicle?.odometer_current?.toLocaleString()} km
          </p>
        </div>

        {analysis?.requiresApproval ? (
          <div className="px-4 py-3 rounded-xl border text-sm"
               style={{ background: '#fce5e5', borderColor: '#e49090', color: '#881616' }}>
            Esta diferencia de labrado requiere autorización del analista.
            Contacta al analista antes de continuar.
          </div>
        ) : (
          <button
            disabled={!odometer || parseInt(odometer) < (selVehicle?.odometer_current ?? 0)}
            onClick={() => setStep('confirm')}
            className="w-full py-4 rounded-xl text-sm font-bold text-white"
            style={{ background: !odometer ? '#ccc8b4' : analysis?.warningLevel === 'warning' ? '#d67200' : '#14130a' }}>
            {analysis?.warningLevel === 'warning'
              ? 'Entendido, continuar de todas formas →'
              : 'Continuar al resumen →'}
          </button>
        )}
      </Screen>
    )
  }

  // P5: Confirmar montaje
  if (step === 'confirm') {
    const m = selTire?.model as { name: string; size: string } | undefined
    const warn = analysis ? WARNING_STYLES[analysis.warningLevel] : WARNING_STYLES.none
    return (
      <Screen title="Confirmar montaje" onBack={() => setStep('analysis')}>
        <div className="space-y-3 mb-6">
          <Row label="Vehículo"  value={selVehicle?.plate ?? '—'} />
          <Row label="Posición"  value={selPosition?.label ?? '—'} />
          <Row label="Llanta"    value={selTire?.serial_number ?? '—'} />
          <Row label="Marca / Modelo" value={`${selTire?.brand?.name ?? ''} ${m?.name ?? ''} · ${m?.size ?? ''}`} />
          <Row label="Condición" value={selTire?.condition === 'new' ? 'Nueva' : `Reencauchada (${selTire?.retread_count}° ciclo)`} />
          <Row label="Km al montar" value={parseInt(odometer).toLocaleString() + ' km'} />

          {analysis && analysis.warningLevel !== 'none' && (
            <div className="px-3 py-2.5 rounded-lg border text-xs"
                 style={{ background: warn.bg, borderColor: warn.border, color: warn.color }}>
              ⚠ Montaje con advertencia técnica: diferencia de {analysis.differencesMm?.toFixed(1)}mm
            </div>
          )}
        </div>

        <button
          disabled={saving}
          onClick={confirmMount}
          className="w-full py-4 rounded-xl text-sm font-bold text-white"
          style={{ background: saving ? '#939188' : '#288808' }}>
          {saving ? 'Registrando...' : 'Confirmar montaje'}
        </button>
      </Screen>
    )
  }

  return null
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between py-2 border-b"
         style={{ borderColor: '#e8e5d8' }}>
      <span className="text-xs font-semibold" style={{ color: '#626059' }}>{label}</span>
      <span className="text-sm font-semibold" style={{ color: '#14130a' }}>{value}</span>
    </div>
  )
}

function Screen({ title, subtitle, onBack, children }: {
  title: string; subtitle?: string; onBack?: () => void; children: React.ReactNode
}) {
  return (
    <div className="min-h-screen" style={{ background: '#fafaf7' }}>
      <div className="px-4 py-3.5 flex items-center gap-3 border-b sticky top-0 z-10"
           style={{ background: '#fff', borderColor: '#e8e5d8' }}>
        {onBack && (
          <button onClick={onBack} className="text-sm font-semibold p-1" style={{ color: '#626059' }}>←</button>
        )}
        <div>
          <div className="text-sm font-bold" style={{ color: '#14130a' }}>{title}</div>
          {subtitle && <div className="text-xs mt-0.5" style={{ color: '#939188' }}>{subtitle}</div>}
        </div>
      </div>
      <div className="px-4 py-4 max-w-lg mx-auto">{children}</div>
    </div>
  )
}
