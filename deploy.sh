#!/bin/bash

# Скрипт автоматического развертывания Хром КЗ на VPS
# Использование: ./deploy.sh

set -e

echo "🚀 Начинаем развертывание Хром КЗ на logistics.xrom.org"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция для вывода с цветом
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Проверка и создание пользователя
if [[ $EUID -eq 0 ]]; then
   print_warning "Скрипт запущен от root. Создаем пользователя hromkz..."
   
   # Создание пользователя hromkz если он не существует
   if ! id "hromkz" &>/dev/null; then
       adduser --disabled-password --gecos "" hromkz
       usermod -aG sudo hromkz
       print_status "Пользователь hromkz создан"
   fi
   
   # Копируем скрипт для пользователя hromkz
   cp "$0" /home/hromkz/deploy.sh
   chown hromkz:hromkz /home/hromkz/deploy.sh
   chmod +x /home/hromkz/deploy.sh
   
   print_status "Перезапускаем скрипт от имени пользователя hromkz..."
   su - hromkz -c "/home/hromkz/deploy.sh"
   exit 0
fi

# Установка зависимостей системы
print_status "Обновление системы и установка зависимостей..."
sudo apt update
sudo apt install -y python3 python3-pip python3-venv nginx postgresql postgresql-contrib certbot python3-certbot-nginx git ufw

# Проверка существования пользователя hromkz
if ! id "hromkz" &>/dev/null; then
    print_error "Пользователь hromkz не существует. Создайте его командой: sudo adduser hromkz"
    exit 1
fi

# Настройка PostgreSQL
print_status "Настройка PostgreSQL..."
sudo -u postgres psql << EOF
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'hromkz_logistics') THEN
      CREATE DATABASE hromkz_logistics;
   END IF;
END
\$\$;

DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_user WHERE usename = 'hromkz_user') THEN
      CREATE USER hromkz_user WITH ENCRYPTED PASSWORD 'HromKZ_2025_SecurePass!';
   END IF;
END
\$\$;

GRANT ALL PRIVILEGES ON DATABASE hromkz_logistics TO hromkz_user;
ALTER USER hromkz_user CREATEDB;
EOF

# Клонирование/обновление репозитория
DEPLOY_DIR="/var/www/logistics.xrom.org"
if [ -d "$DEPLOY_DIR" ]; then
    print_status "Обновление существующего проекта..."
    cd $DEPLOY_DIR
    git pull origin main
else
    print_status "Клонирование проекта..."
    sudo -u hromkz git clone https://github.com/your-repo/hromkz-logistics.git $DEPLOY_DIR
    cd $DEPLOY_DIR
fi

# Настройка виртуального окружения
print_status "Настройка виртуального окружения..."
sudo -u hromkz python3 -m venv venv
sudo -u hromkz ./venv/bin/pip install --upgrade pip

# Установка зависимостей Python
if [ -f "requirements_prod.txt" ]; then
    sudo -u hromkz ./venv/bin/pip install -r requirements_prod.txt
else
    print_warning "requirements_prod.txt не найден, устанавливаем базовые пакеты..."
    sudo -u hromkz ./venv/bin/pip install Flask Flask-SQLAlchemy Flask-WTF WTForms Werkzeug email-validator psycopg2-binary gunicorn requests SQLAlchemy
fi

# Создание .env файла
print_status "Настройка переменных окружения..."
sudo -u hromkz tee $DEPLOY_DIR/.env > /dev/null << EOF
DATABASE_URL=postgresql://hromkz_user:HromKZ_2025_SecurePass!@localhost/hromkz_logistics
SESSION_SECRET=$(openssl rand -hex 32)
FLASK_ENV=production
FLASK_APP=main.py
EOF

# Инициализация базы данных
print_status "Инициализация базы данных..."
cd $DEPLOY_DIR
sudo -u hromkz bash -c 'source venv/bin/activate && source .env && python -c "from app import app, db; app.app_context().push(); db.create_all()"'

# Настройка systemd службы
print_status "Настройка systemd службы..."
sudo tee /etc/systemd/system/hromkz.service > /dev/null << EOF
[Unit]
Description=Gunicorn instance to serve Hrom KZ Logistics
After=network.target

