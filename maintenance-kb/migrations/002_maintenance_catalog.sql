BEGIN;
CREATE SCHEMA IF NOT EXISTS maintenance_kb;

CREATE TABLE maintenance_kb.maintenance_categories (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  category_code text NOT NULL UNIQUE CHECK (btrim(category_code) <> ''),
  category_name text NOT NULL CHECK (btrim(category_name) <> ''),
  description text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE maintenance_kb.maintenance_service_items (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  item_code text NOT NULL UNIQUE CHECK (btrim(item_code) <> ''),
  category_id bigint NOT NULL REFERENCES maintenance_kb.maintenance_categories(id),
  item_name text NOT NULL CHECK (btrim(item_name) <> ''),
  normalized_name text NOT NULL CHECK (btrim(normalized_name) <> ''),
  unit text NOT NULL CHECK (unit IN ('عدد','متر','متر مربع','متر طولي','نقطة','زيارة','جهاز','طقم','قطعة','ساعة','يوم','خدمة')),
  standard_price numeric(12,2) CHECK (standard_price IS NULL OR standard_price >= 0),
  min_price numeric(12,2) CHECK (min_price IS NULL OR min_price >= 0),
  max_price numeric(12,2) CHECK (max_price IS NULL OR max_price >= 0),
  status text NOT NULL DEFAULT 'under_review' CHECK (status IN ('approved','under_review','cancelled')),
  source text NOT NULL CHECK (btrim(source) <> ''),
  is_active boolean NOT NULL DEFAULT true,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT maintenance_item_price_order CHECK (
    (min_price IS NULL OR standard_price IS NULL OR min_price <= standard_price) AND
    (standard_price IS NULL OR max_price IS NULL OR standard_price <= max_price) AND
    (min_price IS NULL OR max_price IS NULL OR min_price <= max_price)
  ),
  CONSTRAINT misc_requires_review_note CHECK (
    NOT (item_code LIKE 'MISC-%') OR status <> 'approved' OR nullif(btrim(notes),'') IS NOT NULL
  ),
  UNIQUE (category_id, normalized_name)
);
COMMIT;

