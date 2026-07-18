#!/bin/bash
# ================================================================
# اسم السكربت: setup_postgres_az.sh
# الغرض: الإعداد الاحترافي لـ PostgreSQL 17 للاستخدام حتى عام 2030
# الإصدار: 1.0
# المؤلف: فريق العزب للمقاولات
# ================================================================

# ================================================================
# 1. متغيرات البيئة الأساسية
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

# ================================================================
# 2. الألوان لجعل الإخراج جميل ومنظم
# ================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ================================================================
# 3. دالة عرض البانر الترحيبي
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

# ================================================================
# 4. دالة عرض التقدم
# ================================================================
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
# 5. التحقق من صلاحيات الجذر
# ================================================================
check_root() {
    step "التحقق من صلاحيات الجذر"
    if [[ $EUID -ne 0 ]]; then
        error "يجب تشغيل السكربت بصلاحيات الجذر (sudo)"
    fi
    success "تم التحقق من الصلاحيات"
}

# ================================================================
# 6. تثبيت حزم النظام الأساسية
# ================================================================
install_system_packages() {
    step "تثبيت حزم النظام الأساسية"
    apt update -y || error "فشل تحديث الحزم"
    apt install -y \
        wget curl gnupg lsb-release \
        build-essential gcc make \
        postgresql-$PG_VER postgresql-client-$PG_VER \
        postgresql-server-dev-$PG_VER \
        postgresql-contrib-$PG_VER \
        language-pack-ar \
        htop nmon sysstat \
        || error "فشل تثبيت الحزم"
    success "تم تثبيت جميع الحزم"
}

# ================================================================
# 7. تثبيت pgvector من المصدر
# ================================================================
install_pgvector() {
    step "تثبيت إضافة pgvector للبحث الدلالي"
    cd /tmp || error "لا يمكن الانتقال إلى /tmp"
    rm -rf pgvector
    git clone https://github.com/pgvector/pgvector.git || error "فشل تحميل pgvector"
    cd pgvector || error "لا يمكن الدخول إلى مجلد pgvector"
    make clean
    make || error "فشل بناء pgvector"
    make install || error "فشل تثبيت pgvector"
    cd /tmp
    rm -rf pgvector
    success "تم تثبيت pgvector بنجاح"
}

# ================================================================
# 8. إيقاف وإزالة الكتل القديمة
# ================================================================
clean_old_clusters() {
    step "تنظيف الكتل القديمة (PostgreSQL 14 و 15 و 16)"
    for ver in 14 15 16; do
        if pg_lsclusters | grep -q "^$ver"; then
            pg_dropcluster "$ver" main --stop 2>/dev/null || true
            rm -rf "/var/lib/postgresql/$ver" 2>/dev/null || true
            warning "تم حذف الإصدار $ver"
        fi
    done
    success "تم تنظيف الكتل القديمة"
}

# ================================================================
# 9. إنشاء كتلة PostgreSQL 17 الجديدة
# ================================================================
create_cluster() {
    step "إنشاء كتلة PostgreSQL $PG_VER الجديدة"
    pg_dropcluster $PG_VER $PG_CLUSTER --stop 2>/dev/null || true
    pg_createcluster -p $PG_PORT -e $LOCALE $PG_VER $PG_CLUSTER || error "فشل إنشاء الكتلة"
    success "تم إنشاء الكتلة على المنفذ $PG_PORT"
}

