#!/bin/bash

echo "🚀 بدء تنصيب المتطلبات..."

# تحديث النظام
sudo apt update -y
sudo apt upgrade -y

# تثبيت Lua 5.3 والمكتبات
sudo apt install -y lua5.3 luarocks git

# تثبيت مكتبات Lua المطلوبة
sudo luarocks install luasocket
sudo luarocks install luasec
sudo luarocks install dkjson

# إعطاء صلاحيات للتشغيل
chmod +x run.sh

echo "✅ تم التنصيب، الآن شغل البوت بـ:"
echo "./run.sh"
