import asyncio
import asyncssh
from typing import Optional, List, Dict, Any, Tuple
from asyncssh.misc import DisconnectError
from typing import Optional, Dict, Any
from app.config import Config, ConnectionMode
from app.messages import MESSAGES


class RouterResponse:
    """Класс для обработки и валидации ответов роутера"""
    ADD_SUCCESS = "ДОБАВЛЕН"
    DELETE_SUCCESS = "УДАЛЕН"
    DELETE_NOT_FOUND = "Такая запись отсутствует в списке разблокировки!"

    @staticmethod
    def validate_add_response(response: str) -> Tuple[bool, str]:
        """
        Проверяет ответ на добавление сайта
        Returns: (success, message)
        """
        if RouterResponse.ADD_SUCCESS in response:
            return True, MESSAGES['site_add_success'].format(response)
        return False, "Не удалось подтвердить добавление сайта"

    @staticmethod
    def validate_delete_response(response: str) -> Tuple[bool, str]:
        """
        Проверяет ответ на удаление сайта
        Returns: (success, message)
        """
        if RouterResponse.DELETE_SUCCESS in response:
            return True, MESSAGES['site_delete_success'].format(response)
        elif RouterResponse.DELETE_NOT_FOUND in response:
            return False, "Сайт отсутствует в списке разблокировки"
        return False, "Не удалось подтвердить удаление сайта"
    
class RouterSSHClient:
    def __init__(self, config: Config):
        self.config = config
        self._connection: Optional[asyncssh.SSHClientConnection] = None
        self._connected = False
        
    async def _get_connection_params(self) -> Dict[str, Any]:
        """Динамическое создание параметров SSH-подключения."""
        params = {
            'host': self.config.ROUTER_IP,
            'port': self.config.ROUTER_PORT,
            'username': self.config.ROUTER_USER,
            'known_hosts': None,
            'connect_timeout': self.config.COMMAND_TIMEOUT,
            'term_type': 'xterm-256color',
            'term_size': (120, 40)
        }
        
        if self.config.CONNECTION_MODE == ConnectionMode.KEY:
            params['client_keys'] = [self.config.ROUTER_SSH_KEY]
        else:
            params['password'] = self.config.ROUTER_PASS
        
        return params

    async def connect(self) -> bool:
        """Надежное SSH-подключение с экспоненциальной задержкой."""
        for attempt in range(self.config.MAX_RETRIES):
            try:
                params = await self._get_connection_params()
                self._connection = await asyncssh.connect(**params)
                self._connected = True
                return True
            except (asyncssh.Error, OSError) as e:
                delay = self.config.RETRY_DELAY * (2 ** attempt)
                if attempt == self.config.MAX_RETRIES - 1:
                    raise ConnectionError("Невозможно установить SSH-подключение")
                await asyncio.sleep(delay)
        return False

    async def _verify_connection(self):
        """Проверка подключения с использованием простой команды."""
        try:
            result = await self._connection.run('pwd', check=True)
        except Exception as e:
            raise ConnectionError("Проверка подключения к роутеру не удалась")

    async def execute_command(self, command: str, timeout: int = None, exec: bool = True) -> str:
        """Безопасное выполнение команды с закрытием соединения после выполнения."""
        if not self._connected:
            await self.connect()

        # Проверяем значение exec, если True - добавляем в команду exec
        modified_command = f"exec {command}" if exec else f"{command}"

        try:
            result = await asyncio.wait_for(
                self._connection.run(modified_command, check=True), 
                timeout=timeout or self.config.COMMAND_TIMEOUT
            )

            # Ответ пользователю сразу после успешного выполнения команды
            return result.stdout.strip()

        except asyncio.TimeoutError:
            raise RuntimeError("Выполнение команды превысило допустимое время")

        except (DisconnectError, asyncssh.Error) as e:
            self._connected = False
            try:
                await self.connect()
                result = await self.execute_command(command)
                return result
            except Exception as reconnect_error:
                raise

        finally:
            self.disconnect()  # Закрытие соединения в конце

    def disconnect(self):
        """Безопасное закрытие SSH-подключения."""
        if self._connection and not self._connection.is_closed():
            self._connection.close()
            self._connected = False