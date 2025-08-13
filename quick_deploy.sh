#!/bin/bash

echo "🔧 Быстрое исправление установки"
echo "==============================="

set -e

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

print_info "Исправление файрвола..."
ufw --force enable
ufw allow ssh
ufw allow 'Nginx Full'
ufw allow 5432/tcp  # PostgreSQL

print_info "Проверка статуса установки..."

# Проверка файлов
if [[ -f "app.py" && -f "main.py" && -f "models.py" ]]; then
    print_status "Файлы приложения созданы"
else
    print_error "Файлы приложения отсутствуют"
    print_info "Продолжайте основную установку"
    exit 1
fi

# Проверка виртуального окружения
if [[ -d "venv" ]]; then
    print_status "Python окружение создано"
else
    print_error "Python окружение отсутствует"
    exit 1
fi

# Тест базы данных
print_info "Проверка подключения к БД..."
if sudo -u postgres psql -d hromkz_logistics -c "SELECT 1;" &>/dev/null; then
    print_status "База данных доступна"
else
    print_error "Проблемы с БД"
    exit 1
fi

# Инициализация таблиц если нужно
print_info "Инициализация таблиц..."
sudo -u hromkz bash -c 'cd /var/www/logistics.xrom.org && source .env && ./venv/bin/python init_database.py'

# Проверка systemd
if systemctl is-active --quiet hromkz; then
    print_status "Сервис hromkz запущен"
else
    print_info "Запуск сервиса hromkz..."
    systemctl start hromkz
fi

# Проверка nginx
if systemctl is-active --quiet nginx; then
    print_status "Nginx запущен"
else
    print_info "Запуск Nginx..."
    systemctl start nginx
fi

print_info "Ожидание запуска..."
sleep 5

# HTTP тест
HTTP_CODE=$(curl -I -s -o /dev/null -w "%{http_code}" http://logistics.xrom.org 2>/dev/null || echo "000")

case "$HTTP_CODE" in
    "200")
        print_status "🎉 САЙТ РАБОТАЕТ!"
        echo ""
        echo "URL: http://logistics.xrom.org"
        echo "Регистрация: http://logistics.xrom.org/register"
        ;;
    "502")
        print_error "HTTP 502 - проверьте логи: journalctl -u hromkz -n 10"
        ;;
    *)
        print_error "HTTP код: $HTTP_CODE"
        print_info "Проверьте: systemctl status hromkz"
        ;;
esac

print_info "Статус сервисов:"
systemctl is-active postgresql && echo "✓ PostgreSQL" || echo "✗ PostgreSQL"
systemctl is-active hromkz && echo "✓ hromkz" || echo "✗ hromkz" 
systemctl is-active nginx && echo "✓ Nginx" || echo "✗ Nginx"