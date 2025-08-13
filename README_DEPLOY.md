# Быстрое развертывание на VPS

## Способ 1: Автоматический скрипт (Рекомендуется)

```bash
# Скачать скрипт на VPS
wget https://your-repo-url/quick_deploy.sh
# или
curl -O https://your-repo-url/quick_deploy.sh

# Запустить от root
sudo bash quick_deploy.sh
```

## Способ 2: Ручная установка

### 1. Подготовка сервера
```bash
# Обновление системы
sudo apt update && sudo apt upgrade -y

# Установка пакетов
sudo apt install -y python3 python3-pip python3-venv nginx postgresql postgresql-contrib git ufw
```

### 2. Настройка базы данных
```bash
sudo -u postgres psql
```

```sql
CREATE DATABASE hromkz_logistics;
CREATE USER hromkz_user WITH ENCRYPTED PASSWORD 'HromKZ_SecurePass2025!';
GRANT ALL PRIVILEGES ON DATABASE hromkz_logistics TO hromkz_user;
\q
```

### 3. Развертывание приложения
```bash
# Создание пользователя
sudo adduser hromkz

# Клонирование проекта
sudo mkdir -p /var/www/logistics.xrom.org
sudo git clone https://github.com/your-repo/project.git /var/www/logistics.xrom.org
cd /var/www/logistics.xrom.org

# Установка зависимостей
python3 -m venv venv
source venv/bin/activate
pip install flask flask-sqlalchemy psycopg2-binary gunicorn werkzeug
```

### 4. Настройка Nginx
```bash
sudo nano /etc/nginx/sites-available/logistics.xrom.org
```

```nginx
server {
    listen 80;
    server_name logistics.xrom.org;
    
    location / {
        include proxy_params;
        proxy_pass http://unix:/var/www/logistics.xrom.org/hromkz.sock;
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/logistics.xrom.org /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

### 5. SSL сертификат
```bash
sudo certbot --nginx -d logistics.xrom.org
```

## Проверка развертывания

1. **Статус служб:**
   ```bash
   sudo systemctl status hromkz
   sudo systemctl status nginx
   ```

2. **Логи:**
   ```bash
   sudo journalctl -u hromkz -f
   sudo tail -f /var/log/nginx/error.log
   ```

3. **Тест сайта:**
   - http://logistics.xrom.org
   - https://logistics.xrom.org (после SSL)

## Управление

### Обновление приложения
```bash
cd /var/www/logistics.xrom.org
git pull
sudo systemctl restart hromkz
```

### Резервное копирование
```bash
pg_dump -U hromkz_user hromkz_logistics > backup.sql
```

### Восстановление
```bash
psql -U hromkz_user hromkz_logistics < backup.sql
```

## Устранение неисправностей

### Приложение не запускается
```bash
sudo journalctl -u hromkz --no-pager -l
```

### Проблемы с базой данных
```bash
sudo -u postgres psql -l  # список баз
sudo -u postgres psql -c "\du"  # пользователи
```

### Проблемы с Nginx
```bash
sudo nginx -t  # проверка конфигурации
sudo tail -f /var/log/nginx/error.log
```

## Требования к серверу

- **ОС:** Ubuntu 20.04+ или CentOS 8+
- **RAM:** Минимум 1GB, рекомендуется 2GB
- **Диск:** 10GB свободного места
- **Сеть:** Открытые порты 80, 443, 22

## DNS настройка

В панели управления доменом добавить:
```
Тип: A
Имя: logistics
Значение: [IP_адрес_VPS]
TTL: 300
```