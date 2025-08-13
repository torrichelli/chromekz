#!/bin/bash

echo "🛠️ Полное исправление PostgreSQL и развертывание"
echo "=============================================="

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[OK]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
   print_error "Запустите с sudo: sudo bash fix_postgresql_and_deploy.sh"
   exit 1
fi

print_info "Остановка всех сервисов..."
systemctl stop hromkz || true
systemctl stop hromkz-test || true
systemctl stop postgresql || true

print_info "Исправление PostgreSQL..."
# Исправляем права доступа к PostgreSQL
chown -R postgres:postgres /var/lib/postgresql/
chmod -R 755 /var/lib/postgresql/
chmod -R 700 /var/lib/postgresql/*/main/

print_info "Запуск PostgreSQL..."
systemctl start postgresql
systemctl enable postgresql

# Ждем запуска PostgreSQL
sleep 5

print_info "Пересоздание базы данных и пользователя..."
sudo -u postgres psql << 'EOF'
-- Закрытие всех соединений к базе
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'hromkz_logistics' AND pid <> pg_backend_pid();

-- Удаление и пересоздание
DROP DATABASE IF EXISTS hromkz_logistics;
DROP USER IF EXISTS hromkz_user;

-- Создание нового пользователя и базы
CREATE USER hromkz_user WITH ENCRYPTED PASSWORD 'HromKZ_SecurePass2025!';
CREATE DATABASE hromkz_logistics OWNER hromkz_user;
GRANT ALL PRIVILEGES ON DATABASE hromkz_logistics TO hromkz_user;
ALTER USER hromkz_user CREATEDB;

\q
EOF

print_status "База данных пересоздана"

print_info "Создание версии app.py без автоматической инициализации БД..."
cd /var/www/logistics.xrom.org

# Сохраняем оригинальный app.py
cp app.py app_original.py

# Создаем новую версию app.py без db.create_all() в импорте
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

# Импортируем модели и маршруты БЕЗ автоматической инициализации БД
with app.app_context():
    import models
    import routes
EOF

print_info "Создание отдельного скрипта инициализации БД..."
cat > init_db.py << 'EOF'
from app import app, db

if __name__ == '__main__':
    with app.app_context():
        print("Создание таблиц базы данных...")
        db.create_all()
        print("База данных инициализирована успешно!")
EOF

chown hromkz:www-data app.py init_db.py

print_info "Инициализация базы данных..."
sudo -u hromkz bash -c 'cd /var/www/logistics.xrom.org && source .env && ./venv/bin/python init_db.py'

print_info "Тестирование импорта приложения..."
if sudo -u hromkz bash -c 'cd /var/www/logistics.xrom.org && source .env && ./venv/bin/python -c "from app import app; print(\"Flask app OK\")"'; then
    print_status "Flask приложение импортируется успешно"
else
    print_error "Проблемы с импортом Flask приложения"
    exit 1
fi

print_info "Настройка прав доступа..."
chown -R hromkz:www-data /var/www/logistics.xrom.org
chmod 775 /var/www/logistics.xrom.org
mkdir -p /var/www/logistics.xrom.org/run
chown hromkz:www-data /var/www/logistics.xrom.org/run
chmod 775 /var/www/logistics.xrom.org/run

print_info "Обновление systemd конфигурации..."
cat > /etc/systemd/system/hromkz.service << 'EOF'
[Unit]
Description=Hrom KZ Full Logistics System
After=network.target postgresql.service
Requires=postgresql.service

[Service]
User=hromkz
Group=www-data
WorkingDirectory=/var/www/logistics.xrom.org
Environment="PATH=/var/www/logistics.xrom.org/venv/bin"
EnvironmentFile=/var/www/logistics.xrom.org/.env
ExecStart=/var/www/logistics.xrom.org/venv/bin/gunicorn --workers 3 --bind unix:/var/www/logistics.xrom.org/run/hromkz.sock --umask 0007 main:app
ExecReload=/bin/kill -s HUP $MAINPID
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

print_info "Запуск сервисов..."
systemctl daemon-reload
systemctl enable hromkz
systemctl start hromkz
systemctl reload nginx

print_info "Ожидание запуска..."
sleep 8

print_status "Проверка результатов:"
echo ""

# Проверка PostgreSQL
if systemctl is-active --quiet postgresql; then
    print_status "PostgreSQL: работает"
else
    print_error "PostgreSQL: ошибка"
fi

# Проверка приложения
if systemctl is-active --quiet hromkz; then
    print_status "Сервис hromkz: работает"
    
    # Проверка socket файла
    if [[ -S "/var/www/logistics.xrom.org/run/hromkz.sock" ]]; then
        print_status "Socket файл создан"
    else
        print_error "Socket файл отсутствует"
    fi
    
else
    print_error "Сервис hromkz: ошибка"
    print_info "Последние логи:"
    journalctl -u hromkz --no-pager -n 5
fi

# Проверка HTTP
print_info "Тестирование HTTP ответа..."
sleep 2
HTTP_CODE=$(curl -I -s -o /dev/null -w "%{http_code}" http://logistics.xrom.org || echo "000")

case "$HTTP_CODE" in
    "200")
        print_status "🎉 УСПЕХ! Сайт работает: http://logistics.xrom.org"
        print_status "Можете открывать сайт в браузере"
        ;;
    "502")
        print_error "HTTP 502 - Сервис не отвечает"
        print_info "Проверьте логи: journalctl -u hromkz -f"
        ;;
    "000")
        print_error "Сервер недоступен"
        ;;
    *)
        print_error "HTTP код: $HTTP_CODE"
        ;;
esac

echo ""
print_info "Управление сервисом:"
echo "  sudo systemctl status hromkz     # Статус"
echo "  sudo journalctl -u hromkz -f     # Логи"
echo "  sudo systemctl restart hromkz    # Перезапуск"
echo ""
print_info "Следующие шаги:"
echo "  1. Откройте http://logistics.xrom.org"
echo "  2. Перейдите на /register для создания первого сотрудника"
echo "  3. Настройте SSL: sudo certbot --nginx -d logistics.xrom.org"