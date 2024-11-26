import os
import re
from enum import Enum, auto
from dotenv import load_dotenv

# Расширенное управление конфигурацией
class ConfigError(Exception):
    """Пользовательское исключение для ошибок конфигурации."""
    pass

class ConnectionMode(Enum):
    PASSWORD = auto()
    KEY = auto()

class Config:
    def __init__(self):
        # Load environment variables from .env file
        load_dotenv()

        # Проверка критической конфигурации
        self.validate_config()

        self.BOT_TOKEN = self._get_env('BOT_TOKEN')
        self.ALLOWED_USERS = set(map(int, self._get_env('ALLOWED_USERS').split(',')))

        # Конфигурация безопасности и повторных попыток
        self.MAX_RETRIES = 3
        self.RETRY_DELAY = 2  # Базовая задержка в секундах
        self.COMMAND_TIMEOUT = 120  # Секунды 

    def _get_env(self, key: str) -> str:
        """Безопасное получение переменных окружения с проверкой."""
        value = os.getenv(key)
        if not value:
            raise ConfigError(f"Missing critical ENV configuration: {key}")
        return value

    def validate_config(self):
        """Всесторонняя проверка конфигурации."""
        required_vars = ['BOT_TOKEN', 'ALLOWED_USERS']

        for var in required_vars:
            if not os.getenv(var):
                raise ConfigError(f"Missing critical configuration: {var}")

        # Проверка токена
        if not re.match(r'^\d{10,12}:[A-Za-z0-9_-]{34,36}$', os.getenv('BOT_TOKEN', '')):
            raise ConfigError("Invalid Telegram bot token")