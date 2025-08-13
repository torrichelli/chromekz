#!/bin/bash

echo "🚀 Исправленная установка Хром КЗ Logistics"
echo "=========================================="
echo "Целевой домен: logistics.xrom.org"
echo ""

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[OK]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
print_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
   print_error "Запустите с правами root: sudo bash fixed_vps_deploy.sh"
   exit 1
fi

print_step "ЭТАП 1: Продолжение установки с текущего места"

PROJECT_DIR="/var/www/logistics.xrom.org"

# Проверим что уже создано
if [[ -d "$PROJECT_DIR" ]]; then
    print_status "Директория проекта существует"
    cd $PROJECT_DIR
else
    print_info "Создание директории проекта..."
    mkdir -p $PROJECT_DIR/static/css $PROJECT_DIR/static/js $PROJECT_DIR/static/images $PROJECT_DIR/templates $PROJECT_DIR/run
    chown -R hromkz:www-data $PROJECT_DIR
    chmod 775 $PROJECT_DIR
    cd $PROJECT_DIR
fi

print_step "ЭТАП 2: Python окружение"

if [[ ! -d "venv" ]]; then
    print_info "Создание виртуального окружения..."
    sudo -u hromkz python3 -m venv $PROJECT_DIR/venv
    
    print_info "Установка Python пакетов..."
    sudo -u hromkz $PROJECT_DIR/venv/bin/pip install --upgrade pip
    sudo -u hromkz $PROJECT_DIR/venv/bin/pip install \
        flask flask-sqlalchemy flask-wtf wtforms werkzeug \
        gunicorn psycopg2-binary requests sqlalchemy email-validator
else
    print_status "Python окружение уже существует"
fi

print_step "ЭТАП 3: Файлы приложения"

print_info "Создание .env конфигурации..."
cat > $PROJECT_DIR/.env << 'EOF'
DATABASE_URL=postgresql://hromkz_user:HromKZ_SecurePass2025!@localhost/hromkz_logistics
SESSION_SECRET=HromKZ_Production_Secret_2025_LogisticsSystem_FixedVPS
FLASK_ENV=production
TELEGRAM_BOT_TOKEN=
TELEGRAM_ADMIN_ID=
EOF

print_info "Создание app.py..."
cat > $PROJECT_DIR/app.py << 'EOF'
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

app = create_app()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
EOF

print_info "Создание main.py..."
cat > $PROJECT_DIR/main.py << 'EOF'
import os
from app import app

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

print_info "Создание models.py..."
cat > $PROJECT_DIR/models.py << 'EOF'
from app import db
from werkzeug.security import generate_password_hash, check_password_hash
from datetime import datetime