# ================================================================
# 10. إعداد ملف postgresql.conf - الإعداد الاحترافي حتى 2030
# ================================================================
configure_postgresql() {
    step "تكوين ملف postgresql.conf - الإعدادات الاحترافية"

    cat > $PG_CONF << 'EOF'
# ================================================================
# PostgreSQL 17 - الإعداد الاحترافي لشركة العزب للمقاولات
# صالح للاستخدام حتى عام 2030 - مبني على أفضل الممارسات العالمية
# ================================================================

# -------------------------------
# الاتصالات والأمان
# -------------------------------
listen_addresses = '*'
port = 5433
max_connections = 200
superuser_reserved_connections = 10
unix_socket_directories = '/var/run/postgresql'
ssl = on
ssl_cert_file = '/etc/ssl/certs/ssl-cert-snakeoil.pem'
ssl_key_file = '/etc/ssl/private/ssl-cert-snakeoil.key'

# -------------------------------
# الذاكرة والأداء - محسن لـ 64GB RAM
# -------------------------------
shared_buffers = '16GB'                    # 25% من إجمالي الذاكرة
work_mem = '64MB'                          # للفرز والتجميع
maintenance_work_mem = '1GB'               # للصيانة والفهرسة
effective_cache_size = '48GB'              # 75% من إجمالي الذاكرة
huge_pages = 'try'                         # استخدام الصفحات الضخمة

# -------------------------------
# المعالج (CPU)
# -------------------------------
max_worker_processes = 16                  # عدد أنوية المعالج
max_parallel_workers = 16
max_parallel_workers_per_gather = 8
parallel_leader_participation = on

# -------------------------------
# القرص الصلب (I/O)
# -------------------------------
effective_io_concurrency = 200             # لـ NVMe/SSD
random_page_cost = 1.1                     # لـ SSD
seq_page_cost = 1.0

# -------------------------------
# السجلات والمراقبة (Monitoring)
# -------------------------------
logging_collector = on
log_directory = '/var/log/postgresql'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = '1d'
log_rotation_size = '100MB'
log_line_prefix = '%m [%p] %q%u@%d '
log_timezone = 'Africa/Cairo'
log_statement = 'ddl'                      # تسجيل تغييرات الهيكل فقط
log_min_duration_statement = 1000          # الاستعلامات التي تستغرق أكثر من 1 ثانية
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
log_temp_files = 0
log_autovacuum_min_duration = 0

# -------------------------------
# الفهرسة والبحث (pgvector)
# -------------------------------
# ملاحظة: pgvector يستخدم هذه الإعدادات
enable_seqscan = off                       # تفضيل الفهارس في البحث الدلالي
enable_indexscan = on
enable_bitmapscan = on

# -------------------------------
# Autovacuum - الصيانة التلقائية
# -------------------------------
autovacuum = on
autovacuum_max_workers = 4
autovacuum_naptime = '1min'
autovacuum_vacuum_threshold = 50
autovacuum_analyze_threshold = 50
autovacuum_vacuum_scale_factor = 0.1
autovacuum_analyze_scale_factor = 0.05
autovacuum_freeze_max_age = 200000000
autovacuum_multixact_freeze_max_age = 400000000

# -------------------------------
# Checkpoints - التوازن بين الأداء والأمان
# -------------------------------
checkpoint_timeout = '15min'
checkpoint_completion_target = 0.9
max_wal_size = '4GB'
min_wal_size = '1GB'

# -------------------------------
# اللغة والمنطقة الزمنية
# -------------------------------
timezone = 'Africa/Cairo'
lc_messages = 'ar_EG.UTF-8'
lc_monetary = 'ar_EG.UTF-8'
lc_numeric = 'ar_EG.UTF-8'
lc_time = 'ar_EG.UTF-8'
default_text_search_config = 'arabic'

# -------------------------------
# إعدادات متقدمة أخرى
# -------------------------------
track_activity_query_size = 4096
stats_temp_directory = '/var/run/postgresql'
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.track = all
pg_stat_statements.max = 10000

# -------------------------------
# إعدادات مخصصة لـ pgvector
# -------------------------------
# تسريع البحث عن المتجهات
max_parallel_workers = 16
max_parallel_workers_per_gather = 8
enable_seqscan = off

EOF

    success "تم تحديث ملف postgresql.conf"
}

