"""
Configuration file for Telegram notifications
Add your bot token and chat ID here
"""

import os

# Telegram Bot Configuration
TELEGRAM_BOT_TOKEN = os.environ.get('TELEGRAM_BOT_TOKEN', 'YOUR_BOT_TOKEN_HERE')
TELEGRAM_CHAT_ID = os.environ.get('TELEGRAM_CHAT_ID', 'YOUR_CHAT_ID_HERE')

# Validate configuration
def validate_telegram_config():
    """Check if Telegram configuration is properly set"""
    if TELEGRAM_BOT_TOKEN == 'YOUR_BOT_TOKEN_HERE' or not TELEGRAM_BOT_TOKEN:
        return False, "TELEGRAM_BOT_TOKEN not configured"
    
    if TELEGRAM_CHAT_ID == 'YOUR_CHAT_ID_HERE' or not TELEGRAM_CHAT_ID:
        return False, "TELEGRAM_CHAT_ID not configured"
    
    return True, "Configuration valid"