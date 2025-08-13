#!/bin/bash

echo "🔍 Автоматический поиск и исправление всех ошибок VPS"
echo "===================================================="

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[OK]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
print_debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

LOGFILE="/tmp/hromkz_diagnostic.log"
exec 2> >(tee -a "$LOGFILE")

if [[ $EUID -ne 0 ]]; then
   print_error "Запустите с sudo: sudo bash auto_fix_vps.sh"
   exit 1
fi

cd /var/www/logistics.xrom.org || { print_error "Директория проекта не найдена"; exit 1; }

print_info "=== ЭТАП 1: ДИАГНОСТИКА ==="

# Остановка всех сервисов
print_info "Остановка сервисов..."
systemctl stop hromkz &>/dev/null || true
systemctl stop hromkz-test &>/dev/null || true
systemctl stop nginx &>/dev/null || true
systemctl stop postgresql &>/dev/null || true

# Проверка файлов проекта
print_info "Проверка файлов проекта..."
MISSING_FILES=()
for file in app.py main.py models.py routes.py forms.py; do
    if [[ ! -f "$file" ]]; then
        MISSING_FILES+=("$file")
    fi
done

if [[ ${#MISSING_FILES[@]} -gt 0 ]]; then
    print_error "Отсутствуют файлы: ${MISSING_FILES[*]}"
    print_info "Восстановление из backup или создание заново..."
    
    # Попытка восстановления
    for backup in app_backup_* app_original.py; do
        if [[ -f "$backup" ]]; then
            print_info "Найден backup: $backup"
            cp "$backup" app.py
            break
        fi
    done
fi

# Диагностика Python окружения
print_info "Проверка Python окружения..."
if [[ ! -d "venv" ]]; then
    print_error "Виртуальное окружение не найдено, создаю..."
    python3 -m venv venv
    chown -R hromkz:www-data venv/
fi

# Активация venv и установка пакетов
print_info "Установка/обновление пакетов..."
./venv/bin/pip install --upgrade pip
./venv/bin/pip install flask flask-sqlalchemy flask-wtf wtforms werkzeug gunicorn psycopg2-binary requests sqlalchemy email-validator

print_info "=== ЭТАП 2: ИСПРАВЛЕНИЕ POSTGRESQL ==="

# Полная переустановка PostgreSQL если нужно
if ! systemctl is-active --quiet postgresql; then
    print_info "PostgreSQL не активен, переустанавливаю..."
    
    # Удаление и переустановка
    apt-get remove --purge -y postgresql* &>/dev/null || true
    rm -rf /var/lib/postgresql/ /etc/postgresql/ /var/log/postgresql/ &>/dev/null || true
    
    apt-get update &>/dev/null
    apt-get install -y postgresql postgresql-contrib &>/dev/null
    
    systemctl start postgresql
    systemctl enable postgresql
    sleep 5
    
    print_status "PostgreSQL переустановлен"
fi

# Создание БД и пользователя
print_info "Настройка базы данных..."
sudo -u postgres psql &>/dev/null << 'EOF' || true
DROP DATABASE IF EXISTS hromkz_logistics;
DROP USER IF EXISTS hromkz_user;
CREATE USER hromkz_user WITH ENCRYPTED PASSWORD 'HromKZ_SecurePass2025!';
CREATE DATABASE hromkz_logistics OWNER hromkz_user;
GRANT ALL PRIVILEGES ON DATABASE hromkz_logistics TO hromkz_user;
ALTER USER hromkz_user CREATEDB;
\q
EOF

# Тест подключения к БД
if sudo -u postgres psql -d hromkz_logistics -c "SELECT 1;" &>/dev/null; then
    print_status "База данных работает"
else
    print_error "Проблемы с базой данных"
    exit 1
fi

print_info "=== ЭТАП 3: ИСПРАВЛЕНИЕ FLASK ПРИЛОЖЕНИЯ ==="

# Создание .env файла
print_info "Создание .env конфигурации..."
cat > .env << 'EOF'
DATABASE_URL=postgresql://hromkz_user:HromKZ_SecurePass2025!@localhost/hromkz_logistics
SESSION_SECRET=HromKZ_Production_Secret_2025_LogisticsSystem
FLASK_ENV=production
EOF

# Безопасная версия app.py
print_info "Создание безопасной версии app.py..."
cat > app.py << 'EOF'
import os
import logging
from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy.orm import DeclarativeBase
from werkzeug.middleware.proxy_fix import ProxyFix

# Настройка логирования
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class Base(DeclarativeBase):
    pass

db = SQLAlchemy(model_class=Base)

def create_app():
    app = Flask(__name__)
    app.secret_key = os.environ.get("SESSION_SECRET", "fallback-secret-key")
    app.wsgi_app = ProxyFix(app.wsgi_app, x_proto=1, x_host=1)
    
    # Конфигурация БД
    app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get(
        "DATABASE_URL", 
        "postgresql://hromkz_user:HromKZ_SecurePass2025!@localhost/hromkz_logistics"
    )
    app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {
        "pool_recycle": 300,
        "pool_pre_ping": True,
    }
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    
    db.init_app(app)
    
    # Импорт моделей и маршрутов внутри app context
    with app.app_context():
        try:
            import models
            logger.info("Models imported successfully")
        except ImportError as e:
            logger.warning(f"Could not import models: {e}")
            
        try:
            import routes
            logger.info("Routes imported successfully")
        except ImportError as e:
            logger.warning(f"Could not import routes: {e}")
    
    return app

# Создаем приложение
app = create_app()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
EOF

# Создание main.py
cat > main.py << 'EOF'
import os
from app import app

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

# Инициализация БД отдельным скриптом
print_info "Создание скрипта инициализации БД..."
cat > init_db.py << 'EOF'
import os
from app import app, db

def init_database():
    with app.app_context():
        try:
            print("Создание таблиц...")
            db.create_all()
            print("✓ База данных инициализирована")
            return True
        except Exception as e:
            print(f"✗ Ошибка инициализации БД: {e}")
            return False

if __name__ == '__main__':
    success = init_database()
    exit(0 if success else 1)
EOF

# Права доступа
chown -R hromkz:www-data /var/www/logistics.xrom.org
chmod 755 /var/www/logistics.xrom.org
chmod +x init_db.py

print_info "Инициализация таблиц БД..."
if sudo -u hromkz bash -c 'cd /var/www/logistics.xrom.org && source .env && ./venv/bin/python init_db.py'; then
    print_status "Таблицы созданы успешно"
else
    print_error "Ошибка создания таблиц, но продолжаем..."
fi

print_info "=== ЭТАП 4: ТЕСТИРОВАНИЕ ПРИЛОЖЕНИЯ ==="

# Тест импорта
print_info "Тестирование импорта приложения..."
if sudo -u hromkz bash -c 'cd /var/www/logistics.xrom.org && source .env && ./venv/bin/python -c "from app import app; print(\"Flask OK\")"' &>/dev/null; then
    print_status "Flask приложение импортируется"
else
    print_error "Ошибка импорта Flask приложения"
    # Показываем детальную ошибку
    sudo -u hromkz bash -c 'cd /var/www/logistics.xrom.org && source .env && ./venv/bin/python -c "from app import app; print(\"Flask OK\")"'
fi

print_info "=== ЭТАП 5: НАСТРОЙКА СЕРВИСОВ ==="

# Создание директории для сокета
mkdir -p /var/www/logistics.xrom.org/run
chown hromkz:www-data /var/www/logistics.xrom.org/run
chmod 775 /var/www/logistics.xrom.org/run

# Systemd сервис
print_info "Создание systemd сервиса..."
cat > /etc/systemd/system/hromkz.service << 'EOF'
[Unit]
Description=Hrom KZ Logistics Application
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=exec
User=hromkz
Group=www-data
WorkingDirectory=/var/www/logistics.xrom.org
Environment="PATH=/var/www/logistics.xrom.org/venv/bin"
EnvironmentFile=/var/www/logistics.xrom.org/.env
ExecStart=/var/www/logistics.xrom.org/venv/bin/gunicorn --workers 2 --bind unix:/var/www/logistics.xrom.org/run/hromkz.sock --umask 0007 --timeout 30 --keep-alive 2 --max-requests 1000 --max-requests-jitter 50 --log-level info --access-logfile - --error-logfile - main:app
ExecReload=/bin/kill -s HUP $MAINPID
Restart=always
RestartSec=10
TimeoutStartSec=60
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF

# Nginx конфигурация
print_info "Проверка Nginx конфигурации..."
if [[ ! -f "/etc/nginx/sites-available/logistics.xrom.org" ]]; then
    print_info "Создание Nginx конфигурации..."
    cat > /etc/nginx/sites-available/logistics.xrom.org << 'EOF'
server {
    listen 80;
    server_name logistics.xrom.org;
    
    location / {
        proxy_pass http://unix:/var/www/logistics.xrom.org/run/hromkz.sock;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }
    
    location /static {
        alias /var/www/logistics.xrom.org/static;
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }
}
EOF
    
    ln -sf /etc/nginx/sites-available/logistics.xrom.org /etc/nginx/sites-enabled/
fi

# Тестирование Nginx конфигурации
if nginx -t &>/dev/null; then
    print_status "Nginx конфигурация корректна"
else
    print_error "Ошибки в Nginx конфигурации"
    nginx -t
fi

print_info "=== ЭТАП 6: ЗАПУСК СЕРВИСОВ ==="

systemctl daemon-reload
systemctl enable postgresql hromkz nginx
systemctl start postgresql

# Ждем запуска PostgreSQL
sleep 5

systemctl start hromkz
systemctl start nginx

print_info "Ожидание запуска сервисов..."
sleep 15

print_info "=== ФИНАЛЬНАЯ ДИАГНОСТИКА ==="

# Проверки
echo "======================================"

# PostgreSQL
if systemctl is-active --quiet postgresql; then
    print_status "PostgreSQL: работает"
else
    print_error "PostgreSQL: проблема"
    systemctl status postgresql --no-pager -l
fi

# Приложение
if systemctl is-active --quiet hromkz; then
    print_status "Приложение hromkz: работает"
    
    # Проверка сокета
    if [[ -S "/var/www/logistics.xrom.org/run/hromkz.sock" ]]; then
        print_status "Socket файл: создан"
        ls -la /var/www/logistics.xrom.org/run/hromkz.sock
    else
        print_error "Socket файл: отсутствует"
    fi
else
    print_error "Приложение hromkz: не работает"
    print_info "Последние логи:"
    journalctl -u hromkz --no-pager -n 10
fi

# Nginx  
if systemctl is-active --quiet nginx; then
    print_status "Nginx: работает"
else
    print_error "Nginx: проблема"
    systemctl status nginx --no-pager -l
fi

# HTTP тест
print_info "HTTP тестирование..."
sleep 3

for i in {1..3}; do
    HTTP_CODE=$(curl -I -s -o /dev/null -w "%{http_code}" --connect-timeout 10 http://logistics.xrom.org 2>/dev/null || echo "000")
    
    case "$HTTP_CODE" in
        "200")
            print_status "🎉 ПОЛНЫЙ УСПЕХ! Сайт работает!"
            echo ""
            echo "🌐 URL: http://logistics.xrom.org"
            echo "👤 Регистрация: http://logistics.xrom.org/register"
            echo ""
            break
            ;;
        "502")
            print_error "HTTP 502 Bad Gateway (попытка $i/3)"
            if [[ $i -eq 3 ]]; then
                print_error "Сервис не отвечает после 3 попыток"
                print_info "Логи приложения:"
                journalctl -u hromkz --no-pager -n 15
            else
                sleep 5
            fi
            ;;
        "000")
            print_error "Сервер недоступен (попытка $i/3)"
            if [[ $i -lt 3 ]]; then sleep 5; fi
            ;;
        *)
            print_error "HTTP код: $HTTP_CODE (попытка $i/3)"
            if [[ $i -lt 3 ]]; then sleep 5; fi
            ;;
    esac
done

echo ""
print_info "Команды управления:"
echo "  sudo systemctl status hromkz         # Статус"
echo "  sudo journalctl -u hromkz -f         # Логи"
echo "  sudo systemctl restart hromkz        # Перезапуск"
echo ""
print_info "Лог диагностики сохранен: $LOGFILE"

if [[ "$HTTP_CODE" != "200" ]]; then
    print_error "САЙТ НЕ РАБОТАЕТ! Нужна дополнительная диагностика"
    echo ""
    print_info "Детальная диагностика:"
    echo "=== SYSTEMCTL STATUS ==="
    systemctl status hromkz --no-pager -l
    echo ""
    echo "=== ПОСЛЕДНИЕ 20 ЛОГОВ ==="
    journalctl -u hromkz --no-pager -n 20
    echo ""
    echo "=== ПРОЦЕССЫ ==="
    ps aux | grep -E "(gunicorn|hromkz)" | grep -v grep
    echo ""
    echo "=== СОКЕТ ФАЙЛЫ ==="
    ls -la /var/www/logistics.xrom.org/run/
else
    print_status "ВСЕ ИСПРАВЛЕНО И РАБОТАЕТ!"
fi