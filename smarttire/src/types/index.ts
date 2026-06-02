// src/types/index.ts

export type UserRole = 'superadmin' | 'admin' | 'analyst' | 'inspector' | 'readonly'

export interface Profile {
  id: string
  tenant_id: string
  full_name: string
  role: UserRole
  is_active: boolean
}

export interface Tenant {
  id: string
  name: string
  slug: string
}

export interface Fleet {
  id: string
  tenant_id: string
  client_id: string
  name: string
}

export interface Vehicle {
  id: string
  tenant_id: string
  fleet_id: string
  plate: string
  brand: string | null
  model: string | null
  year: number | null
  odometer_current: number
  is_active: boolean
  fleet?: Fleet
}

export interface AxlePosition {
  id: string
  vehicle_id: string
  axle_number: number
  side: 'left' | 'right' | 'center'
  position_type: 'outer' | 'inner' | 'single' | 'spare'
  axle_type: 'steering' | 'drive' | 'tag' | 'spare'
  label: string
  sort_order: number
}

export interface Brand {
  id: string
  name: string
}

export interface TireModel {
  id: string
  brand_id: string
  name: string
  size: string
  original_depth_mm: number
  retread_min_depth_mm: number
  scrap_depth_mm: number
  max_retreads: number
  expected_km_new: number
  expected_km_retread: number
  retread_allowed: boolean
  brand?: Brand
}

export interface Tire {
  id: string
  tenant_id: string
  serial_number: string
  brand_id: string
  model_id: string
  condition: 'new' | 'retread' | 'scrap'
  status: 'warehouse' | 'mounted' | 'repair' | 'retread_out' | 'pending_scrap' | 'scrapped'
  retread_count: number
  current_depth_min_mm: number | null
  current_pressure_psi: number | null
  current_vehicle_id: string | null
  current_position_id: string | null
  total_km: number
  total_cost: number
  last_inspection_date: string | null
  purchase_date: string | null
  brand?: Brand
  model?: TireModel
}

export interface Mounting {
  id: string
  tenant_id: string
  tire_id: string
  vehicle_id: string
  position_id: string
  mount_date: string
  mount_odometer: number
  mount_depth_mm: number | null
  is_active: boolean
  tread_warning_level: 'none' | 'advisory' | 'warning' | 'critical'
  tread_difference_mm: number | null
  km_in_position: number | null
  tire?: Tire
}

export interface Inspection {
  id: string
  tenant_id: string
  vehicle_id: string
  fleet_id: string
  inspector_id: string | null
  inspection_date: string
  odometer: number | null
  status: 'open' | 'completed' | 'partial'
  tires_inspected: number
  tires_ok: number
  tires_attention: number
  tires_critical: number
  created_at: string
  closed_at: string | null
  vehicle?: Vehicle
}

export interface InspectionLine {
  id: string
  inspection_id: string
  tire_id: string
  position_id: string
  tread_inner_mm: number | null
  tread_center_mm: number | null
  tread_outer_mm: number | null
  tread_min_mm: number | null
  pressure_psi: number | null
  condition: 'ok' | 'attention' | 'critical' | 'propose_scrap'
  recommended_action: string | null
  life_remaining_pct: number | null
  notes: string | null
}

export interface DamageCatalog {
  id: string
  name: string
  zone: string
  is_scrap_cause: boolean
  is_repairable: boolean
}

// Estado de una posición en el diagrama del vehículo
export interface PositionState {
  position: AxlePosition
  tire: Tire | null
  mounting: Mounting | null
  lastInspection: InspectionLine | null
}

// Línea de inspección en progreso (antes de guardar)
export interface InspectionDraft {
  positionId: string
  tireId: string
  treadInner: string
  treadCenter: string
  treadOuter: string
  pressurePsi: string
  condition: 'ok' | 'attention' | 'critical' | 'propose_scrap'
  hasDamage: boolean
  damageType: string
  damageSeverity: 'low' | 'medium' | 'high' | 'critical'
  damageNotes: string
  notes: string
  saved: boolean
}

// Estado de una revisión activa
export interface ActiveInspection {
  inspectionId: string
  vehicleId: string
  odometer: number
  lines: Record<string, InspectionDraft>  // positionId → draft
}

// Análisis de diferencia de labrado (M-MON)
export interface TreadAnalysis {
  warningLevel: 'none' | 'advisory' | 'warning' | 'critical'
  differencesMm: number | null
  mountingTreadMm: number | null
  companionTreadMm: number | null
  companionTireId: string | null
  companionSerialNumber: string | null
  impactText: string | null
  requiresApproval: boolean
}
