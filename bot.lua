-- =========================
-- Milano Bot - Enhanced (Group-ready)
-- =========================
-- ميزات:
-- 1) تفعيل تلقائي عند إضافة/ترقية البوت مع زر "شفاف" باسم اللي أضافه
-- 2) لوحة حماية كاملة بأزرار Inline تتبدّل ✅/❌ وتطبّق القيود (حذف/تقييد/قفل الدردشة)
-- 3) أمر مغادرة مؤكّد للمطور (زرّان: تأكيد/إلغاء)
-- 4) رفع/تنزيل مشرف + زر "تعديل صلاحيات المستخدم" بلوحة أذونات قابلة للتبديل فوريًا
-- 5) حصانة (إضافة/إزالة) تُستثني من القيود
-- 6) أمر /id (أو ايدي) يرسل صورة الحساب (إن وُجدت) + الاسم/المعرف/ID/عدد الصور/البايو
-- 7) إدارة رابط المجموعة:
--     - أي عضو يكتب "الرابط" أو "/الرابط" → يرسل البوت الرابط حسب النوع المحدد
--     - المشرف يختار النوع عبر "/تحديد الرابط" : (رابط بطلب انضمام | رابط عام)
-- =========================

local https  = require("ssl.https")
local ltn12  = require("ltn12")
local json   = require("dkjson")

-- ---------- إعدادات ----------
local cfgf = io.open("config.json","r")
if not cfgf then
  print("❌ لا يوجد config.json (ضع token و admin_id)"); os.exit(1)
end
local cfg = json.decode(cfgf:read("*a")); cfgf:close()
local TOKEN    = cfg.token
local ADMIN_ID = tostring(cfg.admin_id)
local API      = "https://api.telegram.org/bot"..TOKEN