[Service]
User=hromkz
Group=www-data
WorkingDirectory=$DEPLOY_DIR
Environment="PATH=$DEPLOY_DIR/venv/bin"
EnvironmentFile=$DEPLOY_DIR/.env
ExecStart=$DEPLOY_DIR/venv/bin/gunicorn --workers 3 --bind unix:$DEPLOY_DIR/hromkz.sock -m 007 main:app
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Настройка Nginx
print_status "Настройка Nginx..."
sudo tee /etc/nginx/sites-available/logistics.xrom.org > /dev/null << EOF
server {
    listen 80;
    server_name logistics.xrom.org;

    location = /favicon.ico { access_log off; log_not_found off; }
    
    location /static/ {
        alias $DEPLOY_DIR/static/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    location / {
        include proxy_params;
        proxy_pass http://unix:$DEPLOY_DIR/hromkz.sock;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Активация сайта Nginx
sudo ln -sf /etc/nginx/sites-available/logistics.xrom.org /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Проверка конфигурации Nginx
sudo nginx -t

# Настройка прав доступа
print_status "Настройка прав доступа..."
sudo chown -R hromkz:www-data $DEPLOY_DIR
sudo chmod -R 755 $DEPLOY_DIR

# Запуск служб
print_status "Запуск служб..."
sudo systemctl daemon-reload
sudo systemctl start hromkz
sudo systemctl enable hromkz
sudo systemctl restart nginx

# Настройка файрвола
print_status "Настройка файрвола..."
sudo ufw --force enable
sudo ufw allow ssh
sudo ufw allow 'Nginx Full'

# Создание скриптов управления
print_status "Создание скриптов управления..."

# Скрипт резервного копирования
sudo -u hromkz tee /home/hromkz/backup_db.sh > /dev/null << 'EOF'
#!/bin/bash
BACKUP_DIR="/home/hromkz/backups"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p $BACKUP_DIR

export PGPASSWORD="HromKZ_2025_SecurePass!"
pg_dump -h localhost -U hromkz_user hromkz_logistics > $BACKUP_DIR/hromkz_$DATE.sql

# Удаление старых бэкапов (старше 7 дней)
find $BACKUP_DIR -name "hromkz_*.sql" -mtime +7 -delete

echo "Backup completed: $BACKUP_DIR/hromkz_$DATE.sql"
EOF

sudo chmod +x /home/hromkz/backup_db.sh

# Скрипт обновления
sudo -u hromkz tee /home/hromkz/update_app.sh > /dev/null << 'EOF'
#!/bin/bash
cd /home/hromkz/hromkz-logistics
echo "Pulling latest changes..."
git pull origin main

echo "Activating virtual environment..."
source venv/bin/activate

echo "Installing/updating dependencies..."
if [ -f "requirements_prod.txt" ]; then
    pip install -r requirements_prod.txt
fi

echo "Restarting application..."
sudo systemctl restart hromkz

echo "Application updated successfully!"
EOF

sudo chmod +x /home/hromkz/update_app.sh

# Настройка автоматических резервных копий
print_status "Настройка автоматических резервных копий..."
sudo -u hromkz crontab - << 'EOF'
# Ежедневное резервное копирование в 2:00
0 2 * * * /home/hromkz/backup_db.sh >> /home/hromkz/backup.log 2>&1
EOF

# Проверка статуса служб
print_status "Проверка статуса служб..."
systemctl is-active --quiet hromkz && echo "✅ hromkz service: running" || echo "❌ hromkz service: stopped"
systemctl is-active --quiet nginx && echo "✅ nginx service: running" || echo "❌ nginx service: stopped"
systemctl is-active --quiet postgresql && echo "✅ postgresql service: running" || echo "❌ postgresql service: stopped"

print_status "Развертывание завершено!"
echo ""
echo "📋 Следующие шаги:"
echo "1. Настройте DNS запись A для logistics.xrom.org на IP сервера"
echo "2. Получите SSL сертификат: sudo certbot --nginx -d logistics.xrom.org"
echo "3. Проверьте сайт: http://logistics.xrom.org"
echo ""
echo "🔧 Управление:"
echo "- Обновить приложение: /home/hromkz/update_app.sh"
echo "- Резервная копия: /home/hromkz/backup_db.sh"
echo "- Логи приложения: sudo journalctl -u hromkz -f"
echo "- Логи Nginx: sudo tail -f /var/log/nginx/error.log"
echo ""
echo "🎉 Приложение доступно на http://logistics.xrom.org"