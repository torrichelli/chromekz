#!/bin/bash

# Полное развертывание Хром КЗ на VPS
# Запуск: sudo bash full_deploy.sh

echo "🚀 Полное развертывание Хром КЗ на logistics.xrom.org"

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Обновление системы и установка пакетов
print_status "Установка системных пакетов..."
apt update && apt upgrade -y
apt install -y python3 python3-pip python3-venv nginx postgresql postgresql-contrib git ufw curl wget unzip

# Создание пользователя
if ! id "hromkz" &>/dev/null; then
    print_status "Создание пользователя hromkz..."
    adduser --disabled-password --gecos "" hromkz
    usermod -aG sudo hromkz
fi

# Настройка PostgreSQL
print_status "Настройка PostgreSQL..."
sudo -u postgres psql << 'EOF'
DROP DATABASE IF EXISTS hromkz_logistics;
DROP USER IF EXISTS hromkz_user;

CREATE DATABASE hromkz_logistics;
CREATE USER hromkz_user WITH ENCRYPTED PASSWORD 'HromKZ_SecurePass2025!';
GRANT ALL PRIVILEGES ON DATABASE hromkz_logistics TO hromkz_user;
ALTER USER hromkz_user CREATEDB;
\q
EOF

# Создание директории проекта
DEPLOY_DIR="/var/www/logistics.xrom.org"
rm -rf $DEPLOY_DIR
mkdir -p $DEPLOY_DIR
cd $DEPLOY_DIR

print_status "Создание полной структуры проекта..."

# Создание основных файлов приложения
cat > app.py << 'EOF'
import os
from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy.orm import DeclarativeBase
from werkzeug.middleware.proxy_fix import ProxyFix

class Base(DeclarativeBase):
    pass

db = SQLAlchemy(model_class=Base)
app = Flask(__name__)
app.secret_key = os.environ.get("SESSION_SECRET", "dev-secret-key")
app.wsgi_app = ProxyFix(app.wsgi_app, x_proto=1, x_host=1)

app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get(
    "DATABASE_URL", 
    "postgresql://hromkz_user:HromKZ_SecurePass2025!@localhost/hromkz_logistics"
)
app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {
    "pool_recycle": 300,
    "pool_pre_ping": True,
}

db.init_app(app)

with app.app_context():
    import models
    import routes
    db.create_all()
EOF

cat > main.py << 'EOF'
from app import app

if __name__ == "__main__":
    app.run(debug=False, host="0.0.0.0", port=5000)
EOF

cat > config.py << 'EOF'
import os

class Config:
    SECRET_KEY = os.environ.get('SESSION_SECRET') or 'dev-secret-key'
    SQLALCHEMY_DATABASE_URI = os.environ.get('DATABASE_URL') or 'postgresql://hromkz_user:HromKZ_SecurePass2025!@localhost/hromkz_logistics'
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SQLALCHEMY_ENGINE_OPTIONS = {
        "pool_recycle": 300,
        "pool_pre_ping": True,
    }
EOF

# Создание моделей
cat > models.py << 'EOF'
from app import db
from datetime import datetime
from werkzeug.security import generate_password_hash, check_password_hash

