-- ============================================================================
-- نظام إدارة بنود الصيانة الموحد — مجموعة العزب
-- إصدار PostgreSQL + pgvector (بديل نسخة MariaDB/MySQL الأصلية في الملف المضغوط)
--
-- الإضافة الجديدة عن النسخة الأصلية: عمود embedding (vector) على كتالوج البنود
-- يسمح بالبحث الدلالي (semantic similarity search) عبر pgvector، بدل الاعتماد فقط
-- على المطابقة النصية / fuzzy clustering اليدوية المذكورة في README الأصلي.
-- الهدف: عند تسجيل بند جديد، نقدر نسأل "هل يوجد بند مشابه فعليًا بالمعنى؟" حتى لو
-- الصياغة مختلفة تمامًا (وليس فقط تشابه حروف)، فنمنع تكرار الكتالوج تلقائيًا.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS vector;

-- بُعد المتجه: 1536 يناسب نماذج تضمين شائعة (مثل text-embedding-3-small من OpenAI).
-- غيّر الرقم هنا (وفي كل الأماكن المطابقة أدناه) لو استخدمت نموذج تضمين مختلف الأبعاد.
-- ============================================================================
-- 1) التصنيفات الرئيسية لبنود الصيانة
-- ============================================================================
CREATE TABLE maintenance_category (
    category_code   VARCHAR(10)  PRIMARY KEY,      -- ELEC, PLMB, HVAC ...
    category_name   VARCHAR(150) NOT NULL,
    description     TEXT,
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ============================================================================
-- 2) كتالوج البنود الموحدة (المرجع الرسمي بدل التكرار الحر) + عمود embedding
-- ============================================================================
CREATE TYPE item_status AS ENUM ('معتمد', 'تحت المراجعة', 'ملغي');
CREATE TYPE item_source AS ENUM ('أرشيف تاريخي 2023-2024', 'بند جديد مضاف');

CREATE TABLE maintenance_service_item (
    item_code       VARCHAR(20)  PRIMARY KEY,      -- ELEC-001, PLMB-014 ...
    category_code   VARCHAR(10)  NOT NULL REFERENCES maintenance_category(category_code),
    item_name       VARCHAR(255) NOT NULL,          -- الاسم الموحد المعتمد
    unit            VARCHAR(30)  NOT NULL,          -- عدد / مقطوعية / متر طولي / متر مربع / متر مكعب / طقم
    standard_price  NUMERIC(12,2),
    min_price       NUMERIC(12,2),
    max_price       NUMERIC(12,2),
    status          item_status  NOT NULL DEFAULT 'تحت المراجعة',
    source          item_source  NOT NULL DEFAULT 'بند جديد مضاف',
    added_by        VARCHAR(150),
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE,
    notes           TEXT,
    -- === الجزء الجديد: تمثيل دلالي (نص = item_name + كل الـ aliases مدموجة) ===
    embedding       vector(1536),
    embedding_source_text TEXT,      -- النص اللي اتحسب منه الـ embedding (للتتبع/إعادة الحساب)
    embedding_updated_at  TIMESTAMPTZ,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- تحديث updated_at تلقائيًا عند أي تعديل (بديل Postgres لـ ON UPDATE CURRENT_TIMESTAMP)
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_service_item_updated_at
    BEFORE UPDATE ON maintenance_service_item
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================================
-- 2ب) مرادفات/صياغات بديلة لنفس البند (تمنع تكرار إنشاء بند جديد لنفس الخدمة)
-- ============================================================================
CREATE TABLE maintenance_service_item_alias (
    alias_id        BIGSERIAL PRIMARY KEY,
    item_code       VARCHAR(20) NOT NULL REFERENCES maintenance_service_item(item_code),
    alias_text      VARCHAR(255) NOT NULL
);

-- ============================================================================
-- 3) الفروع / المواقع (المخازن / الأفرع / البوثات)
-- ============================================================================
CREATE TABLE branch (
    branch_id       SERIAL PRIMARY KEY,
    branch_name     VARCHAR(255) NOT NULL UNIQUE,
    branch_type     VARCHAR(50),                    -- فرع / بوث / مصنع / إداري
    region          VARCHAR(100),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE
);

-- ============================================================================
-- 4) طلبات الصيانة (رأس الطلب)
-- ============================================================================
CREATE TYPE request_status AS ENUM ('جديد', 'قيد التنفيذ', 'مكتمله', 'ملغي');

CREATE TABLE maintenance_request (
    request_id      VARCHAR(30) PRIMARY KEY,        -- EGS-577219804-00101 ... (نفس ترقيم الأرشيف)
    branch_id       INT NOT NULL REFERENCES branch(branch_id),
    request_date    DATE NOT NULL,
    completion_date DATE,
    status          request_status NOT NULL DEFAULT 'جديد',
    requested_by    VARCHAR(150),
    approved_by     VARCHAR(150),
    total_value     NUMERIC(14,2) DEFAULT 0,
    general_note    TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- 5) بنود طلب الصيانة (تفاصيل الطلب - مرتبطة إجباريًا بالكتالوج الموحد)
