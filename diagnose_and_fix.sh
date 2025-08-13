#!/bin/bash

echo "🔍 Диагностика и исправление HTTP 404"
echo "===================================="

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[OK]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
   print_error "Запустите с sudo"
   exit 1
fi

print_info "=== ДИАГНОСТИКА ==="

echo ""
print_info "1. Логи hromkz приложения:"
journalctl -u hromkz --no-pager -n 10
echo ""

print_info "2. Логи Nginx:"
tail -n 10 /var/log/nginx/error.log
echo ""

print_info "3. Статус процессов:"
ps aux | grep -E "(gunicorn|hromkz)" | grep -v grep
echo ""

print_info "4. Проверка socket файла:"
ls -la /var/www/logistics.xrom.org/run/
echo ""

print_info "5. Тест прямого подключения к приложению:"
if curl -s http://127.0.0.1:5000 > /dev/null 2>&1; then
    print_status "Приложение отвечает напрямую"
else
    print_error "Приложение не отвечает напрямую"
fi

print_info "6. Тест socket подключения:"
if curl -s --unix-socket /var/www/logistics.xrom.org/run/hromkz.sock http://localhost/ > /dev/null 2>&1; then
    print_status "Socket работает"
else
    print_error "Socket не работает"
fi

print_info "=== ИСПРАВЛЕНИЯ ==="

cd /var/www/logistics.xrom.org

print_info "Проверка структуры файлов..."
if [[ ! -f "app.py" ]]; then
    print_error "app.py отсутствует!"
    exit 1
fi

if [[ ! -f "main.py" ]]; then
    print_error "main.py отсутствует!"
    exit 1
fi

if [[ ! -f "routes.py" ]]; then
    print_error "routes.py отсутствует!"
    exit 1
fi

print_info "Тест импорта приложения..."
sudo -u hromkz bash -c 'cd /var/www/logistics.xrom.org && source .env && timeout 10 ./venv/bin/python -c "
try:
    from app import app
    print(\"Flask app OK\")
    with app.app_context():
        print(\"App context OK\")
        from models import Employee, Request
        print(\"Models OK\")
except Exception as e:
    print(f\"Error: {e}\")
    import traceback
    traceback.print_exc()
"'

print_info "Прямой запуск Flask для теста..."
sudo -u hromkz bash -c 'cd /var/www/logistics.xrom.org && source .env && timeout 5 ./venv/bin/python main.py &'
sleep 3

# Тест прямого подключения
if curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:5000 | grep -q "200\|404\|500"; then
    print_status "Flask отвечает при прямом запуске"
    pkill -f "python main.py" || true
else
    print_error "Flask не отвечает при прямом запуске"
    pkill -f "python main.py" || true
fi

print_info "Создание простого тестового маршрута..."
cat > test_routes.py << 'EOF'
from flask import Flask

app = Flask(__name__)

@app.route('/')
def index():
    return "Hello from Hrom KZ Logistics!"

@app.route('/test')
def test():
    return "Test route works!"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

print_info "Создание простого main_test.py..."
cat > main_test.py << 'EOF'
from test_routes import app

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

chown hromkz:www-data test_routes.py main_test.py

print_info "Обновление systemd для тестового приложения..."
cat > /etc/systemd/system/hromkz-test.service << 'EOF'
[Unit]
Description=Hrom KZ Test Application
After=network.target

[Service]
Type=exec
User=hromkz
Group=www-data
WorkingDirectory=/var/www/logistics.xrom.org
Environment="PATH=/var/www/logistics.xrom.org/venv/bin"
ExecStart=/var/www/logistics.xrom.org/venv/bin/gunicorn --workers 1 --bind unix:/var/www/logistics.xrom.org/run/hromkz.sock --umask 0007 main_test:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

print_info "Остановка основного приложения и запуск тестового..."
systemctl stop hromkz
systemctl start hromkz-test

sleep 5

print_info "Тест простого приложения..."
HTTP_CODE=$(curl -I -s -o /dev/null -w "%{http_code}" http://logistics.xrom.org 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" == "200" ]]; then
    print_status "Простое приложение работает - проблема в основном коде"
    
    print_info "Возвращаем основное приложение и исправляем..."
    systemctl stop hromkz-test
    
    # Исправляем main.py - убираем прямой запуск
    cat > main.py << 'EOF'
from app import app

# Только экспорт приложения для gunicorn, без if __name__ == '__main__'
EOF

    # Исправляем app.py - убираем прямой запуск
    sed -i '/if __name__ == .__main__.:/,$d' app.py

    systemctl start hromkz
    sleep 5
    
    HTTP_CODE=$(curl -I -s -o /dev/null -w "%{http_code}" http://logistics.xrom.org 2>/dev/null || echo "000")
    
    if [[ "$HTTP_CODE" == "200" ]]; then
        print_status "🎉 ИСПРАВЛЕНО! Основное приложение работает!"
    else
        print_error "Основное приложение все еще не работает"
        print_info "Детальные логи:"
        journalctl -u hromkz --no-pager -n 15
    fi
else
    print_error "Даже простое приложение не работает - проблема в Nginx или системе"
    systemctl stop hromkz-test
    systemctl start hromkz
    
    print_info "Проверка Nginx конфигурации..."
    nginx -t
    
    print_info "Перезапуск Nginx..."
    systemctl restart nginx
    sleep 3
    
    HTTP_CODE=$(curl -I -s -o /dev/null -w "%{http_code}" http://logistics.xrom.org 2>/dev/null || echo "000")
    print_info "HTTP код после перезапуска Nginx: $HTTP_CODE"
fi

# Очистка тестовых файлов
rm -f /etc/systemd/system/hromkz-test.service
rm -f test_routes.py main_test.py
systemctl daemon-reload

print_info "Финальная проверка..."
HTTP_CODE=$(curl -I -s -o /dev/null -w "%{http_code}" http://logistics.xrom.org 2>/dev/null || echo "000")

case "$HTTP_CODE" in
    "200")
        print_status "🎉 САЙТ РАБОТАЕТ!"
        echo ""
        echo "URL: http://logistics.xrom.org"
        echo "Регистрация: http://logistics.xrom.org/register"
        ;;
    "404")
        print_error "Все еще HTTP 404 - нужна дополнительная диагностика"
        ;;
    "502")
        print_error "HTTP 502 - приложение не отвечает"
        ;;
    *)
        print_error "HTTP код: $HTTP_CODE"
        ;;
esac

print_info "Диагностика завершена!"