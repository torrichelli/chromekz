#!/bin/bash

echo "🔧 Исправление HTTP 404 - создание всех шаблонов"
echo "=============================================="

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

print_info "Создание недостающих HTML шаблонов..."

# request.html
cat > templates/request.html << 'EOF'
{% extends "base.html" %}

{% block title %}Новая заявка - Хром КЗ{% endblock %}

{% block content %}
<div class="row justify-content-center">
    <div class="col-md-8">
        <div class="card">
            <div class="card-header">
                <h4><i class="fas fa-plus-circle"></i> Новая заявка на доставку</h4>
            </div>
            <div class="card-body">
                <form method="POST">
                    {{ form.hidden_tag() }}
                    
                    <div class="row">
                        <div class="col-md-6">
                            <h5 class="text-primary">Отправитель</h5>
                            <div class="mb-3">
                                {{ form.sender_name.label(class="form-label") }}
                                {{ form.sender_name(class="form-control") }}
                            </div>
                            <div class="mb-3">
                                {{ form.sender_phone.label(class="form-label") }}
                                {{ form.sender_phone(class="form-control") }}
                            </div>
                            <div class="mb-3">
                                {{ form.sender_address.label(class="form-label") }}
                                {{ form.sender_address(class="form-control", rows="3") }}
                            </div>
                        </div>
                        
                        <div class="col-md-6">
                            <h5 class="text-success">Получатель</h5>
                            <div class="mb-3">
                                {{ form.recipient_name.label(class="form-label") }}
                                {{ form.recipient_name(class="form-control") }}
                            </div>
                            <div class="mb-3">
                                {{ form.recipient_phone.label(class="form-label") }}
                                {{ form.recipient_phone(class="form-control") }}
                            </div>
                            <div class="mb-3">
                                {{ form.recipient_address.label(class="form-label") }}
                                {{ form.recipient_address(class="form-control", rows="3") }}
                            </div>
                        </div>
                    </div>
                    
                    <hr>
                    
                    <div class="row">
                        <div class="col-md-12">
                            <h5 class="text-warning">Информация о грузе</h5>
                            <div class="mb-3">
                                {{ form.cargo_description.label(class="form-label") }}
                                {{ form.cargo_description(class="form-control", rows="3") }}
                            </div>
                        </div>
                    </div>
                    
                    <div class="row">
                        <div class="col-md-4">
                            <div class="mb-3">
                                {{ form.cargo_weight.label(class="form-label") }}
                                {{ form.cargo_weight(class="form-control") }}
                            </div>
                        </div>
                        <div class="col-md-4">
                            <div class="mb-3">
                                {{ form.cargo_value.label(class="form-label") }}
                                {{ form.cargo_value(class="form-control") }}
                            </div>
                        </div>
                        <div class="col-md-4">
                            <div class="mb-3">
                                {{ form.delivery_type.label(class="form-label") }}
                                {{ form.delivery_type(class="form-control") }}
                            </div>
                        </div>
                    </div>
                    
                    <div class="d-grid">
                        {{ form.submit(class="btn btn-primary btn-lg") }}
                    </div>
                </form>
            </div>
        </div>
    </div>
</div>
{% endblock %}
EOF

# track.html
cat > templates/track.html << 'EOF'
{% extends "base.html" %}

{% block title %}Отследить груз - Хром КЗ{% endblock %}

{% block content %}
<div class="row justify-content-center">
    <div class="col-md-6">
        <div class="card">
            <div class="card-header">
                <h4><i class="fas fa-search"></i> Отследить заявку</h4>
            </div>
            <div class="card-body">
                <form method="POST">
                    {{ form.hidden_tag() }}
                    <div class="mb-3">
                        {{ form.phone.label(class="form-label") }}
                        {{ form.phone(class="form-control", placeholder="+7 XXX XXX XXXX") }}
                        <div class="form-text">Введите номер телефона отправителя или получателя</div>
                    </div>
                    <div class="d-grid">
                        {{ form.submit(class="btn btn-primary") }}
                    </div>
                </form>
            </div>
        </div>
    </div>
</div>

