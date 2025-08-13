from flask_wtf import FlaskForm
from wtforms import StringField, TextAreaField, SelectField, FloatField, DateField, PasswordField, SubmitField
from wtforms.validators import DataRequired, Email, Length, Optional, ValidationError
from models import Employee

class RegistrationForm(FlaskForm):
    username = StringField('Имя пользователя', validators=[DataRequired(), Length(min=4, max=20)])
    email = StringField('Email', validators=[DataRequired(), Email()])
    phone = StringField('Номер телефона', validators=[DataRequired(), Length(min=10, max=20)])
    password = PasswordField('Пароль', validators=[DataRequired(), Length(min=6)])
    submit = SubmitField('Зарегистрироваться')
    
    def validate_username(self, username):
        employee = Employee.query.filter_by(username=username.data).first()
        if employee:
            raise ValidationError('Это имя пользователя уже занято. Выберите другое.')
    
    def validate_email(self, email):
        employee = Employee.query.filter_by(email=email.data).first()
        if employee:
            raise ValidationError('Этот email уже зарегистрирован. Выберите другой.')

class LoginForm(FlaskForm):
    username = StringField('Имя пользователя', validators=[DataRequired()])
    password = PasswordField('Пароль', validators=[DataRequired()])
    submit = SubmitField('Войти')

class RequestForm(FlaskForm):
    customer_name = StringField('Имя клиента', validators=[DataRequired(), Length(max=100)])
    customer_phone = StringField('Номер телефона клиента', validators=[DataRequired(), Length(max=20)])
    customer_address = TextAreaField('Адрес клиента', validators=[DataRequired()])
    
    delivery_type = SelectField('Тип доставки', 
                               choices=[('astana', 'Отгрузки по Астане'), ('regions', 'Отгрузки по Регионам')],
                               validators=[DataRequired()])
    
    cargo_description = TextAreaField('Описание груза', validators=[DataRequired()])
    cargo_weight = FloatField('Вес груза (кг)', validators=[Optional()])
    cargo_volume = FloatField('Объем груза (м³)', validators=[Optional()])
    
    special_instructions = TextAreaField('Особые указания', validators=[Optional()])
    preferred_delivery_date = DateField('Предпочтительная дата доставки', validators=[Optional()])
    
    submit = SubmitField('Подать заявку')

class TrackingForm(FlaskForm):
    customer_phone = StringField('Номер телефона клиента', validators=[DataRequired(), Length(max=20)])
    submit = SubmitField('Отследить заказы')