-- ============================================================================
CREATE TABLE maintenance_request_line (
    line_id         BIGSERIAL PRIMARY KEY,
    request_id      VARCHAR(30) NOT NULL REFERENCES maintenance_request(request_id),
    item_code       VARCHAR(20) NOT NULL REFERENCES maintenance_service_item(item_code),
    quantity        NUMERIC(10,2) NOT NULL DEFAULT 1,
    unit_price      NUMERIC(12,2) NOT NULL,
    line_total      NUMERIC(14,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    custom_note     VARCHAR(500)
);

-- ============================================================================
-- فهارس لتسريع التقارير والبحث
-- ============================================================================
CREATE INDEX idx_request_branch_date ON maintenance_request(branch_id, request_date);
CREATE INDEX idx_line_item           ON maintenance_request_line(item_code);
CREATE INDEX idx_item_category       ON maintenance_service_item(category_code);

-- فهرس pgvector للبحث الدلالي السريع (HNSW: أدق وأسرع في القراءة من IVFFlat لكتالوج بهذا الحجم)
-- ملاحظة: يُبنى فقط بعد ما الأعمدة تتملى بـ embeddings حقيقية (راجع generate_embeddings.py)
-- m/ef_construction مضبوطين صراحة بدل الاعتماد على الافتراضي: مناسبين لكتالوج
-- من مئات لآلاف البنود (دقة عالية بدون بطء بناء محسوس). لو الكتالوج كبر لعشرات
-- الآلاف، ارفع ef_construction لـ128.
CREATE INDEX idx_item_embedding_hnsw
    ON maintenance_service_item
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64)
    WHERE embedding IS NOT NULL;

-- ============================================================================
-- 6) دالة مساعدة: البحث عن أقرب بنود موجودة بالمعنى (لمنع تكرار الكتالوج)
-- تُستخدم قبل إضافة أي بند جديد: لو أعلى تشابه > العتبة، يبقى على الأغلب بند مكرر.
-- ============================================================================
CREATE OR REPLACE FUNCTION find_similar_service_items(
    query_embedding vector(1536),
    match_count     INT DEFAULT 5,
    min_similarity  FLOAT DEFAULT 0.80   -- 1 - cosine_distance ؛ كل ما قرب من 1 كل ما التشابه أعلى
)
RETURNS TABLE (
    item_code    VARCHAR(20),
    item_name    VARCHAR(255),
    category_code VARCHAR(10),
    status       item_status,
    similarity   FLOAT
) AS $$
    SELECT
        i.item_code,
        i.item_name,
        i.category_code,
        i.status,
        1 - (i.embedding <=> query_embedding) AS similarity
    FROM maintenance_service_item i
    WHERE i.embedding IS NOT NULL
      AND i.is_active = TRUE
      AND 1 - (i.embedding <=> query_embedding) >= min_similarity
    ORDER BY i.embedding <=> query_embedding
    LIMIT match_count;
$$ LANGUAGE sql STABLE;

-- ضبط دقة البحث وقت الاستعلام (session-level). القيمة الافتراضية 40؛ ارفعها
-- لدقة أعلى (وبطء أكبر شوية) لو نتائج find_similar_service_items() مش مقنعة:
--   SET hnsw.ef_search = 40;
--
-- بعد أي دفعة كبيرة من UPDATE على عمود embedding (مثلاً بعد تشغيل
-- generate_embeddings.py على كل الكتالوج لأول مرة)، أعد بناء الفهرس بدون قفل
-- الجدول (مهم لو النظام شغال live):
--   REINDEX INDEX CONCURRENTLY idx_item_embedding_hnsw;

-- ============================================================================
-- ملاحظات التنفيذ:
-- - نفس فلسفة الملف الأصلي (maintenance_schema.sql): الكتالوج مرجع وحيد للحقيقة،
--   وأي طلب جديد لازم يشير لـ item_code لا نص حر.
-- - الإضافة هنا: عمود embedding يسمح لـ find_similar_service_items() تكتشف بند
--   مشابه بالمعنى (مش بس بالحروف) قبل ما نسمح بإضافة بند "تحت المراجعة" جديد —
--   ده تطوير مباشر لخطوة "البحث في aliases" المذكورة في README الأصلي، لكن بقدرة
--   أوسع (يمسك صياغات مختلفة تمامًا عن بعضها لفظيًا لكن بنفس المعنى).
-- - حساب الـ embeddings نفسه يحتاج نموذج تضمين خارجي (OpenAI / Cohere / محلي)،
--   راجع scripts/generate_embeddings.py لخطوات الربط — الجدول والفهرس جاهزين
--   ومُختبَرين هنا، لكن تعبئة القيم الفعلية للـ 766 بند يحتاج مفتاح API فعّال.
-- ============================================================================