{% if requests %}
<div class="row mt-4">
    <div class="col-md-12">
        <h4>Найденные заявки:</h4>
        {% for req in requests %}
        <div class="card mb-3">
            <div class="card-header d-flex justify-content-between">
                <span><strong>Заявка #{{ req.id }}</strong></span>
                <span class="badge bg-{% if req.status == 'pending' %}warning{% elif req.status == 'confirmed' %}info{% elif req.status == 'in_transit' %}primary{% elif req.status == 'delivered' %}success{% endif %}">
                    {% if req.status == 'pending' %}Ожидает
                    {% elif req.status == 'confirmed' %}Подтверждено
                    {% elif req.status == 'in_transit' %}В пути
                    {% elif req.status == 'delivered' %}Доставлено
                    {% endif %}
                </span>
            </div>
            <div class="card-body">
                <div class="row">
                    <div class="col-md-6">
                        <h6>От:</h6>
                        <p>{{ req.sender_name }}<br>{{ req.sender_phone }}</p>
                    </div>
                    <div class="col-md-6">
                        <h6>Кому:</h6>
                        <p>{{ req.recipient_name }}<br>{{ req.recipient_phone }}</p>
                    </div>
                </div>
                <p><strong>Груз:</strong> {{ req.cargo_description }}</p>
                <p><small class="text-muted">Создано: {{ req.created_at.strftime('%d.%m.%Y %H:%M') }}</small></p>
            </div>
        </div>
        {% endfor %}
    </div>
</div>
{% endif %}
{% endblock %}
EOF

# register.html
cat > templates/register.html << 'EOF'
{% extends "base.html" %}

{% block title %}Регистрация сотрудника - Хром КЗ{% endblock %}

{% block content %}
<div class="row justify-content-center">
    <div class="col-md-6">
        <div class="card">
            <div class="card-header">
                <h4><i class="fas fa-user-plus"></i> Регистрация сотрудника</h4>
            </div>
            <div class="card-body">
                <form method="POST">
                    {{ form.hidden_tag() }}
                    <div class="mb-3">
                        {{ form.username.label(class="form-label") }}
                        {{ form.username(class="form-control") }}
                        {% if form.username.errors %}
                            <div class="text-danger">
                                {% for error in form.username.errors %}
                                    <small>{{ error }}</small>
                                {% endfor %}
                            </div>
                        {% endif %}
                    </div>
                    <div class="mb-3">
                        {{ form.email.label(class="form-label") }}
                        {{ form.email(class="form-control") }}
                        {% if form.email.errors %}
                            <div class="text-danger">
                                {% for error in form.email.errors %}
                                    <small>{{ error }}</small>
                                {% endfor %}
                            </div>
                        {% endif %}
                    </div>
                    <div class="mb-3">
                        {{ form.password.label(class="form-label") }}
                        {{ form.password(class="form-control") }}
                        {% if form.password.errors %}
                            <div class="text-danger">
                                {% for error in form.password.errors %}
                                    <small>{{ error }}</small>
                                {% endfor %}
                            </div>
                        {% endif %}
                        <div class="form-text">Минимум 6 символов</div>
                    </div>
                    <div class="d-grid">
                        {{ form.submit(class="btn btn-success") }}
                    </div>
                </form>
                <hr>
                <p class="text-center">
                    Уже есть аккаунт? <a href="{{ url_for('login') }}">Войти</a>
                </p>
            </div>
        </div>
    </div>
</div>
{% endblock %}
EOF

# login.html
cat > templates/login.html << 'EOF'
{% extends "base.html" %}

{% block title %}Вход - Хром КЗ{% endblock %}

{% block content %}
<div class="row justify-content-center">
    <div class="col-md-6">
        <div class="card">
            <div class="card-header">
                <h4><i class="fas fa-sign-in-alt"></i> Вход в систему</h4>
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
                <hr>
                <p class="text-center">
                    Нет аккаунта? <a href="{{ url_for('register') }}">Зарегистрироваться</a>
                </p>
            </div>
        </div>
    </div>
</div>
{% endblock %}
EOF

# dashboard.html
cat > templates/dashboard.html << 'EOF'
{% extends "base.html" %}

{% block title %}Панель управления - Хром КЗ{% endblock %}

{% block content %}
<div class="d-flex justify-content-between align-items-center mb-4">
    <h2><i class="fas fa-tachometer-alt"></i> Панель управления</h2>
    <span class="badge bg-primary">Сотрудник: {{ session.employee_username }}</span>
</div>

<div class="row mb-4">
    <div class="col-md-3">
        <div class="card text-white bg-warning">
            <div class="card-body">
                <h5><i class="fas fa-clock"></i> Ожидают</h5>
                <h3>{{ requests|selectattr("status", "equalto", "pending")|list|length }}</h3>
            </div>
        </div>
    </div>
    <div class="col-md-3">
        <div class="card text-white bg-info">
            <div class="card-body">
                <h5><i class="fas fa-check"></i> Подтверждены</h5>
                <h3>{{ requests|selectattr("status", "equalto", "confirmed")|list|length }}</h3>
            </div>
        </div>
    </div>
    <div class="col-md-3">
        <div class="card text-white bg-primary">
            <div class="card-body">
                <h5><i class="fas fa-truck"></i> В пути</h5>
                <h3>{{ requests|selectattr("status", "equalto", "in_transit")|list|length }}</h3>
            </div>
        </div>
    </div>
    <div class="col-md-3">
        <div class="card text-white bg-success">
            <div class="card-body">
                <h5><i class="fas fa-check-circle"></i> Доставлены</h5>
                <h3>{{ requests|selectattr("status", "equalto", "delivered")|list|length }}</h3>
            </div>
        </div>
    </div>
