#!/bin/bash

echo "🔧 Исправление ошибки импорта Python"
echo "=================================="

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

cd /var/www/logistics.xrom.org

print_info "Останавливаем приложение..."
systemctl stop hromkz

print_info "Исправление циркулярного импорта..."

# Создаем исправленный app.py БЕЗ импорта routes внутри
cat > app.py << 'EOF'
import os
import logging
from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy.orm import DeclarativeBase
from werkzeug.middleware.proxy_fix import ProxyFix

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class Base(DeclarativeBase):
    pass

db = SQLAlchemy(model_class=Base)

def create_app():
    app = Flask(__name__)
    app.secret_key = os.environ.get("SESSION_SECRET", "fallback-secret-key")
    app.wsgi_app = ProxyFix(app.wsgi_app, x_proto=1, x_host=1)
    
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
    
    # Импорт моделей внутри app context
    with app.app_context():
        try:
            import models
            logger.info("Models imported successfully")
        except ImportError as e:
            logger.warning(f"Could not import models: {e}")
    
    return app

# Создаем приложение
app = create_app()

# Импорт маршрутов ПОСЛЕ создания приложения
try:
    import routes
    logger.info("Routes imported successfully")
except ImportError as e:
    logger.error(f"Could not import routes: {e}")
EOF

# Создаем новый main.py только для экспорта
cat > main.py << 'EOF'
from app import app

# Экспорт для gunicorn
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
EOF

print_info "Устанавливаем права доступа..."
chown -R hromkz:www-data /var/www/logistics.xrom.org

print_info "Тест импорта исправленного приложения..."
if sudo -u hromkz bash -c 'cd /var/www/logistics.xrom.org && source .env && timeout 10 ./venv/bin/python -c "
try:
    from app import app
    print(\"✓ Flask app imported\")
    from models import Employee, Request  
    print(\"✓ Models imported\")
    import routes
    print(\"✓ Routes imported\")
    print(\"✓ All imports successful\")
except Exception as e:
    print(f\"✗ Error: {e}\")
    import traceback
    traceback.print_exc()
"'; then
    print_status "Импорты исправлены"
else
    print_error "Ошибки импорта остались"
fi

print_info "Запуск исправленного приложения..."
systemctl start hromkz

print_info "Ожидание запуска..."
sleep 8

print_info "Проверка логов после исправления..."
journalctl -u hromkz --no-pager -n 5

print_info "HTTP тест..."
HTTP_CODE=$(curl -I -s -o /dev/null -w "%{http_code}" --connect-timeout 10 http://logistics.xrom.org 2>/dev/null || echo "000")

case "$HTTP_CODE" in
    "200")
        print_status "🎉 ИСПРАВЛЕНО! Сайт работает!"
        echo ""
        echo "Тестирование страниц:"
        curl -s http://logistics.xrom.org | head -n 5
        echo ""
        echo "URL: http://logistics.xrom.org"
        echo "Регистрация: http://logistics.xrom.org/register"
        ;;
    "404")
        print_error "Все еще HTTP 404"
        ;;
    "500")
        print_error "HTTP 500 - внутренняя ошибка сервера"
        ;;
    "502")
        print_error "HTTP 502 - приложение не отвечает"
        ;;
    *)
        print_error "HTTP код: $HTTP_CODE"
        ;;
esac

print_info "Исправление завершено!"