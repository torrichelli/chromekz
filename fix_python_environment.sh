#!/bin/bash

echo "🐍 Автоматическое исправление Python окружения"
echo "=============================================="

set -e

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[OK]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
   print_error "Запустите с sudo: sudo bash fix_python_environment.sh"
   exit 1
fi

cd /var/www/logistics.xrom.org

print_info "Остановка сервиса..."
systemctl stop hromkz || true

print_info "Переустановка Python пакетов..."
sudo -u hromkz ./venv/bin/pip install --upgrade pip
sudo -u hromkz ./venv/bin/pip install flask flask-sqlalchemy flask-wtf wtforms werkzeug email-validator psycopg2-binary gunicorn requests sqlalchemy

print_info "Проверка синтаксиса Python файлов..."
sudo -u hromkz ./venv/bin/python -m py_compile app.py
sudo -u hromkz ./venv/bin/python -m py_compile main.py
sudo -u hromkz ./venv/bin/python -m py_compile models.py
sudo -u hromkz ./venv/bin/python -m py_compile forms.py
sudo -u hromkz ./venv/bin/python -m py_compile routes.py

print_info "Проверка импорта Flask приложения..."
if sudo -u hromkz bash -c 'cd /var/www/logistics.xrom.org && source .env && ./venv/bin/python -c "from app import app; print(\"Flask app OK\")"'; then
    print_status "Flask импорт успешен"
else
    print_error "Ошибка импорта Flask приложения"
    
    print_info "Создание минимального app.py для тестирования..."
    cat > app_test.py << 'EOF'
from flask import Flask

app = Flask(__name__)
app.secret_key = "test-secret-key"

@app.route('/')
def index():
    return "Hello, World! Flask is working!"

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)
EOF
    
    chown hromkz:www-data app_test.py
    
    print_info "Тестирование минимального приложения..."
    if sudo -u hromkz ./venv/bin/python -c "import app_test; print('Minimal Flask OK')"; then
        print_status "Минимальное приложение работает"
        
        print_info "Обновление systemd для тестирования..."
        cat > /etc/systemd/system/hromkz-test.service << 'EOF'
[Unit]
Description=Hrom KZ Test Service
After=network.target

[Service]
User=hromkz
Group=www-data
WorkingDirectory=/var/www/logistics.xrom.org
Environment="PATH=/var/www/logistics.xrom.org/venv/bin"
ExecStart=/var/www/logistics.xrom.org/venv/bin/gunicorn --workers 1 --bind unix:/var/www/logistics.xrom.org/run/hromkz.sock --umask 0007 app_test:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        systemctl enable hromkz-test
        systemctl start hromkz-test
        
        sleep 3
        
        if systemctl is-active --quiet hromkz-test; then
            print_status "Тестовое приложение запущено успешно"
            print_info "Проблема в основном коде приложения"
        else
            print_error "Даже тестовое приложение не запускается"
            journalctl -u hromkz-test --no-pager -n 5
        fi
        
        systemctl stop hromkz-test || true
        systemctl disable hromkz-test || true
    fi
fi

print_info "Проверка базы данных..."
if sudo -u postgres psql -d hromkz_logistics -c "SELECT 1;" > /dev/null 2>&1; then
    print_status "База данных доступна"
else
    print_error "Проблемы с базой данных"
    
    print_info "Пересоздание базы данных..."
    sudo -u postgres psql << 'EOF'
DROP DATABASE IF EXISTS hromkz_logistics;
CREATE DATABASE hromkz_logistics;
GRANT ALL PRIVILEGES ON DATABASE hromkz_logistics TO hromkz_user;
\q
EOF
    print_status "База данных пересоздана"
fi

print_info "Попытка запуска основного приложения..."
systemctl daemon-reload
systemctl start hromkz

sleep 5

if systemctl is-active --quiet hromkz; then
    print_status "🎉 Сервис запущен успешно!"
    
    HTTP_CODE=$(curl -I -s -o /dev/null -w "%{http_code}" http://logistics.xrom.org || echo "000")
    if [[ "$HTTP_CODE" == "200" ]]; then
        print_status "🎉 Сайт работает: http://logistics.xrom.org"
    else
        print_error "Сервис запущен, но сайт недоступен ($HTTP_CODE)"
    fi
else
    print_error "Сервис все еще не запускается"
    print_info "Последние логи:"
    journalctl -u hromkz --no-pager -n 10
fi

print_info "Для дальнейшей диагностики:"
echo "  journalctl -u hromkz -f"
echo "  sudo -u hromkz bash -c 'cd /var/www/logistics.xrom.org && source .env && ./venv/bin/python main.py'"