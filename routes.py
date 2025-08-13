from flask import render_template, request, redirect, url_for, flash, session, jsonify
from app import app, db
from models import Employee, Request
from forms import RegistrationForm, LoginForm, RequestForm, TrackingForm
from telegram_service import send_telegram_notification, test_telegram_connection
from datetime import datetime

@app.route('/')
def index():
    """Main page with request forms"""
    astana_form = RequestForm()
    regions_form = RequestForm()
    tracking_form = TrackingForm()
    
    # Set delivery type for forms
    astana_form.delivery_type.data = 'astana'
    regions_form.delivery_type.data = 'regions'
    
    return render_template('index.html', 
                         astana_form=astana_form, 
                         regions_form=regions_form,
                         tracking_form=tracking_form)

@app.route('/register', methods=['GET', 'POST'])
def register():
    """Employee registration"""
    form = RegistrationForm()
    if form.validate_on_submit():
        employee = Employee()
        employee.username = form.username.data
        employee.email = form.email.data
        employee.phone = form.phone.data
        employee.set_password(form.password.data)
        
        try:
            db.session.add(employee)
            db.session.commit()
            flash('Регистрация прошла успешно! Теперь вы можете войти в систему.', 'success')
            return redirect(url_for('login'))
        except Exception as e:
            db.session.rollback()
            flash('Ошибка при регистрации. Попробуйте еще раз.', 'error')
            app.logger.error(f"Registration error: {e}")
    
    return render_template('register.html', form=form)

@app.route('/login', methods=['GET', 'POST'])
def login():
    """Employee login"""
    form = LoginForm()
    if form.validate_on_submit():
        employee = Employee.query.filter_by(username=form.username.data).first()
        
        if employee and employee.check_password(form.password.data):
            session['employee_id'] = employee.id
            session['employee_username'] = employee.username
            flash(f'Добро пожаловать, {employee.username}!', 'success')
            return redirect(url_for('dashboard'))
        else:
            flash('Неверное имя пользователя или пароль.', 'error')
    
    return render_template('login.html', form=form)

@app.route('/logout')
def logout():
    """Employee logout"""
    session.clear()
    flash('Вы вышли из системы.', 'info')
    return redirect(url_for('index'))

@app.route('/dashboard')
def dashboard():
    """Employee dashboard"""
    if 'employee_id' not in session:
        flash('Пожалуйста, войдите в систему для доступа к панели управления.', 'warning')
        return redirect(url_for('login'))
    
    employee = Employee.query.get(session['employee_id'])
    if not employee:
        session.clear()
        flash('Сессия истекла. Войдите в систему заново.', 'warning')
        return redirect(url_for('login'))
    
    # Get employee's requests
    employee_requests = Request.query.filter_by(employee_id=employee.id).order_by(Request.created_at.desc()).all()
    
    return render_template('dashboard.html', employee=employee, requests=employee_requests)

@app.route('/submit_request', methods=['POST'])
def submit_request():
    """Submit a new shipping request"""
    form = RequestForm()
    if form.validate_on_submit():
        try:
            # Create new request
            new_request = Request()
            new_request.customer_name = form.customer_name.data
            new_request.customer_phone = form.customer_phone.data
            new_request.customer_address = form.customer_address.data
            new_request.delivery_type = form.delivery_type.data
            new_request.cargo_description = form.cargo_description.data
            new_request.cargo_weight = form.cargo_weight.data
            new_request.cargo_volume = form.cargo_volume.data
            new_request.special_instructions = form.special_instructions.data
            new_request.preferred_delivery_date = form.preferred_delivery_date.data
            
            # If employee is logged in, associate request with them
            if 'employee_id' in session:
                new_request.employee_id = session['employee_id']
            
            db.session.add(new_request)
            db.session.commit()
            
            # Prepare data for Telegram notification
            request_data = {
                'customer_name': new_request.customer_name,
                'customer_phone': new_request.customer_phone,
                'customer_address': new_request.customer_address,
                'cargo_description': new_request.cargo_description,
                'cargo_weight': new_request.cargo_weight,
                'cargo_volume': new_request.cargo_volume,
                'preferred_delivery_date': new_request.preferred_delivery_date.strftime('%d.%m.%Y') if new_request.preferred_delivery_date else 'Не указано',
                'special_instructions': new_request.special_instructions,
                'created_at': new_request.created_at.strftime('%d.%m.%Y %H:%M'),
                'request_id': new_request.id
            }
            
            # Send Telegram notification
            success, message = send_telegram_notification(request_data, new_request.delivery_type)
            if not success:
                app.logger.warning(f"Telegram notification failed: {message}")
            
            flash(f'Заявка №{new_request.id} успешно подана!', 'success')
            
            # Redirect to dashboard if employee is logged in, otherwise to main page
            if 'employee_id' in session:
                return redirect(url_for('dashboard'))
            else:
                return redirect(url_for('index'))
                
        except Exception as e:
            db.session.rollback()
            flash('Ошибка при подаче заявки. Попробуйте еще раз.', 'error')
            app.logger.error(f"Request submission error: {e}")
    else:
        # Show form errors
        for field, errors in form.errors.items():
            for error in errors:
                field_obj = getattr(form, field, None)
                if field_obj and hasattr(field_obj, 'label'):
                    flash(f'Ошибка в поле "{field_obj.label.text}": {error}', 'error')
                else:
                    flash(f'Ошибка в поле "{field}": {error}', 'error')
    
    return redirect(url_for('index'))

