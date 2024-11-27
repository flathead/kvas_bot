import re
import asyncio
from typing import Optional

from telegram import Update, ReplyKeyboardMarkup
from telegram.ext import (
    Application, 
    CommandHandler, 
    MessageHandler, 
    ConversationHandler, 
    ContextTypes, 
    filters,
)

from app.config import Config
from app.formatter import OutputFormatter
from app.messages import MESSAGES
from app.router_client import RouterLocalClient
from app.logger import get_logger

# Enum-like states for clearer state management
class ConversationStates:
    ADD_SITE = 0        # Добавление сайта
    DELETE_SITE = 1     # Удаление сайта
    REBOOT_ROUTER = 2   # Перезагрузка роутера

class VPNBot:
    def __init__(self, config: Config, router_client: RouterLocalClient):
        self.config = config
        self.router_client = router_client
        self.output_formatter = OutputFormatter()
        self.logger = get_logger(__name__)
        
        self.application: Optional[Application] = None
        
        # Усовершенствованное ограничение запросов
        self.user_request_counters = {}
        self.MAX_REQUESTS_PER_MINUTE = 10
        self.request_cooldown = 60  # секунд

    async def initialize(self):
        """Initialize the bot application."""
        try:
            # Create application
            self.application = (
                Application.builder()
                .token(self.config.BOT_TOKEN)
                .build()
            )
            
            # Register handlers
            self._register_handlers()
            
            return self
        except Exception as e:
            self.logger.critical(f"Bot initialization failed: {e}", exc_info=True)
            raise

    def _register_handlers(self):
        """Регистрация обработчиков с улучшенной безопасностью."""
        if not self.application:
            return

        # Создание расширенного ConversationHandler
        conversation_handler = ConversationHandler(
            entry_points=[
                MessageHandler(filters.Regex(r"➕ Добавить сайт"), self.ask_add_site),
                MessageHandler(filters.Regex(r"➖ Удалить сайт"), self.ask_delete_site),
                MessageHandler(filters.Regex(r"🔄 Перезагрузить роутер"), self.ask_reboot_router)
            ],
            states={
                ConversationStates.ADD_SITE: [
                    MessageHandler(filters.TEXT & ~filters.COMMAND, self.add_site)
                ],
                ConversationStates.DELETE_SITE: [
                    MessageHandler(filters.TEXT & ~filters.COMMAND, self.delete_site)
                ],
                ConversationStates.REBOOT_ROUTER: [
                    MessageHandler(filters.Regex(r"^(Да|Нет)$"), self.reboot_router)
                ]
            },
            fallbacks=[CommandHandler('cancel', self.cancel_operation)],
            allow_reentry=True
        )

        # Главные обработчики
        handlers = [
            CommandHandler("start", self.cmd_start),

            MessageHandler(filters.Regex(r"📜 Список сайтов"), self.list_sites),
            MessageHandler(filters.Regex(r"🆘 Помощь"), self.cmd_help),
        ]

        # Добавление обработчиков
        for handler in handlers:
            self.application.add_handler(handler)
        self.application.add_handler(conversation_handler)

    async def start(self):
        """Start bot with comprehensive error handling."""
        try:
            # Инициализируем приложение только один раз, если оно еще не создано
            if not self.application:
                await self.initialize()

            # Проверка и остановка текущего updater, если он запущен
            if self.application.updater.running:
                try:
                    await self.application.updater.stop()
                except Exception as stop_error:
                    self.logger.warning(f"Error stopping existing updater: {stop_error}")

            # Удаление вебхука
            await self.application.bot.delete_webhook(drop_pending_updates=True)
            
            # Инициализация приложения
            await self.application.initialize()
            await self.application.start()
            
            # Запуск polling
            await self.application.updater.start_polling(
                poll_interval=1.0,   
                timeout=20,           
                drop_pending_updates=True  
            )

            # Бесконечный цикл
            while True:
                await asyncio.sleep(3600)  # Периодическая проверка каждый час

        except asyncio.CancelledError:
            self.logger.info("Bot polling was cancelled")
        except Exception as e:
            self.logger.critical(f"Bot startup failed: {str(e)}", exc_info=True)
        finally:
            # Безопасная остановка
            try:
                if self.application and self.application.updater.running:
                    await self.application.updater.stop()
                if self.application and self.application.running:
                    await self.application.stop()
                    await self.application.shutdown()
            except Exception as shutdown_error:
                self.logger.error(f"Error during shutdown: {shutdown_error}")

    async def cmd_start(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Start command handler."""
        if not await self._is_user_allowed(update.effective_user.id):
            await update.message.reply_text(MESSAGES['access_denied'])
            return
        
        # Debugging print
        self.logger.info(f"Start command received from user {update.effective_user.id}")
        
        await update.message.reply_text(
            MESSAGES['start'], 
            reply_markup=self._get_menu_keyboard(), 
            parse_mode="HTML"
        )

    async def cmd_help(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Help command handler."""
        if not await self._is_user_allowed(update.effective_user.id):
            await update.message.reply_text(MESSAGES['access_denied'])
            return
        
        await update.message.reply_text(
            MESSAGES['help'], 
            reply_markup=self._get_menu_keyboard(), 
            parse_mode="HTML"
        )

    async def list_sites(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Вывод списка заблокированных сайтов."""
        if not await self._is_user_allowed(update.effective_user.id):
            await update.message.reply_text(MESSAGES['access_denied'])
            return
        try:
            sites_raw = await self.router_client.execute_command("kvas list")
            sites_formatted = self.output_formatter.clean_terminal_output(sites_raw)
            await update.message.reply_text(
                f"📋 Список заблокированных сайтов:\n\n{sites_formatted or MESSAGES['site_list_empty']}",
                parse_mode="HTML",
            )
        except Exception as e:
            self.logger.error(f"Ошибка получения списка сайтов: {e}", exc_info=True)
            await update.message.reply_text("❌ Не удалось получить список сайтов.")

    async def ask_add_site(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Запрос на добавление сайта с улучшенной обработкой."""
        if not await self._is_user_allowed(update.effective_user.id):
            await update.message.reply_text(MESSAGES['access_denied'])
            return ConversationHandler.END

        await update.message.reply_text(
            MESSAGES['site_add_prompt'], 
            reply_markup=ReplyKeyboardMarkup([['Отмена']], resize_keyboard=True)
        )
        return ConversationStates.ADD_SITE

    async def add_site(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Добавление сайта с расширенной валидацией."""
        if update.message.text.lower() == 'отмена':
            await update.message.reply_text(
                "Операция отменена.",
                reply_markup=self._get_menu_keyboard()
            )
            return ConversationHandler.END

        site = update.message.text.strip().lower()

        if not self._validate_domain(site):
            await update.message.reply_text(
                "❌ Некорректный формат домена. Пример: google.com",
                reply_markup=self._get_menu_keyboard()
            )
            return ConversationHandler.END

        try:
            status_message = await update.message.reply_text(
                "<i>Добавление сайта...</i>",
                parse_mode="HTML",
                reply_markup=self._get_menu_keyboard()
            )
            
            output = await self.router_client.execute_command(f"kvas add {site} -y")
            if "добавлен" in output.lower():
                try:
                    await status_message.edit_text(
                        f"✅ Сайт {site} успешно добавлен.",
                        reply_markup=self._get_menu_keyboard()
                    )
                except Exception as edit_error:
                    self.logger.warning(f"Failed to edit message: {edit_error}")
                    await update.message.reply_text(
                        f"✅ Сайт {site} успешно добавлен.",
                        reply_markup=self._get_menu_keyboard()
                    )
            else:
                try:
                    await status_message.edit_text(
                        f"❌ Не удалось добавить сайт. Ответ: {output}",
                        reply_markup=self._get_menu_keyboard()
                    )
                except Exception as edit_error:
                    self.logger.warning(f"Failed to edit message: {edit_error}")
                    await update.message.reply_text(
                        f"❌ Не удалось добавить сайт. Ответ: {output}",
                        reply_markup=self._get_menu_keyboard()
                    )
        except Exception as e:
            self.logger.error(f"Error adding site: {e}")
            await update.message.reply_text(
                f"❌ Произошла ошибка: {str(e)}",
                reply_markup=self._get_menu_keyboard()
            )

        return ConversationHandler.END

    async def ask_delete_site(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Запрос на удаление сайта."""
        if not await self._is_user_allowed(update.effective_user.id):
            await update.message.reply_text(MESSAGES['access_denied'])
            return ConversationHandler.END

        await update.message.reply_text(
            MESSAGES['site_delete_prompt'], 
            reply_markup=ReplyKeyboardMarkup([['Отмена']], resize_keyboard=True)
        )
        return ConversationStates.DELETE_SITE

    async def delete_site(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Удаление сайта с расширенной валидацией."""
        if update.message.text.lower() == 'отмена':
            await update.message.reply_text(
                "Операция отменена.",
                reply_markup=self._get_menu_keyboard()
            )
            return ConversationHandler.END

        site = update.message.text.strip().lower()

        if not self._validate_domain(site):
            await update.message.reply_text(
                "❌ Некорректный формат домена. Пример: google.com",
                reply_markup=self._get_menu_keyboard()
            )
            return ConversationHandler.END

        try:
            # Отправляем начальное сообщение
            status_message = await update.message.reply_text(
                "<i>Удаление сайта...</i>",
                parse_mode="HTML",
                reply_markup=self._get_menu_keyboard()
            )
            
            # Выполняем команду удаления
            output = await self.router_client.execute_command(f"kvas del {site} -y")
            
            # Определяем текст результата
            message_text = (
                f"✅ Сайт {site} успешно удален."
                if "удален" in output.lower()
                else f"❌ Не удалось удалить сайт. Ответ: {output}"
            )
            
            # Пытаемся редактировать сообщение
            try:
                await status_message.edit_text(
                    message_text,
                    reply_markup=self._get_menu_keyboard()
                )
            except Exception as edit_error:
                # Если редактирование не удалось, отправляем новое сообщение
                self.logger.warning(f"Failed to edit message: {edit_error}")
                await update.message.reply_text(
                    message_text,
                    reply_markup=self._get_menu_keyboard()
                )
        except Exception as e:
            # Обрабатываем общие ошибки
            self.logger.error(f"Ошибка удаления сайта: {e}")
            await update.message.reply_text(
                f"❌ Произошла ошибка: {str(e)}",
                reply_markup=self._get_menu_keyboard()
            )

        return ConversationHandler.END


    async def ask_reboot_router(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Вопрос на перезагрузку роутера."""
        if not await self._is_user_allowed(update.effective_user.id):
            await update.message.reply_text(MESSAGES['access_denied'])
            return ConversationHandler.END
        await update.message.reply_text(
            "🤔 Вы действительно хотите перезагрузить роутер?",
            reply_markup=ReplyKeyboardMarkup([["Да", "Нет"]], resize_keyboard=True),
        )
        return ConversationStates.REBOOT_ROUTER

    async def reboot_router(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Перезагрузка роутера."""
        if update.message.text.strip().lower() == "да":
            try:
                await update.message.reply_text(text="✅ Роутер успешно перезагружен.", reply_markup=self._get_menu_keyboard())
                await self.router_client.execute_command("reboot")
            except Exception as e:
                self.logger.error(f"Ошибка перезагрузки роутера: {e}", exc_info=True)
                await update.message.reply_text(f"❌ Ошибка перезагрузки: {str(e)}")
        else:
            await update.message.reply_text(text="❌ Перезагрузка отменена.", reply_markup=self._get_menu_keyboard())
        return ConversationHandler.END

    async def cancel_operation(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Cancel the current operation."""
        await update.message.reply_text("Операция отменена.")
        return ConversationHandler.END

    def _validate_domain(self, domain: str) -> bool:
        """Enhanced domain validation."""
        if not domain or len(domain) > 255:
            return False
        
        # More comprehensive domain validation
        domain_regex = r'^(?!-)[A-Za-z0-9-]{1,63}(?<!-)(\.[A-Za-z0-9-]{1,63})*\.[A-Za-z]{2,}$'
        return bool(re.match(domain_regex, domain, re.IGNORECASE))

    async def _is_user_allowed(self, user_id: int) -> bool:
        """Enhanced user access control."""
        # Debugging print
        self.logger.info(f"Checking access for user {user_id}")
        
        # Check if user is in allowed list
        is_allowed = user_id in self.config.ALLOWED_USERS
        
        if not is_allowed:
            self.logger.warning(f"Access denied for user {user_id}")
        
        return is_allowed

    def _get_menu_keyboard(self) -> ReplyKeyboardMarkup:
        """Create menu keyboard."""
        keyboard = [
            ["📜 Список сайтов"],
            ["➕ Добавить сайт", "➖ Удалить сайт"],
            ["🆘 Помощь"],
            ["🔄 Перезагрузить роутер"],
        ]
        return ReplyKeyboardMarkup(
            keyboard=keyboard, 
            resize_keyboard=True, 
            one_time_keyboard=False
        )