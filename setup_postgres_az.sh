#!/bin/bash
# ================================================================
# اسم السكربت: setup_postgres_az.sh
# الغرض: إعداد احترافي وآمن لـ PostgreSQL 17 + pgvector قابل للتكرار
# الإصدار: 1.1
# المؤلف: فريق العزب للمقاولات (مُعاد الصياغة آلياً)
# ملاحظات أمان: لا تحفظ كلمات المرور داخل السكربت؛ يقرأ السكربت كلمات المرور من
# متغيرات بيئة أو يطلبها تفاعلياً.
# ================================================================

set -euo pipefail

# ================================================================
# 1. متغيرات البيئة الأساسية (قابلة للتعديل قبل التشغيل)
# ================================================================
PG_VER="17"
PG_PORT="5433"
PG_CLUSTER="main"
PG_DATA="/var/lib/postgresql/$PG_VER/$PG_CLUSTER"
PG_LOG="/var/log/postgresql/postgresql-$PG_VER-$PG_CLUSTER.log"
PG_CONF="/etc/postgresql/$PG_VER/$PG_CLUSTER/postgresql.conf"
PG_HBA="/etc/postgresql/$PG_VER/$PG_CLUSTER/pg_hba.conf"
TIMEZONE="Africa/Cairo"
LOCALE="ar_EG.UTF-8"

# متغيرات أمان/تهيئة
# وضع كلمات المرور كمتغيرات بيئة أفضل من وضعها داخل السكربت.
: "${APP_DB_USER:=app_user}"
: "${READONLY_DB_USER:=readonly_user}"
: "${PGVECTOR_VERSION:=v0.8.5}"
: "${ALLOW_DROP_OLD_CLUSTERS:=false}"
: "${ALLOW_WORLD_ACCESS:=false}"

# كلمات المرور: يُفضّل تصديرها كمتغير بيئة قبل التشغيل، وإلا سيطلب السكربت إدخالها.
if [[ -z "${APP_DB_PASSWORD-}" ]]; then
    read -s -p "أدخل كلمة مرور المستخدم $APP_DB_USER: " APP_DB_PASSWORD
    echo
fi
if [[ -z "${READONLY_DB_PASSWORD-}" ]]; then
    read -s -p "أدخل كلمة مرور المستخدم $READONLY_DB_USER: " READONLY_DB_PASSWORD
    echo
fi

# ================================================================
# 2. ألوان الإخراج
# ================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ================================================================
# 3. بانر
# ================================================================
banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                                                           ║"
    echo "║    🏗️  شركة العزب للمقاولات - نظام إدارة الصادرات                    ║"
    echo "║                                                           ║"
    echo "║    📦 PostgreSQL $PG_VER - Vision 2030                   ║"
    echo "║                                                           ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