-- ---------- أدوات HTTP ----------
local function POST(method, tbl)
  local body = json.encode(tbl or {})
  local resp = {}
  local ok, code = https.request{
    url = API.."/"..method, method = "POST",
    headers = { ["Content-Type"]="application/json", ["Content-Length"]=tostring(#body) },
    source  = ltn12.source.string(body),
    sink    = ltn12.sink.table(resp)
  }
  return tonumber(code) or 0, table.concat(resp)
end

local function GET(path)
  local resp = {}
  local ok, code = https.request{ url = API..path, sink = ltn12.sink.table(resp) }
  return tonumber(code) or 0, table.concat(resp)
end

local function sendMessage(chat_id, text, reply_markup, parse_mode)
  return POST("sendMessage", {
    chat_id = chat_id, text = text, parse_mode = parse_mode or "HTML",
    reply_markup = reply_markup
  })
end

local function editMessageText(chat_id, message_id, text, reply_markup)
  return POST("editMessageText", {
    chat_id = chat_id, message_id = message_id, text = text,
    parse_mode = "HTML", reply_markup = reply_markup
  })
end

local function editMarkup(chat_id, message_id, reply_markup)
  return POST("editMessageReplyMarkup", {
    chat_id = chat_id, message_id = message_id, reply_markup = reply_markup
  })
end

local function answerCallbackQuery(id, text, alert)
  return POST("answerCallbackQuery",{ callback_query_id=id, text=text or "", show_alert = alert or false })
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

-- ---------- Bot ID ----------
local BOT_ID = nil
do
  local code, body = GET("/getMe")
  if code == 200 then
    local d = json.decode(body); if d and d.ok then BOT_ID = tostring(d.result.id) end
  end
end

-- ---------- حالة القفل/الحصانة/الرابط لكل مجموعة ----------
local locks  = {}   -- [chat_id] = { chat, photos, documents, forward, edit, stickers, links, joins, voice }
local immunes= {}   -- [chat_id] = { [user_id]=true }
local linkType = {} -- [chat_id] = "invite" | "public"

local function state_path(chat_id) return "locks_"..tostring(chat_id)..".json" end
local function load_state(chat_id)
  local f = io.open(state_path(chat_id),"r"); if not f then return end
  local d = json.decode(f:read("*a")); f:close()
  locks[chat_id]    = d.locks or {}
  immunes[chat_id]  = d.immunes or {}
  linkType[chat_id] = d.linkType or "invite"
end
local function save_state(chat_id)
  local f = io.open(state_path(chat_id),"w+")
  f:write(json.encode({ locks = locks[chat_id] or {}, immunes = immunes[chat_id] or {}, linkType = linkType[chat_id] or "invite"}))
  f:close()
end
local function ensure_defaults(chat_id)
  if not locks[chat_id] then
    locks[chat_id] = { chat=false, photos=false, documents=false, forward=false, edit=false, stickers=false, links=false, joins=false, voice=false }
  end
  if not immunes[chat_id] then immunes[chat_id] = {} end
  if not linkType[chat_id] then linkType[chat_id] = "invite" end
end

-- ---------- مساعدة ----------
local function label(flag, name) return (flag and "✅ " or "❌ ")..name end

local function lock_keyboard(chat_id)
  ensure_defaults(chat_id)
  local L = locks[chat_id]
  return {
    inline_keyboard = {
      {
        {text=label(L.chat,"قفل الدردشة"),    callback_data="t:chat"},
        {text=label(L.photos,"الصور"),        callback_data="t:photos"}
      },{
        {text=label(L.documents,"الملفات"),   callback_data="t:documents"},
        {text=label(L.forward,"التوجيه"),     callback_data="t:forward"}
      },{
        {text=label(L.edit,"التعديل"),        callback_data="t:edit"},
        {text=label(L.stickers,"الملصقات/GIF"), callback_data="t:stickers"}
      },{
        {text=label(L.links,"الروابط"),       callback_data="t:links"},
        {text=label(L.joins,"الإضافات"),      callback_data="t:joins"}
      },{
        {text=label(L.voice,"الصوتيات"),      callback_data="t:voice"}
      }
    }
  }
end

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

local function isImmune(chat_id, user_id)
  ensure_defaults(chat_id)
  if tostring(user_id) == ADMIN_ID then return true end
  return immunes[chat_id][tostring(user_id)] and true or false
end
local function immune_add(chat_id, user_id) ensure_defaults(chat_id); immunes[chat_id][tostring(user_id)] = true;  save_state(chat_id) end
local function immune_del(chat_id, user_id) ensure_defaults(chat_id); immunes[chat_id][tostring(user_id)] = nil;   save_state(chat_id) end

-- ---------- تفعيل عند الإضافة/الترقية ----------
local function activationMessage(chat, actor)
  local title = chat.title or (chat.username and ("@"..chat.username)) or "مجموعة"
  local who   = (actor and (actor.username and ("@"..actor.username) or actor.first_name)) or "مستخدم"
  local text  = ("✅ <b>تم تفعّيلي تلقائيًا</b>\nالمجموعة: <b>%s</b>\n(ID: <code>%s</code>)"):format(title, tostring(chat.id))
  local kb = { inline_keyboard = { { {text="• بواسطة: "..who.." •", callback_data="noop"} } } }
  sendMessage(chat.id, text, kb, "HTML")
end

-- ---------- رتب (Promote/Demote) ----------
local function promote(chat_id, user_id, rights)
  rights = rights or {
    can_manage_chat = true,
    can_delete_messages = true,
    can_manage_video_chats = true,
    can_restrict_members = true,
    can_promote_members = false,
    can_change_info = false,
    can_invite_users = true,
    can_pin_messages = true
  }
  rights.chat_id = chat_id; rights.user_id = user_id
  return POST("promoteChatMember", rights)
end

local function demote(chat_id, user_id)
  return POST("promoteChatMember", {
    chat_id = chat_id, user_id = user_id,
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

local function get_admin_rights(chat_id, user_id)
  local code, body = GET("/getChatMember?chat_id="..tostring(chat_id).."&user_id="..tostring(user_id))
  local R = {
    can_delete_messages=false, can_invite_users=false, can_change_info=false,
    can_promote_members=false, can_manage_video_chats=false, can_restrict_members=false
  }
  if code == 200 then
    local d = json.decode(body)
    if d and d.ok and d.result and d.result.status == "administrator" then
      local p = d.result
      R.can_delete_messages   = p.can_delete_messages or false
      R.can_invite_users      = p.can_invite_users or false
      R.can_change_info       = p.can_change_info or false
      R.can_promote_members   = p.can_promote_members or false
      R.can_manage_video_chats= p.can_manage_video_chats or false
      R.can_restrict_members  = p.can_restrict_members or false
    end
  end
  return R
end

local function rights_keyboard(chat_id, user_id)
  local R = get_admin_rights(chat_id, user_id)
  local function mark(b, t) return (b and "✅ " or "❌ ")..t end
  return {
    inline_keyboard = {
      {
        {text=mark(R.can_restrict_members,"صلاحية حظر"), callback_data="pr:"..user_id..":can_restrict_members"},
        {text=mark(R.can_invite_users,"صلاحية دعوة"),    callback_data="pr:"..user_id..":can_invite_users"}
      },{
        {text=mark(R.can_change_info,"تغيير معلومات مجموعة"), callback_data="pr:"..user_id..":can_change_info"},
        {text=mark(R.can_promote_members,"رفع مشرفين جدد"),    callback_data="pr:"..user_id..":can_promote_members"}
      },{
        {text=mark(R.can_manage_video_chats,"إدارة اتصال"),    callback_data="pr:"..user_id..":can_manage_video_chats"},
        {text=mark(R.can_delete_messages,"حذف الرسائل"),       callback_data="pr:"..user_id..":can_delete_messages"}
      }
    }
  }
end

local function apply_right_toggle(chat_id, user_id, field)
  local R = get_admin_rights(chat_id, user_id)
  R[field] = not R[field]
  local payload = {
    chat_id = chat_id, user_id = user_id,
    can_manage_chat = true,
    can_delete_messages = R.can_delete_messages,
    can_manage_video_chats = R.can_manage_video_chats,
    can_restrict_members = R.can_restrict_members,
    can_promote_members = R.can_promote_members,
    can_change_info = R.can_change_info,
    can_invite_users = R.can_invite_users,
    can_pin_messages = true
  }
  return POST("promoteChatMember", payload)
end

local function send_promoted_with_rights_button(chat_id, target_user_id)
  local kb = { inline_keyboard = { { {text="تعديل صلاحيات المستخدم", callback_data="rights:"..tostring(target_user_id)} } } }
  sendMessage(chat_id, "✅ تم رفعه مشرف.", kb, "HTML")
end

-- ---------- أمر ايدي ----------
local function user_profile(user_id)
  local code1, body1 = GET("/getUserProfilePhotos?user_id="..tostring(user_id).."&limit=1")
  local count, file_id = 0, nil
  if code1 == 200 then
    local d = json.decode(body1)
    if d and d.ok then
      count = d.result.total_count or 0
      if d.result.photos and d.result.photos[1] then
        local last = d.result.photos[1][#d.result.photos[1]]
        file_id = last and last.file_id or nil
      end
    end
  end
  local bio = "-"
  local code2, body2 = GET("/getChat?chat_id="..tostring(user_id))
  if code2 == 200 then
    local d = json.decode(body2); if d and d.ok then bio = d.result.bio or "-" end
  end
  return file_id, count, bio
end

local function send_user_id_card(msg)
  local u = msg.from
  local uname = u.username and ("@"..u.username) or "—"
  local name  = (u.first_name or "")..((u.last_name and (" "..u.last_name)) or "")
  local file_id, count, bio = user_profile(u.id)
  local caption = ("<b>الاسم:</b> %s\n<b>المعرف:</b> %s\n<b>ID:</b> <code>%s</code>\n<b>عدد الصور:</b> %d\n<b>البايو:</b> %s")
                  :format(name, uname, tostring(u.id), count or 0, bio or "-")
  if file_id then
    POST("sendPhoto", { chat_id = msg.chat.id, photo = file_id, caption = caption, parse_mode="HTML" })
  else
    sendMessage(msg.chat.id, caption, nil, "HTML")
  end
end

-- ---------- القيود ----------
local function enforce_rules(msg)
  if msg.chat.type == "private" then return end
  local cid = msg.chat.id
  ensure_defaults(cid)
  local L = locks[cid]
  local from = msg.from or {}
  local uid = from.id

  if isImmune(cid, uid) or isAdmin(cid, uid) then return end

  if L.chat then deleteMessage(cid, msg.message_id); return end
  if L.photos and (msg.photo or (msg.document and msg.document.mime_type and msg.document.mime_type:match("^image/"))) then
    deleteMessage(cid, msg.message_id); return
  end
  if L.documents and (msg.document or msg.video or msg.audio or msg.animation) then
    deleteMessage(cid, msg.message_id); return
  end
  if L.forward and (msg.forward_from or msg.forward_from_chat) then
    deleteMessage(cid, msg.message_id); return
  end
  if L.stickers and (msg.sticker or msg.animation) then
    deleteMessage(cid, msg.message_id); return
  end
  if L.links and message_has_link(msg.text, msg.entities) then
    deleteMessage(cid, msg.message_id); return
  end
  if L.voice and (msg.voice or msg.video_note) then
    deleteMessage(cid, msg.message_id); return
  end
end

-- ---------- لوحة الرابط ----------
local function link_type_keyboard(chat_id)
  ensure_defaults(chat_id)
  local cur = linkType[chat_id] or "invite"
  local function mark(opt, title) return (cur==opt and "✅ " or "❌ ")..title end
  return {
    inline_keyboard = {
      {
        {text=mark("invite","رابط بطلب انضمام"), callback_data="linkset:invite"},
        {text=mark("public","رابط عام"),          callback_data="linkset:public"}
      }
    }
  }
end

local function get_group_link(chat)
  if (linkType[chat.id] or "invite") == "public" then
    if chat.username then return "https://t.me/"..chat.username end
  end
  local code, body = POST("createChatInviteLink", { chat_id = chat.id })
  if code == 200 then
    local d = json.decode(body); if d and d.ok and d.result then return d.result.invite_link end
  end
  return "⚠️ تعذر جلب رابط المجموعة."
end

-- ---------- مغادرة مؤكدة ----------
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
            if not locks[chat.id] then load_state(chat.id); ensure_defaults(chat.id) end

            if msg.new_chat_members and BOT_ID then
              for _, nm in ipairs(msg.new_chat_members) do
                if tostring(nm.id) == BOT_ID then
                  activationMessage(chat, msg.from)
                end
              end
            end

            enforce_rules(msg)

            local txt = msg.text
            if txt then
              if txt == "/start" then
                sendMessage(chat.id, "✅ البوت شغال.\nأرسل <b>/lock</b> لعرض لوحة الحماية.\nاطلب <b>/الرابط</b> للحصول على رابط المجموعة.", nil, "HTML")

              elseif txt == "/lock" then
                if isAdmin(chat.id, msg.from.id) then
                  sendMessage(chat.id, "لوحة الحماية — بدّل الحالات بالضغط على الأزرار:", lock_keyboard(chat.id))
                else
                  sendMessage(chat.id, "⚠️ الأمر للمشرفين فقط.")
                end

              elseif txt == "/id" or txt == "ايدي" or txt == "/ايدي" then
                send_user_id_card(msg)

              elseif txt:match("^رفع%s+مشرف") and isAdmin(chat.id, msg.from.id) then
                local uid = msg.reply_to_message and msg.reply_to_message.from and msg.reply_to_message.from.id
                if not uid then
                  uid = tonumber((txt:gsub("^رفع%s+مشرف%s*",""):gsub("%s+","")))
                end
                if uid then
                  local c,_ = promote(chat.id, uid)
                  if c == 200 then
                    send_promoted_with_rights_button(chat.id, uid)
                  else
                    sendMessage(chat.id, "❌ فشل رفع المستخدم مشرف. تأكد من صلاحيات البوت.")
                  end
                else
                  sendMessage(chat.id, "استخدم: رفع مشرف <ID> أو ردّ على رسالة الشخص.")
                end

              elseif txt:match("^تنزيل%s+مشرف") and isAdmin(chat.id, msg.from.id) then
                local uid = msg.reply_to_message and msg.reply_to_message.from and msg.reply_to_message.from.id
                if not uid then
                  uid = tonumber((txt:gsub("^تنزيل%s+مشرف%s*",""):gsub("%s+","")))
                end
                if uid then
                  local c,_ = demote(chat.id, uid)
                  if c == 200 then
                    sendMessage(chat.id, "✅ تم تنزيل المستخدم من الإشراف.")
                  else
                    sendMessage(chat.id, "❌ فشل تنزيل المستخدم. تأكد من صلاحيات البوت.")
                  end
                else
                  sendMessage(chat.id, "استخدم: تنزيل مشرف <ID> أو ردّ على رسالة الشخص.")
                end

              elseif txt:match("^رفع%s+محصن") and isAdmin(chat.id, msg.from.id) then
                local uid = msg.reply_to_message and msg.reply_to_message.from and msg.reply_to_message.from.id
                if not uid then uid = tonumber((txt:gsub("^رفع%s+محصن%s*",""):gsub("%s+",""))) end
                if uid then immune_add(chat.id, uid); sendMessage(chat.id, "🛡️ تمت إضافة الحصانة للمستخدم: <code>"..tostring(uid).."</code>", nil, "HTML")
                else sendMessage(chat.id, "استخدم: رفع محصن <ID> أو ردّ على رسالة الشخص.") end

              elseif txt:match("^تنزيل%s+محصن") and isAdmin(chat.id, msg.from.id) then
                local uid = msg.reply_to_message and msg.reply_to_message.from and msg.reply_to_message.from.id
                if not uid then uid = tonumber((txt:gsub("^تنزيل%s+محصن%s*",""):gsub("%s+",""))) end
                if uid then immune_del(chat.id, uid); sendMessage(chat.id, "🛡️ تمت إزالة الحصانة عن المستخدم: <code>"..tostring(uid).."</code>", nil, "HTML")
                else sendMessage(chat.id, "استخدم: تنزيل محصن <ID> أو ردّ على رسالة الشخص.") end

              elseif (txt == "غادر البوت" or txt == "/leave") and tostring(msg.from.id) == ADMIN_ID then
                ask_leave(chat.id)

              elseif txt == "/الرابط" or txt == "الرابط" then
                local link = get_group_link(chat)
                sendMessage(chat.id, tostring(link))

              elseif txt == "/تحديد الرابط" and isAdmin(chat.id, msg.from.id) then
                sendMessage(chat.id, "شنو نوع الرابط تريد تحدده؟", link_type_keyboard(chat.id))
              end
            end
          end
        end

        if u.edited_message then
          local em = u.edited_message
          local cid = em.chat.id
          if not locks[cid] then load_state(cid); ensure_defaults(cid) end
          if locks[cid].edit and not isImmune(cid, em.from.id) and not isAdmin(cid, em.from.id) then
            deleteMessage(cid, em.message_id)
          end
        end

        if u.callback_query then
          local cq   = u.callback_query
          local data = cq.data or ""
          local msg  = cq.message or {}
          local cid  = msg.chat and msg.chat.id
          local mid  = msg.message_id
          local uid  = cq.from and cq.from.id

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

          elseif data:match("^t:") then
            if not isAdmin(cid, uid) then
              answerCallbackQuery(cq.id, "⚠️ الأزرار للمشرفين فقط")
            else
              local key = data:sub(3)
              ensure_defaults(cid)
              locks[cid][key] = not locks[cid][key]
              save_state(cid)
              if key == "chat" then setChatPermissions(cid, not locks[cid].chat) end
              editMarkup(cid, mid, lock_keyboard(cid))
              answerCallbackQuery(cq.id, "تم التبديل")
            end

          elseif data:match("^linkset:") then
            if not isAdmin(cid, uid) then
              answerCallbackQuery(cq.id, "⚠️ للمشرفين فقط")
            else
              local typ = data:gsub("^linkset:","")
              linkType[cid] = (typ=="public") and "public" or "invite"
              save_state(cid)
              editMarkup(cid, mid, link_type_keyboard(cid))
              answerCallbackQuery(cq.id, "تم تحديد نوع الرابط: "..(linkType[cid]=="public" and "عام" or "دعوة"))
            end

          elseif data:match("^rights:%d+$") then
            local target = tonumber(data:match("rights:(%d+)"))
            if not isAdmin(cid, uid) then
              answerCallbackQuery(cq.id, "⚠️ للمشرفين فقط")
            else
              editMarkup(cid, mid, rights_keyboard(cid, target))
              answerCallbackQuery(cq.id, "لوحة الصلاحيات")
            end

          elseif data:match("^pr:%d+:[%w_]+$") then
            if not isAdmin(cid, uid) then
              answerCallbackQuery(cq.id, "⚠️ للمشرفين فقط")
            else
              local tuid, field = data:match("^pr:(%d+):([%w_]+)$")
              tuid = tonumber(tuid)
              local c,_ = apply_right_toggle(cid, tuid, field)
              if c == 200 then
                editMarkup(cid, mid, rights_keyboard(cid, tuid))
                answerCallbackQuery(cq.id, "تم التبديل")
              else
                answerCallbackQuery(cq.id, "❌ فشل تعديل الصلاحية", true)
              end
            end
          end
        end
      end
    end
  end
end