# ================================================================
# 11. إعداد ملف pg_hba.conf - سياسات الاتصال
# ================================================================
configure_pg_hba() {
    step "تكوين سياسات الاتصال (pg_hba.conf)"

    cat > $PG_HBA << 'EOF'
# ================================================================
# سياسات الاتصال لـ PostgreSQL 17
# شركة العزب للمقاولات - إعداد احترافي
# ================================================================

# نوع المصادقة: scram-sha-256 (الأكثر أماناً)

# الاتصال المحلي (Local)
local   all             postgres                                peer
local   all             all                                     scram-sha-256

# الاتصال عبر IPv4 من الشبكة الداخلية
host    all             all             10.0.0.0/8              scram-sha-256
host    all             all             172.16.0.0/12           scram-sha-256
host    all             all             192.168.0.0/16          scram-sha-256

# الاتصال عبر IPv6 المحلي
host    all             all             ::1/128                 scram-sha-256
host    all             all             fe80::/10               scram-sha-256

# الاتصال عبر IPv4 من أي مكان (مع كلمة مرور قوية)
# ملاحظة: يجب تغيير هذا في بيئة الإنتاج
host    all             all             0.0.0.0/0               scram-sha-256

# الاتصال عبر IPv6 من أي مكان
host    all             all             ::0/0                   scram-sha-256

EOF

    success "تم تحديث ملف pg_hba.conf"
}

# ================================================================
# 12. تشغيل الخدمة والتحقق
# ================================================================
start_service() {
    step "تشغيل خدمة PostgreSQL $PG_VER"
    pg_ctlcluster $PG_VER $PG_CLUSTER start || error "فشل تشغيل الخدمة"
    sleep 3
    success "تم تشغيل الخدمة بنجاح"
}

# ================================================================
# 13. تفعيل pgvector
# ================================================================
enable_pgvector() {
    step "تفعيل إضافة pgvector في قاعدة البيانات"
    sudo -u postgres psql -p $PG_PORT -d postgres -c "CREATE EXTENSION IF NOT EXISTS vector;" || error "فشل تفعيل pgvector"
    success "تم تفعيل pgvector بنجاح"
}

