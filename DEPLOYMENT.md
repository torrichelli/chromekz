# Развертывание Хром КЗ на VPS

Инструкция по установке системы логистики Хром КЗ на VPS с доменом logistics.xrom.org

## Требования к серверу

- Ubuntu 20.04/22.04 LTS или CentOS 8+
- Минимум 2GB RAM
- 20GB свободного места
- Python 3.8+
- PostgreSQL 12+
- Nginx
- SSL сертификат (Let's Encrypt)

## 1. Подготовка сервера

### Обновление системы
```bash
sudo apt update && sudo apt upgrade -y
```

### Установка необходимых пакетов
```bash
sudo apt install -y python3 python3-pip python3-venv nginx postgresql postgresql-contrib certbot python3-certbot-nginx git
```

### Создание пользователя для приложения
```bash
sudo adduser hromkz
sudo usermod -aG sudo hromkz
su - hromkz
```

## 2. Настройка PostgreSQL

### Создание базы данных
```bash
sudo -u postgres psql
```

```sql
CREATE DATABASE hromkz_logistics;
CREATE USER hromkz_user WITH ENCRYPTED PASSWORD 'your_secure_password';
GRANT ALL PRIVILEGES ON DATABASE hromkz_logistics TO hromkz_user;
ALTER USER hromkz_user CREATEDB;
\q
```

### Настройка доступа к PostgreSQL
```bash
sudo nano /etc/postgresql/*/main/pg_hba.conf
```

Добавить строку:
```
local   hromkz_logistics    hromkz_user                     md5
```

Перезапустить PostgreSQL:
```bash
sudo systemctl restart postgresql
```

## 3. Развертывание приложения

### Клонирование проекта
```bash
cd /home/hromkz
git clone https://github.com/your-repo/hromkz-logistics.git
cd hromkz-logistics
```

### Создание виртуального окружения
```bash
python3 -m venv venv
source venv/bin/activate
```

### Установка зависимостей
```bash
pip install --upgrade pip
pip install -r requirements.txt
```

### Создание файла requirements.txt (если не существует)
```bash
cat > requirements.txt << EOF
Flask==3.0.0
Flask-SQLAlchemy==3.1.1
Flask-WTF==1.2.1
WTForms==3.1.1
Werkzeug==3.0.1
email-validator==2.1.0
psycopg2-binary==2.9.9
gunicorn==21.2.0
requests==2.31.0
EOF
```

### Настройка переменных окружения
```bash
nano .env
```

Содержимое .env файла:
```bash
DATABASE_URL=postgresql://hromkz_user:your_secure_password@localhost/hromkz_logistics
SESSION_SECRET=your_very_secure_session_secret_key_here
FLASK_ENV=production
FLASK_APP=main.py
```

### Инициализация базы данных
```bash
source .env
python -c "from app import app, db; app.app_context().push(); db.create_all()"
```

### Тестирование приложения
```bash
gunicorn --bind 127.0.0.1:5000 main:app
```

## 4. Настройка Gunicorn как системной службы

### Создание файла службы
```bash
sudo nano /etc/systemd/system/hromkz.service
```

Содержимое файла:
```ini
[Unit]
Description=Gunicorn instance to serve Hrom KZ Logistics
After=network.target

[Service]
User=hromkz
Group=www-data
WorkingDirectory=/home/hromkz/hromkz-logistics
Environment="PATH=/home/hromkz/hromkz-logistics/venv/bin"
EnvironmentFile=/home/hromkz/hromkz-logistics/.env
ExecStart=/home/hromkz/hromkz-logistics/venv/bin/gunicorn --workers 3 --bind unix:hromkz.sock -m 007 main:app
ExecReload=/bin/kill -s HUP $MAINPID

[Install]
WantedBy=multi-user.target
```

### Запуск и включение службы
```bash
sudo systemctl start hromkz
sudo systemctl enable hromkz
sudo systemctl status hromkz
```

## 5. Настройка Nginx

### Создание конфигурации Nginx
```bash
sudo nano /etc/nginx/sites-available/logistics.xrom.org
```

Содержимое файла:
```nginx
server {
    listen 80;
    server_name logistics.xrom.org;

    location = /favicon.ico { access_log off; log_not_found off; }
    location /static/ {
        root /home/hromkz/hromkz-logistics;
    }

    location / {
        include proxy_params;
        proxy_pass http://unix:/home/hromkz/hromkz-logistics/hromkz.sock;
    }
}
```

### Активация сайта
```bash
sudo ln -s /etc/nginx/sites-available/logistics.xrom.org /etc/nginx/sites-enabled
sudo nginx -t
sudo systemctl restart nginx
```

## 6. Настройка SSL с Let's Encrypt

### Получение SSL сертификата
```bash
sudo certbot --nginx -d logistics.xrom.org
```

### Автоматическое обновление сертификата
```bash
sudo crontab -e
```

Добавить строку:
```
0 12 * * * /usr/bin/certbot renew --quiet
```

## 7. Настройка DNS

В панели управления доменом xrom.org добавить A-запись:

```
Тип: A
Имя: logistics
Значение: IP_адрес_вашего_VPS
TTL: 300
```

## 8. Настройка файрвола

```bash
sudo ufw allow ssh
sudo ufw allow 'Nginx Full'
sudo ufw enable
```

## 9. Мониторинг и логи

### Просмотр логов приложения
```bash
sudo journalctl -u hromkz -f
```

### Просмотр логов Nginx
```bash
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/access.log
```

### Статус служб
```bash
sudo systemctl status hromkz
sudo systemctl status nginx
sudo systemctl status postgresql
```

## 10. Резервное копирование

### Скрипт резервного копирования базы данных
```bash
nano ~/backup_db.sh
```

```bash
#!/bin/bash
BACKUP_DIR="/home/hromkz/backups"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p $BACKUP_DIR

pg_dump -h localhost -U hromkz_user hromkz_logistics > $BACKUP_DIR/hromkz_$DATE.sql

# Удаление старых бэкапов (старше 7 дней)
find $BACKUP_DIR -name "hromkz_*.sql" -mtime +7 -delete
```

```bash
chmod +x ~/backup_db.sh
```

### Автоматическое резервное копирование
```bash
crontab -e
```

Добавить:
```
0 2 * * * /home/hromkz/backup_db.sh
```

## 11. Обновление приложения

### Скрипт обновления
```bash
nano ~/update_app.sh
```

```bash
#!/bin/bash
cd /home/hromkz/hromkz-logistics
git pull origin main
source venv/bin/activate
pip install -r requirements.txt
sudo systemctl restart hromkz
```

```bash
chmod +x ~/update_app.sh
```

## 12. Проверка развертывания

1. Откройте https://logistics.xrom.org в браузере
2. Проверьте работу всех форм
3. Проверьте регистрацию и авторизацию
4. Убедитесь в работе SSL сертификата

## Устранение неисправностей

### Проблемы с базой данных
```bash
sudo -u postgres psql -c "\l" # список баз данных
sudo -u postgres psql -d hromkz_logistics -c "\dt" # таблицы
```

### Проблемы с правами доступа
```bash
sudo chown -R hromkz:www-data /home/hromkz/hromkz-logistics
sudo chmod -R 755 /home/hromkz/hromkz-logistics
```

### Перезапуск всех служб
```bash
sudo systemctl restart hromkz nginx postgresql
```

## Контакты для поддержки

При возникновении проблем обращайтесь к системному администратору или разработчику проекта.