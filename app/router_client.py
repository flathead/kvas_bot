import asyncio
import subprocess
from typing import Optional
from app.config import Config
from app.logger import get_logger

class RouterResponse:
    """Класс для обработки и валидации ответов роутера"""
    ADD_SUCCESS = "ДОБАВЛЕН"
    DELETE_SUCCESS = "УДАЛЕН"
    DELETE_NOT_FOUND = "Такая запись отсутствует в списке разблокировки!"

class RouterLocalClient:
    def __init__(self, config: Config):
        self.config = config
        self.logger = get_logger(__name__)

    async def execute_command(self, command: str, timeout: int = 120) -> str:
        """
        Асинхронное выполнение команды с таймаутом
        
        Args:
            command (str): Команда для выполнения
            timeout (int): Максимальное время выполнения команды в секундах
        
        Returns:
            str: Вывод команды
        """
        try:
            # Создаем команду с корректным путем или полным путем к исполняемому файлу
            proc = await asyncio.create_subprocess_shell(
                command,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )

            try:
                stdout, stderr = await asyncio.wait_for(
                    proc.communicate(), 
                    timeout=timeout
                )
            except asyncio.TimeoutError:
                proc.kill()
                stdout, stderr = await proc.communicate()
                raise RuntimeError(f"Время выполнения команды превышено: {command}")

            if stderr:
                error_msg = stderr.decode().strip()
                self.logger.error(f"Ошибка выполнения команды {command}: {error_msg}")
                raise RuntimeError(error_msg)

            return stdout.decode().strip()

        except Exception as e:
            self.logger.error(f"Ошибка при выполнении команды {command}: {e}")
            raise