# ================================================================
# 14. إنشاء المستخدمين وقواعد البيانات الأساسية
# ================================================================
create_users_and_databases() {
    step "إنشاء المستخدمين وقواعد البيانات"

    sudo -u postgres psql -p $PG_PORT << 'EOF'
-- مستخدم التطبيق الرئيسي
CREATE USER app_user WITH PASSWORD 'Azab_2030_Strong!' CREATEDB CREATEROLE;

-- مستخدم للقراءة فقط (للتحليلات)
CREATE USER readonly_user WITH PASSWORD 'ReadOnly_2030!';

-- قاعدة البيانات الرئيسية للشركة
CREATE DATABASE azab_company OWNER app_user;

-- قاعدة البيانات للاختبارات
CREATE DATABASE azab_test OWNER app_user;

-- منح الصلاحيات
GRANT CONNECT ON DATABASE azab_company TO app_user;
GRANT CONNECT ON DATABASE azab_company TO readonly_user;

-- الاتصال بقاعدة البيانات الرئيسية
\c azab_company

-- إنشاء مخططات (Schemas)
CREATE SCHEMA IF NOT EXISTS products;
CREATE SCHEMA IF NOT EXISTS sales;
CREATE SCHEMA IF NOT EXISTS inventory;
CREATE SCHEMA IF NOT EXISTS agents;
CREATE SCHEMA IF NOT EXISTS logs;

-- منح الصلاحيات على المخططات
GRANT ALL PRIVILEGES ON SCHEMA products TO app_user;
GRANT ALL PRIVILEGES ON SCHEMA sales TO app_user;
GRANT ALL PRIVILEGES ON SCHEMA inventory TO app_user;
GRANT ALL PRIVILEGES ON SCHEMA agents TO app_user;
GRANT ALL PRIVILEGES ON SCHEMA logs TO app_user;

-- إنشاء جدول المنتجات مع دعم المتجهات
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

-- إنشاء جدول الخدمات
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

-- إنشاء جدول الصادرات
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

-- إنشاء جدول الواردات
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

-- إنشاء جدول سجل الأنشطة للوكيل الذكي
CREATE TABLE IF NOT EXISTS logs.agent_logs (
    id BIGSERIAL PRIMARY KEY,
    action TEXT,
    query TEXT,
    response TEXT,
    model_used TEXT,
    execution_time_ms INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- إنشاء فهارس لتحسين الأداء
CREATE INDEX idx_products_name ON products.products USING GIN (to_tsvector('arabic', name || ' ' || COALESCE(description, '')));
CREATE INDEX idx_services_name ON products.services USING GIN (to_tsvector('arabic', name || ' ' || COALESCE(description, '')));
CREATE INDEX idx_exports_customer ON sales.exports(customer_name);
CREATE INDEX idx_imports_supplier ON sales.imports(supplier_name);
CREATE INDEX idx_exports_date ON sales.exports(export_date DESC);
CREATE INDEX idx_imports_date ON sales.imports(import_date DESC);

-- فهارس المتجهات للبحث الدلالي السريع
CREATE INDEX idx_products_embedding ON products.products USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
CREATE INDEX idx_services_embedding ON products.services USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- إضافة بعض البيانات التجريبية
INSERT INTO products.products (name, description, category, price, unit) VALUES
('أسمنت بورتلاند 42.5', 'أسمنت بورتلاند عالي الجودة مناسب للخرسانة المسلحة والأساسات', 'مواد بناء', 850.00, 'طن'),
('حديد تسليح 12 مم', 'حديد تسليح مصري عالي الجودة مطابق للمواصفات القياسية', 'مواد بناء', 18500.00, 'طن'),
('مضخة خرسانة', 'مضخة خرسانة متنقلة بقدرة 40 متر مكعب في الساعة', 'معدات', 350000.00, 'وحدة'),
('سقالات معدنية', 'سقالات معدنية قابلة للتفكيك بارتفاع يصل إلى 20 متر', 'معدات', 25000.00, 'مجموعة');

INSERT INTO products.services (name, description, service_type, price) VALUES
('استشارات هندسية', 'خدمات استشارية هندسية متكاملة تشمل التصميم والإشراف', 'استشارات', 5000.00),
('اختبارات المواد', 'اختبارات معملية لمواد البناء والتربة والخرسانة', 'مختبرات', 3000.00),
('تأجير معدات', 'تأجير معدات البناء الثقيلة للمشاريع', 'تأجير', 10000.00);

EOF

    success "تم إنشاء المستخدمين وقواعد البيانات والجداول"
}

# ================================================================
# 15. إعداد التحديثات التلقائية (للأمان)
# ================================================================
setup_autoupdates() {
    step "إعداد التحديثات التلقائية للصيانة"
    apt install -y unattended-upgrades || warning "فشل تثبيت التحديثات التلقائية"
    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
    success "تم إعداد التحديثات التلقائية"
}

# ================================================================
# 16. إعداد النسخ الاحتياطي التلقائي
# ================================================================
setup_backup() {
    step "إعداد النسخ الاحتياطي التلقائي"
    mkdir -p /var/backups/postgresql
    chown postgres:postgres /var/backups/postgresql

    cat > /etc/cron.d/postgres_backup << 'EOF'
# النسخ الاحتياطي اليومي الساعة 2 صباحاً
0 2 * * * postgres pg_dump -p 5433 azab_company | gzip > /var/backups/postgresql/azab_company_$(date +\%Y\%m\%d).sql.gz

# تنظيف النسخ الاحتياطي الأقدم من 30 يوماً
0 3 * * * find /var/backups/postgresql -name "*.sql.gz" -mtime +30 -delete
EOF

    success "تم إعداد النسخ الاحتياطي التلقائي"
}

# ================================================================
# 17. إعداد المراقبة (Monitoring)
# ================================================================
setup_monitoring() {
    step "إعداد أدوات المراقبة"

    cat > /usr/local/bin/pg_monitor.sh << 'EOF'
#!/bin/bash
echo "=== PostgreSQL 17 - حالة النظام ==="
echo "-----------------------------------"
echo "📊 الاتصالات النشطة:"
sudo -u postgres psql -p 5433 -c "SELECT count(*) FROM pg_stat_activity;"
echo ""
echo "📊 حجم قاعدة البيانات:"
sudo -u postgres psql -p 5433 -c "SELECT pg_database_size('azab_company')/1024/1024/1024 || ' GB';"
echo ""
echo "📊 حالة الـ Autovacuum:"
sudo -u postgres psql -p 5433 -c "SELECT schemaname, relname, last_vacuum, last_autovacuum FROM pg_stat_all_tables WHERE last_autovacuum IS NOT NULL ORDER BY last_autovacuum DESC LIMIT 5;"
echo ""
echo "📊 الاستعلامات البطيئة (أكثر من 1 ثانية):"
sudo -u postgres psql -p 5433 -c "SELECT query, calls, total_time, mean_time FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 5;"
EOF

    chmod +x /usr/local/bin/pg_monitor.sh
    success "تم إعداد أدوات المراقبة"
}

# ================================================================
# 18. إنشاء ملف المعلومات النهائية
# ================================================================
final_info() {
    cat > /root/postgres_2030_info.txt << 'EOF'
╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║     📋 تقرير الإعداد النهائي - PostgreSQL 17 حتى 2030                             ║
║                                                                           ║
╠═══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║   📅 تاريخ الإعداد: $(date)                                                   ║
║   🏗️  للشركة: شركة العزب للمقاولات                                               ║
║                                                                           ║
║   🐘 الإصدار: PostgreSQL 17                                                 ║
║   📍 المنفذ: 5433                                                            ║
║   🌐 المنطقة الزمنية: Africa/Cairo                                              ║
║   🗣️  اللغة: العربية (ar_EG.UTF-8)                                             ║
║                                                                           ║
║   📦 الإضافات المثبتة:                                                         ║
║     - pgvector (للبحث الدلالي)                                                ║
║     - pg_stat_statements (لتحليل الأداء)                                       ║
║                                                                           ║
║   👤 المستخدمون:                                                             ║
║     - app_user (مدير التطبيق)                                                 ║
║     - readonly_user (للقراءة فقط)                                             ║
║                                                                           ║
║   🗄️  قواعد البيانات:                                                          ║
║     - azab_company (الرئيسية)                                                ║
║     - azab_test (للاختبارات)                                                 ║
║                                                                           ║
║   📂 المخططات (Schemas):                                                  ║
║     - products (المنتجات والخدمات)                                            ║
║     - sales (الصادرات والواردات)                                              ║
║     - inventory (المخزون)                                                  ║
║     - agents (الوكلاء الذكيون)                                                ║
║     - logs (السجلات)                                                      ║
║                                                                           ║
║   📊 أدوات المراقبة:                                                          ║
║     - htop, nmon, sysstat                                                ║
║     - pg_monitor.sh (سكربت مخصص)                                         ║
║                                                                           ║
║   💾 النسخ الاحتياطي:                                                         ║
║     - يومياً الساعة 2 صباحاً                                                     ║
║     - حفظ لمدة 30 يوماً                                                       ║
║                                                                           ║
║   🔐 الأمان:                                                               ║
║     - SSL مشغل                                                            ║
║     - scram-sha-256 للمصادقة                                                ║
║     - تحديثات أمنية تلقائية                                                       ║
║                                                                           ║
║   📁 ملفات الإعدادات:                                                          ║
║     - $PG_CONF                                                            ║
║     - $PG_HBA                                                             ║
║                                                                           ║
║   🚀 للاتصال بقاعدة البيانات:                                                     ║
║     psql -p 5433 -U app_user -d azab_company -h localhost                 ║
║                                                                           ║
║   📊 لمراقبة الأداء:                                                           ║
║     /usr/local/bin/pg_monitor.sh                                          ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
EOF

    cat /root/postgres_2030_info.txt
}

# ================================================================
# 19. الدالة الرئيسية - تشغيل كل شيء بالترتيب
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

    echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║ ✅ اكتمل الإعداد الاحترافي لـ PostgreSQL 17 بنجاح!         ║${NC}"
    echo -e "${GREEN}║ 🎯 صالح للاستخدام حتى عام 2030                            ║${NC}"
    echo -e "${GREEN}║ 🏗️  شركة العزب للمقاولات                                  ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo -e "\n${CYAN}📋 للحصول على معلومات كاملة، استخدم:${NC}"
    echo -e "   cat /root/postgres_2030_info.txt\n"
}

# ================================================================
# تشغيل السكربت
# ================================================================
main "$@"
