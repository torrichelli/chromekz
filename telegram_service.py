"""
Telegram notification service for sending shipping request alerts
"""

import requests
import logging
from config import TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, validate_telegram_config

# Configure logging
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

def format_request_message(request_data, delivery_type):
    """
    Format shipping request data into a detailed Telegram message
    
    Args:
        request_data: Dictionary containing request information
        delivery_type: 'astana' or 'regions'
    
    Returns:
        Formatted message string
    """
    delivery_types = {
        'astana': '🏢 Отгрузка по Астане',
        'regions': '🌍 Отгрузка по Регионам'
    }
    
    message = f"""
🚚 <b>Новая заявка на отгрузку!</b>

📋 <b>Тип:</b> {delivery_types.get(delivery_type, 'Неизвестно')}

👤 <b>Заказчик:</b> {request_data.get('customer_name', 'Не указано')}
📞 <b>Телефон:</b> {request_data.get('customer_phone', 'Не указано')}
🏠 <b>Адрес:</b> {request_data.get('customer_address', 'Не указано')}

📦 <b>Детали груза:</b>
{request_data.get('cargo_description', 'Не указано')}

⚖️ <b>Вес:</b> {request_data.get('cargo_weight', 'Не указано')} кг
📏 <b>Объем:</b> {request_data.get('cargo_volume', 'Не указано')} м³

📅 <b>Предпочитаемая дата доставки:</b> {request_data.get('preferred_delivery_date', 'Не указано')}

💬 <b>Особые требования:</b> {request_data.get('special_instructions', 'Нет') if request_data.get('special_instructions') else 'Нет'}

⏰ <b>Время подачи заявки:</b> {request_data.get('created_at', 'Только что')}
"""
    
    return message.strip()

def send_telegram_notification(request_data, delivery_type):
    """
    Send notification to Telegram chat about new shipping request
    
    Args:
        request_data: Dictionary containing request information
        delivery_type: 'astana' or 'regions'
    
    Returns:
        tuple: (success: bool, message: str)
    """
    try:
        # Validate configuration
        is_valid, config_message = validate_telegram_config()
        if not is_valid:
            logger.warning(f"Telegram configuration invalid: {config_message}")
            return False, f"Configuration error: {config_message}"
        
        # Format message
        message_text = format_request_message(request_data, delivery_type)
        
        # Prepare API request
        url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
        
        payload = {
            'chat_id': TELEGRAM_CHAT_ID,
            'text': message_text,
            'parse_mode': 'HTML',
            'disable_web_page_preview': True
        }
        
        # Send request
        response = requests.post(url, data=payload, timeout=10)
        
        if response.status_code == 200:
            response_data = response.json()
            if response_data.get('ok'):
                logger.info("Telegram notification sent successfully")
                return True, "Notification sent successfully"
            else:
                error_msg = response_data.get('description', 'Unknown error')
                logger.error(f"Telegram API error: {error_msg}")
                return False, f"Telegram API error: {error_msg}"
        else:
            logger.error(f"HTTP error {response.status_code}: {response.text}")
            return False, f"HTTP error {response.status_code}"
            
    except requests.exceptions.Timeout:
        logger.error("Telegram API request timeout")
        return False, "Request timeout"
    except requests.exceptions.RequestException as e:
        logger.error(f"Request error: {str(e)}")
        return False, f"Request error: {str(e)}"
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return False, f"Unexpected error: {str(e)}"

def test_telegram_connection():
    """
    Test Telegram bot connection
    
    Returns:
        tuple: (success: bool, message: str)
    """
    try:
        # Validate configuration
        is_valid, config_message = validate_telegram_config()
        if not is_valid:
            return False, f"Configuration error: {config_message}"
        
        # Test bot info
        url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/getMe"
        response = requests.get(url, timeout=10)
        
        if response.status_code == 200:
            data = response.json()
            if data.get('ok'):
                bot_info = data.get('result', {})
                bot_name = bot_info.get('first_name', 'Unknown')
                logger.info(f"Connected to Telegram bot: {bot_name}")
                return True, f"Connected to bot: {bot_name}"
            else:
                error_msg = data.get('description', 'Unknown error')
                return False, f"Bot error: {error_msg}"
        else:
            return False, f"HTTP error {response.status_code}"
            
    except Exception as e:
        logger.error(f"Connection test failed: {str(e)}")
        return False, f"Connection test failed: {str(e)}"