class Employee(db.Model):
    __tablename__ = 'employees'
    
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password_hash = db.Column(db.String(256), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    def set_password(self, password):
        self.password_hash = generate_password_hash(password)
    
    def check_password(self, password):
        return check_password_hash(self.password_hash, password)

class Request(db.Model):
    __tablename__ = 'requests'
    
    id = db.Column(db.Integer, primary_key=True)
    
    sender_name = db.Column(db.String(100), nullable=False)
    sender_phone = db.Column(db.String(20), nullable=False)
    sender_address = db.Column(db.Text, nullable=False)
    
    recipient_name = db.Column(db.String(100), nullable=False)
    recipient_phone = db.Column(db.String(20), nullable=False)
    recipient_address = db.Column(db.Text, nullable=False)
    
    cargo_description = db.Column(db.Text, nullable=False)
    cargo_weight = db.Column(db.Float)
    cargo_value = db.Column(db.Float)
    
    delivery_type = db.Column(db.String(20), nullable=False)
    status = db.Column(db.String(20), default='pending')
    
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    notes = db.Column(db.Text)
EOF

print_info "Создание forms.py..."
cat > $PROJECT_DIR/forms.py << 'EOF'
from flask_wtf import FlaskForm
from wtforms import StringField, TextAreaField, FloatField, SelectField, PasswordField, SubmitField
from wtforms.validators import DataRequired, Email, Length, Optional

class EmployeeRegistrationForm(FlaskForm):
    username = StringField('Имя пользователя', validators=[DataRequired(), Length(min=3, max=80)])
    email = StringField('Email', validators=[DataRequired(), Email()])
    password = PasswordField('Пароль', validators=[DataRequired(), Length(min=6)])
    submit = SubmitField('Зарегистрироваться')

class EmployeeLoginForm(FlaskForm):
    username = StringField('Имя пользователя', validators=[DataRequired()])
    password = PasswordField('Пароль', validators=[DataRequired()])
    submit = SubmitField('Войти')

class RequestForm(FlaskForm):
    sender_name = StringField('Имя отправителя', validators=[DataRequired(), Length(max=100)])
    sender_phone = StringField('Телефон отправителя', validators=[DataRequired(), Length(max=20)])
    sender_address = TextAreaField('Адрес отправителя', validators=[DataRequired()])
    
    recipient_name = StringField('Имя получателя', validators=[DataRequired(), Length(max=100)])
    recipient_phone = StringField('Телефон получателя', validators=[DataRequired(), Length(max=20)])
    recipient_address = TextAreaField('Адрес получателя', validators=[DataRequired()])
    
    cargo_description = TextAreaField('Описание груза', validators=[DataRequired()])
    cargo_weight = FloatField('Вес (кг)', validators=[Optional()])
    cargo_value = FloatField('Стоимость груза (тенге)', validators=[Optional()])
    
    delivery_type = SelectField('Тип доставки', 
                               choices=[('astana', 'По Астане'), ('regional', 'Межгород')],
                               validators=[DataRequired()])
    
    submit = SubmitField('Отправить заявку')

class TrackingForm(FlaskForm):
    phone = StringField('Номер телефона', validators=[DataRequired(), Length(max=20)])
    submit = SubmitField('Найти заявки')
EOF

print_info "Создание routes.py..."
cat > $PROJECT_DIR/routes.py << 'EOF'
from flask import render_template, request, redirect, url_for, flash, session
from app import app, db
from models import Employee, Request
from forms import EmployeeRegistrationForm, EmployeeLoginForm, RequestForm, TrackingForm

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/request', methods=['GET', 'POST'])
def create_request():
    form = RequestForm()
    if form.validate_on_submit():
        new_request = Request(
            sender_name=form.sender_name.data,
            sender_phone=form.sender_phone.data,
            sender_address=form.sender_address.data,
            recipient_name=form.recipient_name.data,
            recipient_phone=form.recipient_phone.data,
            recipient_address=form.recipient_address.data,
            cargo_description=form.cargo_description.data,
            cargo_weight=form.cargo_weight.data,
            cargo_value=form.cargo_value.data,
            delivery_type=form.delivery_type.data
        )
        
        db.session.add(new_request)
        db.session.commit()
        
        flash('Заявка успешно отправлена! Мы свяжемся с вами в ближайшее время.', 'success')
        return redirect(url_for('index'))
    
    return render_template('request.html', form=form)

@app.route('/track', methods=['GET', 'POST'])
def track():
    form = TrackingForm()
    requests = []
    
    if form.validate_on_submit():
        phone = form.phone.data
        requests = Request.query.filter(
            (Request.sender_phone == phone) | (Request.recipient_phone == phone)
        ).order_by(Request.created_at.desc()).all()
        
        if not requests:
            flash('Заявки с указанным номером телефона не найдены.', 'warning')
    
    return render_template('track.html', form=form, requests=requests)

@app.route('/register', methods=['GET', 'POST'])
def register():
    form = EmployeeRegistrationForm()
    if form.validate_on_submit():
        if Employee.query.filter_by(username=form.username.data).first():
            flash('Пользователь с таким именем уже существует.', 'error')
        elif Employee.query.filter_by(email=form.email.data).first():
            flash('Пользователь с таким email уже существует.', 'error')
        else:
            employee = Employee(username=form.username.data, email=form.email.data)
            employee.set_password(form.password.data)
            db.session.add(employee)
            db.session.commit()
            flash('Регистрация успешна!', 'success')
            return redirect(url_for('login'))
    
    return render_template('register.html', form=form)

@app.route('/login', methods=['GET', 'POST'])
def login():
    form = EmployeeLoginForm()
    if form.validate_on_submit():
        employee = Employee.query.filter_by(username=form.username.data).first()
        if employee and employee.check_password(form.password.data):
            session['employee_id'] = employee.id
            session['employee_username'] = employee.username
            flash('Вход выполнен успешно!', 'success')
            return redirect(url_for('dashboard'))
        else:
            flash('Неверное имя пользователя или пароль.', 'error')
    
    return render_template('login.html', form=form)

@app.route('/logout')
def logout():
    session.pop('employee_id', None)
    session.pop('employee_username', None)
    flash('Вы вышли из системы.', 'info')
    return redirect(url_for('index'))

@app.route('/dashboard')
def dashboard():
    if 'employee_id' not in session:
        flash('Пожалуйста, войдите в систему.', 'warning')
        return redirect(url_for('login'))
    
    requests = Request.query.order_by(Request.created_at.desc()).all()
    return render_template('dashboard.html', requests=requests)

@app.route('/update_status/<int:request_id>/<new_status>')
def update_status(request_id, new_status):
    if 'employee_id' not in session:
        return redirect(url_for('login'))
    
    req = Request.query.get_or_404(request_id)
    req.status = new_status
    db.session.commit()
    
    flash(f'Статус заявки №{request_id} обновлен на "{new_status}".', 'success')
    return redirect(url_for('dashboard'))
EOF

print_info "Создание HTML шаблонов..."
mkdir -p templates

cat > $PROJECT_DIR/templates/base.html << 'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{% block title %}Хром КЗ - Логистические услуги{% endblock %}</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
</head>
<body>
    <nav class="navbar navbar-expand-lg navbar-dark bg-primary">
        <div class="container">
            <a class="navbar-brand" href="{{ url_for('index') }}">
                <i class="fas fa-truck"></i> Хром КЗ
            </a>
            <div class="navbar-nav ms-auto">
                <a class="nav-link" href="{{ url_for('index') }}">Главная</a>
                <a class="nav-link" href="{{ url_for('create_request') }}">Заявка</a>
                <a class="nav-link" href="{{ url_for('track') }}">Отследить</a>
                {% if session.employee_id %}
                    <a class="nav-link" href="{{ url_for('dashboard') }}">Панель</a>
                    <a class="nav-link" href="{{ url_for('logout') }}">Выход</a>
                {% else %}
                    <a class="nav-link" href="{{ url_for('login') }}">Вход</a>
                {% endif %}
            </div>
        </div>
    </nav>

    <div class="container mt-4">
        {% with messages = get_flashed_messages(with_categories=true) %}
            {% if messages %}
                {% for category, message in messages %}
                    <div class="alert alert-{{ 'danger' if category == 'error' else category }} alert-dismissible fade show" role="alert">
                        {{ message }}
                        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                    </div>
                {% endfor %}
            {% endif %}
        {% endwith %}

        {% block content %}{% endblock %}
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
EOF

cat > $PROJECT_DIR/templates/index.html << 'EOF'
{% extends "base.html" %}

{% block content %}
<div class="row">
    <div class="col-md-8">
        <h1><i class="fas fa-truck text-primary"></i> Хром КЗ - Логистические услуги</h1>
        <p class="lead">Надежная доставка грузов по Астане и всему Казахстану</p>
        
        <div class="row mt-4">
            <div class="col-md-6 mb-3">
                <div class="card">
                    <div class="card-body text-center">
                        <i class="fas fa-city fa-3x text-primary mb-3"></i>
                        <h5>Доставка по Астане</h5>
                        <p>Быстрая доставка в пределах города</p>
                        <a href="{{ url_for('create_request') }}" class="btn btn-primary">Заказать</a>
                    </div>
                </div>
            </div>
            <div class="col-md-6 mb-3">
                <div class="card">
                    <div class="card-body text-center">
                        <i class="fas fa-map-marked-alt fa-3x text-success mb-3"></i>
                        <h5>Межгородские перевозки</h5>
                        <p>Доставка по всему Казахстану</p>
                        <a href="{{ url_for('create_request') }}" class="btn btn-success">Заказать</a>
                    </div>
                </div>
            </div>
        </div>
    </div>
    <div class="col-md-4">
        <div class="card">
            <div class="card-header">
                <h5><i class="fas fa-search"></i> Отследить груз</h5>
            </div>
            <div class="card-body">
                <p>Введите номер телефона для поиска ваших заявок</p>
                <a href="{{ url_for('track') }}" class="btn btn-outline-primary w-100">Отследить заявку</a>
            </div>
        </div>
    </div>
</div>
{% endblock %}
EOF

cat > $PROJECT_DIR/init_database.py << 'EOF'
import os
from app import app, db

def init_database():
    with app.app_context():
        try:
            print("Создание таблиц базы данных...")
            db.create_all()
            print("✓ База данных инициализирована успешно!")
            return True
        except Exception as e:
            print(f"✗ Ошибка инициализации БД: {e}")
            return False

if __name__ == '__main__':
    success = init_database()
    exit(0 if success else 1)
EOF

chown -R hromkz:www-data $PROJECT_DIR
chmod +x $PROJECT_DIR/init_database.py

print_step "ЭТАП 4: Инициализация базы данных"

print_info "Инициализация таблиц..."
if sudo -u hromkz bash -c "cd $PROJECT_DIR && source .env && ./venv/bin/python init_database.py"; then
    print_status "База данных инициализирована"
else
    print_error "Ошибка инициализации БД, но продолжаем..."
fi

print_step "ЭТАП 5: Systemd сервис"

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
ExecStart=/var/www/logistics.xrom.org/venv/bin/gunicorn --workers 2 --bind unix:/var/www/logistics.xrom.org/run/hromkz.sock --umask 0007 --timeout 30 main:app
ExecReload=/bin/kill -s HUP $MAINPID
Restart=always
RestartSec=10
TimeoutStartSec=60

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hromkz

print_step "ЭТАП 6: Nginx"

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
    }
    
    location /static {
        alias /var/www/logistics.xrom.org/static;
        expires 30d;
    }
}
EOF
    
    ln -sf /etc/nginx/sites-available/logistics.xrom.org /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
