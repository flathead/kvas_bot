import os
import re
from enum import Enum, auto
from dotenv import load_dotenv
from app.logger import get_logger

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

        # Параметры подключения к роутеру
        self.ROUTER_IP = self._get_env('ROUTER_IP')
        self.ROUTER_USER = self._get_env('ROUTER_USER')
        self.ROUTER_PASS = os.getenv('ROUTER_PASS')
        self.ROUTER_SSH_KEY = os.getenv('ROUTER_SSH_KEY')

        self.ROUTER_PORT = int(os.getenv('ROUTER_PORT', 22))
        self.CONNECTION_MODE = (
            ConnectionMode.KEY if self.ROUTER_SSH_KEY 
            else ConnectionMode.PASSWORD
        )

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
        required_vars = ['BOT_TOKEN', 'ALLOWED_USERS', 'ROUTER_IP', 'ROUTER_USER']

        for var in required_vars:
            if not os.getenv(var):
                raise ConfigError(f"Missing critical configuration: {var}")

        # Проверка IP
        ip = os.getenv('ROUTER_IP', '')
        ip_parts = ip.split('.')
        if len(ip_parts) != 4 or not all(part.isdigit() and 0 <= int(part) <= 255 for part in ip_parts):
            raise ConfigError("Invalid router IP address")

        # Проверка токена
        if not re.match(r'^\d{10,12}:[A-Za-z0-9_-]{34,36}$', os.getenv('BOT_TOKEN', '')):
            raise ConfigError("Invalid Telegram bot token")