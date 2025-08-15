#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# تثبيت المتطلبات (أوبنتو 18)
if ! command -v lua5.3 >/dev/null 2>&1; then
  sudo apt update -y
  sudo apt install -y lua5.3 luarocks liblua5.3-dev unzip curl
fi

# مكتبات Lua الأساسية
luarocks install luasocket || true
luarocks install luasec    || true
luarocks install dkjson    || true

# إنشاء/تحديث .env عبر أسئلة بسيطة
if [ ! -f .env ]; then
  echo "أدخل توكن البوت:"
  read -r TOKEN
  echo "أدخل معرف المطور (ID فقط رقم):"
  read -r SUDO
  printf "TOKEN=%s\nSUDO=%s\n" "$TOKEN" "$SUDO" > .env
fi

# تأكد من تنسيق يونكس (لو الملف جاي من ويندوز)
tr -d '\r' < .env > .env.tmp && mv .env.tmp .env

# تصدير متغيرات البيئة من .env للسيشن الحالي
set -a
. ./.env
set +a

# فحص القيم
: "${TOKEN:?❌ متغير TOKEN غير موجود}"
: "${SUDO:?❌ متغير SUDO غير موجود}"

# تشغيل في screen مع إعادة تشغيل تلقائي
if ! command -v screen >/dev/null 2>&1; then
  sudo apt install -y screen
fi

# اغلق أي جلسة قديمة بنفس الاسم
screen -S milano -X quit >/dev/null 2>&1 || true

# ارفع حد الملفات وافتح حلقة إعادة تشغيل
screen -S milano -dm bash -lc 'ulimit -n 10240; while true; do lua5.3 bot.lua; echo "[milano] تعطل البوت، إعادة التشغيل بعد 5 ثواني"; sleep 5; done'

echo "✅ تم تشغيل البوت داخل جلسة screen اسمها: milano"
echo "استخدم:  screen -r milano   لمشاهدة السجلات"