fi

if nginx -t; then
    print_status "Nginx конфигурация корректна"
else
    print_error "Ошибка Nginx конфигурации"
fi

print_step "ЭТАП 7: Файрвол (исправленный)"

print_info "Настройка файрвола без ошибок..."
ufw --force enable
ufw allow ssh
ufw allow 'Nginx Full'
ufw allow 5432/tcp  # PostgreSQL прямым портом

print_step "ЭТАП 8: Запуск сервисов"

print_info "Запуск всех сервисов..."
systemctl restart postgresql || print_error "PostgreSQL restart failed"
systemctl start hromkz || print_error "hromkz start failed"  
systemctl restart nginx || print_error "nginx restart failed"

print_info "Ожидание запуска сервисов..."
sleep 10

print_step "ФИНАЛЬНАЯ ПРОВЕРКА"

echo "======================================"

# Статус сервисов
print_info "Статус сервисов:"
systemctl is-active --quiet postgresql && print_status "PostgreSQL: работает" || print_error "PostgreSQL: не работает"
systemctl is-active --quiet hromkz && print_status "hromkz: работает" || print_error "hromkz: не работает"
systemctl is-active --quiet nginx && print_status "Nginx: работает" || print_error "Nginx: не работает"

# Socket файл
if [[ -S "/var/www/logistics.xrom.org/run/hromkz.sock" ]]; then
    print_status "Socket файл создан"