class Employee(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    phone = db.Column(db.String(20), nullable=False)
    password_hash = db.Column(db.String(255), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    assigned_requests = db.relationship('Request', backref='assigned_employee', lazy=True)

    def set_password(self, password):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password):
        return check_password_hash(self.password_hash, password)

    def __repr__(self):
        return f'<Employee {self.username}>'

class Request(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    customer_name = db.Column(db.String(100), nullable=False)
    customer_phone = db.Column(db.String(20), nullable=False)
    customer_address = db.Column(db.Text, nullable=False)
    cargo_description = db.Column(db.Text, nullable=False)
    cargo_weight = db.Column(db.Float)
    cargo_volume = db.Column(db.Float)
    delivery_type = db.Column(db.String(20), nullable=False)
    status = db.Column(db.String(20), default='pending')
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    preferred_delivery_date = db.Column(db.Date)
    pickup_address = db.Column(db.Text)
    special_instructions = db.Column(db.Text)
    assigned_employee_id = db.Column(db.Integer, db.ForeignKey('employee.id'))

    def __repr__(self):
        return f'<Request {self.id}: {self.customer_name}>'
EOF

# Создание форм
cat > forms.py << 'EOF'
from flask_wtf import FlaskForm
from wtforms import StringField, PasswordField, SubmitField, TextAreaField, SelectField, FloatField, DateField
from wtforms.validators import DataRequired, Email, Length, Optional
from email_validator import validate_email

class EmployeeRegistrationForm(FlaskForm):
    username = StringField('Имя пользователя', validators=[DataRequired(), Length(min=4, max=20)])
    email = StringField('Email', validators=[DataRequired(), Email()])
    phone = StringField('Номер телефона', validators=[DataRequired(), Length(min=10, max=20)])
    password = PasswordField('Пароль', validators=[DataRequired(), Length(min=6)])
    submit = SubmitField('Зарегистрироваться')

class EmployeeLoginForm(FlaskForm):
    username = StringField('Имя пользователя', validators=[DataRequired()])
    password = PasswordField('Пароль', validators=[DataRequired()])
    submit = SubmitField('Войти')

class AstanaDeliveryForm(FlaskForm):
    customer_name = StringField('Имя клиента', validators=[DataRequired(), Length(max=100)])
    customer_phone = StringField('Номер телефона клиента', validators=[DataRequired(), Length(max=20)])
    customer_address = TextAreaField('Адрес доставки', validators=[DataRequired()])
    pickup_address = TextAreaField('Адрес забора груза', validators=[DataRequired()])
    cargo_description = TextAreaField('Описание груза', validators=[DataRequired()])
    cargo_weight = FloatField('Вес (кг)', validators=[Optional()])
    cargo_volume = FloatField('Объем (м³)', validators=[Optional()])
    preferred_delivery_date = DateField('Предпочтительная дата доставки', validators=[Optional()])
    special_instructions = TextAreaField('Особые указания', validators=[Optional()])
    submit = SubmitField('Оформить заявку')

class RegionalDeliveryForm(FlaskForm):
    customer_name = StringField('Имя клиента', validators=[DataRequired(), Length(max=100)])
    customer_phone = StringField('Номер телефона клиента', validators=[DataRequired(), Length(max=20)])
    customer_address = TextAreaField('Адрес доставки', validators=[DataRequired()])
    pickup_address = TextAreaField('Адрес забора груза', validators=[DataRequired()])
    cargo_description = TextAreaField('Описание груза', validators=[DataRequired()])
    cargo_weight = FloatField('Вес (кг)', validators=[Optional()])
    cargo_volume = FloatField('Объем (м³)', validators=[Optional()])
    preferred_delivery_date = DateField('Предпочтительная дата доставки', validators=[Optional()])
    special_instructions = TextAreaField('Особые указания', validators=[Optional()])
    submit = SubmitField('Оформить заявку')

class TrackOrderForm(FlaskForm):
    customer_phone = StringField('Номер телефона', validators=[DataRequired(), Length(max=20)])
    submit = SubmitField('Найти заявки')

class UpdateStatusForm(FlaskForm):
    status = SelectField('Статус', choices=[
        ('pending', 'Ожидает обработки'),
        ('processing', 'В обработке'),
        ('shipped', 'Отправлен'),
        ('delivered', 'Доставлен')
    ], validators=[DataRequired()])
    submit = SubmitField('Обновить статус')
EOF

# Создание маршрутов (routes.py будет создан в следующем блоке из-за ограничений размера)
print_status "Создание системы маршрутов..."

# Создание директорий для статических файлов и шаблонов
mkdir -p static/{css,js,images}
mkdir -p templates

# Создание CSS стилей
cat > static/css/custom.css << 'EOF'
/* Apple Design System Colors */
:root {
    --apple-blue: #007AFF;
    --apple-gray: #8E8E93;
    --apple-dark: #1D1D1F;
    --apple-light: #F2F2F7;
    --text-primary: #1D1D1F;
    --text-secondary: #86868B;
    --bg-primary: #FFFFFF;
    --bg-secondary: #F2F2F7;
}

body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    background: var(--bg-secondary);
    color: var(--text-primary);
}

.modern-nav {
    background: rgba(255, 255, 255, 0.8);
    backdrop-filter: blur(20px);
    border-bottom: 0.5px solid rgba(0, 0, 0, 0.1);
}

.hero-section {
    background: linear-gradient(135deg, var(--apple-blue), #5856D6);
    color: white;
    padding: 4rem 0;
}

.card {
    border: none;
    border-radius: 12px;
    box-shadow: 0 4px 20px rgba(0, 0, 0, 0.1);
}

.btn-primary {
    background: var(--apple-blue);
    border: none;
    border-radius: 8px;
    font-weight: 500;
}

.btn-primary:hover {
    background: #0056CC;
}

.form-control {
    border: 1px solid #D1D1D6;
    border-radius: 8px;
    padding: 12px;
}

.form-control:focus {
    border-color: var(--apple-blue);
    box-shadow: 0 0 0 3px rgba(0, 122, 255, 0.1);
}

.table {
    background: white;
    border-radius: 12px;
    overflow: hidden;
}

.badge {
    border-radius: 6px;
    font-weight: 500;
}
EOF

# Создание основного JavaScript
cat > static/js/main.js << 'EOF'
// Phone mask functionality
document.addEventListener('DOMContentLoaded', function() {
    const phoneInputs = document.querySelectorAll('.phone-mask');
    
    phoneInputs.forEach(input => {
        input.addEventListener('input', function(e) {
            let value = e.target.value.replace(/\D/g, '');
            if (!value.startsWith('7')) value = '7' + value;
            value = value.substring(0, 11);
            
            let formatted = '+7(';
            if (value.length > 1) {
                formatted += '7';
                if (value.length > 2) {
                    formatted += value.substring(2, 4) + ')';
                    if (value.length > 4) {
                        formatted += value.substring(4, 7);
                        if (value.length > 7) {
                            formatted += '-' + value.substring(7, 9);
                            if (value.length > 9) {
                                formatted += '-' + value.substring(9, 11);
                            }
                        }
                    }
                }
            }
            e.target.value = formatted;
        });
        
        input.addEventListener('focus', function(e) {
            if (!e.target.value) e.target.value = '+7(7';
        });
    });
});

// Form functions
function showForm(formId) {
    document.querySelectorAll('.form-container').forEach(form => {
        form.style.display = 'none';
    });
    const form = document.getElementById(formId);
    if (form) {
        form.style.display = 'block';
        form.scrollIntoView({ behavior: 'smooth' });
    }
}

function hideForm(formId) {
    const form = document.getElementById(formId);
    if (form) form.style.display = 'none';
}
EOF

print_status "Создание шаблонов..."

# Создание базового шаблона
cat > templates/base.html << 'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{% block title %}Хром КЗ - Логистика{% endblock %}</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css">
    <link rel="stylesheet" href="{{ url_for('static', filename='css/custom.css') }}">
</head>
<body>
    <nav class="navbar navbar-expand-lg modern-nav">
        <div class="container">
            <a class="navbar-brand fw-bold" href="{{ url_for('index') }}">Хром КЗ</a>
            <div class="navbar-nav ms-auto">
                {% if session.employee_id %}
                    <a class="nav-link" href="{{ url_for('dashboard') }}">Панель</a>
                    <a class="nav-link" href="{{ url_for('logout') }}">Выйти</a>
                {% else %}
                    <a class="nav-link" href="{{ url_for('login') }}">Вход</a>
                    <a class="nav-link" href="{{ url_for('register') }}">Регистрация</a>
                {% endif %}
            </div>
        </div>
    </nav>

    {% with messages = get_flashed_messages(with_categories=true) %}
        {% if messages %}
            <div class="container mt-3">
                {% for category, message in messages %}
                    <div class="alert alert-{{ 'danger' if category == 'error' else category }}">
                        {{ message }}
                    </div>
                {% endfor %}
            </div>
        {% endif %}
    {% endwith %}

    <main>{% block content %}{% endblock %}</main>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <script src="{{ url_for('static', filename='js/main.js') }}"></script>
</body>
</html>
EOF

print_status "Создание routes.py..."

# Создание маршрутов - разбито на части из-за размера
cat > routes.py << 'EOF'
from flask import render_template, redirect, url_for, flash, request, session
from app import app, db
from models import Employee, Request
from forms import *
from datetime import datetime
import logging

logging.basicConfig(level=logging.INFO)

@app.route('/')
def index():
    astana_form = AstanaDeliveryForm()
    regions_form = RegionalDeliveryForm()
    return render_template('index.html', 
                         astana_form=astana_form, 
                         regions_form=regions_form)

@app.route('/submit_astana', methods=['POST'])
def submit_astana():
    form = AstanaDeliveryForm()
    if form.validate_on_submit():
        request_obj = Request(
            customer_name=form.customer_name.data,
            customer_phone=form.customer_phone.data,
            customer_address=form.customer_address.data,
            pickup_address=form.pickup_address.data,
            cargo_description=form.cargo_description.data,
            cargo_weight=form.cargo_weight.data,
            cargo_volume=form.cargo_volume.data,
            delivery_type='astana',
            preferred_delivery_date=form.preferred_delivery_date.data,
            special_instructions=form.special_instructions.data
        )
        db.session.add(request_obj)
        db.session.commit()
        flash(f'Заявка №{request_obj.id} успешно создана!', 'success')
        return redirect(url_for('index'))
    
    for field, errors in form.errors.items():
        for error in errors:
            flash(f'{getattr(form, field).label.text}: {error}', 'error')
    return redirect(url_for('index'))

@app.route('/submit_regions', methods=['POST'])
def submit_regions():
    form = RegionalDeliveryForm()
    if form.validate_on_submit():
        request_obj = Request(
            customer_name=form.customer_name.data,
            customer_phone=form.customer_phone.data,
            customer_address=form.customer_address.data,
            pickup_address=form.pickup_address.data,
            cargo_description=form.cargo_description.data,
            cargo_weight=form.cargo_weight.data,
            cargo_volume=form.cargo_volume.data,
            delivery_type='regions',
            preferred_delivery_date=form.preferred_delivery_date.data,
            special_instructions=form.special_instructions.data
        )
        db.session.add(request_obj)
        db.session.commit()
        flash(f'Заявка №{request_obj.id} успешно создана!', 'success')
        return redirect(url_for('index'))
    
    for field, errors in form.errors.items():
        for error in errors:
            flash(f'{getattr(form, field).label.text}: {error}', 'error')
    return redirect(url_for('index'))

@app.route('/register', methods=['GET', 'POST'])
def register():
    form = EmployeeRegistrationForm()
    if form.validate_on_submit():
        if Employee.query.filter_by(username=form.username.data).first():
            flash('Пользователь с таким именем уже существует', 'error')
            return render_template('register.html', form=form)
        
        if Employee.query.filter_by(email=form.email.data).first():
            flash('Пользователь с таким email уже существует', 'error')
            return render_template('register.html', form=form)
        
        employee = Employee(
            username=form.username.data,
            email=form.email.data,
            phone=form.phone.data
        )
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
        flash('Неверное имя пользователя или пароль', 'error')
    
    return render_template('login.html', form=form)

@app.route('/logout')
def logout():
    session.clear()
    flash('Выход выполнен', 'info')
    return redirect(url_for('index'))

@app.route('/dashboard')
def dashboard():
    if 'employee_id' not in session:
        return redirect(url_for('login'))
    
    requests = Request.query.order_by(Request.created_at.desc()).all()
    status_names = {
        'pending': 'Ожидает',
        'processing': 'В обработке', 
        'shipped': 'Отправлен',
        'delivered': 'Доставлен'
    }
    return render_template('dashboard.html', requests=requests, status_names=status_names)

@app.route('/track_order', methods=['GET', 'POST'])
def track_order():
    form = TrackOrderForm()
    orders = []
    status_names = {
        'pending': 'Ожидает',
        'processing': 'В обработке',
        'shipped': 'Отправлен', 
        'delivered': 'Доставлен'
    }
    
    if form.validate_on_submit():
        orders = Request.query.filter_by(customer_phone=form.customer_phone.data).all()
        if not orders:
            flash('Заявки с указанным номером телефона не найдены', 'info')
    
    return render_template('track_order.html', form=form, orders=orders, status_names=status_names)

@app.route('/update_status/<int:request_id>', methods=['POST'])
def update_status(request_id):
    if 'employee_id' not in session:
        return redirect(url_for('login'))
    
    request_obj = Request.query.get_or_404(request_id)
    form = UpdateStatusForm()
    
    if form.validate_on_submit():
        request_obj.status = form.status.data
        request_obj.updated_at = datetime.utcnow()
        request_obj.assigned_employee_id = session['employee_id']
        db.session.commit()
        flash('Статус заявки обновлен!', 'success')
    
    return redirect(url_for('dashboard'))

@app.route('/health')
def health():
    return {'status': 'ok', 'message': 'Хром КЗ работает'}
EOF

print_status "Создание основных шаблонов..."

# Создание главной страницы
cat > templates/index.html << 'EOF'
{% extends "base.html" %}

{% block content %}
<div class="hero-section text-white text-center py-5">
    <div class="container">
        <h1 class="display-4 fw-bold mb-3">Хром КЗ</h1>
        <p class="lead mb-4">Профессиональные логистические решения</p>
        <div class="row g-3">
            <div class="col-md-6">
                <button class="btn btn-light btn-lg w-100" onclick="showForm('astanaForm')">
                    <i class="fas fa-city me-2"></i>Доставка по Астане
                </button>
            </div>
            <div class="col-md-6">
                <button class="btn btn-outline-light btn-lg w-100" onclick="showForm('regionsForm')">
                    <i class="fas fa-map me-2"></i>Межрегиональная доставка
                </button>
            </div>
        </div>
    </div>
</div>

<div class="container py-5">
    <!-- Форма доставки по Астане -->
    <div id="astanaForm" class="form-container" style="display:none;">
        <div class="row justify-content-center">
            <div class="col-lg-8">
                <div class="card">
                    <div class="card-header">
                        <h4><i class="fas fa-city me-2"></i>Доставка по Астане</h4>
                    </div>
                    <div class="card-body">
                        <form method="POST" action="{{ url_for('submit_astana') }}">
                            {{ astana_form.hidden_tag() }}
                            <div class="row">
                                <div class="col-md-6">
                                    <div class="mb-3">
                                        {{ astana_form.customer_name.label(class="form-label") }}
                                        {{ astana_form.customer_name(class="form-control") }}
                                    </div>
                                </div>
                                <div class="col-md-6">
                                    <div class="mb-3">
                                        {{ astana_form.customer_phone.label(class="form-label") }}
                                        {{ astana_form.customer_phone(class="form-control phone-mask", placeholder="+7(7__)___-__-__") }}
                                    </div>
                                </div>
                            </div>
                            <div class="mb-3">
                                {{ astana_form.customer_address.label(class="form-label") }}
                                {{ astana_form.customer_address(class="form-control", rows="2") }}
                            </div>
                            <div class="mb-3">
                                {{ astana_form.pickup_address.label(class="form-label") }}
                                {{ astana_form.pickup_address(class="form-control", rows="2") }}
                            </div>
                            <div class="mb-3">
                                {{ astana_form.cargo_description.label(class="form-label") }}
                                {{ astana_form.cargo_description(class="form-control", rows="3") }}
                            </div>
                            <div class="row">
                                <div class="col-md-6">
                                    <div class="mb-3">
                                        {{ astana_form.cargo_weight.label(class="form-label") }}
                                        {{ astana_form.cargo_weight(class="form-control") }}
                                    </div>
                                </div>
                                <div class="col-md-6">
                                    <div class="mb-3">
                                        {{ astana_form.cargo_volume.label(class="form-label") }}
                                        {{ astana_form.cargo_volume(class="form-control") }}
                                    </div>
                                </div>
                            </div>
                            <div class="row">
                                <div class="col-md-6">
                                    <button type="button" class="btn btn-secondary w-100" onclick="hideForm('astanaForm')">Отменить</button>
                                </div>
                                <div class="col-md-6">
                                    {{ astana_form.submit(class="btn btn-primary w-100") }}
                                </div>
                            </div>
                        </form>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- Форма межрегиональной доставки -->
    <div id="regionsForm" class="form-container" style="display:none;">
        <div class="row justify-content-center">
            <div class="col-lg-8">
                <div class="card">
                    <div class="card-header">
                        <h4><i class="fas fa-map me-2"></i>Межрегиональная доставка</h4>
                    </div>
                    <div class="card-body">
                        <form method="POST" action="{{ url_for('submit_regions') }}">
                            {{ regions_form.hidden_tag() }}
                            <div class="row">
                                <div class="col-md-6">
                                    <div class="mb-3">
                                        {{ regions_form.customer_name.label(class="form-label") }}
                                        {{ regions_form.customer_name(class="form-control") }}
                                    </div>
                                </div>
                                <div class="col-md-6">
                                    <div class="mb-3">
                                        {{ regions_form.customer_phone.label(class="form-label") }}
                                        {{ regions_form.customer_phone(class="form-control phone-mask", placeholder="+7(7__)___-__-__") }}
                                    </div>
                                </div>
                            </div>
                            <div class="mb-3">
                                {{ regions_form.customer_address.label(class="form-label") }}
                                {{ regions_form.customer_address(class="form-control", rows="2") }}
                            </div>
                            <div class="mb-3">
                                {{ regions_form.pickup_address.label(class="form-label") }}
                                {{ regions_form.pickup_address(class="form-control", rows="2") }}
                            </div>
                            <div class="mb-3">
                                {{ regions_form.cargo_description.label(class="form-label") }}
                                {{ regions_form.cargo_description(class="form-control", rows="3") }}
                            </div>
                            <div class="row">
                                <div class="col-md-6">
                                    <button type="button" class="btn btn-secondary w-100" onclick="hideForm('regionsForm')">Отменить</button>
                                </div>
                                <div class="col-md-6">
                                    {{ regions_form.submit(class="btn btn-primary w-100") }}
                                </div>
                            </div>
                        </form>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <div class="row mt-5">
        <div class="col-md-4">
            <div class="text-center">
                <i class="fas fa-shipping-fast fa-3x text-primary mb-3"></i>
                <h4>Быстро</h4>
                <p>Доставка по Астане за 1-3 часа</p>
            </div>
        </div>
        <div class="col-md-4">
            <div class="text-center">
                <i class="fas fa-shield-alt fa-3x text-primary mb-3"></i>
                <h4>Надежно</h4>
                <p>100% сохранность груза</p>
            </div>
        </div>
        <div class="col-md-4">
            <div class="text-center">
                <i class="fas fa-headset fa-3x text-primary mb-3"></i>
                <h4>Поддержка 24/7</h4>
                <p>Всегда на связи</p>
            </div>
        </div>
    </div>
</div>
{% endblock %}
EOF

print_status "Создание остальных шаблонов..."

# Остальные шаблоны
cat > templates/register.html << 'EOF'
{% extends "base.html" %}

{% block content %}
<div class="container py-5">
    <div class="row justify-content-center">
        <div class="col-md-6">
            <div class="card">
                <div class="card-header text-center">
                    <h4>Регистрация сотрудника</h4>
                </div>
                <div class="card-body">
                    <form method="POST">
                        {{ form.hidden_tag() }}
                        <div class="mb-3">
                            {{ form.username.label(class="form-label") }}
                            {{ form.username(class="form-control") }}
                        </div>
                        <div class="mb-3">
                            {{ form.email.label(class="form-label") }}
                            {{ form.email(class="form-control") }}
                        </div>
                        <div class="mb-3">
                            {{ form.phone.label(class="form-label") }}
                            {{ form.phone(class="form-control phone-mask", placeholder="+7(7__)___-__-__") }}
                        </div>
                        <div class="mb-3">
                            {{ form.password.label(class="form-label") }}
                            {{ form.password(class="form-control") }}
                        </div>
                        <div class="d-grid">
                            {{ form.submit(class="btn btn-primary") }}
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </div>
</div>
{% endblock %}
EOF

cat > templates/login.html << 'EOF'
{% extends "base.html" %}

{% block content %}
<div class="container py-5">
    <div class="row justify-content-center">
        <div class="col-md-6">
            <div class="card">
                <div class="card-header text-center">
                    <h4>Вход для сотрудников</h4>
                </div>
                <div class="card-body">
                    <form method="POST">
                        {{ form.hidden_tag() }}
                        <div class="mb-3">
                            {{ form.username.label(class="form-label") }}
                            {{ form.username(class="form-control") }}
                        </div>
                        <div class="mb-3">
                            {{ form.password.label(class="form-label") }}
                            {{ form.password(class="form-control") }}
                        </div>
                        <div class="d-grid">
                            {{ form.submit(class="btn btn-primary") }}
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </div>
</div>
{% endblock %}
EOF

# Создание виртуального окружения и установка зависимостей
print_status "Настройка Python окружения..."
python3 -m venv venv
./venv/bin/pip install --upgrade pip
./venv/bin/pip install flask flask-sqlalchemy flask-wtf wtforms werkzeug email-validator psycopg2-binary gunicorn requests sqlalchemy

# Создание переменных окружения
cat > .env << 'EOF'
DATABASE_URL=postgresql://hromkz_user:HromKZ_SecurePass2025!@localhost/hromkz_logistics
SESSION_SECRET=HromKZ_Ultra_Secure_Session_Key_2025_Production_Full_Deploy
FLASK_ENV=production
FLASK_APP=main.py
EOF

# Инициализация базы данных
print_status "Инициализация базы данных..."
source .env
./venv/bin/python -c "from app import app, db; app.app_context().push(); db.create_all(); print('База данных инициализирована')"

# Создание systemd службы
print_status "Настройка systemd службы..."
cat > /etc/systemd/system/hromkz.service << EOF
[Unit]
Description=Hrom KZ Full Logistics System
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
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Nginx конфигурация
print_status "Настройка Nginx..."
cat > /etc/nginx/sites-available/logistics.xrom.org << 'EOF'
server {
    listen 80;
    server_name logistics.xrom.org;

    location = /favicon.ico { 
        access_log off; 
        log_not_found off; 
    }
    
    location /static/ {
        alias /var/www/logistics.xrom.org/static/;
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header Vary Accept-Encoding;
        gzip_static on;
    }

    location / {
        include proxy_params;
        proxy_pass http://unix:/var/www/logistics.xrom.org/hromkz.sock;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }
}
EOF

ln -sf /etc/nginx/sites-available/logistics.xrom.org /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Настройка прав доступа
print_status "Настройка прав доступа..."
chown -R www-data:www-data $DEPLOY_DIR
chmod -R 755 $DEPLOY_DIR
chmod 644 $DEPLOY_DIR/.env
# Добавляем пользователя hromkz в группу www-data для управления
usermod -a -G www-data hromkz

# Запуск служб
print_status "Запуск служб..."
systemctl daemon-reload
systemctl start hromkz
systemctl enable hromkz
nginx -t && systemctl restart nginx

# Файрвол
print_status "Настройка файрвола..."
ufw --force enable
ufw allow ssh
ufw allow 'Nginx Full'

# Создание скриптов управления
print_status "Создание скриптов управления..."
cat > /var/www/backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/var/www/backups"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p $BACKUP_DIR

export PGPASSWORD="HromKZ_SecurePass2025!"
pg_dump -h localhost -U hromkz_user hromkz_logistics > $BACKUP_DIR/hromkz_full_$DATE.sql

find $BACKUP_DIR -name "hromkz_full_*.sql" -mtime +7 -delete
echo "Backup completed: $BACKUP_DIR/hromkz_full_$DATE.sql"
EOF

chmod +x /var/www/backup.sh
chown www-data:www-data /var/www/backup.sh

# Создание скрипта обновления
cat > /var/www/update.sh << 'EOF'
#!/bin/bash
cd /var/www/logistics.xrom.org
echo "Updating application..."
# git pull origin main  # раскомментировать когда будет git репозиторий
systemctl restart hromkz
echo "Application updated!"
EOF

chmod +x /var/www/update.sh
chown www-data:www-data /var/www/update.sh

# Автоматические бэкапы
sudo -u www-data crontab - << 'EOF'
0 2 * * * /var/www/backup.sh >> /var/www/backup.log 2>&1
EOF

print_status "Проверка статуса служб..."
sleep 5

echo ""
echo "✅ ПОЛНОЕ РАЗВЕРТЫВАНИЕ ЗАВЕРШЕНО!"
echo "==============================================="
echo "🌐 Сайт: http://logistics.xrom.org"
echo "📊 Статус служб:"
systemctl is-active --quiet hromkz && echo "  ✅ Приложение: работает" || echo "  ❌ Приложение: ошибка"
systemctl is-active --quiet nginx && echo "  ✅ Nginx: работает" || echo "  ❌ Nginx: ошибка"
systemctl is-active --quiet postgresql && echo "  ✅ PostgreSQL: работает" || echo "  ❌ PostgreSQL: ошибка"
echo ""
echo "📋 Следующие шаги:"
echo "1. Настройте DNS: logistics.xrom.org -> $(curl -s ifconfig.me 2>/dev/null || echo 'ВАШ_IP')"
echo "2. SSL сертификат: sudo certbot --nginx -d logistics.xrom.org"
echo "3. Создайте первого сотрудника на /register"
echo ""
echo "🔧 Управление:"
echo "  Логи: sudo journalctl -u hromkz -f"
echo "  Перезапуск: sudo systemctl restart hromkz"
echo "  Бэкап: /var/www/backup.sh"
echo "  Обновление: /var/www/update.sh"
echo ""
echo "🎉 Полная система готова к работе!"
EOF

chmod +x full_deploy.sh

print_status "Создание краткой инструкции..."

cat > templates/dashboard.html << 'EOF'
{% extends "base.html" %}

{% block content %}
<div class="container py-4">
    <div class="d-flex justify-content-between align-items-center mb-4">
        <h2>Панель управления</h2>
        <span class="badge bg-primary">{{ session.employee_username }}</span>
    </div>

    {% if requests %}
        <div class="card">
            <div class="card-header">
                <h5 class="mb-0">Все заявки ({{ requests|length }})</h5>
            </div>
            <div class="card-body p-0">
                <div class="table-responsive">
                    <table class="table table-striped mb-0">
                        <thead>
                            <tr>
                                <th>№</th>
                                <th>Клиент</th>
                                <th>Телефон</th>
                                <th>Тип</th>
                                <th>Статус</th>
                                <th>Дата</th>
                                <th>Действия</th>
                            </tr>
                        </thead>
                        <tbody>
                            {% for req in requests %}
                            <tr>
                                <td><strong>#{{ req.id }}</strong></td>
                                <td>{{ req.customer_name }}</td>
                                <td>{{ req.customer_phone }}</td>
                                <td>
                                    {% if req.delivery_type == 'astana' %}
                                        <span class="badge bg-primary">Астана</span>
                                    {% else %}
                                        <span class="badge bg-secondary">Регионы</span>
                                    {% endif %}
                                </td>
                                <td>
                                    {% set status_colors = {
                                        'pending': 'warning',
                                        'processing': 'info',
                                        'shipped': 'primary',
                                        'delivered': 'success'
                                    } %}
                                    <span class="badge bg-{{ status_colors[req.status] }}">
                                        {{ status_names[req.status] }}
                                    </span>
                                </td>
                                <td>{{ req.created_at.strftime('%d.%m.%Y') }}</td>
                                <td>
                                    <button class="btn btn-sm btn-outline-info" 
                                            data-bs-toggle="modal" 
                                            data-bs-target="#modal{{ req.id }}">
                                        Подробнее
                                    </button>
                                </td>
                            </tr>
                            {% endfor %}
                        </tbody>
                    </table>
                </div>
            </div>
        </div>

        <!-- Модальные окна для каждой заявки -->
        {% for req in requests %}
        <div class="modal fade" id="modal{{ req.id }}">
            <div class="modal-dialog modal-lg">
                <div class="modal-content">
                    <div class="modal-header">
                        <h5 class="modal-title">Заявка #{{ req.id }}</h5>
                        <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                    </div>
                    <div class="modal-body">
                        <div class="row">
                            <div class="col-md-6">
                                <h6>Клиент</h6>
                                <p><strong>Имя:</strong> {{ req.customer_name }}</p>
                                <p><strong>Телефон:</strong> {{ req.customer_phone }}</p>
                                <p><strong>Адрес доставки:</strong> {{ req.customer_address }}</p>
                                {% if req.pickup_address %}
                                <p><strong>Адрес забора:</strong> {{ req.pickup_address }}</p>
                                {% endif %}
                            </div>
                            <div class="col-md-6">
                                <h6>Груз</h6>
                                <p><strong>Описание:</strong> {{ req.cargo_description }}</p>
                                {% if req.cargo_weight %}
                                <p><strong>Вес:</strong> {{ req.cargo_weight }} кг</p>
                                {% endif %}
                                {% if req.cargo_volume %}
                                <p><strong>Объем:</strong> {{ req.cargo_volume }} м³</p>
                                {% endif %}
                            </div>
                        </div>
                        {% if req.special_instructions %}
                        <h6>Особые указания</h6>
                        <p>{{ req.special_instructions }}</p>
                        {% endif %}
                        
                        <form method="POST" action="{{ url_for('update_status', request_id=req.id) }}" class="mt-3">
                            <div class="row">
                                <div class="col-md-8">
                                    <select name="status" class="form-select">
                                        <option value="pending" {{ 'selected' if req.status == 'pending' }}>Ожидает</option>
                                        <option value="processing" {{ 'selected' if req.status == 'processing' }}>В обработке</option>
                                        <option value="shipped" {{ 'selected' if req.status == 'shipped' }}>Отправлен</option>
                                        <option value="delivered" {{ 'selected' if req.status == 'delivered' }}>Доставлен</option>
                                    </select>
                                </div>
                                <div class="col-md-4">
                                    <button type="submit" class="btn btn-primary w-100">Обновить</button>
                                </div>
                            </div>
                        </form>
                    </div>
                </div>
            </div>
        </div>
        {% endfor %}
    {% else %}
        <div class="text-center py-5">
            <i class="fas fa-inbox fa-4x text-muted mb-3"></i>
            <h4>Заявок пока нет</h4>
            <p class="text-muted">Новые заявки будут отображаться здесь</p>
        </div>
    {% endif %}
</div>
{% endblock %}
EOF

cat > templates/track_order.html << 'EOF'
{% extends "base.html" %}

{% block content %}
<div class="container py-4">
    <div class="row justify-content-center">
        <div class="col-md-8">
            <div class="card">
                <div class="card-header text-center">
                    <h4><i class="fas fa-search me-2"></i>Отследить заказ</h4>
                </div>
                <div class="card-body">
                    <form method="POST">
                        {{ form.hidden_tag() }}
                        <div class="row">
                            <div class="col-md-8">
                                {{ form.customer_phone.label(class="form-label") }}
                                {{ form.customer_phone(class="form-control phone-mask", placeholder="+7(7__)___-__-__") }}
                            </div>
                            <div class="col-md-4 d-flex align-items-end">
                                {{ form.submit(class="btn btn-primary w-100") }}
                            </div>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </div>

    {% if orders %}
    <div class="row mt-4">
        <div class="col-12">
            <div class="card">
                <div class="card-header">
                    <h5><i class="fas fa-list me-2"></i>Найдено заявок: {{ orders|length }}</h5>
                </div>
                <div class="card-body p-0">
                    <div class="table-responsive">
                        <table class="table table-striped mb-0">
                            <thead>
                                <tr>
                                    <th>№ заявки</th>
                                    <th>Дата</th>
                                    <th>Тип доставки</th>
                                    <th>Статус</th>
                                </tr>
                            </thead>
                            <tbody>
                                {% for order in orders %}
                                <tr>
                                    <td><strong>#{{ order.id }}</strong></td>
                                    <td>{{ order.created_at.strftime('%d.%m.%Y %H:%M') }}</td>
                                    <td>
                                        {% if order.delivery_type == 'astana' %}
                                            <span class="badge bg-primary">Астана</span>
                                        {% else %}
                                            <span class="badge bg-secondary">Регионы</span>
                                        {% endif %}
                                    </td>
                                    <td>
                                        {% set status_colors = {
                                            'pending': 'warning',
                                            'processing': 'info',
                                            'shipped': 'primary',
                                            'delivered': 'success'
                                        } %}
                                        <span class="badge bg-{{ status_colors[order.status] }}">
                                            {{ status_names[order.status] }}
                                        </span>
                                    </td>
                                </tr>
                                {% endfor %}
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
        </div>
    </div>
    {% endif %}
</div>
{% endblock %}
EOF

print_status "✅ Полный проект готов к развертыванию!"
print_status "Запустите: sudo bash full_deploy.sh"