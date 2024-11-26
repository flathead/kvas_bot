import asyncio
import html
import logging
import re
from aiogram import F, Bot, Dispatcher, Router
from aiogram.fsm.storage.memory import MemoryStorage
from aiogram.types import Message, ReplyKeyboardMarkup, KeyboardButton
from aiogram.filters import Command
from aiogram.fsm.context import FSMContext
from app.config import Config
from app.formatter import OutputFormatter
from app.states import AddSiteState, DeleteSiteState, RebootRouterState
from app.messages import MESSAGES
from app.router_client import RouterLocalClient
from app.logger import get_logger

class VPNBot:
    def __init__(self, config: Config, router_client: RouterLocalClient):
        self.config = config
        self.router_client = router_client
        self.bot = Bot(token=config.BOT_TOKEN)
        self.storage = MemoryStorage()
        self.dp = Dispatcher(storage=self.storage)
        self.router = Router()
        self.output_formatter = OutputFormatter()
        self.logger = get_logger(__name__)
        self._setup_handlers()

    def _setup_handlers(self):
        self.router.message.register(self.cmd_start, Command("start"))
        self.router.message.register(self.test_connection, Command("test"))
        self.router.message.register(
            self.list_sites, F.text == "📜 Список сайтов"
        )
        self.router.message.register(
            self.ask_add_site, F.text == "➕ Добавить сайт"
        )
        self.router.message.register(
            self.add_site, AddSiteState.waiting_for_site_name
        )
        self.router.message.register(
            self.ask_delete_site, F.text == "➖ Удалить сайт"
        )
        self.router.message.register(
            self.delete_site, DeleteSiteState.waiting_for_site_name
        )
        self.router.message.register(
            self.ask_reboot_router, F.text == "🔄 Перезагрузить роутер"
        )
        self.router.message.register(
            self.reboot_router, RebootRouterState.waiting_for_confirmation
        )

    async def cmd_start(self, message: Message):
        """Обработчик команды /start."""
        if not await self._is_user_allowed(message.from_user.id):
            await message.answer(MESSAGES['access_denied'])
            return
        await message.answer(
            MESSAGES['start'], 
            reply_markup=self._get_menu_keyboard(), 
            parse_mode="HTML"
        )

    async def test_connection(self, message: Message):
        """Тестовая команда /test для проверки возможности выполнения команд."""
        try:
            # Выполняем тестовую команду
            await self.router_client.execute_command("pwd")
            await message.answer("🟢 Тест успешен: команды роутера доступны.")
        except Exception as e:
            self.logger.error(f"Ошибка выполнения команды: {e}")
            await message.answer("🔴 Тест неудачен: не удалось выполнить команду.")

    async def _is_user_allowed(self, user_id: int) -> bool:
        return user_id in self.config.ALLOWED_USERS

    def _get_menu_keyboard(self) -> ReplyKeyboardMarkup:
        keyboard = [
            [KeyboardButton(text="📜 Список сайтов")],
            [
                KeyboardButton(text="➕ Добавить сайт"), 
                KeyboardButton(text="➖ Удалить сайт")
            ],
            [KeyboardButton(text="🔄 Перезагрузить роутер")]
        ]
        return ReplyKeyboardMarkup(keyboard=keyboard, resize_keyboard=True)

    async def list_sites(self, message: Message):
        if not await self._is_user_allowed(message.from_user.id):
            await message.answer(MESSAGES['access_denied'])
            return
        try:
            # Используем await для execute_command
            sites_raw = await self.router_client.execute_command("kvas list")
            sites_formatted = self.output_formatter.clean_terminal_output(sites_raw)
            
            if not sites_formatted:
                self.logger.warning("Получен пустой список сайтов")
                await message.answer(MESSAGES['site_list_empty'])
                return
            
            await message.answer(
                text=f"📋 Список заблокированных сайтов:\n\n{sites_formatted}", 
                parse_mode="HTML"
            )
        except Exception as e:
            self.logger.error(f"Полная ошибка списка сайтов: {e}", exc_info=True)
            await message.answer("❌ Не удалось получить список: Проверьте настройки")

    async def ask_add_site(self, message: Message, state: FSMContext):
        if not await self._is_user_allowed(message.from_user.id):
            await message.answer(MESSAGES['access_denied'])
            return
        await message.answer(MESSAGES['site_add_prompt'])
        await state.set_state(AddSiteState.waiting_for_site_name)

    async def add_site(self, message: Message, state: FSMContext):
        site = message.text.strip().lower()
        if not self._validate_domain(site):
            await message.answer(
                "❌ Некорректный формат домена. Пожалуйста, введите корректное доменное имя (например: example.com)", 
                parse_mode="HTML"
            )
            await state.clear()
            return

        status_message = await message.answer(
            text=f"⌛️ Добавление сайта: {site}...\n\n" 
                 f"<i>Процедура может занять от 15 до 40 секунд, наберитесь терпения.</i>", 
            parse_mode="HTML"
        )

        try:
            # Используем await для execute_command
            raw_output = await self.router_client.execute_command(
                f"kvas add {site} -y", timeout=60
            )
            
            if "ДОБАВЛЕН" in raw_output:
                await status_message.edit_text(
                    f"✅ Сайт <i>{site}</i> успешно добавлен в список разблокировки.", 
                    parse_mode="HTML"
                )
            else:
                error_msg = f"❌ Не удалось добавить сайт. Ответ сервера:\n<pre>{raw_output[:200]}</pre>"
                await status_message.edit_text(error_msg, parse_mode="HTML")
                self.logger.error(f"Ошибка при добавлении {site}: {raw_output}")
        
        except asyncio.TimeoutError:
            await status_message.edit_text(
                f"⚠️ Превышено время ожидания при добавлении сайта {site}. Попробуйте позже.", 
                parse_mode="HTML"
            )
        
        except Exception as e:
            await status_message.edit_text(
                f"❌ Произошла ошибка при добавлении сайта:\n<pre>{str(e)[:200]}</pre>", 
                parse_mode="HTML"
            )
            self.logger.error(f"Исключение при добавлении сайта {site}: {str(e)}", exc_info=True)
        
        finally:
            await state.clear()

    async def ask_delete_site(self, message: Message, state: FSMContext):
        if not await self._is_user_allowed(message.from_user.id):
            await message.answer(MESSAGES['access_denied'])
            return
        await state.clear()
        await message.answer(MESSAGES['site_delete_prompt'])
        await state.set_state(DeleteSiteState.waiting_for_site_name)

    async def delete_site(self, message: Message, state: FSMContext):
        site = message.text.strip().lower()
        current_state = await state.get_state()
        
        if current_state != DeleteSiteState.waiting_for_site_name.state:
            self.logger.warning("Попытка обработки вне состояния удаления")
            await message.answer("⚠️ Процесс удаления был прерван. Попробуйте начать заново.")
            return

        if not self._validate_domain(site):
            await message.answer(
                "❌ Некорректный формат домена. Введите корректное доменное имя, например: example.com", 
                parse_mode="HTML"
            )
            return

        status_message = await message.answer(
            text=f"⌛ Удаление сайта: {site}...\n\n" 
                 f"<i>Это может занять некоторое время.</i>", 
            parse_mode="HTML"
        )

        try:
            # Используем await для execute_command
            raw_output = await self.router_client.execute_command(
                f"kvas del {site} -y", timeout=30
            )
            
            if "УДАЛЕН" in raw_output:
                await status_message.edit_text(
                    f"✅ Сайт <i>{site}</i> успешно удален из списка.", 
                    parse_mode="HTML"
                )
            elif "Такая запись отсутствует в списке разблокировки!" in raw_output:
                await status_message.edit_text(
                    f"ℹ️ Сайт <i>{site}</i> отсутствует в списке.", 
                    parse_mode="HTML"
                )
            else:
                await status_message.edit_text(
                    f"❌ Ошибка удаления. Ответ сервера:\n<pre>{raw_output[:200]}</pre>", 
                    parse_mode="HTML"
                )
        
        except Exception as e:
            self.logger.error(f"Ошибка удаления сайта {site}: {e}", exc_info=True)
            await status_message.edit_text(
                f"❌ Произошла ошибка при удалении: <pre>{html.escape(str(e))}</pre>", 
                parse_mode="HTML"
            )
        
        finally:
            await state.clear()

    async def ask_reboot_router(self, message: Message, state: FSMContext):
        if not await self._is_user_allowed(message.from_user.id):
            await message.answer(MESSAGES['access_denied'])
            return
        await state.clear()
        await message.answer(
            f"🤔 Вы действительно хотите перезагрузить роутер?", 
            reply_markup=ReplyKeyboardMarkup(
                keyboard=[ 
                    [ 
                        KeyboardButton(text="Да"), 
                        KeyboardButton(text="Нет") 
                    ], 
                ], 
                resize_keyboard=True
            )
        )
        await state.set_state(RebootRouterState.waiting_for_confirmation)

    async def reboot_router(self, message: Message, state: FSMContext):
        answer = message.text.strip().lower()
        current_state = await state.get_state()
        
        if current_state != RebootRouterState.waiting_for_confirmation.state:
            self.logger.warning("Попытка обработки вне состояния удаления")
            await message.answer("⚠️ Процесс перезагрузки был прерван. Попробуйте начать заново.")
            return

        if answer == "да":
            reboot = True
        elif answer == "нет":
            reboot = False
        else:
            await message.answer("❌ Некорректный ответ. Пожалуйста, введите 'Да' или 'Нет'.")
            return

        if reboot:
            try:
                # Используем await для execute_command
                await self.router_client.execute_command("system reboot", timeout=10)
                await message.answer(
                    "✅ Роутер успешно перезагружен.", 
                    reply_markup=self._get_menu_keyboard()
                )
            except Exception as e:
                self.logger.error(f"Ошибка перезагрузки роутера: {e}", exc_info=True)
                await message.answer("❌ Произошла ошибка при перезагрузке роутера.")
        else:
            await message.answer(
                "❌ Роутер не перезагружен.", 
                reply_markup=self._get_menu_keyboard()
            )
        
        await state.clear()

    def _validate_domain(self, domain: str) -> bool:
        """Проверка корректности доменного имени."""
        domain_pattern = re.compile(
            r'^(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
        )
        return bool(domain_pattern.match(domain))

    async def start(self):
        try:
            # Отключаем логирование aiogram
            aiogram_logger = get_logger('aiogram.dispatcher')
            aiogram_logger.setLevel(logging.CRITICAL)
            
            await self.bot.delete_webhook(drop_pending_updates=True)
            self.dp.include_router(self.router)
            await self.dp.start_polling(self.bot, polling_timeout=30)
        
        except Exception as e:
            self.logger.critical(f"Критическая ошибка бота: {e}")
        
        finally:
            await self.bot.session.close()