
-- =========================================================
-- KaiTasks - Script SQL inicial (PostgreSQL)
-- Esquema: usuarios, tareas, validaciones, notificaciones
-- Incluye tipos ENUM, índices, vistas y datos de prueba.
-- =========================================================

-- 0) Extensiones necesarias
CREATE EXTENSION IF NOT EXISTS pgcrypto; -- para gen_random_uuid()

-- 1) Tipos de datos (ENUM)
DO $$ BEGIN
    CREATE TYPE rol AS ENUM ('JEFATURA','COLABORADOR','GERENTE');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE estado_tarea AS ENUM ('PENDIENTE','EN_PROGRESO','COMPLETADA','FINALIZADA','ATRASADA');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 2) Tablas
CREATE TABLE IF NOT EXISTS usuarios (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre       TEXT NOT NULL,
    correo       TEXT NOT NULL UNIQUE,
    rol          rol  NOT NULL,
    area         TEXT,
    activo       BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tareas (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    titulo          TEXT NOT NULL,
    descripcion     TEXT,
    estado          estado_tarea NOT NULL DEFAULT 'PENDIENTE',
    fecha_inicio    DATE NOT NULL DEFAULT CURRENT_DATE,
    fecha_fin       DATE NOT NULL,
    creador_id      UUID NOT NULL REFERENCES usuarios(id) ON DELETE RESTRICT,
    responsable_id  UUID REFERENCES usuarios(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_fechas_validas CHECK (fecha_fin >= fecha_inicio)
);

-- Trigger para updated_at
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_tareas_updated_at ON tareas;
CREATE TRIGGER trg_tareas_updated_at
BEFORE UPDATE ON tareas
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS validaciones (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tarea_id      UUID NOT NULL REFERENCES tareas(id) ON DELETE CASCADE,
    validador_id  UUID NOT NULL REFERENCES usuarios(id) ON DELETE RESTRICT,
    fecha         TIMESTAMPTZ NOT NULL DEFAULT now(),
    resultado     BOOLEAN NOT NULL,  -- TRUE=aprobada, FALSE=rechazada
    comentario    TEXT
);

CREATE TABLE IF NOT EXISTS notificaciones (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tarea_id    UUID NOT NULL REFERENCES tareas(id) ON DELETE CASCADE,
    usuario_id  UUID NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    mensaje     TEXT NOT NULL,
    fecha       TIMESTAMPTZ NOT NULL DEFAULT now(),
    leida       BOOLEAN NOT NULL DEFAULT FALSE
);

-- 3) Índices recomendados
CREATE INDEX IF NOT EXISTS idx_tareas_responsable_estado ON tareas (responsable_id, estado);
CREATE INDEX IF NOT EXISTS idx_notif_usuario_leida ON notificaciones (usuario_id, leida);
CREATE INDEX IF NOT EXISTS idx_validaciones_tarea_fecha ON validaciones (tarea_id, fecha DESC);

-- 4) Vista para Dashboard (resumen de estados)
CREATE OR REPLACE VIEW dashboard_resumen AS
SELECT
  COUNT(*) FILTER (WHERE estado = 'PENDIENTE')                                  AS pendientes,
  COUNT(*) FILTER (WHERE estado = 'EN_PROGRESO')                                AS en_progreso,
  COUNT(*) FILTER (WHERE estado = 'ATRASADA')                                   AS atrasadas,
  COUNT(*) FILTER (WHERE estado IN ('COMPLETADA','FINALIZADA'))                 AS completadas
FROM tareas;

-- 5) Datos de prueba (mini-DB)
-- Usuarios
INSERT INTO usuarios (nombre, correo, rol, area) VALUES
  ('Ana Jefa',      'ana@org.com',      'JEFATURA',   'Logística'),
  ('Carlos Colab',  'carlos@org.com',   'COLABORADOR','Logística'),
  ('Gabriela Gte',  'gabriela@org.com', 'GERENTE',    'Dirección')
ON CONFLICT (correo) DO NOTHING;

-- Tareas de ejemplo (usando CTE para tomar IDs)
WITH j AS (SELECT id FROM usuarios WHERE correo='ana@org.com'),
     c AS (SELECT id FROM usuarios WHERE correo='carlos@org.com')
INSERT INTO tareas (titulo, descripcion, fecha_fin, creador_id, responsable_id)
SELECT 'Inventario de bodega', 'Levantamiento de SKUs y conteo físico', CURRENT_DATE + INTERVAL '7 day', j.id, c.id FROM j, c
ON CONFLICT DO NOTHING;

WITH j AS (SELECT id FROM usuarios WHERE correo='ana@org.com'),
     c AS (SELECT id FROM usuarios WHERE correo='carlos@org.com')
INSERT INTO tareas (titulo, descripcion, estado, fecha_fin, creador_id, responsable_id)
SELECT 'Orden de compra insumos', 'Preparar OC prioritaria', 'EN_PROGRESO', CURRENT_DATE + INTERVAL '3 day', j.id, c.id FROM j, c
ON CONFLICT DO NOTHING;

-- Validación (ejemplo: aprobar una tarea completada)
-- Primero ponemos una tarea en COMPLETADA para ilustrar
UPDATE tareas SET estado='COMPLETADA'
WHERE titulo='Inventario de bodega' AND estado <> 'COMPLETADA';

WITH t AS (SELECT id FROM tareas WHERE titulo='Inventario de bodega'),
     v AS (SELECT id FROM usuarios WHERE correo='ana@org.com')
INSERT INTO validaciones (tarea_id, validador_id, resultado, comentario)
SELECT t.id, v.id, TRUE, 'Cumple criterios de aceptación' FROM t, v
ON CONFLICT DO NOTHING;

-- Notificaciones de ejemplo
WITH t AS (SELECT id FROM tareas WHERE titulo='Inventario de bodega'),
     u AS (SELECT id FROM usuarios WHERE correo='carlos@org.com')
INSERT INTO notificaciones (tarea_id, usuario_id, mensaje)
SELECT t.id, u.id, 'Tarea validada por Jefatura' FROM t, u
ON CONFLICT DO NOTHING;

-- 6) Consultas de verificación (opcionales)
-- SELECT * FROM dashboard_resumen;
-- SELECT t.titulo, t.estado, u.nombre AS responsable
--   FROM tareas t LEFT JOIN usuarios u ON u.id = t.responsable_id;

-- Fin del script
