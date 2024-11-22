import asyncio
from app.bot import VPNBot
from app.config import Config
from app.router_client import RouterSSHClient
from app.logger import get_logger

async def main():
    try:
        # Получаем основной логгер
        logger = get_logger(__name__)
        # Устанавливаем уровень логирования для конкретных библиотек
        logger.setLevel('CRITICAL')
        get_logger("aiogram").setLevel("CRITICAL")
        get_logger("asyncio").setLevel("CRITICAL")

        # Инициализируем конфигурацию, SSH-клиент и бота
        config = Config()
        ssh_client = RouterSSHClient(config)
        bot = VPNBot(config, ssh_client)
        
        await bot.start()
    except Exception as e:
        logger.critical(f"Application launched with error: {e}")
        logger.debug("Full information about error: %s", e.__traceback__)
    finally:
        # Закрываем все соединения при выходе
        if 'bot' in locals():
            await bot.bot.session.close()

if __name__ == "__main__":
    asyncio.run(main())