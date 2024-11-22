import logging
import os
from dotenv import load_dotenv

# Загрузка переменных окружения из .env файла
load_dotenv()

# Установка уровня логирования из .env (по умолчанию INFO)
log_level = os.getenv('LOG', 'INFO').upper()
level = getattr(logging, log_level, logging.INFO)

# Базовая настройка логгера
logging.basicConfig(
    level=level,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('./router_bot.log'),
        logging.StreamHandler()
    ]
)

# Функция для получения логгера
def get_logger(name=__name__):
    """Возвращает настроенный логгер."""
    return logging.getLogger(name)