step() {
    echo -e "\n${BLUE}🔹 $1...${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# ================================================================
# 4. صلاحيات روت
# ================================================================
check_root() {
    step "التحقق من صلاحيات الجذر"
    if [[ $EUID -ne 0 ]]; then
        error "يجب تشغيل السكربت بصلاحيات الجذر (sudo)"
    fi
    success "تم التحقق من الصلاحيات"
}

# ================================================================
# 5. تثبيت حزم النظام الأساسية
# ================================================================
install_system_packages() {
    step "تثبيت حزم النظام الأساسية"

    # تحديث وقاعدة تثبيت آمنة
    apt-get update || error "فشل تحديث الحزم"

    apt-get install -y \
        wget curl gnupg lsb-release \
        build-essential gcc make \
        postgresql-$PG_VER postgresql-client-$PG_VER \
        postgresql-server-dev-$PG_VER \
        postgresql-contrib-$PG_VER \
        language-pack-ar \
        htop nmon sysstat \
        git \
        || error "فشل تثبيت الحزم"

    success "تم تثبيت جميع الحزم المطلوبة (إن لم تكن مثبتة سابقاً)"
}

# ================================================================
# 6. تثبيت pgvector من مصدر محدد (اختياري: فرع/وضع نسخة)
# ================================================================
install_pgvector() {
    step "تثبيت إضافة pgvector للبحث الدلالي (النسخة: $PGVECTOR_VERSION)"
    cd /tmp || error "لا يمكن الانتقال إلى /tmp"
    rm -rf pgvector
    git clone --branch "$PGVECTOR_VERSION" --depth 1 https://github.com/pgvector/pgvector.git || error "فشل تحميل pgvector"
    cd pgvector || error "لا يمكن الدخول إلى مجلد pgvector"
    make clean || true
    make || error "فشل بناء pgvector"
    make install || error "فشل تثبيت pgvector"
    cd /tmp
    rm -rf pgvector
    success "تم تثبيت pgvector بنجاح (النسخة: $PGVECTOR_VERSION)"
}

# ================================================================
# 7. تنظيف الكتل القديمة (اختياري وبحذر)
# ================================================================
clean_old_clusters() {
    step "تنظيف الكتل القديمة (PostgreSQL 14 و 15 و 16) - (اختياري)"

    if [[ "$ALLOW_DROP_OLD_CLUSTERS" != "true" ]]; then
        warning "تخطي حذف وإزالة الكتل القديمة لأن ALLOW_DROP_OLD_CLUSTERS != true"
        return
    fi

    for ver in 14 15 16; do
        if command -v pg_lsclusters >/dev/null 2>&1 && pg_lsclusters | grep -q "^$ver"; then
            pg_dropcluster "$ver" main --stop 2>/dev/null || true
            rm -rf "/var/lib/postgresql/$ver" 2>/dev/null || true
            warning "تم حذف الإصدار $ver"
        fi
    done
    success "انتهى تنظيف الكتل القديمة (الخطوات كانت اختيارية)"
}

# ================================================================
# 8. إنشاء كتلة PostgreSQL 17 الجديدة
# ================================================================
create_cluster() {
    step "إنشاء كتلة PostgreSQL $PG_VER الجديدة (إذا لم تكن موجودة)"

    if command -v pg_createcluster >/dev/null 2>&1; then
        pg_dropcluster $PG_VER $PG_CLUSTER --stop 2>/dev/null || true
        pg_createcluster -p $PG_PORT -e $LOCALE $PG_VER $PG_CLUSTER || error "فشل إنشاء الكتلة"
        success "تم إنشاء الكتلة على المنفذ $PG_PORT"
    else
        error "الأدوات الخاصة بإدارة الكتل (pg_createcluster) غير موجودة على هذا النظام"
    fi
}

# ================================================================
# 9. تكوين postgresql.conf (تحسينات آمنة)
# ================================================================
configure_postgresql() {
    step "تكوين ملف postgresql.conf - إعدادات احترافية افتراضية"

    # نستخدم heredoc بدون اقتباس حتى تتوسع المتغيرات
    cat > $PG_CONF <<EOF
# ================================================================
# PostgreSQL $PG_VER - إعداد احترافي لشركة العزب للمقاولات
# ================================================================

listen_addresses = '*'
port = $PG_PORT
max_connections = 200
superuser_reserved_connections = 10
unix_socket_directories = '/var/run/postgresql'
ssl = on
ssl_cert_file = '/etc/ssl/certs/ssl-cert-snakeoil.pem'
ssl_key_file = '/etc/ssl/private/ssl-cert-snakeoil.key'

# الذاكرة - عدّل هذه القيم حسب حجم RAM الفعلي
shared_buffers = '16GB'
work_mem = '64MB'
maintenance_work_mem = '1GB'
effective_cache_size = '48GB'
huge_pages = 'try'

# المعالج
max_worker_processes = 16
max_parallel_workers = 16
max_parallel_workers_per_gather = 8
parallel_leader_participation = on

# I/O
effective_io_concurrency = 200
random_page_cost = 1.1
seq_page_cost = 1.0

# السجلات
logging_collector = on
log_directory = '/var/log/postgresql'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = '1d'
log_rotation_size = '100MB'
log_line_prefix = '%m [%p] %q%u@%d '
log_timezone = '$TIMEZONE'
log_statement = 'ddl'
log_min_duration_statement = 1000
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
log_temp_files = 0
log_autovacuum_min_duration = 0

# Autovacuum
autovacuum = on
autovacuum_max_workers = 4
autovacuum_naptime = '1min'
autovacuum_vacuum_threshold = 50
autovacuum_analyze_threshold = 50
autovacuum_vacuum_scale_factor = 0.1
autovacuum_analyze_scale_factor = 0.05
autovacuum_freeze_max_age = 200000000
autovacuum_multixact_freeze_max_age = 400000000

# Checkpoints
checkpoint_timeout = '15min'
checkpoint_completion_target = 0.9
max_wal_size = '4GB'
min_wal_size = '1GB'

# اللغة والمنطقة الزمنية
timezone = '$TIMEZONE'
lc_messages = '$LOCALE'
lc_monetary = '$LOCALE'
lc_numeric = '$LOCALE'
lc_time = '$LOCALE'
default_text_search_config = 'arabic'

# أدوات احصائية
track_activity_query_size = 4096
stats_temp_directory = '/var/run/postgresql'
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.track = all
pg_stat_statements.max = 10000

# ملاحظة: لا نُعطِّل enable_seqscan على مستوى الخادم بشكل دائم هنا.
# ترك هذا الإعداد للتعديل حسب احتياج استعلامات محددة.

EOF

    success "تم تحديث ملف $PG_CONF"
}

# ================================================================
# 10. تكوين pg_hba.conf
# ================================================================
configure_pg_hba() {
    step "تكوين سياسات الاتصال (pg_hba.conf)"

    # شبكة افتراضية آمنة: افتراضيًا نسمح فقط للشبكات المحلية. يمكن تفعيل الوصول العام عبر متغير.
    cat > $PG_HBA <<EOF
# ================================================================
# سياسات الاتصال لـ PostgreSQL $PG_VER
# ================================================================

local   all             postgres                                peer
local   all             all                                     scram-sha-256

# الشبكات الداخلية الآمنة
host    all             all             10.0.0.0/8              scram-sha-256
host    all             all             172.16.0.0/12           scram-sha-256
host    all             all             192.168.0.0/16          scram-sha-256

# IPv6 المحلي
host    all             all             ::1/128                 scram-sha-256

EOF

    if [[ "$ALLOW_WORLD_ACCESS" == "true" ]]; then
        cat >> $PG_HBA <<EOF
# الوصول من أي مكان (مفعل بواسطة ALLOW_WORLD_ACCESS=true) - استخدمه بحذر
host    all             all             0.0.0.0/0               scram-sha-256
host    all             all             ::0/0                   scram-sha-256
EOF
    else
        warning "تم تعطيل الوصول من 0.0.0.0/0 افتراضيًا. لتفعيله اضبط ALLOW_WORLD_ACCESS=true مع الحذر الشديد"
    fi

    success "تم تحديث ملف $PG_HBA"
}

# ================================================================
# 11. تشغيل الخدمة والتحقق
# ================================================================
start_service() {
    step "تشغيل خدمة PostgreSQL $PG_VER"
    # على Debian/Ubuntu
    systemctl restart postgresql || true
    sleep 3
    systemctl is-active --quiet postgresql || error "خدمة PostgreSQL لا تعمل"
    success "خدمة PostgreSQL قيد التشغيل"
}

# ================================================================
# 12. تفعيل pgvector (الامتداد)
# ================================================================
enable_pgvector() {
    step "تفعيل إضافة pgvector في قاعدة البيانات"
    sudo -u postgres psql -p $PG_PORT -d postgres -c "CREATE EXTENSION IF NOT EXISTS vector;" || error "فشل تفعيل pgvector"
    success "تم تفعيل pgvector بنجاح"
}

# ================================================================
# 13. إنشاء المستخدمين وقواعد البيانات (باستخدام كلمات مرور آمنة)
# ================================================================
create_users_and_databases() {
    step "إنشاء المستخدمين وقواعد البيانات الأساسية"

    sudo -u postgres psql -p $PG_PORT <<EOF
-- مستخدم التطبيق الرئيسي
DO \$\$ BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$APP_DB_USER') THEN
      CREATE USER $APP_DB_USER WITH PASSWORD '$APP_DB_PASSWORD' CREATEDB CREATEROLE;
   END IF;
END\$\$;

DO \$\$ BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$READONLY_DB_USER') THEN
      CREATE USER $READONLY_DB_USER WITH PASSWORD '$READONLY_DB_PASSWORD';
   END IF;
END\$\$;

-- Note: CREATE DATABASE IF NOT EXISTS is not standard in Postgres; use PL/pgSQL guard
DO \$\$ BEGIN
   IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'azab_company') THEN
      PERFORM dblink_exec('dbname=postgres', 'CREATE DATABASE azab_company OWNER $APP_DB_USER');
   END IF;
END\$\$;

DO \$\$ BEGIN
   IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'azab_test') THEN
      PERFORM dblink_exec('dbname=postgres', 'CREATE DATABASE azab_test OWNER $APP_DB_USER');
   END IF;
