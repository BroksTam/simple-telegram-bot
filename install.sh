#!/usr/bin/env bash
# سكربت تنصيب بوت تليجرام يعمل مع ملف bot.lua

# تثبيت المتطلبات
echo "🔄 تثبيت المتطلبات..."
sudo apt update -y
sudo apt install -y luarocks lua5.3 liblua5.3-dev unzip curl

# تثبيت المكتبات المطلوبة
luarocks install luasocket
luarocks install luasec
luarocks install redis-lua
luarocks install lua-cjson
luarocks install serpent

# تحميل ملف البوت إذا ما كان موجود
if [ ! -f bot.lua ]; then
    echo "📥 تحميل bot.lua..."
    curl -o bot.lua "رابط-ملف-bot.lua-على-السيرفر-مالتك"
fi

# حفظ التوكن واسم المستخدم في متغيرات البيئة
echo "🔑 حفظ بيانات التوكن..."
read -p "ادخل التوكن: " token
read -p "ادخل معرف البوت بدون @: " botuser

# نضيف المتغيرات في ملف .env
echo "TOKEN=$token" > .env
echo "BOT_USER=$botuser" >> .env

# تشغيل البوت
echo "🚀 تشغيل البوت..."
lua5.3 bot.lua
