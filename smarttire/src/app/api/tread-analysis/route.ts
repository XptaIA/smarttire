// src/app/api/tread-analysis/route.ts
import { createServerClient } from '@supabase/ssr'
import { cookies } from 'next/headers'
import { NextResponse, type NextRequest } from 'next/server'

export async function POST(request: NextRequest) {
  const cookieStore = await cookies()
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { cookies: { getAll: () => cookieStore.getAll(), setAll: (list) => { list.forEach(({name,value,options}) => cookieStore.set(name,value,options)) } } }
  )

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'No autenticado' }, { status: 401 })

  const { tireId, positionId, vehicleId } = await request.json()

  // Datos de la llanta a montar
  const { data: tire } = await supabase
    .from('tires')
    .select('id, serial_number, current_depth_min_mm, retread_count, model:tire_models(original_depth_mm)')
    .eq('id', tireId).single()

  if (!tire) return NextResponse.json({ error: 'Llanta no encontrada' }, { status: 404 })

  const mountingTread = tire.current_depth_min_mm
    ?? (tire.model as {original_depth_mm: number})?.original_depth_mm
    ?? 16

  // Posición seleccionada
  const { data: position } = await supabase
    .from('axle_positions')
    .select('id, axle_number, side, position_type')
    .eq('id', positionId).single()

  if (!position) return NextResponse.json({ warningLevel: 'none', differencesMm: null, mountingTreadMm: mountingTread, companionTreadMm: null, companionTireId: null, companionSerialNumber: null, impactText: null, requiresApproval: false })

  // Buscar posición compañera
  const isDual = position.position_type === 'outer' || position.position_type === 'inner'
  let companionQuery = supabase
    .from('axle_positions')
    .select('id')
    .eq('vehicle_id', vehicleId)
    .eq('axle_number', position.axle_number)
    .neq('id', positionId)

  if (isDual) {
    companionQuery = companionQuery.eq('side', position.side)
  } else {
    companionQuery = companionQuery.neq('side', position.side)
  }

  const { data: companions } = await companionQuery.limit(1)

  if (!companions || companions.length === 0) {
    return NextResponse.json({ warningLevel: 'none', differencesMm: null, mountingTreadMm: mountingTread, companionTreadMm: null, companionTireId: null, companionSerialNumber: null, impactText: null, requiresApproval: false })
  }

  // Llanta actualmente montada en la posición compañera
  const { data: companionMounting } = await supabase
    .from('mountings')
    .select('tire:tires(id, serial_number, current_depth_min_mm)')
    .eq('position_id', companions[0].id)
    .eq('is_active', true)
    .single()

  if (!companionMounting?.tire) {
    return NextResponse.json({ warningLevel: 'none', differencesMm: null, mountingTreadMm: mountingTread, companionTreadMm: null, companionTireId: null, companionSerialNumber: null, impactText: 'La posición compañera está vacía.', requiresApproval: false })
  }

  const ct = companionMounting.tire as {id:string;serial_number:string;current_depth_min_mm:number|null}
  const companionTread = ct.current_depth_min_mm

  if (!companionTread) {
    return NextResponse.json({ warningLevel: 'none', differencesMm: null, mountingTreadMm: mountingTread, companionTreadMm: null, companionTireId: ct.id, companionSerialNumber: ct.serial_number, impactText: 'Sin datos de labrado de la llanta compañera.', requiresApproval: false })
  }

  const diff = Math.abs(mountingTread - companionTread)
  let warningLevel: 'none' | 'advisory' | 'warning' | 'critical'
  let impactText: string

  if (diff < 2.0) {
    warningLevel = 'none'
    impactText = 'Conjunto bien balanceado. Sin impacto significativo.'
  } else if (diff < 3.0) {
    warningLevel = 'advisory'
    impactText = `Diferencia leve (${diff.toFixed(1)}mm). Impacto estimado: 5–10% de desgaste adicional. (Estimación referencial.)`
  } else if (diff < 5.0) {
    warningLevel = 'warning'
    impactText = `Diferencia de ${diff.toFixed(1)}mm. Impacto estimado: 15–25% de desgaste adicional en la llanta más desgastada. (Estimación referencial.)`
  } else {
    warningLevel = 'critical'
    impactText = `Diferencia crítica de ${diff.toFixed(1)}mm. Impacto estimado: 30–40% o más. Requiere autorización del analista. (Estimación referencial.)`
  }

  return NextResponse.json({
    warningLevel,
    differencesMm: diff,
    mountingTreadMm: mountingTread,
    companionTreadMm: companionTread,
    companionTireId: ct.id,
    companionSerialNumber: ct.serial_number,
    impactText,
    requiresApproval: warningLevel === 'critical',
  })
}
