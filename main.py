import asyncio
import os
import signal
from dotenv import load_dotenv

from app.bot import VPNBot
from app.config import Config
from app.logger import get_logger
from app.router_client import RouterLocalClient

async def main():
    logger = get_logger(__name__)
    logger.setLevel('INFO')

    config = Config()
    router_client = RouterLocalClient(config)
    bot = VPNBot(config, router_client)
    
    # Создаем задачу для запуска бота
    bot_task = asyncio.create_task(bot.start())
    
    # Настройка обработки сигналов
    loop = asyncio.get_running_loop()

    load_dotenv()
    env = os.getenv('ENV')
    if env and env.upper() == 'PROD':
        for sig in (signal.SIGINT, signal.SIGTERM):
            loop.add_signal_handler(sig, lambda: bot_task.cancel())
    
    try:
        await bot_task
    except asyncio.CancelledError:
        print("Бот остановлен")
    except Exception as e:
        print(f"Критическая ошибка: {e}")
    finally:
        # Дополнительная очистка, если необходимо
        pass

if __name__ == "__main__":
    asyncio.run(main())