</div>

<div class="card">
    <div class="card-header">
        <h5><i class="fas fa-list"></i> Все заявки</h5>
    </div>
    <div class="card-body">
        <div class="table-responsive">
            <table class="table table-striped">
                <thead>
                    <tr>
                        <th>ID</th>
                        <th>Отправитель</th>
                        <th>Получатель</th>
                        <th>Груз</th>
                        <th>Тип</th>
                        <th>Статус</th>
                        <th>Дата</th>
                        <th>Действия</th>
                    </tr>
                </thead>
                <tbody>
                    {% for req in requests %}
                    <tr>
                        <td>{{ req.id }}</td>
                        <td>{{ req.sender_name }}<br><small>{{ req.sender_phone }}</small></td>
                        <td>{{ req.recipient_name }}<br><small>{{ req.recipient_phone }}</small></td>
                        <td>{{ req.cargo_description[:50] }}...</td>
                        <td>
                            {% if req.delivery_type == 'astana' %}
                                <span class="badge bg-info">Астана</span>
                            {% else %}
                                <span class="badge bg-success">Межгород</span>
                            {% endif %}
                        </td>
                        <td>
                            <span class="badge bg-{% if req.status == 'pending' %}warning{% elif req.status == 'confirmed' %}info{% elif req.status == 'in_transit' %}primary{% elif req.status == 'delivered' %}success{% endif %}">
                                {% if req.status == 'pending' %}Ожидает
                                {% elif req.status == 'confirmed' %}Подтверждено  
                                {% elif req.status == 'in_transit' %}В пути
                                {% elif req.status == 'delivered' %}Доставлено
                                {% endif %}
                            </span>
                        </td>
                        <td>{{ req.created_at.strftime('%d.%m.%Y %H:%M') }}</td>
                        <td>
                            <div class="dropdown">
                                <button class="btn btn-sm btn-outline-primary dropdown-toggle" type="button" data-bs-toggle="dropdown">
                                    Изменить статус
                                </button>
                                <ul class="dropdown-menu">
                                    <li><a class="dropdown-item" href="{{ url_for('update_status', request_id=req.id, new_status='confirmed') }}">Подтвердить</a></li>
                                    <li><a class="dropdown-item" href="{{ url_for('update_status', request_id=req.id, new_status='in_transit') }}">В пути</a></li>
                                    <li><a class="dropdown-item" href="{{ url_for('update_status', request_id=req.id, new_status='delivered') }}">Доставлено</a></li>
                                </ul>
                            </div>
                        </td>
                    </tr>
                    {% endfor %}
                </tbody>
            </table>
        </div>
    </div>
</div>
{% endblock %}
EOF

# Права доступа
chown -R hromkz:www-data /var/www/logistics.xrom.org/templates
chmod -R 755 /var/www/logistics.xrom.org/templates

print_status "Все HTML шаблоны созданы"

print_info "Перезапуск сервисов..."
systemctl restart hromkz
systemctl reload nginx

print_info "Ожидание перезапуска..."
sleep 5

print_info "Повторное HTTP тестирование..."
HTTP_CODE=$(curl -I -s -o /dev/null -w "%{http_code}" --connect-timeout 10 http://logistics.xrom.org 2>/dev/null || echo "000")

case "$HTTP_CODE" in
    "200")
        print_status "🎉 ИСПРАВЛЕНО! Сайт работает!"
        echo ""
        echo "URL: http://logistics.xrom.org"
        echo "Заявка: http://logistics.xrom.org/request"
        echo "Отслеживание: http://logistics.xrom.org/track"  
        echo "Регистрация: http://logistics.xrom.org/register"
        echo ""
        echo "Создайте первого сотрудника через /register"
        ;;
    "404")
        print_error "Все еще HTTP 404"
        print_info "Проверьте логи: journalctl -u hromkz -n 10"
        ;;
    "502")
        print_error "HTTP 502 - приложение не отвечает"
        ;;
    *)
        print_error "HTTP код: $HTTP_CODE"
        ;;
esac

print_info "Исправление завершено!"