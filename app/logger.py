import logging
import os
from dotenv import load_dotenv

# Загрузка переменных окружения из .env файла
load_dotenv()

# Установка уровня логирования из .env (по умолчанию INFO)
log_level = os.getenv('LOG', 'INFO').upper()
level = getattr(logging, log_level, logging.INFO)

# Базовая настройка логгера
env = os.getenv('ENV')

if env and env.upper() == 'PROD':
    file_handler = logging.FileHandler('/opt/apps/vpnbot/logs/router_bot.log')
elif env and env.upper() == 'DEV':
    file_handler = logging.FileHandler('./router_bot.log')
else:
    file_handler = logging.StreamHandler()

logging.basicConfig(
    level=level,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        file_handler,
        logging.StreamHandler()
    ]
)

# Функция для получения логгера
def get_logger(name=__name__):
    """Возвращает настроенный логгер."""
    return logging.getLogger(name)