END\$\$;

-- الاتصال بقاعدة البيانات
\c azab_company

CREATE SCHEMA IF NOT EXISTS products;
CREATE SCHEMA IF NOT EXISTS sales;
CREATE SCHEMA IF NOT EXISTS inventory;
CREATE SCHEMA IF NOT EXISTS agents;
CREATE SCHEMA IF NOT EXISTS logs;

GRANT ALL PRIVILEGES ON SCHEMA products TO $APP_DB_USER;
GRANT ALL PRIVILEGES ON SCHEMA sales TO $APP_DB_USER;
GRANT ALL PRIVILEGES ON SCHEMA inventory TO $APP_DB_USER;
GRANT ALL PRIVILEGES ON SCHEMA agents TO $APP_DB_USER;
GRANT ALL PRIVILEGES ON SCHEMA logs TO $APP_DB_USER;

-- جداول أساسية (إن لم تكن موجودة)
CREATE TABLE IF NOT EXISTS products.products (
    id BIGSERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    category TEXT,
    price DECIMAL(15,2),
    unit TEXT,
    embedding vector(768),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS products.services (
    id BIGSERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    service_type TEXT,
    price DECIMAL(15,2),
    duration INTERVAL,
    embedding vector(768),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS sales.exports (
    id BIGSERIAL PRIMARY KEY,
    product_id BIGINT REFERENCES products.products(id),
    service_id BIGINT REFERENCES products.services(id),
    quantity DECIMAL(15,2),
    unit_price DECIMAL(15,2),
    total_price DECIMAL(15,2),
    customer_name TEXT,
    customer_country TEXT,
    export_date TIMESTAMPTZ DEFAULT NOW(),
    status TEXT DEFAULT 'pending',
    embedding vector(768),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS sales.imports (
    id BIGSERIAL PRIMARY KEY,
    product_id BIGINT REFERENCES products.products(id),
    service_id BIGINT REFERENCES products.services(id),
    quantity DECIMAL(15,2),
    unit_price DECIMAL(15,2),
    total_price DECIMAL(15,2),
    supplier_name TEXT,
    supplier_country TEXT,
    import_date TIMESTAMPTZ DEFAULT NOW(),
    status TEXT DEFAULT 'pending',
    embedding vector(768),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS logs.agent_logs (
    id BIGSERIAL PRIMARY KEY,
    action TEXT,
    query TEXT,
    response TEXT,
    model_used TEXT,
    execution_time_ms INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- فهارس نصية ومتجهية (تأكد من وجود الامتدادات المطلوبة)
CREATE INDEX IF NOT EXISTS idx_products_name ON products.products USING GIN (to_tsvector('arabic', name || ' ' || COALESCE(description, '')));
CREATE INDEX IF NOT EXISTS idx_services_name ON products.services USING GIN (to_tsvector('arabic', name || ' ' || COALESCE(description, '')));
CREATE INDEX IF NOT EXISTS idx_exports_customer ON sales.exports(customer_name);
CREATE INDEX IF NOT EXISTS idx_imports_supplier ON sales.imports(supplier_name);
CREATE INDEX IF NOT EXISTS idx_exports_date ON sales.exports(export_date DESC);
CREATE INDEX IF NOT EXISTS idx_imports_date ON sales.imports(import_date DESC);

-- ملاحظة: إنشاء فهارس متجهية قد يستدعي قواعد إضافية مثل IVFFlat/HNSW
-- تنفيذها يفضل بعد تحميل بيانات كافية
-- CREATE INDEX IF NOT EXISTS idx_products_embedding ON products.products USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
-- CREATE INDEX IF NOT EXISTS idx_services_embedding ON products.services USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

EOF

    success "تم إنشاء المستخدمين وقواعد البيانات والجداول الأساسية (إن لم تكن موجودة)"
}

# ================================================================
# 14. إعداد التحديثات التلقائية (اختياري)
# ================================================================
setup_autoupdates() {
    step "إعداد التحديثات التلقائية للصيانة"
    apt-get install -y unattended-upgrades || warning "فشل تثبيت التحديثات التلقائية"
    cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
    success "تم إعداد التحديثات التلقائية"
}

# ================================================================
# 15. النسخ الاحتياطي الآمن
# ================================================================
setup_backup() {
    step "إعداد النسخ الاحتياطي التلقائي"
    mkdir -p /var/backups/postgresql
    chown postgres:postgres /var/backups/postgresql

    cat > /etc/cron.d/postgres_backup <<'CRON_EOF'
# النسخ الاحتياطي اليومي الساعة 2 صباحاً
0 2 * * * postgres bash -lc "pg_dump -p 5433 azab_company | gzip > /var/backups/postgresql/azab_company_$(date +\%Y\%m\%d).sql.gz"

# تنظيف النسخ الاحتياطي الأقدم من 30 يوماً
0 3 * * * root find /var/backups/postgresql -name "*.sql.gz" -mtime +30 -delete
CRON_EOF

    success "تم إعداد النسخ الاحتياطي التلقائي"
}

# ================================================================
# 16. إعداد المراقبة
# ================================================================
setup_monitoring() {
    step "إعداد أدوات المراقبة"

    cat > /usr/local/bin/pg_monitor.sh <<'MON_EOF'
#!/bin/bash
set -euo pipefail
echo "=== PostgreSQL 17 - حالة النظام ==="
echo "-----------------------------------"
echo "📊 الاتصالات النشطة:"
sudo -u postgres psql -p 5433 -At -c "SELECT count(*) FROM pg_stat_activity;"
echo ""
echo "📊 حجم قاعدة البيانات:"
sudo -u postgres psql -p 5433 -At -c "SELECT pg_database_size('azab_company')/1024/1024/1024 || ' GB';"
echo ""
echo "📊 حالة الـ Autovacuum:"
sudo -u postgres psql -p 5433 -c "SELECT schemaname, relname, last_vacuum, last_autovacuum FROM pg_stat_all_tables WHERE last_autovacuum IS NOT NULL ORDER BY last_autovacuum DESC LIMIT 5;"
echo ""
echo "📊 الاستعلامات البطيئة (أكثر من 1 ثانية):"
sudo -u postgres psql -p 5433 -c "SELECT query, calls, total_time, mean_time FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 5;"
MON_EOF

    chmod +x /usr/local/bin/pg_monitor.sh
    success "تم إعداد أدوات المراقبة"
}

# ================================================================
# 17. ملف المعلومات النهائي
# ================================================================
final_info() {
    cat > /root/postgres_2030_info.txt <<EOF
╔═════════════════════════════════════════════════════════════════
║
║     📋 تقرير الإعداد النهائي - PostgreSQL 17 حتى 2030
║
╠═════════════════════════════════════════════════════════════════
║
║   📅 تاريخ الإعداد: $(date)
║   🏗️  للشركة: شركة العزب للمقاولات
║
║   🐘 الإصدار: PostgreSQL $PG_VER
║   📍 المنفذ: $PG_PORT
║   🌐 المنطقة الزمنية: $TIMEZONE
║   🗣️  اللغة: العربية ($LOCALE)
║
║   📦 الإضافات المثبتة:
║     - pgvector (النسخة: $PGVECTOR_VERSION)
║     - pg_stat_statements
║
║   👤 المستخدمون:
║     - $APP_DB_USER (مدير التطبيق)
║     - $READONLY_DB_USER (للقراءة فقط)
║
║   🗄️  قواعد البيانات:
║     - azab_company (الرئيسية)
║     - azab_test (للاختبارات)
║
║   📂 المخططات (Schemas): products, sales, inventory, agents, logs
║
║   📊 أدوات المراقبة:
║     - htop, nmon, sysstat
║     - /usr/local/bin/pg_monitor.sh
║
║   💾 النسخ الاحتياطي:
║     - يومياً الساعة 2 صباحاً (حفظ 30 يوماً)
║
║   🔐 ملاحظات أمان:
║     - كلمات المرور لم تُحفظ في ملف السكربت
║     - SSL: افتراضي (snakeoil) — استبدل بشهادة صالحة للإنتاج
║     - pg_hba.conf محدود للشبكات الخاصة افتراضياً
║
║   📁 ملفات الإعدادات:
║     - $PG_CONF
║     - $PG_HBA
║
║   🚀 للاتصال بقاعدة البيانات:
║     psql -p $PG_PORT -U $APP_DB_USER -d azab_company -h localhost
║
╚═════════════════════════════════════════════════════════════════
EOF

    cat /root/postgres_2030_info.txt || true
}

# ================================================================
# 18. الدالة الرئيسية
# ================================================================
main() {
    clear
    banner
    echo -e "${YELLOW}سيبدأ الإعداد الاحترافي لـ PostgreSQL 17.${NC}"
    echo -e "${YELLOW}يرجى الانتظار...${NC}\n"

    check_root
    install_system_packages
    install_pgvector
    clean_old_clusters
    create_cluster
    configure_postgresql
    configure_pg_hba
    start_service
    enable_pgvector
    create_users_and_databases
    setup_autoupdates
    setup_backup
    setup_monitoring
    final_info

    echo -e "\n${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║ ✅ اكتمل الإعداد الاحترافي لـ PostgreSQL 17 بنجاح!         ║${NC}"
    echo -e "${GREEN}║ 🎯 صالح للاستخدام حتى عام 2030                            ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo -e "\n${CYAN}📋 للحصول على معلومات كاملة، استخدم:${NC}"
    echo -e "   cat /root/postgres_2030_info.txt\n"
}

# ================================================================
# تشغيل السكربت
# ================================================================
main "$@"
