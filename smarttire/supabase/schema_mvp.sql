-- ============================================================
-- SMARTTIRE IA.XPTA — SUPABASE MVP
-- Ejecutar en: Supabase → SQL Editor → New query
-- Una sola ejecución. Incluye datos de prueba.
-- ============================================================

-- EXTENSIONES
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- ============================================================
-- TABLAS CORE
-- ============================================================

CREATE TABLE IF NOT EXISTS tenants (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  slug        TEXT UNIQUE NOT NULL,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  settings    JSONB NOT NULL DEFAULT '{}',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Extender auth.users con perfil de la app
CREATE TABLE IF NOT EXISTS profiles (
  id          UUID PRIMARY KEY REFERENCES auth.users ON DELETE CASCADE,
  tenant_id   UUID NOT NULL REFERENCES tenants(id),
  full_name   TEXT NOT NULL,
  role        TEXT NOT NULL DEFAULT 'inspector'
              CHECK (role IN ('superadmin','admin','analyst','inspector','readonly')),
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- ESTRUCTURA OPERATIVA
-- ============================================================

CREATE TABLE IF NOT EXISTS clients (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   UUID NOT NULL REFERENCES tenants(id),
  name        TEXT NOT NULL,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS fleets (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   UUID NOT NULL REFERENCES tenants(id),
  client_id   UUID NOT NULL REFERENCES clients(id),
  name        TEXT NOT NULL,
  description TEXT,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS vehicle_types (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL,
  description   TEXT,
  axle_count    INT NOT NULL DEFAULT 3,
  total_positions INT NOT NULL DEFAULT 10
);

CREATE TABLE IF NOT EXISTS vehicles (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id         UUID NOT NULL REFERENCES tenants(id),
  fleet_id          UUID NOT NULL REFERENCES fleets(id),
  vehicle_type_id   UUID REFERENCES vehicle_types(id),
  plate             TEXT NOT NULL,
  brand             TEXT,
  model             TEXT,
  year              INT,
  odometer_current  BIGINT NOT NULL DEFAULT 0,
  is_active         BOOLEAN NOT NULL DEFAULT TRUE,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(tenant_id, plate)
);

CREATE TABLE IF NOT EXISTS axle_positions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  vehicle_id    UUID NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
  axle_number   INT NOT NULL,
  side          TEXT NOT NULL CHECK (side IN ('left','right','center')),
  position_type TEXT NOT NULL CHECK (position_type IN ('outer','inner','single','spare')),
  axle_type     TEXT NOT NULL CHECK (axle_type IN ('steering','drive','tag','spare')),
  label         TEXT NOT NULL,   -- ej: "Eje 1 · Izquierda"
  sort_order    INT NOT NULL DEFAULT 0,
  UNIQUE(vehicle_id, axle_number, side, position_type)
);

-- ============================================================
-- CATÁLOGO DE LLANTAS
-- ============================================================

CREATE TABLE IF NOT EXISTS brands (
  id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name  TEXT UNIQUE NOT NULL
);

CREATE TABLE IF NOT EXISTS tire_models (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  brand_id            UUID NOT NULL REFERENCES brands(id),
  name                TEXT NOT NULL,
  size                TEXT NOT NULL,     -- ej: 295/80R22.5
  original_depth_mm   DECIMAL(4,1) NOT NULL DEFAULT 16.0,
  retread_min_depth_mm DECIMAL(4,1) NOT NULL DEFAULT 4.0,
  scrap_depth_mm      DECIMAL(4,1) NOT NULL DEFAULT 2.0,
  max_retreads        INT NOT NULL DEFAULT 2,
  expected_km_new     INT NOT NULL DEFAULT 120000,
  expected_km_retread INT NOT NULL DEFAULT 80000,
  retread_allowed     BOOLEAN NOT NULL DEFAULT TRUE
);

-- ============================================================
-- CATÁLOGOS OPERATIVOS
-- ============================================================

CREATE TABLE IF NOT EXISTS damage_catalog (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL,
  zone          TEXT NOT NULL CHECK (zone IN ('tread','sidewall','shoulder','bead','full')),
  is_scrap_cause BOOLEAN NOT NULL DEFAULT FALSE,
  is_repairable BOOLEAN NOT NULL DEFAULT TRUE,
  description   TEXT
);

-- ============================================================
-- LLANTAS
-- ============================================================

CREATE TABLE IF NOT EXISTS tires (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           UUID NOT NULL REFERENCES tenants(id),
  serial_number       TEXT NOT NULL,
  brand_id            UUID NOT NULL REFERENCES brands(id),
  model_id            UUID NOT NULL REFERENCES tire_models(id),
  condition           TEXT NOT NULL DEFAULT 'new'
                      CHECK (condition IN ('new','retread','scrap')),
  status              TEXT NOT NULL DEFAULT 'warehouse'
                      CHECK (status IN ('warehouse','mounted','repair','retread_out','pending_scrap','scrapped')),
  retread_count       INT NOT NULL DEFAULT 0,
  current_depth_min_mm DECIMAL(4,1),
  current_pressure_psi DECIMAL(5,1),
  current_vehicle_id  UUID REFERENCES vehicles(id),
  current_position_id UUID REFERENCES axle_positions(id),
  total_km            BIGINT NOT NULL DEFAULT 0,
  total_cost          DECIMAL(12,2) NOT NULL DEFAULT 0,
  last_inspection_date DATE,
  purchase_date       DATE,
  notes               TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(tenant_id, serial_number)
);

CREATE INDEX IF NOT EXISTS idx_tires_tenant_status ON tires(tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_tires_serial ON tires USING gin(serial_number gin_trgm_ops);

-- ============================================================
-- MONTAJES (event sourcing del ciclo de posición)
-- ============================================================

CREATE TABLE IF NOT EXISTS mountings (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id         UUID NOT NULL REFERENCES tenants(id),
  tire_id           UUID NOT NULL REFERENCES tires(id),
  vehicle_id        UUID NOT NULL REFERENCES vehicles(id),
  position_id       UUID NOT NULL REFERENCES axle_positions(id),

  -- Montaje
  mount_date        DATE NOT NULL DEFAULT CURRENT_DATE,
  mount_odometer    BIGINT NOT NULL,
  mount_depth_mm    DECIMAL(4,1),
  mounted_by        UUID REFERENCES profiles(id),
  is_active         BOOLEAN NOT NULL DEFAULT TRUE,

  -- Advertencia de labrado (M-MON)
  tread_warning_level TEXT CHECK (tread_warning_level IN ('none','advisory','warning','critical')) DEFAULT 'none',
  tread_difference_mm DECIMAL(4,2),
  tread_warning_confirmed_by UUID REFERENCES profiles(id),

  -- Desmontaje (NULL mientras está montada)
  unmount_date          DATE,
  unmount_odometer      BIGINT,
  unmount_depth_min_mm  DECIMAL(4,1),
  destination           TEXT CHECK (destination IN ('retread','scrap','swap','repair')),
  destination_reason    TEXT,
  unmounted_by          UUID REFERENCES profiles(id),

  -- Métricas calculadas
  km_in_position    BIGINT GENERATED ALWAYS AS (
    CASE WHEN unmount_odometer IS NOT NULL AND mount_odometer IS NOT NULL
    THEN unmount_odometer - mount_odometer ELSE NULL END
  ) STORED,

  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Una posición: máximo una llanta activa
  EXCLUDE USING gist (position_id WITH =) WHERE (is_active = TRUE),
  -- Una llanta: máximo un montaje activo
  EXCLUDE USING gist (tire_id WITH =) WHERE (is_active = TRUE),
  CONSTRAINT chk_odometer_order
    CHECK (unmount_odometer IS NULL OR unmount_odometer >= mount_odometer)
);

CREATE INDEX IF NOT EXISTS idx_mountings_vehicle_active ON mountings(vehicle_id) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_mountings_tire ON mountings(tire_id, mount_date DESC);

-- ============================================================
-- INSPECCIONES (M-REV)
-- ============================================================

CREATE TABLE IF NOT EXISTS inspections (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id),
  vehicle_id      UUID NOT NULL REFERENCES vehicles(id),
  fleet_id        UUID NOT NULL REFERENCES fleets(id),
  inspector_id    UUID REFERENCES profiles(id),

  inspection_date DATE NOT NULL DEFAULT CURRENT_DATE,
  odometer        BIGINT,
  inspection_type TEXT NOT NULL DEFAULT 'scheduled'
                  CHECK (inspection_type IN ('scheduled','unscheduled','complaint')),

  -- Estado de la revisión
  status          TEXT NOT NULL DEFAULT 'open'
                  CHECK (status IN ('open','completed','partial')),

  tires_inspected INT NOT NULL DEFAULT 0,
  tires_ok        INT NOT NULL DEFAULT 0,
  tires_attention INT NOT NULL DEFAULT 0,
  tires_critical  INT NOT NULL DEFAULT 0,

  -- Checklist general del vehículo (opcional)
  checklist       JSONB DEFAULT '{}',
  notes           TEXT,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  closed_at       TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_inspections_vehicle ON inspections(vehicle_id, inspection_date DESC);
CREATE INDEX IF NOT EXISTS idx_inspections_fleet ON inspections(fleet_id, inspection_date DESC);

CREATE TABLE IF NOT EXISTS inspection_lines (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  inspection_id     UUID NOT NULL REFERENCES inspections(id) ON DELETE CASCADE,
  tire_id           UUID NOT NULL REFERENCES tires(id),
  position_id       UUID NOT NULL REFERENCES axle_positions(id),

  -- Mediciones
  tread_inner_mm    DECIMAL(4,1),
  tread_center_mm   DECIMAL(4,1),
  tread_outer_mm    DECIMAL(4,1),
  tread_min_mm      DECIMAL(4,1) GENERATED ALWAYS AS (
    LEAST(
      COALESCE(tread_inner_mm, 99),
      COALESCE(tread_center_mm, 99),
      COALESCE(tread_outer_mm, 99)
    )
  ) STORED,
  pressure_psi      DECIMAL(5,1),

  -- Estado evaluado por el inspector
  condition         TEXT NOT NULL DEFAULT 'ok'
                    CHECK (condition IN ('ok','attention','critical','propose_scrap')),

  -- Recomendación automática del sistema
  recommended_action TEXT CHECK (recommended_action IN (
    'none','monitor','pressure_adjust','retread','repair','scrap','rotation'
  )),

  life_remaining_pct DECIMAL(5,2),
  notes             TEXT,

  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(inspection_id, tire_id)
);

CREATE TABLE IF NOT EXISTS inspection_damages (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  inspection_line_id UUID NOT NULL REFERENCES inspection_lines(id) ON DELETE CASCADE,
  damage_catalog_id  UUID REFERENCES damage_catalog(id),
  severity          TEXT NOT NULL CHECK (severity IN ('low','medium','high','critical')),
  zone              TEXT,
  photo_url         TEXT,
  notes             TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- EVENTOS DE CICLO DE VIDA (append-only)
-- ============================================================

CREATE TABLE IF NOT EXISTS tire_events (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     UUID NOT NULL REFERENCES tenants(id),
  tire_id       UUID NOT NULL REFERENCES tires(id),
  vehicle_id    UUID REFERENCES vehicles(id),
  position_id   UUID REFERENCES axle_positions(id),
  event_type    TEXT NOT NULL CHECK (event_type IN (
    'purchase','mount','unmount','inspection',
    'retread_send','retread_receive','repair_in','repair_out',
    'warehouse_in','scrap','adjustment','pressure_check'
  )),
  event_date    DATE NOT NULL DEFAULT CURRENT_DATE,
  odometer      BIGINT,
  performed_by  UUID REFERENCES profiles(id),
  metadata      JSONB DEFAULT '{}',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_events_tire ON tire_events(tire_id, event_date DESC);
CREATE INDEX IF NOT EXISTS idx_events_tenant ON tire_events(tenant_id, event_date DESC);

-- Trigger: bloquear UPDATE/DELETE en tire_events
CREATE OR REPLACE FUNCTION fn_prevent_event_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'tire_events es append-only. Use un evento de ajuste para correcciones.';
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_update ON tire_events;
DROP TRIGGER IF EXISTS trg_prevent_delete ON tire_events;
CREATE TRIGGER trg_prevent_update BEFORE UPDATE ON tire_events FOR EACH ROW EXECUTE FUNCTION fn_prevent_event_mutation();
CREATE TRIGGER trg_prevent_delete BEFORE DELETE ON tire_events FOR EACH ROW EXECUTE FUNCTION fn_prevent_event_mutation();

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE tenants          ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles         ENABLE ROW LEVEL SECURITY;
ALTER TABLE clients          ENABLE ROW LEVEL SECURITY;
ALTER TABLE fleets           ENABLE ROW LEVEL SECURITY;
ALTER TABLE vehicles         ENABLE ROW LEVEL SECURITY;
ALTER TABLE axle_positions   ENABLE ROW LEVEL SECURITY;
ALTER TABLE tires            ENABLE ROW LEVEL SECURITY;
ALTER TABLE mountings        ENABLE ROW LEVEL SECURITY;
ALTER TABLE inspections      ENABLE ROW LEVEL SECURITY;
ALTER TABLE inspection_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE inspection_damages ENABLE ROW LEVEL SECURITY;
ALTER TABLE tire_events      ENABLE ROW LEVEL SECURITY;

-- Función helper: obtener tenant_id del usuario autenticado
CREATE OR REPLACE FUNCTION get_my_tenant_id()
RETURNS UUID LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT tenant_id FROM profiles WHERE id = auth.uid();
$$;

-- Política genérica por tenant (aplicada a todas las tablas operativas)
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'clients','fleets','vehicles','tires','mountings',
    'inspections','inspection_lines','inspection_damages','tire_events'
  ] LOOP
    EXECUTE format('
      DROP POLICY IF EXISTS tenant_isolation ON %I;
      CREATE POLICY tenant_isolation ON %I
        USING (tenant_id = get_my_tenant_id());
    ', t, t);
  END LOOP;
END $$;

-- axle_positions: aislamiento por vehicle → fleet → tenant
CREATE POLICY ap_tenant ON axle_positions
  USING (vehicle_id IN (
    SELECT id FROM vehicles WHERE tenant_id = get_my_tenant_id()
  ));

-- profiles: cada usuario ve los de su tenant
CREATE POLICY profiles_tenant ON profiles
  USING (tenant_id = get_my_tenant_id());

-- tenants: un usuario solo ve su propio tenant
CREATE POLICY tenants_own ON tenants
  USING (id = get_my_tenant_id());

-- Tablas de catálogo: acceso público de lectura (no tienen tenant_id)
CREATE POLICY brands_read    ON brands    FOR SELECT USING (TRUE);
CREATE POLICY models_read    ON tire_models FOR SELECT USING (TRUE);
CREATE POLICY damage_read    ON damage_catalog FOR SELECT USING (TRUE);
CREATE POLICY vtype_read     ON vehicle_types FOR SELECT USING (TRUE);
ALTER TABLE brands           ENABLE ROW LEVEL SECURITY;
ALTER TABLE tire_models      ENABLE ROW LEVEL SECURITY;
ALTER TABLE damage_catalog   ENABLE ROW LEVEL SECURITY;
ALTER TABLE vehicle_types    ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- TRIGGER: actualizar tires cuando cambia el estado
-- ============================================================
CREATE OR REPLACE FUNCTION fn_sync_tire_from_event()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.event_type = 'mount' THEN
    UPDATE tires SET
      status = 'mounted',
      current_vehicle_id = NEW.vehicle_id,
      current_position_id = NEW.position_id,
      updated_at = NOW()
    WHERE id = NEW.tire_id;

  ELSIF NEW.event_type = 'unmount' THEN
    UPDATE tires SET
      status = COALESCE(
        (SELECT CASE destination
          WHEN 'retread' THEN 'retread_out'
          WHEN 'scrap'   THEN 'pending_scrap'
          WHEN 'repair'  THEN 'repair'
          ELSE 'warehouse' END
        FROM mountings WHERE tire_id = NEW.tire_id AND is_active = TRUE LIMIT 1),
        'warehouse'
      ),
      current_vehicle_id = NULL,
      current_position_id = NULL,
      total_km = total_km + COALESCE(
        (SELECT km_in_position FROM mountings WHERE tire_id = NEW.tire_id AND is_active = TRUE LIMIT 1), 0
      ),
      updated_at = NOW()
    WHERE id = NEW.tire_id;

    UPDATE mountings SET is_active = FALSE, updated_at = NOW()
      WHERE tire_id = NEW.tire_id AND is_active = TRUE;

  ELSIF NEW.event_type = 'inspection' THEN
    UPDATE tires SET
      current_depth_min_mm = (NEW.metadata->>'tread_min_mm')::DECIMAL,
      current_pressure_psi = (NEW.metadata->>'pressure_psi')::DECIMAL,
      last_inspection_date = NEW.event_date,
      updated_at = NOW()
    WHERE id = NEW.tire_id;

  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_tire ON tire_events;
CREATE TRIGGER trg_sync_tire
  AFTER INSERT ON tire_events
  FOR EACH ROW EXECUTE FUNCTION fn_sync_tire_from_event();

-- ============================================================
-- FUNCIÓN: proponer destino al desmontar
-- ============================================================
CREATE OR REPLACE FUNCTION fn_propose_destination(
  p_tire_id UUID,
  p_tread_min DECIMAL
) RETURNS TEXT LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_model RECORD;
  v_tire  RECORD;
BEGIN
  SELECT tm.scrap_depth_mm, tm.retread_min_depth_mm, tm.max_retreads, tm.retread_allowed
  INTO v_model
  FROM tires t JOIN tire_models tm ON tm.id = t.model_id
  WHERE t.id = p_tire_id;

  SELECT retread_count INTO v_tire FROM tires WHERE id = p_tire_id;

  IF p_tread_min <= COALESCE(v_model.scrap_depth_mm, 2.0) THEN
    RETURN 'scrap';
  ELSIF p_tread_min >= COALESCE(v_model.retread_min_depth_mm, 4.0)
    AND v_tire.retread_count < COALESCE(v_model.max_retreads, 2)
    AND COALESCE(v_model.retread_allowed, TRUE) THEN
    RETURN 'retread';
  ELSE
    RETURN 'swap';
  END IF;
END;
$$;

-- ============================================================
-- DATOS SEMILLA — CATÁLOGOS
-- ============================================================

INSERT INTO vehicle_types (id, name, description, axle_count, total_positions) VALUES
  ('11111111-0001-0001-0001-000000000001', 'Tracto simple',        '2 ejes + repuesto',        2, 6),
  ('11111111-0001-0001-0001-000000000002', 'Tracto doble',         '2 ejes dobles + repuesto', 2, 10),
  ('11111111-0001-0001-0001-000000000003', 'Camión rígido 3 ejes', '3 ejes',                   3, 10),
  ('11111111-0001-0001-0001-000000000004', 'Camión 2 ejes',        '2 ejes sencillos',         2, 6)
ON CONFLICT DO NOTHING;

INSERT INTO brands (id, name) VALUES
  ('22222222-0001-0001-0001-000000000001', 'Michelin'),
  ('22222222-0001-0001-0001-000000000002', 'Bridgestone'),
  ('22222222-0001-0001-0001-000000000003', 'Goodyear'),
  ('22222222-0001-0001-0001-000000000004', 'Continental'),
  ('22222222-0001-0001-0001-000000000005', 'Hankook')
ON CONFLICT DO NOTHING;

INSERT INTO tire_models (id, brand_id, name, size, original_depth_mm, retread_min_depth_mm, scrap_depth_mm, max_retreads, expected_km_new, expected_km_retread, retread_allowed) VALUES
  ('33333333-0001-0001-0001-000000000001', '22222222-0001-0001-0001-000000000001', 'XZE2+', '295/80R22.5', 16.0, 4.0, 2.0, 2, 130000, 85000, TRUE),
  ('33333333-0001-0001-0001-000000000002', '22222222-0001-0001-0001-000000000001', 'X MultiWay 3D', '315/80R22.5', 17.0, 4.5, 2.0, 2, 140000, 90000, TRUE),
  ('33333333-0001-0001-0001-000000000003', '22222222-0001-0001-0001-000000000002', 'M788', '295/80R22.5', 16.0, 4.0, 2.0, 2, 120000, 80000, TRUE),
  ('33333333-0001-0001-0001-000000000004', '22222222-0001-0001-0001-000000000003', 'OMNITRAC S', '295/80R22.5', 16.5, 4.0, 2.0, 2, 125000, 80000, TRUE)
ON CONFLICT DO NOTHING;

INSERT INTO damage_catalog (id, name, zone, is_scrap_cause, is_repairable) VALUES
  ('44444444-0001-0001-0001-000000000001', 'Corte en costado',      'sidewall', TRUE,  FALSE),
  ('44444444-0001-0001-0001-000000000002', 'Perforación reparable', 'tread',    FALSE, TRUE),
  ('44444444-0001-0001-0001-000000000003', 'Burbuja / deformación', 'sidewall', TRUE,  FALSE),
  ('44444444-0001-0001-0001-000000000004', 'Desgaste irregular',    'tread',    FALSE, FALSE),
  ('44444444-0001-0001-0001-000000000005', 'Daño en pestaña',       'bead',     FALSE, TRUE),
  ('44444444-0001-0001-0001-000000000006', 'Corte en banda',        'tread',    TRUE,  FALSE),
  ('44444444-0001-0001-0001-000000000007', 'Separación de banda',   'tread',    TRUE,  FALSE)
ON CONFLICT DO NOTHING;

-- ============================================================
-- DATOS SEMILLA — TENANT DE PRUEBA
-- ============================================================

INSERT INTO tenants (id, name, slug) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Empresa Demo', 'demo')
ON CONFLICT DO NOTHING;

INSERT INTO clients (id, tenant_id, name) VALUES
  ('bbbbbbbb-0001-0001-0001-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Transportes El Condor')
ON CONFLICT DO NOTHING;

INSERT INTO fleets (id, tenant_id, client_id, name) VALUES
  ('cccccccc-0001-0001-0001-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'bbbbbbbb-0001-0001-0001-000000000001', 'Flota Carretera Norte')
ON CONFLICT DO NOTHING;

-- Vehículos de prueba
INSERT INTO vehicles (id, tenant_id, fleet_id, vehicle_type_id, plate, brand, model, year, odometer_current) VALUES
  ('dddddddd-0001-0001-0001-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'cccccccc-0001-0001-0001-000000000001', '11111111-0001-0001-0001-000000000001', 'ABC-123', 'Kenworth', 'T800', 2020, 145000),
  ('dddddddd-0001-0001-0001-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'cccccccc-0001-0001-0001-000000000001', '11111111-0001-0001-0001-000000000001', 'DEF-456', 'International', 'ProStar', 2019, 198000),
  ('dddddddd-0001-0001-0001-000000000003', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'cccccccc-0001-0001-0001-000000000001', '11111111-0001-0001-0001-000000000002', 'GHI-789', 'Freightliner', 'Cascadia', 2021, 87000)
ON CONFLICT DO NOTHING;

-- Posiciones del vehículo ABC-123 (tracto simple: 6 posiciones)
INSERT INTO axle_positions (id, vehicle_id, axle_number, side, position_type, axle_type, label, sort_order) VALUES
  ('eeeeeeee-0001-0001-0001-000000000001', 'dddddddd-0001-0001-0001-000000000001', 1, 'left',   'single', 'steering', 'Eje 1 · Izquierda',  1),
  ('eeeeeeee-0001-0001-0001-000000000002', 'dddddddd-0001-0001-0001-000000000001', 1, 'right',  'single', 'steering', 'Eje 1 · Derecha',    2),
  ('eeeeeeee-0001-0001-0001-000000000003', 'dddddddd-0001-0001-0001-000000000001', 2, 'left',   'outer',  'drive',    'Eje 2 · Izq Ext',    3),
  ('eeeeeeee-0001-0001-0001-000000000004', 'dddddddd-0001-0001-0001-000000000001', 2, 'left',   'inner',  'drive',    'Eje 2 · Izq Int',    4),
  ('eeeeeeee-0001-0001-0001-000000000005', 'dddddddd-0001-0001-0001-000000000001', 2, 'right',  'outer',  'drive',    'Eje 2 · Der Ext',    5),
  ('eeeeeeee-0001-0001-0001-000000000006', 'dddddddd-0001-0001-0001-000000000001', 2, 'right',  'inner',  'drive',    'Eje 2 · Der Int',    6)
ON CONFLICT DO NOTHING;

-- Posiciones del vehículo DEF-456
INSERT INTO axle_positions (id, vehicle_id, axle_number, side, position_type, axle_type, label, sort_order) VALUES
  ('eeeeeeee-0002-0001-0001-000000000001', 'dddddddd-0001-0001-0001-000000000002', 1, 'left',  'single', 'steering', 'Eje 1 · Izquierda', 1),
  ('eeeeeeee-0002-0001-0001-000000000002', 'dddddddd-0001-0001-0001-000000000002', 1, 'right', 'single', 'steering', 'Eje 1 · Derecha',   2),
  ('eeeeeeee-0002-0001-0001-000000000003', 'dddddddd-0001-0001-0001-000000000002', 2, 'left',  'outer',  'drive',    'Eje 2 · Izq Ext',   3),
  ('eeeeeeee-0002-0001-0001-000000000004', 'dddddddd-0001-0001-0001-000000000002', 2, 'left',  'inner',  'drive',    'Eje 2 · Izq Int',   4),
  ('eeeeeeee-0002-0001-0001-000000000005', 'dddddddd-0001-0001-0001-000000000002', 2, 'right', 'outer',  'drive',    'Eje 2 · Der Ext',   5),
  ('eeeeeeee-0002-0001-0001-000000000006', 'dddddddd-0001-0001-0001-000000000002', 2, 'right', 'inner',  'drive',    'Eje 2 · Der Int',   6)
ON CONFLICT DO NOTHING;

-- Llantas en bodega (disponibles para montar)
INSERT INTO tires (id, tenant_id, serial_number, brand_id, model_id, condition, status, current_depth_min_mm, purchase_date) VALUES
  ('ffffffff-0001-0001-0001-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'MIC-2024-001', '22222222-0001-0001-0001-000000000001', '33333333-0001-0001-0001-000000000001', 'new',     'warehouse', 16.0, '2024-01-15'),
  ('ffffffff-0001-0001-0001-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'MIC-2024-002', '22222222-0001-0001-0001-000000000001', '33333333-0001-0001-0001-000000000001', 'new',     'warehouse', 16.0, '2024-01-15'),
  ('ffffffff-0001-0001-0001-000000000003', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'MIC-2024-003', '22222222-0001-0001-0001-000000000001', '33333333-0001-0001-0001-000000000001', 'new',     'warehouse', 16.0, '2024-01-15'),
  ('ffffffff-0001-0001-0001-000000000004', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'MIC-2024-004', '22222222-0001-0001-0001-000000000001', '33333333-0001-0001-0001-000000000001', 'new',     'warehouse', 16.0, '2024-01-15'),
  ('ffffffff-0001-0001-0001-000000000005', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'BRI-2023-010', '22222222-0001-0001-0001-000000000002', '33333333-0001-0001-0001-000000000003', 'retread', 'warehouse', 13.0, '2023-06-10'),
  ('ffffffff-0001-0001-0001-000000000006', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'BRI-2023-011', '22222222-0001-0001-0001-000000000002', '33333333-0001-0001-0001-000000000003', 'retread', 'warehouse', 11.5, '2023-06-10'),
  ('ffffffff-0001-0001-0001-000000000007', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'GOO-2024-020', '22222222-0001-0001-0001-000000000003', '33333333-0001-0001-0001-000000000004', 'new',     'warehouse', 16.5, '2024-03-01'),
  ('ffffffff-0001-0001-0001-000000000008', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'GOO-2024-021', '22222222-0001-0001-0001-000000000003', '33333333-0001-0001-0001-000000000004', 'new',     'warehouse', 16.5, '2024-03-01')
ON CONFLICT DO NOTHING;

-- ============================================================
-- USUARIO DE PRUEBA
-- IMPORTANTE: crear en Supabase → Authentication → Users:
-- Email: inspector@demo.com  Password: Demo2024!
-- Email: analista@demo.com   Password: Demo2024!
-- Luego copiar los UUID generados y ejecutar:
-- ============================================================
-- UPDATE profiles SET ... WHERE id = '<uuid_del_auth_user>';
-- El trigger de abajo lo crea automáticamente al registrarse.

-- Trigger: crear perfil automáticamente al registrarse
CREATE OR REPLACE FUNCTION fn_create_profile_on_signup()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_tenant_id UUID := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'; -- tenant demo
BEGIN
  INSERT INTO profiles (id, tenant_id, full_name, role)
  VALUES (
    NEW.id,
    v_tenant_id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
    COALESCE(NEW.raw_user_meta_data->>'role', 'inspector')
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION fn_create_profile_on_signup();

-- ============================================================
-- LISTO. Próximo paso:
-- 1. Ir a Supabase → Authentication → Users → Add user
-- 2. Crear: inspector@demo.com / Demo2024!
-- 3. Crear: analista@demo.com  / Demo2024!
-- Los perfiles se crean automáticamente como rol 'inspector'.
-- Para el analista, ejecutar:
-- UPDATE profiles SET role = 'analyst' WHERE id = (SELECT id FROM auth.users WHERE email = 'analista@demo.com');
-- ============================================================