else
    print_error "Socket файл отсутствует"
fi

# HTTP тест
print_info "HTTP тестирование..."
sleep 3
HTTP_CODE=$(curl -I -s -o /dev/null -w "%{http_code}" --connect-timeout 10 http://logistics.xrom.org 2>/dev/null || echo "000")

case "$HTTP_CODE" in
    "200")
        print_status "🎉 ПОЛНЫЙ УСПЕХ!"
        echo ""
        echo "========================================"  
        echo "URL: http://logistics.xrom.org"
        echo "Регистрация: http://logistics.xrom.org/register"
        echo "Заявка: http://logistics.xrom.org/request"
        echo "Отслеживание: http://logistics.xrom.org/track"
        echo ""
        echo "Следующие шаги:"
        echo "1. Создайте первого сотрудника через /register"
        echo "2. Настройте SSL: sudo certbot --nginx -d logistics.xrom.org"
        echo "========================================"
        ;;
    "502")
        print_error "HTTP 502 - приложение не отвечает"
        print_info "Проверьте логи: journalctl -u hromkz -n 10"
        ;;
    "000")
        print_error "Сервер недоступен"
        ;;
    *)
        print_error "HTTP код: $HTTP_CODE"
        ;;
esac

if [[ "$HTTP_CODE" != "200" ]]; then
    echo ""
    print_info "Для диагностики:"
    echo "sudo journalctl -u hromkz -n 20"
    echo "sudo systemctl status hromkz"
fi

print_info "Установка завершена!"