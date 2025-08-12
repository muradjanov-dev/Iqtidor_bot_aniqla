import asyncio
from aiogram import Bot, Dispatcher
from config import BOT_TOKEN
from database.db import init_db
from handlers.start_router import start_router
from handlers.test_router import test_router
from handlers.admin_router import admin_router

async def main():
    bot = Bot(token=BOT_TOKEN)
    dp = Dispatcher()
    dp.include_routers(start_router, test_router, admin_router)
    init_db()  # Database jadvallarini yaratish
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())