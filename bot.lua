-- =========================
-- Milano Bot - Enhanced
-- ميزات:
-- 1) رسالة تفعيل تلقائي عند إضافة/ترقية البوت لمشرف مع زر "شفاف" باسم اللي أضافه
-- 2) لوحة حماية كاملة بأزرار Inline تتبدّل حالتها ✅/❌:
--    (قفل الدردشة/الصور/الملفات/التوجيه/التعديل/الملصقات-GIF/الروابط/الإضافات/الصوتيات)
--    وتطبيق القوانين بحذف المخالفات + setChatPermissions لقفل/فتح الدردشة
-- 3) أمر مغادرة مؤكّد للمطور: يرسل زرّين (تأكيد/إلغاء) قبل ما يغادر
-- 4) أوامر رتب: رفع/تنزيل مشرف (Promote/Demote) + حصانة (إعفاء من القيود)
-- 5) أمر ايدي: يرسل صورة الحساب (إن وجدت) + الاسم/المعرف/الآيدي/الصور/البايو
-- =========================

local https  = require("ssl.https")
local ltn12  = require("ltn12")
local json   = require("dkjson")

-- ---------- تحميل الإعدادات ----------
local cfgf = io.open("config.json","r")
if not cfgf then
  print("❌ لا يوجد config.json (ضع token و admin_id)")
  os.exit(1)
end
local cfg = json.decode(cfgf:read("*a")); cfgf:close()
local TOKEN    = cfg.token
local ADMIN_ID = tostring(cfg.admin_id)
local API      = "https://api.telegram.org/bot"..TOKEN

