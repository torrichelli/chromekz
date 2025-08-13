#!/bin/bash

echo "🔍 Выполнение диагностики Python на VPS"
echo "======================================="

echo ""
echo "СКОПИРУЙТЕ И ВЫПОЛНИТЕ ЭТИ КОМАНДЫ ПО ПОРЯДКУ:"
echo ""

echo "cd /var/www/logistics.xrom.org"
echo ""

echo "# Команда 1: Проверка пакетов"
echo "./venv/bin/pip list"
echo ""

echo "# Команда 2: Тест импорта приложения"  
echo "sudo -u hromkz ./venv/bin/python -c \"import app; print('Flask app imported successfully')\""
echo ""

echo "# Команда 3: Тест зависимостей"
echo "sudo -u hromkz ./venv/bin/python -c \"import flask, flask_sqlalchemy, flask_wtf, wtforms, werkzeug; print('All imports OK')\""
echo ""

echo "# Команда 4: Проверка базы данных"
echo "sudo -u postgres psql -c \"\\l\" | grep hromkz"
echo ""

echo "# Команда 5: Переменные окружения"
echo "cat .env"
echo ""

echo "# Команда 6: Прямой запуск Flask"
echo "sudo -u hromkz bash -c 'source .env && ./venv/bin/python main.py'"
echo ""

echo "📋 ПОЖАЛУЙСТА, ВЫПОЛНИТЕ ЭТИ КОМАНДЫ И ПОКАЖИТЕ РЕЗУЛЬТАТ"
echo "Особенно важно увидеть ошибки из команд 2 и 6"