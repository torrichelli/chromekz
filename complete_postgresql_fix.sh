#!/bin/bash

echo "🔧 Полная переустановка PostgreSQL и развертывание"
echo "==============================================="

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[OK]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
   print_error "Запустите с sudo: sudo bash complete_postgresql_fix.sh"
   exit 1
fi

print_info "Остановка всех сервисов..."
systemctl stop hromkz || true
systemctl stop hromkz-test || true
systemctl stop postgresql || true

print_info "ПОЛНАЯ переустановка PostgreSQL..."

# Удаляем PostgreSQL полностью
apt-get remove --purge -y postgresql postgresql-* 
rm -rf /var/lib/postgresql/
rm -rf /etc/postgresql/
rm -rf /var/log/postgresql/

print_info "Установка свежего PostgreSQL..."
apt-get update
apt-get install -y postgresql postgresql-contrib

print_info "Запуск PostgreSQL..."
systemctl start postgresql
systemctl enable postgresql

# Ждем полной инициализации
sleep 10

print_info "Создание пользователя и базы данных..."
sudo -u postgres psql << 'EOF'
-- Создание пользователя
CREATE USER hromkz_user WITH ENCRYPTED PASSWORD 'HromKZ_SecurePass2025!';
ALTER USER hromkz_user CREATEDB;

-- Создание базы данных
CREATE DATABASE hromkz_logistics OWNER hromkz_user;
GRANT ALL PRIVILEGES ON DATABASE hromkz_logistics TO hromkz_user;

-- Выход
\q
EOF

print_status "PostgreSQL переустановлен и настроен"

print_info "Тестирование подключения к базе данных..."
if sudo -u postgres psql -d hromkz_logistics -c "SELECT 1;" > /dev/null 2>&1; then
    print_status "База данных доступна"
else
    print_error "Проблемы с подключением к базе данных"
    exit 1
fi

cd /var/www/logistics.xrom.org

print_info "Создание нового app.py без автоинициализации БД..."
# Сохраняем оригинальный файл
cp app.py app_backup_$(date +%s).py

cat > app.py << 'EOF'
import os
from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy.orm import DeclarativeBase
from werkzeug.middleware.proxy_fix import ProxyFix

class Base(DeclarativeBase):
    pass

db = SQLAlchemy(model_class=Base)
app = Flask(__name__)
app.secret_key = os.environ.get("SESSION_SECRET", "dev-secret-key")
app.wsgi_app = ProxyFix(app.wsgi_app, x_proto=1, x_host=1)

app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get(
    "DATABASE_URL", 
    "postgresql://hromkz_user:HromKZ_SecurePass2025!@localhost/hromkz_logistics"
)
app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {
    "pool_recycle": 300,
    "pool_pre_ping": True,
}

db.init_app(app)

# НЕ создаем таблицы автоматически при импорте
# Импортируем модели и маршруты
try:
    import models
    import routes
except ImportError as e:
    print(f"Warning: Could not import models or routes: {e}")
EOF

print_info "Создание скрипта инициализации БД..."
cat > init_database.py << 'EOF'
#!/usr/bin/env python3
import os
from app import app, db

def init_db():
    with app.app_context():
        print("Создание таблиц базы данных...")
        db.create_all()
        print("База данных инициализирована успешно!")

if __name__ == '__main__':
    init_db()
EOF

# Устанавливаем права
chown hromkz:www-data app.py init_database.py
chmod +x init_database.py

print_info "Инициализация таблиц базы данных..."
if sudo -u hromkz bash -c 'cd /var/www/logistics.xrom.org && source .env && ./venv/bin/python init_database.py'; then
    print_status "Таблицы созданы успешно"
else
    print_error "Ошибка создания таблиц"
    # Покажем детальную ошибку
    print_info "Попытка диагностики..."
    sudo -u hromkz bash -c 'cd /var/www/logistics.xrom.org && source .env && ./venv/bin/python -c "from app import db; print(\"DB connection OK\")"'
fi

print_info "Тестирование Flask приложения..."
if sudo -u hromkz bash -c 'cd /var/www/logistics.xrom.org && source .env && ./venv/bin/python -c "from app import app; print(\"Flask app imported successfully\")"'; then
    print_status "Flask приложение работает"