@app.route('/track_order', methods=['GET', 'POST'])
def track_order():
    """Track orders by customer phone"""
    form = TrackingForm()
    orders = []
    
    if form.validate_on_submit():
        customer_phone = form.customer_phone.data
        orders = Request.query.filter_by(customer_phone=customer_phone).order_by(Request.created_at.desc()).all()
        
        if not orders:
            flash(f'Заказы для номера телефона {customer_phone} не найдены.', 'info')
    
    return render_template('track_order.html', form=form, orders=orders)

@app.route('/update_request_status/<int:request_id>/<new_status>')
def update_request_status(request_id, new_status):
    """Update request status (employee only)"""
    if 'employee_id' not in session:
        flash('Доступ запрещен.', 'error')
        return redirect(url_for('login'))
    
    request_obj = Request.query.get_or_404(request_id)
    
    # Check if employee owns this request
    if request_obj.employee_id != session['employee_id']:
        flash('Вы можете изменять статус только своих заявок.', 'error')
        return redirect(url_for('dashboard'))
    
    valid_statuses = ['pending', 'processing', 'shipped', 'delivered']
    if new_status in valid_statuses:
        request_obj.status = new_status
        db.session.commit()
        flash(f'Статус заявки №{request_id} обновлен.', 'success')
    else:
        flash('Недопустимый статус.', 'error')
    
    return redirect(url_for('dashboard'))

@app.route('/admin/telegram', methods=['GET', 'POST'])
def telegram_admin():
    """Telegram configuration and testing (employee only)"""
    if 'employee_id' not in session:
        flash('Доступ запрещен.', 'error')
        return redirect(url_for('login'))
    
    if request.method == 'POST':
        action = request.form.get('action')
        
        if action == 'test_connection':
            success, message = test_telegram_connection()
            if success:
                flash(f'Telegram: {message}', 'success')
            else:
                flash(f'Ошибка Telegram: {message}', 'error')
        
        elif action == 'test_notification':
            # Send test notification
            test_data = {
                'customer_name': 'Тестовый клиент',
                'customer_phone': '+7 (777) 123-45-67',
                'customer_address': 'г. Астана, ул. Тестовая, 123',
                'cargo_description': 'Тестовый груз для проверки уведомлений',
                'cargo_weight': '10.5',
                'cargo_volume': '0.5',
                'preferred_delivery_date': '15.08.2025',
                'special_instructions': 'Тестовое уведомление',
                'created_at': datetime.now().strftime('%d.%m.%Y %H:%M'),
                'request_id': 'TEST'
            }
            
            success, message = send_telegram_notification(test_data, 'astana')
            if success:
                flash('Тестовое уведомление отправлено в Telegram!', 'success')
            else:
                flash(f'Ошибка отправки: {message}', 'error')
    
    return render_template('telegram_admin.html')

@app.context_processor
def inject_status_names():
    """Inject status display names into templates"""
    return dict(
        status_names={
            'pending': 'Ожидает',
            'processing': 'В обработке', 
            'shipped': 'Отправлено',
            'delivered': 'Доставлено'
        }
    )
