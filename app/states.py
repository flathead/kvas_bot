from aiogram.fsm.state import StatesGroup, State

class AddSiteState(StatesGroup):
    waiting_for_site_name = State()

class DeleteSiteState(StatesGroup):
    waiting_for_site_name = State()

class RebootRouterState(StatesGroup):
    waiting_for_confirmation = State()