else
    print_error "Проблемы с Flask приложением"
    exit 1
fi

print_info "Настройка прав доступа..."
chown -R hromkz:www-data /var/www/logistics.xrom.org
chmod 775 /var/www/logistics.xrom.org
mkdir -p /var/www/logistics.xrom.org/run
chown hromkz:www-data /var/www/logistics.xrom.org/run
chmod 775 /var/www/logistics.xrom.org/run

print_info "Настройка systemd сервиса..."
cat > /etc/systemd/system/hromkz.service << 'EOF'
[Unit]
Description=Hrom KZ Logistics System
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=notify
User=hromkz
Group=www-data
WorkingDirectory=/var/www/logistics.xrom.org
Environment="PATH=/var/www/logistics.xrom.org/venv/bin"
EnvironmentFile=/var/www/logistics.xrom.org/.env
ExecStart=/var/www/logistics.xrom.org/venv/bin/gunicorn --workers 3 --bind unix:/var/www/logistics.xrom.org/run/hromkz.sock --umask 0007 main:app
ExecReload=/bin/kill -s HUP $MAINPID
Restart=always
RestartSec=5
TimeoutStartSec=30

[Install]
WantedBy=multi-user.target
EOF

print_info "Запуск сервисов..."
systemctl daemon-reload
systemctl enable hromkz
systemctl start hromkz

print_info "Проверка Nginx конфигурации..."
nginx -t
systemctl reload nginx

print_info "Ожидание полного запуска сервисов..."
sleep 10

print_status "ИТОГОВАЯ ПРОВЕРКА:"
echo "================================"

# PostgreSQL
if systemctl is-active --quiet postgresql; then
    print_status "PostgreSQL: активен"
    
    # Тест подключения
    if sudo -u postgres psql -d hromkz_logistics -c "SELECT COUNT(*) FROM information_schema.tables;" > /dev/null 2>&1; then
        print_status "База данных: подключение OK"
    else
        print_error "База данных: ошибка подключения"
    fi
else
    print_error "PostgreSQL: не активен"
fi

# Приложение
if systemctl is-active --quiet hromkz; then
    print_status "Сервис hromkz: активен"
    
    # Socket файл
    if [[ -S "/var/www/logistics.xrom.org/run/hromkz.sock" ]]; then
        print_status "Socket файл: создан"
        ls -la /var/www/logistics.xrom.org/run/hromkz.sock
    else
        print_error "Socket файл: отсутствует"
    fi
else
    print_error "Сервис hromkz: не активен"
    print_info "Логи сервиса:"
    journalctl -u hromkz --no-pager -n 10
fi

# HTTP тест
print_info "HTTP тестирование..."
sleep 3
HTTP_CODE=$(curl -I -s -o /dev/null -w "%{http_code}" http://logistics.xrom.org || echo "000")

case "$HTTP_CODE" in
    "200")
        print_status "🎉 ПОЛНЫЙ УСПЕХ! Сайт работает!"
        print_status "URL: http://logistics.xrom.org"
        print_info "Создайте первого сотрудника: http://logistics.xrom.org/register"
        ;;
    "502")
        print_error "HTTP 502 Bad Gateway - сервис не отвечает"
        ;;
    "404")
        print_error "HTTP 404 - маршрут не найден"
        ;;
    "500")
        print_error "HTTP 500 - внутренняя ошибка сервера"
        ;;
    *)
        print_error "HTTP код: $HTTP_CODE"
        ;;
esac

echo ""
print_info "Команды управления:"
echo "  sudo systemctl status hromkz        # Статус сервиса"
echo "  sudo journalctl -u hromkz -f        # Логи в реальном времени"  
echo "  sudo systemctl restart hromkz       # Перезапуск сервиса"
echo "  sudo systemctl restart postgresql   # Перезапуск БД"

if [[ "$HTTP_CODE" != "200" ]]; then
    print_info "Для диагностики запустите:"
    echo "  sudo journalctl -u hromkz --no-pager -n 20"
fi