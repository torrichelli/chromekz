from app import db
from datetime import datetime
from werkzeug.security import generate_password_hash, check_password_hash

class Employee(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(64), unique=True, nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    phone = db.Column(db.String(20), nullable=False)
    password_hash = db.Column(db.String(256), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    # Relationship with requests
    requests = db.relationship('Request', backref='employee', lazy=True)
    
    def set_password(self, password):
        self.password_hash = generate_password_hash(password)
    
    def check_password(self, password):
        return check_password_hash(self.password_hash, password)
    
    def __repr__(self):
        return f'<Employee {self.username}>'

class Request(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    
    # Customer information
    customer_name = db.Column(db.String(100), nullable=False)
    customer_phone = db.Column(db.String(20), nullable=False)
    customer_address = db.Column(db.Text, nullable=False)
    
    # Shipment details
    delivery_type = db.Column(db.String(20), nullable=False)  # 'astana' or 'regions'
    cargo_description = db.Column(db.Text, nullable=False)
    cargo_weight = db.Column(db.Float)
    cargo_volume = db.Column(db.Float)
    
    # Additional information
    special_instructions = db.Column(db.Text)
    preferred_delivery_date = db.Column(db.Date)
    
    # System fields
    status = db.Column(db.String(20), default='pending')  # pending, processing, shipped, delivered
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    employee_id = db.Column(db.Integer, db.ForeignKey('employee.id'), nullable=True)
    
    def __repr__(self):
        return f'<Request {self.id} - {self.customer_name}>'
