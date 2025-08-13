# Хром КЗ Logistics System

## Overview

This is a Flask-based logistics management system for "Хром КЗ" company. The system provides a dual-interface approach where customers can submit shipping requests without authentication, while employees can register, log in, and manage requests through a personalized dashboard. The application supports two types of deliveries: local deliveries within Astana and regional deliveries, with comprehensive order tracking capabilities. The system now includes Telegram bot integration for instant notifications when new shipping requests are submitted.

## User Preferences

- **Communication style**: Simple, everyday language
- **Design preference**: Clean white minimalist design (not bright colorful design)
- **UI Style**: Prefers simple, professional layouts with subtle colors and clean typography

## Features

### Core Features
- **Public Request Submission**: Customers can submit shipping requests without authentication
- **Employee Authentication**: Secure registration and login system for company employees
- **Request Management**: Employee dashboard with request tracking and status updates
- **Order Tracking**: Public order tracking by phone number
- **Dual Delivery Types**: Support for Astana local and regional deliveries
- **Russian Language Interface**: Full Cyrillic text support throughout the application

### Telegram Integration (New - August 2025)
- **Instant Notifications**: Automatic Telegram notifications when new requests are submitted
- **Admin Testing Panel**: Telegram configuration and testing interface for employees
- **Structured Messages**: Formatted notifications with complete request details
- **Connection Testing**: Built-in tools to verify Telegram bot connectivity

### Apple Design System Implementation (Updated - August 2025)
- **Official Apple Colors**: Exact color palette from apple.com (#0071e3, #1d1d1f)
- **SF Pro Display Typography**: Official Apple font system with proper sizing
- **Glass Effects**: Apple-style backdrop filters with saturate(180%) blur(20px)
- **Apple Spacing System**: 17px, 21px, 48px spacing following Apple guidelines
- **Hover States Fixed**: Resolved white-on-white text issues with proper contrast

## System Architecture

### Frontend Architecture
- **Template Engine**: Jinja2 templates with Bootstrap dark theme integration
- **UI Framework**: Bootstrap 5 with custom CSS for enhanced user experience
- **JavaScript**: Vanilla JavaScript for form interactions and dynamic content display
- **Multilingual Support**: Russian language interface with Cyrillic text support
- **Responsive Design**: Mobile-first approach with Bootstrap grid system

### Backend Architecture
- **Framework**: Flask with SQLAlchemy ORM for database operations
- **Authentication**: Session-based authentication with password hashing using Werkzeug
- **Form Handling**: Flask-WTF with WTForms for form validation and CSRF protection
- **Database**: SQLAlchemy with DeclarativeBase for model definitions
- **Logging**: Python logging module configured for debugging

### Data Storage
- **Primary Database**: SQLite for development (configurable to other databases via DATABASE_URL)
- **Database Models**:
  - Employee: Stores employee credentials and profile information
  - Request: Stores shipping requests with customer and cargo details
- **Connection Management**: SQLAlchemy with connection pooling and health checks

### Authentication & Authorization
- **Employee Registration**: Username/email uniqueness validation with secure password hashing
- **Session Management**: Flask sessions with configurable secret key
- **Access Control**: Route-based authentication checking for employee-only features
- **Password Security**: Werkzeug password hashing with salt

### Application Structure
- **Modular Design**: Separated concerns with dedicated files for models, forms, routes, and configuration
- **Environment Configuration**: Environment variables for database URL and session secrets
- **Database Initialization**: Automatic table creation on application startup
- **Error Handling**: Comprehensive error handling with user-friendly flash messages

## Deployment Information (Updated - August 2025)

### VPS Deployment Guide
- **Target Domain**: logistics.xrom.org
- **Deployment Path**: /var/www/logistics.xrom.org (standard web directory structure)
- **Server Requirements**: Ubuntu 20.04+, 2GB RAM, 20GB storage  
- **Technology Stack**: Nginx + Gunicorn + PostgreSQL
- **SSL**: Let's Encrypt automatic renewal
- **Monitoring**: systemd services with log monitoring
- **Backup Strategy**: Daily PostgreSQL dumps with 7-day retention in /var/www/backups

### Production Configuration
- **Database**: PostgreSQL with dedicated user and secure connection
- **Web Server**: Nginx reverse proxy with static file serving
- **Application Server**: Gunicorn with 3 workers and Unix socket
- **Security**: UFW firewall, SSL/TLS encryption, environment variable secrets
- **Process Management**: systemd service for automatic startup and restart

### Maintenance Procedures
- **Updates**: Git-based deployment with automatic dependency installation
- **Backups**: Automated daily database backups via cron
- **Monitoring**: systemd journal logs and Nginx access/error logs
- **SSL Renewal**: Automatic certificate renewal via certbot cron job

## External Dependencies

### Python Packages
- **Flask**: Web framework for application routing and HTTP handling
- **Flask-SQLAlchemy**: Database ORM integration with Flask
- **Flask-WTF**: Form handling and CSRF protection
- **WTForms**: Form validation and rendering
- **Werkzeug**: Password hashing and security utilities
- **Requests**: HTTP library for Telegram API communication

### Frontend Libraries
- **Bootstrap 5**: CSS framework with dark theme support
- **Font Awesome 6**: Icon library for UI elements
- **Replit Bootstrap Theme**: Custom dark theme optimized for Replit environment

### Database Support
- **SQLite**: Default database for development
- **PostgreSQL**: Supported via SQLAlchemy (configurable through DATABASE_URL)
- **Connection Pooling**: Built-in SQLAlchemy connection management

### Development Tools
- **Python Logging**: Debugging and error tracking
- **Flask Debug Mode**: Development server with auto-reload
- **Environment Variables**: Configuration management for deployment