-- ---------- أدوات HTTP ----------
local function POST(method, tbl)
  local body = json.encode(tbl)
  local resp = {}
  local ok, code = https.request{
    url = API.."/"..method,
    method = "POST",
    headers = { ["Content-Type"]="application/json", ["Content-Length"]=tostring(#body) },
    source = ltn12.source.string(body),
    sink   = ltn12.sink.table(resp)
  }
  return code or 0, table.concat(resp)
end

local function GET(path) -- path يبدأ بـ /method?query=...
  local resp = {}
  local ok, code = https.request{
    url = API..path,
    sink = ltn12.sink.table(resp)
  }
  return code or 0, table.concat(resp)
end

local function sendMessage(chat_id, text, reply_markup, parse_mode)
  return POST("sendMessage", {
    chat_id = chat_id, text = text, parse_mode = parse_mode or "HTML",
    reply_markup = reply_markup
  })
end

local function editMarkup(chat_id, msg_id, reply_markup)
  return POST("editMessageReplyMarkup", {
    chat_id = chat_id, message_id = msg_id, reply_markup = reply_markup
  })
end

local function answerCallbackQuery(id, text, alert)
  return POST("answerCallbackQuery",{
    callback_query_id=id, text=text or "", show_alert = alert or false
  })
end

local function deleteMessage(chat_id, message_id)
  return GET("/deleteMessage?chat_id="..tostring(chat_id).."&message_id="..tostring(message_id))
end

local function setChatPermissions(chat_id, can_send)
  local p = can_send and true or false
  return POST("setChatPermissions",{
    chat_id = chat_id,
    permissions = {
      can_send_messages = p,
      can_send_audios = p,
      can_send_documents = p,
      can_send_photos = p,
      can_send_videos = p,
      can_send_video_notes = p,
      can_send_voice_notes = p,
      can_send_polls = p,
      can_send_other_messages = p,
      can_add_web_page_previews = p,
      can_invite_users = true,
      can_change_info = false,
      can_pin_messages = false
    }
  })
end

local function getChatAdministrators(chat_id)
  local code, body = GET("/getChatAdministrators?chat_id="..tostring(chat_id))
  if code == 200 then
    local d = json.decode(body); if d and d.ok then return d.result end
  end
  return {}
end

local function isAdmin(chat_id, user_id)
  if tostring(user_id) == ADMIN_ID then return true end
  local admins = getChatAdministrators(chat_id)
  for _,a in ipairs(admins) do
    if tostring(a.user.id) == tostring(user_id) then return true end
  end
  return false
end

-- ---------- جلب Bot ID ----------
local BOT_ID = nil
do
  local code, body = GET("/getMe")
  if code == 200 then
    local d = json.decode(body)
    if d and d.ok then BOT_ID = tostring(d.result.id) end
  end
end

-- ---------- تخزين حالة القفل لكل مجموعة ----------
-- سنخزن الحالات بالذاكرة + ملف json لكل مجموعة (اختياري للاستمرارية)
local locks = {}       -- [chat_id] = { chat=bool, photos=bool, documents=bool, forward=bool, edit=bool, stickers=bool, links=bool, joins=bool, voice=bool }
local immunes = {}     -- [chat_id] = { [user_id]=true }  -- أصحاب الحصانة

local function load_state(chat_id)
  local path = "locks_"..tostring(chat_id)..".json"
  local f = io.open(path,"r"); if not f then return end
  local d = json.decode(f:read("*a")); f:close()
  locks[chat_id]   = d.locks or {}
  immunes[chat_id] = d.immunes or {}
end

local function save_state(chat_id)
  local path = "locks_"..tostring(chat_id)..".json"
  local f = io.open(path,"w+")
  f:write(json.encode({locks = locks[chat_id] or {}, immunes = immunes[chat_id] or {}}))
  f:close()
end

local function ensure_defaults(chat_id)
  locks[chat_id] = locks[chat_id] or {
    chat=false, photos=false, documents=false, forward=false, edit=false,
    stickers=false, links=false, joins=false, voice=false
  }
  immunes[chat_id] = immunes[chat_id] or {}
end

-- ---------- لوحة الأزرار ----------
local function label(flag, name)
  return (flag and "✅ " or "❌ ")..name
end

local function lock_keyboard(chat_id)
  ensure_defaults(chat_id)
  local L = locks[chat_id]
  return {
    inline_keyboard = {
      {
        {text=label(L.chat,"قفل الدردشة"),   callback_data="t:chat"},
        {text=label(L.photos,"الصور"),       callback_data="t:photos"}
      },{
        {text=label(L.documents,"الملفات"),  callback_data="t:documents"},
        {text=label(L.forward,"التوجيه"),    callback_data="t:forward"}
      },{
        {text=label(L.edit,"التعديل"),       callback_data="t:edit"},
        {text=label(L.stickers,"الملصقات/GIF"), callback_data="t:stickers"}
      },{
        {text=label(L.links,"الروابط"),      callback_data="t:links"},
        {text=label(L.joins,"الإضافات"),     callback_data="t:joins"}
      },{
        {text=label(L.voice,"الصوتيات"),     callback_data="t:voice"}
      }
    }
  }
end

-- ---------- رسالة تفعيل عند الإضافة/الترقية ----------
local function activationMessage(chat, actor)
  local title = chat.title or (chat.username and ("@"..chat.username)) or "مجموعة"
  local who   = (actor and (actor.username and ("@"..actor.username) or actor.first_name)) or "مستخدم"
  local text  = ("✅ <b>تم تفعّيلي تلقائيًا</b>\nالمجموعة: <b>%s</b>\n(ID: <code>%s</code>)"):format(title, tostring(chat.id))
  local kb = { inline_keyboard = { { {text="• بواسطة: "..who.." •", callback_data="noop"} } } }
  sendMessage(chat.id, text, kb, "HTML")
end

-- ---------- أوامر الرتب والحصانة ----------
local function promote(chat_id, user_id)  -- يتطلب أن يكون البوت أدمن مع صلاحية إضافة مشرفين
  return POST("promoteChatMember", {
    chat_id = chat_id,
    user_id = user_id,
    can_manage_chat = true,
    can_delete_messages = true,
    can_manage_video_chats = true,
    can_restrict_members = true,
    can_promote_members = false,
    can_change_info = false,
    can_invite_users = true,
    can_pin_messages = true
  })
end

local function demote(chat_id, user_id)
  return POST("promoteChatMember", {
    chat_id = chat_id,
    user_id = user_id,
    can_manage_chat = false,
    can_delete_messages = false,
    can_manage_video_chats = false,
    can_restrict_members = false,
    can_promote_members = false,
    can_change_info = false,
    can_invite_users = false,
    can_pin_messages = false
  })
end

-- حصانة: إضافة/إزالة
local function immune_add(chat_id, user_id)
  ensure_defaults(chat_id)
  immunes[chat_id][tostring(user_id)] = true
  save_state(chat_id)
end
local function immune_del(chat_id, user_id)
  ensure_defaults(chat_id)
  immunes[chat_id][tostring(user_id)] = nil
  save_state(chat_id)
end
local function isImmune(chat_id, user_id)
  ensure_defaults(chat_id)
  if tostring(user_id) == ADMIN_ID then return true end
  return immunes[chat_id][tostring(user_id)] and true or false
end

-- ---------- أمر ايدي بالصورة والمعلومات ----------
local function user_profile(chat_id, user_id)
  -- عدد الصور:
  local code1, body1 = GET("/getUserProfilePhotos?user_id="..tostring(user_id).."&limit=1")
  local count = 0
  local file_id = nil
  if code1 == 200 then
    local d = json.decode(body1)
    if d and d.ok then
      count = d.result.total_count or 0
      if d.result.photos and d.result.photos[1] and d.result.photos[1][#d.result.photos[1]] then
        file_id = d.result.photos[1][#d.result.photos[1]].file_id
      end
    end
  end
  -- البايو:
  local bio = "-"
  local code2, body2 = GET("/getChat?chat_id="..tostring(user_id))
  if code2 == 200 then
    local d = json.decode(body2)
    if d and d.ok then bio = d.result.bio or "-" end
  end
  return file_id, count, bio
end

local function send_user_id_card(msg)
  local u = msg.from
  local uname = u.username and ("@"..u.username) or "—"
  local name  = (u.first_name or "")..((u.last_name and (" "..u.last_name)) or "")
  local file_id, count, bio = user_profile(msg.chat.id, u.id)
  local caption = ("<b>الاسم:</b> %s\n<b>المعرف:</b> %s\n<b>ID:</b> <code>%s</code>\n<b>عدد الصور:</b> %d\n<b>البايو:</b> %s")
                  :format(name, uname, tostring(u.id), count or 0, bio or "-")
  if file_id then
    POST("sendPhoto", { chat_id = msg.chat.id, photo = file_id, caption = caption, parse_mode="HTML" })
  else
    sendMessage(msg.chat.id, caption, nil, "HTML")
  end
end

-- ---------- تطبيق القيود (حذف مخالفات) ----------
local function message_has_link(text, entities)
  if not text then return false end
  if text:match("https?://") or text:match("t%.me/") then return true end
  if entities then
    for _,e in ipairs(entities) do
      if e.type == "url" or e.type == "text_link" then return true end
    end
  end
  return false
end

local function enforce_rules(msg)
  if msg.chat.type == "private" then return end
  local cid = msg.chat.id
  ensure_defaults(cid)
  local L = locks[cid]
  local from = msg.from or {}
  local uid = from.id

  if isImmune(cid, uid) or isAdmin(cid, uid) then return end

  -- قفل الدردشة = حذف أي رسالة نص/ميديا
  if L.chat then
    deleteMessage(cid, msg.message_id); return
  end

  -- صور
  if L.photos and (msg.photo or (msg.document and msg.document.mime_type and msg.document.mime_type:match("^image/"))) then
    deleteMessage(cid, msg.message_id); return
  end

  -- ملفات
  if L.documents and (msg.document or msg.video or msg.audio or msg.animation) then
    deleteMessage(cid, msg.message_id); return
  end

  -- توجيه
  if L.forward and msg.forward_from or msg.forward_from_chat then
    deleteMessage(cid, msg.message_id); return
  end

  -- ملصقات/GIF
  if L.stickers and (msg.sticker or msg.animation) then
    deleteMessage(cid, msg.message_id); return
  end

  -- روابط
  if L.links and message_has_link(msg.text, msg.entities) then
    deleteMessage(cid, msg.message_id); return
  end

  -- صوتيات
  if L.voice and (msg.voice or msg.video_note) then
    deleteMessage(cid, msg.message_id); return
  end

  -- التعديل (نمنع التعديل بحذف الرسالة بعد التعديل) — يُعالج في edited_message بالأسفل
end

-- ---------- لوحات وأوامر ----------
local function send_lock_panel(chat_id)
  sendMessage(chat_id, "لوحة الحماية — بدّل الحالات بالضغط على الأزرار:", lock_keyboard(chat_id))
end

local function toggle_lock(chat_id, key)
  ensure_defaults(chat_id)
  locks[chat_id][key] = not locks[chat_id][key]
  save_state(chat_id)
end

-- ---------- أمر مغادرة البوت (للمطور فقط) ----------
local function ask_leave(chat_id)
  local kb = { inline_keyboard = { { {text="✅ تأكيد المغادرة",callback_data="leave_yes"}, {text="❌ إلغاء",callback_data="leave_no"} } } }
  sendMessage(chat_id, "⚠️ هل أنت متأكد أنك تريد مغادرة البوت من هذه المجموعة؟", kb)
end

-- ---------- الحلقة الرئيسية ----------
local offset = 0
while true do
  local code, body = GET("/getUpdates?timeout=30&offset="..tostring(offset))
  if code ~= 200 then
    print("⚠️ مشكلة اتصال.. إعادة المحاولة بعد 5 ثوانٍ"); os.execute("sleep 5")
  else
    local upd = json.decode(body)
    if upd and upd.result then
      for _,u in ipairs(upd.result) do
        offset = u.update_id + 1

        -- إضافة/ترقية البوت
        if u.my_chat_member then
          local m = u.my_chat_member
          if m.new_chat_member and m.new_chat_member.user and tostring(m.new_chat_member.user.id) == (BOT_ID or "") then
            if m.new_chat_member.status == "administrator" or m.new_chat_member.status == "member" then
              load_state(m.chat.id); ensure_defaults(m.chat.id); save_state(m.chat.id)
              activationMessage(m.chat, m.from)
            end
          end
        end

        -- رسائل جديدة
        if u.message then
          local msg = u.message
          local chat = msg.chat
          if chat and chat.id then
            -- تهيئة الحالة
            if not locks[chat.id] then load_state(chat.id); ensure_defaults(chat.id) end

            -- لو انضاف البوت بالمجموعة عبر new_chat_members
            if msg.new_chat_members and BOT_ID then
              for _, nm in ipairs(msg.new_chat_members) do
                if tostring(nm.id) == BOT_ID then
                  activationMessage(chat, msg.from)
                end
              end
            end

            -- تطبيق القيود
            enforce_rules(msg)

            -- أوامر نصية
            local txt = msg.text
            if txt then
              -- /start بسيط
              if txt == "/start" then
                sendMessage(chat.id, "✅ البوت شغال.\nأرسل <b>/lock</b> لعرض لوحة الحماية.", nil, "HTML")

              -- لوحة القفل
              elseif txt == "/lock" then
                if isAdmin(chat.id, msg.from.id) then
                  send_lock_panel(chat.id)
                else
                  sendMessage(chat.id, "⚠️ الأمر للمشرفين فقط.")
                end

              -- أمر ايدي
              elseif txt == "/id" or txt == "ايدي" or txt == "/ايدي" then
                send_user_id_card(msg)

              -- أوامر الرتب
              elseif txt:match("^رفع%s+مشرف%s+") and isAdmin(chat.id, msg.from.id) then
                local uid = txt:gsub("^رفع%s+مشرف%s+",""):gsub("%s+","")
                uid = tonumber(uid) or (msg.reply_to_message and msg.reply_to_message.from and msg.reply_to_message.from.id)
                if uid then
                  promote(chat.id, uid)
                  sendMessage(chat.id, "✅ تم رفع المستخدم مشرف: <code>"..tostring(uid).."</code>", nil, "HTML")
                else
                  sendMessage(chat.id, "استخدم: رفع مشرف <ID> أو ردّ على رسالة الشخص.")
                end

              elseif txt:match("^تنزيل%s+مشرف%s*") and isAdmin(chat.id, msg.from.id) then
                local uid = txt:gsub("^تنزيل%s+مشرف%s*",""):gsub("%s+","")
                uid = tonumber(uid) or (msg.reply_to_message and msg.reply_to_message.from and msg.reply_to_message.from.id)
                if uid then
                  demote(chat.id, uid)
                  sendMessage(chat.id, "✅ تم تنزيل المستخدم من الإشراف: <code>"..tostring(uid).."</code>", nil, "HTML")
                else
                  sendMessage(chat.id, "استخدم: تنزيل مشرف <ID> أو ردّ على رسالة الشخص.")
                end

              -- حصانة
              elseif txt:match("^رفع%s+محصن") and isAdmin(chat.id, msg.from.id) then
                local uid = msg.reply_to_message and msg.reply_to_message.from and msg.reply_to_message.from.id
                if not uid then
                  uid = tonumber((txt:gsub("^رفع%s+محصن%s*",""):gsub("%s+","")))
                end
                if uid then
                  immune_add(chat.id, uid)
                  sendMessage(chat.id, "🛡️ تمت إضافة الحصانة للمستخدم: <code>"..tostring(uid).."</code>", nil, "HTML")
                else
                  sendMessage(chat.id, "استخدم: رفع محصن <ID> أو ردّ على رسالة الشخص.")
                end

              elseif txt:match("^تنزيل%s+محصن") and isAdmin(chat.id, msg.from.id) then
                local uid = msg.reply_to_message and msg.reply_to_message.from and msg.reply_to_message.from.id
                if not uid then
                  uid = tonumber((txt:gsub("^تنزيل%s+محصن%s*",""):gsub("%s+","")))
                end
                if uid then
                  immune_del(chat.id, uid)
                  sendMessage(chat.id, "🛡️ تمت إزالة الحصانة عن المستخدم: <code>"..tostring(uid).."</code>", nil, "HTML")
                else
                  sendMessage(chat.id, "استخدم: تنزيل محصن <ID> أو ردّ على رسالة الشخص.")
                end

              -- مغادرة البوت (للمطور فقط)
              elseif (txt == "غادر البوت" or txt == "/leave") and tostring(msg.from.id) == ADMIN_ID then
                ask_leave(chat.id)
              end
            end
          end
        end

        -- رسائل معدلة (لتطبيق قفل التعديل)
        if u.edited_message then
          local em = u.edited_message
          local cid = em.chat.id
          if not locks[cid] then load_state(cid); ensure_defaults(cid) end
          if locks[cid].edit and not isImmune(cid, em.from.id) and not isAdmin(cid, em.from.id) then
            deleteMessage(cid, em.message_id)
          end
        end

        -- ضغطات الأزرار
        if u.callback_query then
          local cq = u.callback_query
          local data = cq.data
          local mid = cq.message and cq.message.message_id
          local cid = cq.message and cq.message.chat and cq.message.chat.id
          local uid = cq.from and cq.from.id

          if data == "noop" then
            answerCallbackQuery(cq.id, " ")
          elseif data == "leave_yes" then
            if tostring(uid) == ADMIN_ID then
              sendMessage(cid, "🚪 تم مغادرتي للمجموعة. إلى اللقاء!")
              GET("/leaveChat?chat_id="..tostring(cid))
            else
              answerCallbackQuery(cq.id, "⚠️ هذا الزر للمطور فقط", true)
            end
          elseif data == "leave_no" then
            if tostring(uid) == ADMIN_ID or isAdmin(cid, uid) then
              answerCallbackQuery(cq.id, "تم الإلغاء")
              sendMessage(cid, "❌ تم إلغاء عملية المغادرة.")
            else
              answerCallbackQuery(cq.id, "⚠️ ليس لديك صلاحية")
            end

          elseif data and data:match("^t:") then
            if not isAdmin(cid, uid) then
              answerCallbackQuery(cq.id, "⚠️ الأزرار للمشرفين فقط")
            else
              local key = data:sub(3)
              toggle_lock(cid, key)
              -- لو قفل الدردشة، نضبط صلاحيات تيليجرام مباشرة
              if key == "chat" then
                setChatPermissions(cid, not locks[cid].chat)
              end
              editMarkup(cid, mid, lock_keyboard(cid))
              answerCallbackQuery(cq.id, "تم التبديل")
            end
          end
        end
      end
    end
  end
end
