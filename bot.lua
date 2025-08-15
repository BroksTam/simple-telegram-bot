-- =========================================================
--  Milano Bot - Group Power (merged features, no token inside)
--  يحافظ على ميزاتك القديمة + يضيف كل الميزات المطلوبة
--  يعمل بالمجموعات / تخزين الحالة JSON / أزرار Inline
-- =========================================================

-- المتطلبات
local https  = require("ssl.https")
local ltn12  = require("ltn12")
local json   = require("dkjson")

-- ========= إعدادات خارجية =========
-- ملاحظة: لا يوجد token هنا. سكربت التشغيل عندك يمرر TOKEN بمتغير بيئة
-- مثال: export TOKEN="123:ABC"
local TOKEN = os.getenv("TOKEN")
if not TOKEN or TOKEN == "" then
  print("❌ TOKEN غير موجود بمتغير البيئة. عيّنه من سكربتات التنصيب/التشغيل.")
  os.exit(1)
end
local API = "https://api.telegram.org/bot"..TOKEN

-- تعيين ADMIN_ID (مطور أساسي) من متغير بيئة أيضاً
local ADMIN_ID = tostring(os.getenv("ADMIN_ID") or "")

-- ========= أدوات HTTP =========
local function POST(method, tbl)
  local body = json.encode(tbl or {})
  local resp = {}
  local _, code = https.request{
    url = API.."/"..method, method="POST",
    headers = {
      ["Content-Type"]="application/json",
      ["Content-Length"]=tostring(#body)
    },
    source = ltn12.source.string(body),
    sink   = ltn12.sink.table(resp)
  }
  return tonumber(code) or 0, table.concat(resp)
end

local function GET(path)
  local resp = {}
  local _, code = https.request{
    url = API..path,
    sink = ltn12.sink.table(resp)
  }
  return tonumber(code) or 0, table.concat(resp)
end

-- ========= أدوات رسائل =========
local function sendMessage(chat_id, text, reply_markup, parse_mode, reply_to)
  return POST("sendMessage", {
    chat_id = chat_id,
    text = text,
    parse_mode = parse_mode or "HTML",
    reply_markup = reply_markup,
    reply_to_message_id = reply_to
  })
end

local function editMessageText(chat_id, message_id, text, reply_markup)
  return POST("editMessageText", {
    chat_id = chat_id, message_id = message_id,
    text = text, parse_mode = "HTML",
    reply_markup = reply_markup
  })
end

local function editMarkup(chat_id, message_id, reply_markup)
  return POST("editMessageReplyMarkup", {
    chat_id = chat_id, message_id = message_id,
    reply_markup = reply_markup
  })
end

local function answerCallbackQuery(id, text, alert)
  return POST("answerCallbackQuery", {
    callback_query_id = id, text = text or "",
    show_alert = alert or false
  })
end

local function deleteMessage(chat_id, message_id)
  return GET("/deleteMessage?chat_id="..tostring(chat_id).."&message_id="..tostring(message_id))
end

local function kick(chat_id, user_id)   return POST("banChatMember", {chat_id=chat_id, user_id=user_id}) end
local function unban(chat_id, user_id)  return POST("unbanChatMember",{chat_id=chat_id, user_id=user_id, only_if_banned=false}) end
local function restrictMute(chat_id, user_id, mute)
  local perms = {
    can_send_messages = not mute,
    can_send_audios = not mute,
    can_send_documents = not mute,
    can_send_photos = not mute,
    can_send_videos = not mute,
    can_send_video_notes = not mute,
    can_send_voice_notes = not mute,
    can_send_polls = not mute,
    can_send_other_messages = not mute,
    can_add_web_page_previews = not mute,
    can_invite_users = true
  }
  return POST("restrictChatMember", {
    chat_id = chat_id, user_id = user_id,
    permissions = perms
  })
end

local function setChatPermissions(chat_id, can_send)
  local p = can_send and true or false
  return POST("setChatPermissions",{
    chat_id = chat_id,
    permissions = {
      can_send_messages = p, can_send_audios = p,
      can_send_documents = p, can_send_photos = p,
      can_send_videos = p, can_send_video_notes = p,
      can_send_voice_notes = p, can_send_polls = p,
      can_send_other_messages = p, can_add_web_page_previews = p,
      can_invite_users = true
    }
  })
end

-- ========= معلومات البوت =========
local BOT_ID
do
  local c,b = GET("/getMe")
  if c==200 then
    local d = json.decode(b)
    if d and d.ok then BOT_ID = tostring(d.result.id) end
  end
end

-- ========= تخزين الحالة =========
local function ensure_dir()
  os.execute("mkdir -p data")
end
ensure_dir()

local function path_for(chat_id)
  return "data/state_"..tostring(chat_id)..".json"
end

local function default_state()
  return {
    locks = {
      chat=false, photos=false, documents=false, forward=false, edit=false,
      stickers=false, links=false, joins=false, voice=false,
      -- الجديدة
      flood=false, spam=false, english=false, pin=false, contacts=false,
      fwd=false, via_channel=false, location=false, profanity=false,
      nsfw=false, noise=false, premium_stickers=false, media_edit=false
    },
    immunes = {},                 -- محصنين
    ranks = {                     -- رتب: user_id=true
      special={}, admin={}, manager={}, owner2={}, creator={}, super_creator={}, developer={}
    },
    banned = {},                  -- محظورين
    muted = {},                   -- مكتومين
    custom_cmds = {},             -- أوامر مضافة: ["نص الامر"]=الرد
    replies = {},                 -- ردود: ["كلمة"]= "الرد"
    linkType = "invite"
  }
end

local function load_state(chat_id)
  local f = io.open(path_for(chat_id),"r")
  if not f then return default_state() end
  local t = f:read("*a"); f:close()
  local ok, d = pcall(json.decode, t)
  if ok and d then
    -- دمج الافتراضي مع الموجود (لإضافة أقفال جديدة بدون فقدان قديم)
    local base = default_state()
    d.locks = d.locks or {}
    for k,v in pairs(base.locks) do if d.locks[k]==nil then d.locks[k]=v end end
    d.immunes = d.immunes or {}
    d.ranks = d.ranks or base.ranks
    for rk,_ in pairs(base.ranks) do d.ranks[rk] = d.ranks[rk] or {} end
    d.banned = d.banned or {}
    d.muted  = d.muted or {}
    d.custom_cmds = d.custom_cmds or {}
    d.replies = d.replies or {}
    d.linkType = d.linkType or "invite"
    return d
  end
  return default_state()
end

local function save_state(chat_id, state)
  local f = io.open(path_for(chat_id),"w+")
  f:write(json.encode(state)); f:close()
end

-- ========= مساعدات صلاحيات =========
local function getChatAdministrators(chat_id)
  local code, body = GET("/getChatAdministrators?chat_id="..tostring(chat_id))
  if code == 200 then
    local d = json.decode(body); if d and d.ok then return d.result end
  end
  return {}
end

local function isAdmin(chat_id, user_id)
  if ADMIN_ID ~= "" and tostring(user_id)==ADMIN_ID then return true end
  local a = getChatAdministrators(chat_id)
  for _,x in ipairs(a) do
    if tostring(x.user.id)==tostring(user_id) then return true end
  end
  return false
end

local function inRank(state, rank, user_id)
  return state.ranks[rank][tostring(user_id)] and true or false
end

local function anyPrivileged(state, chat_id, user_id)
  return isAdmin(chat_id, user_id) or inRank(state,"developer",user_id)
      or inRank(state,"super_creator",user_id) or inRank(state,"creator",user_id)
      or inRank(state,"owner2",user_id) or inRank(state,"manager",user_id)
      or inRank(state,"admin",user_id)
end

local function isImmune(state, user_id)
  return state.immunes[tostring(user_id)] and true or false
end

local function label(flag, name)
  return (flag and "✅ " or "❌ ")..name
end

-- ========= لوحات =========
local function lock_keyboard(state)
  local L = state.locks
  return {
    inline_keyboard = {
      {
        {text=label(L.chat, "قفل الدردشة"), callback_data="t:chat"},
        {text=label(L.photos, "الصور"), callback_data="t:photos"},
      },{
        {text=label(L.documents, "الملفات/ميديا"), callback_data="t:documents"},
        {text=label(L.forward, "التوجيه"), callback_data="t:forward"},
      },{
        {text=label(L.stickers, "الملصقات/GIF"), callback_data="t:stickers"},
        {text=label(L.links, "الروابط"), callback_data="t:links"},
      },{
        {text=label(L.voice, "الصوتيات"), callback_data="t:voice"},
        {text=label(L.edit, "التعديل"), callback_data="t:edit"},
      },
      -- الجديدة
      {
        {text=label(L.flood, "التفليش"), callback_data="t:flood"},
        {text=label(L.spam, "الكلايش"), callback_data="t:spam"},
      },{
        {text=label(L.english, "الإنجليزية"), callback_data="t:english"},
        {text=label(L.pin, "التثبيت"), callback_data="t:pin"},
      },{
        {text=label(L.contacts,"الجهات"), callback_data="t:contacts"},
        {text=label(L.fwd,"إرسال بواسطة قناة"), callback_data="t:fwd"},
      },{
        {text=label(L.location,"الموقع"), callback_data="t:location"},
        {text=label(L.profanity,"الكفر"), callback_data="t:profanity"},
      },{
        {text=label(L.nsfw,"الإباحي"), callback_data="t:nsfw"},
        {text=label(L.noise,"التشويش"), callback_data="t:noise"},
      },{
        {text=label(L.premium_stickers,"ملصقات مميزة"), callback_data="t:premium_stickers"},
        {text=label(L.media_edit,"تعديل الميديا"), callback_data="t:media_edit"},
      }
    }
  }
end

local function rights_keyboard(chat_id, user_id)
  -- جلب حقوق المشرف الحالية
  local code, body = GET("/getChatMember?chat_id="..tostring(chat_id).."&user_id="..tostring(user_id))
  local p = {}
  if code==200 then
    local d = json.decode(body)
    if d and d.ok then p = d.result or {} end
  end
  local function has(field) return p[field] and true or false end
  local function mark(b,t) return (b and "✅ " or "❌ ")..t end
  return {
    inline_keyboard = {
      {
        {text=mark(has("can_restrict_members"),"صلاحية حظر"), callback_data="pr:"..user_id..":can_restrict_members"},
        {text=mark(has("can_invite_users"),"دعوة"), callback_data="pr:"..user_id..":can_invite_users"},
      },{
        {text=mark(has("can_change_info"),"تغيير معلومات مجموعة"), callback_data="pr:"..user_id..":can_change_info"},
        {text=mark(has("can_promote_members"),"رفع مشرفين"), callback_data="pr:"..user_id..":can_promote_members"},
      },{
        {text=mark(has("can_manage_video_chats"),"إدارة اتصال"), callback_data="pr:"..user_id..":can_manage_video_chats"},
        {text=mark(has("can_delete_messages"),"حذف الرسائل"), callback_data="pr:"..user_id..":can_delete_messages"},
      }
    }
  }
end

-- ========= أدوات نص =========
local function normalize_username(s)
  if not s then return nil end
  s = s:gsub("^@","")
  if s=="" then return nil end
  return s
end

-- ========= أوامر الرتب العامة =========
local RANKS_ORDER = {"developer","super_creator","creator","owner2","manager","admin","special"}
local RANKS_TITLES = {
  developer="مطور", super_creator="منشئ أساسي", creator="منشئ",
  owner2="مالك ثاني", manager="مدير", admin="أدمن", special="مميز"
}

local function rank_list_text(state, rank)
  local t = {}
  for uid,_ in pairs(state.ranks[rank]) do table.insert(t, uid) end
  table.sort(t)
  if #t==0 then return "لا يوجد أحد في قائمة: "..RANKS_TITLES[rank] end
  local lines = {"قائمة "..RANKS_TITLES[rank]..":"}
  for _,uid in ipairs(t) do table.insert(lines, "• <code>"..uid.."</code>") end
  return table.concat(lines, "\n")
end

local function list_keyboard(tag) -- لمسح قائمة كاملة
  return { inline_keyboard = { { {text="🗑️ مسح الكل", callback_data="clrlist:"..tag} } } }
end

-- ========= أوامر مخصصة وردود =========
local function list_map_text(map, title)
  local t = {}; for k,_ in pairs(map) do table.insert(t, k) end
  table.sort(t)
  if #t==0 then return "لا توجد "..title end
  local lines = {"قائمة "..title..":"}
  for _,k in ipairs(t) do table.insert(lines, "• "..k) end
  return table.concat(lines, "\n")
end

local function wipe_keyboard(tag)
  return { inline_keyboard = { { {text="🗑️ مسح الكل", callback_data="wipe:"..tag} } } }
end

-- ========= بطاقة ايدي =========
local function get_user_profile(user_id)
  local c1,b1 = GET("/getUserProfilePhotos?user_id="..tostring(user_id).."&limit=1")
  local file_id, count = nil, 0
  if c1==200 then
    local d = json.decode(b1)
    if d and d.ok then
      count = d.result.total_count or 0
      local ph = d.result.photos and d.result.photos[1]
      if ph then
        local last = ph[#ph]; file_id = last and last.file_id or nil
      end
    end
  end
  -- bio
  local bio = "-"
  local c2,b2 = GET("/getChat?chat_id="..tostring(user_id))
  if c2==200 then
    local d = json.decode(b2); if d and d.ok then bio = d.result.bio or "-" end
  end
  return file_id, count, bio
end

local function id_card(msg)
  local u = msg.from
  local uname = u.username and ("@"..u.username) or "—"
  local name  = (u.first_name or "")..((u.last_name and (" "..u.last_name)) or "")
  local file_id, count, bio = get_user_profile(u.id)
  local caption = ("<b>الاسم:</b> %s\n<b>المعرف:</b> %s\n<b>ID:</b> <code>%s</code>\n<b>عدد الصور:</b> %d\n<b>البايو:</b> %s")
    :format(name, uname, tostring(u.id), count or 0, bio or "-")
  local kb = { inline_keyboard = { { {text="• بواسطة: "..(uname~="—" and uname or (u.first_name or "مستخدم")), callback_data="noop"} } } }
  if file_id then
    POST("sendPhoto", { chat_id = msg.chat.id, photo = file_id, caption = caption, parse_mode="HTML", reply_markup = kb })
  else
    sendMessage(msg.chat.id, caption, kb, "HTML")
  end
end

-- ========= رابط المجموعة =========
local function get_group_link(state, chat)
  if (state.linkType or "invite")=="public" and chat.username then
    return "https://t.me/"..chat.username
  end
  local c,b = POST("createChatInviteLink", { chat_id = chat.id })
  if c==200 then
    local d=json.decode(b); if d and d.ok and d.result then return d.result.invite_link end
  end
  return "⚠️ تعذر جلب رابط المجموعة."
end

local function link_type_keyboard(state)
  local cur = state.linkType or "invite"
  local function mark(opt,title) return (cur==opt and "✅ " or "❌ ")..title end
  return { inline_keyboard = {
    { {text=mark("invite","رابط بطلب انضمام"), callback_data="linkset:invite"},
      {text=mark("public","رابط عام"), callback_data="linkset:public"} }
  } }
end

-- ========= فلترة/تنفيذ القيود =========
local function has_url(text, entities)
  if not text then return false end
  if text:match("https?://") or text:match("t%.me/") then return true end
  if entities then for _,e in ipairs(entities) do if e.type=="url" or e.type=="text_link" then return true end end end
  return false
end

local function is_english_only(text)
  if not text or text=="" then return false end
  local s = text:gsub("[%s%p%d]","")
  if s=="" then return false end
  return s:match("^[A-Za-z]+$") ~= nil
end

local function is_profanity(text)
  if not text then return false end
  local list = {"fuck","bitch","shit","كس","عاهرة","قحب","نياك","كسم"} -- عينة، يمكنك توسعتها
  local t = text:lower()
  for _,w in ipairs(list) do if t:find(w,1,true) then return true end end
  return false
end

local function is_nsfw(msg)
  if not msg then return false end
  local cap = (msg.caption or ""):lower()
  local t = (msg.text or ""):lower()
  local s = cap.." "..t
  local keys = {"porn","sex","سكس","اباحي","جماع"} -- تبسيط
  for _,k in ipairs(keys) do if s:find(k,1,true) then return true end end
  return false
end

local function enforce_rules(state, msg)
  if msg.chat.type=="private" then return end
  local cid = msg.chat.id
  local uid = msg.from and msg.from.id

  if isImmune(state, uid) or isAdmin(cid, uid) or inRank(state,"developer",uid) then return end

  local L = state.locks

  -- قفل الدردشة العام
  if L.chat then deleteMessage(cid, msg.message_id); return end

  -- صور / ملفات / صوتيات
  if L.photos and (msg.photo or (msg.document and msg.document.mime_type and msg.document.mime_type:match("^image/"))) then
    deleteMessage(cid, msg.message_id); return
  end
  if L.documents and (msg.document or msg.video or msg.audio or msg.animation) then
    deleteMessage(cid, msg.message_id); return
  end
  if L.voice and (msg.voice or msg.video_note) then
    deleteMessage(cid, msg.message_id); return
  end

  -- توجيه وروابط
  if L.forward and (msg.forward_from or msg.forward_from_chat) then
    deleteMessage(cid, msg.message_id); return
  end
  if L.links and has_url(msg.text, msg.entities) then
    deleteMessage(cid, msg.message_id); return
  end

  -- الجديدة:
  if L.english and msg.text and is_english_only(msg.text) then
    deleteMessage(cid, msg.message_id); return
  end
  if L.contacts and msg.contact then deleteMessage(cid, msg.message_id); return end
  if L.location and msg.location then deleteMessage(cid, msg.message_id); return end
  if L.profanity and is_profanity(msg.text or msg.caption) then deleteMessage(cid, msg.message_id); return end
  if L.nsfw and is_nsfw(msg) then deleteMessage(cid, msg.message_id); return end
  if L.premium_stickers and msg.sticker and msg.sticker.is_video then deleteMessage(cid, msg.message_id); return end
  if L.media_edit and msg.edit_date then deleteMessage(cid, msg.message_id); return end
  -- التفليش/الكلايش/التشويش تبسيط (يمكن توسعة لاحقاً)
  if L.spam and msg.text and #msg.text>1000 then deleteMessage(cid, msg.message_id); return end
end

-- ========= رفع/تنزيل + حظر/كتم =========
local function set_rank(state, rank, user_id, val)
  if state.ranks[rank] then
    if val then state.ranks[rank][tostring(user_id)] = true else state.ranks[rank][tostring(user_id)] = nil end
  end
end

local function promote_to_admin(chat_id, user_id)
  return POST("promoteChatMember", {
    chat_id=chat_id, user_id=user_id,
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

local function demote_from_admin(chat_id, user_id)
  return POST("promoteChatMember", {
    chat_id=chat_id, user_id=user_id,
    can_manage_chat=false, can_delete_messages=false,
    can_manage_video_chats=false, can_restrict_members=false,
    can_promote_members=false, can_change_info=false,
    can_invite_users=false, can_pin_messages=false
  })
end

local function send_promoted_with_rights_button(chat_id, target_user_id)
  local kb = { inline_keyboard = { { {text="تعديل صلاحيات المستخدم", callback_data="rights:"..tostring(target_user_id)} } } }
  sendMessage(chat_id, "✅ تم رفعه مشرف.", kb, "HTML")
end

-- ========= أوامر نصية =========
local function parse_id_from_text_or_reply(msg, tail)
  if msg.reply_to_message and msg.reply_to_message.from then
    return msg.reply_to_message.from.id
  end
  local id = tonumber((msg.text or ""):gsub("^%s*"..tail,"%1"):match("(%d+)$") or "")
  return id
end

local function username_to_id(chat_id, username)
  username = normalize_username(username)
  if not username then return nil end
  -- API ما يوفر تحويل مباشر بدون DB؛ نكتفي بالرد/ID مباشر.
  return nil
end

-- ========= حلقة تحديث =========
local offset = 0

-- رسالة تفعيل عند إضافة البوت/ترقيته
local function activationMessage(chat, actor)
  local title = chat.title or (chat.username and ("@"..chat.username)) or "مجموعة"
  local who   = (actor and (actor.username and ("@"..actor.username) or actor.first_name)) or "مستخدم"
  local text  = ("✅ <b>تم تفعّيلي تلقائيًا</b>\nالمجموعة: <b>%s</b>\n(ID: <code>%s</code>)"):format(title, tostring(chat.id))
  local kb = { inline_keyboard = { { {text="• بواسطة: "..who.." •", callback_data="noop"} } } }
  sendMessage(chat.id, text, kb, "HTML")
end

while true do
  local code, body = GET("/getUpdates?timeout=30&offset="..tostring(offset))
  if code ~= 200 then
    print("⚠️ مشكلة اتصال.. انتظر 5 ثوانٍ"); os.execute("sleep 5")
  else
    local up = json.decode(body) or {}
    for _,u in ipairs(up.result or {}) do
      offset = u.update_id + 1

      -- تغيّر حالة البوت بالمجموعة
      if u.my_chat_member and BOT_ID then
        local m = u.my_chat_member
        if m.new_chat_member and tostring(m.new_chat_member.user.id)==BOT_ID then
          if m.new_chat_member.status=="administrator" or m.new_chat_member.status=="member" then
            local st = load_state(m.chat.id); save_state(m.chat.id, st)
            activationMessage(m.chat, m.from)
          end
        end
      end

      -- أزرار
      if u.callback_query then
        local cq = u.callback_query
        local data = cq.data or ""
        local msg  = cq.message or {}
        local cid  = msg.chat and msg.chat.id
        local mid  = msg.message_id
        local uid  = cq.from and cq.from.id
        if not cid then goto continue_cb end
        local st = load_state(cid)

        if data=="noop" then
          answerCallbackQuery(cq.id, " ")

        elseif data:match("^t:") then
          if not isAdmin(cid, uid) and not inRank(st,"manager",uid) and tostring(uid)~=ADMIN_ID then
            answerCallbackQuery(cq.id, "⚠️ للأدمنية فقط")
          else
            local key = data:sub(3)
            if st.locks[key] ~= nil then
              st.locks[key] = not st.locks[key]
              save_state(cid, st)
              if key=="chat" then setChatPermissions(cid, not st.locks.chat) end
              editMarkup(cid, mid, lock_keyboard(st))
              answerCallbackQuery(cq.id, "تم التبديل")
            end
          end

        elseif data:match("^linkset:") then
          if not isAdmin(cid, uid) then
            answerCallbackQuery(cq.id, "⚠️ للمشرفين فقط")
          else
            local typ = data:gsub("^linkset:","")
            st.linkType = (typ=="public") and "public" or "invite"
            save_state(cid, st)
            editMarkup(cid, mid, link_type_keyboard(st))
            answerCallbackQuery(cq.id, "تم التحديد")
          end

        elseif data:match("^rights:%d+$") then
          if not isAdmin(cid, uid) then
            answerCallbackQuery(cq.id, "⚠️ للمشرفين فقط")
          else
            local target = tonumber(data:match("rights:(%d+)"))
            editMarkup(cid, mid, rights_keyboard(cid, target))
            answerCallbackQuery(cq.id, "لوحة الصلاحيات")
          end

        elseif data:match("^pr:%d+:[%w_]+$") then
          if not isAdmin(cid, uid) then
            answerCallbackQuery(cq.id, "⚠️ للمشرفين فقط")
          else
            local tuid, field = data:match("^pr:(%d+):([%w_]+)$")
            tuid = tonumber(tuid)
            local c,_ = POST("promoteChatMember", {
              chat_id=cid, user_id=tuid,
              can_manage_chat = true,
              can_delete_messages = (field=="can_delete_messages") and true or nil,
              can_manage_video_chats = (field=="can_manage_video_chats") and true or nil,
              can_restrict_members = (field=="can_restrict_members") and true or nil,
              can_promote_members = (field=="can_promote_members") and true or nil,
              can_change_info = (field=="can_change_info") and true or nil,
              can_invite_users = (field=="can_invite_users") and true or nil,
              can_pin_messages = true
            })
            if c==200 then
              editMarkup(cid, mid, rights_keyboard(cid, tuid))
              answerCallbackQuery(cq.id, "تم التبديل")
            else
              answerCallbackQuery(cq.id, "فشل التبديل", true)
            end
          end

        elseif data=="leave_yes" then
          if tostring(uid)==ADMIN_ID then
            sendMessage(cid, "🚪 تم مغادرتي للمجموعة. إلى اللقاء!")
            GET("/leaveChat?chat_id="..tostring(cid))
          else
            answerCallbackQuery(cq.id, "للمطور فقط", true)
          end

        elseif data=="leave_no" then
          if tostring(uid)==ADMIN_ID or isAdmin(cid, uid) then
            answerCallbackQuery(cq.id, "تم الإلغاء")
            sendMessage(cid, "❌ تم إلغاء عملية المغادرة.")
          end

        elseif data:match("^clrlist:") then
          local tag = data:gsub("^clrlist:","")
          if not isAdmin(cid, uid) then
            answerCallbackQuery(cq.id, "للمشرفين فقط")
          else
            if st.ranks[tag] then st.ranks[tag] = {} end
            save_state(cid, st)
            answerCallbackQuery(cq.id, "تم المسح")
            editMessageText(cid, mid, "تم مسح قائمة "..(RANKS_TITLES[tag] or tag), list_keyboard(tag))
          end

        elseif data:match("^wipe:") then
          local tag = data:gsub("^wipe:","")
          if not isAdmin(cid, uid) then
            answerCallbackQuery(cq.id, "للمشرفين فقط")
          else
            if tag=="replies" then st.replies = {}
            elseif tag=="custom_cmds" then st.custom_cmds = {}
            elseif tag=="banned" then st.banned = {}
            elseif tag=="muted" then st.muted = {}
            end
            save_state(cid, st)
            answerCallbackQuery(cq.id, "تم المسح")
            editMessageText(cid, mid, "تم مسح: "..tag, wipe_keyboard(tag))
          end
        end
        ::continue_cb::
      end

      -- رسائل
      if u.message then
        local msg = u.message
        local chat = msg.chat
        local cid = chat.id
        local st = load_state(cid)
        local text = msg.text

        -- تفعيل عند دخول البوت
        if msg.new_chat_members and BOT_ID then
          for _, nm in ipairs(msg.new_chat_members) do
            if tostring(nm.id)==BOT_ID then
              activationMessage(chat, msg.from)
            end
          end
        end

        -- تطبيق قيود
        enforce_rules(st, msg)

        -- تنفيذ ردود مخصصة
        if text and st.replies[text] then
          sendMessage(cid, st.replies[text])
        end

        -- تنفيذ أوامر مضافة
        if text and st.custom_cmds[text] then
          sendMessage(cid, st.custom_cmds[text])
        end

        -- أوامر
        if text then
          -- start
          if text=="/start" then
            sendMessage(cid, "✅ البوت شغال بالمجموعة.\nأرسل /lock لعرض لوحة الحماية.\n- /id لبطاقة معلوماتك\n- اكتب: الرابط / /تحديد الرابط", nil, "HTML")

          elseif text=="/id" or text=="ايدي" or text=="/ايدي" then
            id_card(msg)

          -- لوحة القفل
          elseif text=="/lock" then
            if isAdmin(cid, msg.from.id) or inRank(st,"manager",msg.from.id) or tostring(msg.from.id)==ADMIN_ID then
              sendMessage(cid, "لوحة الحماية — بدّل الحالات بالضغط على الأزرار:", lock_keyboard(st))
            else
              sendMessage(cid, "⚠️ الأمر للمشرفين فقط.")
            end

          -- رابط
          elseif text=="/الرابط" or text=="الرابط" then
            sendMessage(cid, get_group_link(st, chat))
          elseif text=="/تحديد الرابط" then
            if isAdmin(cid, msg.from.id) then
              sendMessage(cid, "شنو نوع الرابط تريد تحدده؟", link_type_keyboard(st))
            end

          -- مغادرة مؤكد (للمطور)
          elseif (text=="غادر البوت" or text=="/leave") and tostring(msg.from.id)==ADMIN_ID then
            local kb = { inline_keyboard = { { {text="✅ تأكيد المغادرة", callback_data="leave_yes"}, {text="❌ إلغاء", callback_data="leave_no"} } } }
            sendMessage(cid, "⚠️ هل أنت متأكد من مغادرة البوت؟", kb)

          -- رفع/تنزيل رتب (بالرد أو id)
          elseif text:match("^رفع%s+") or text:match("^تنزيل%s+") then
            local is_up   = text:match("^رفع%s+")
            local is_down = text:match("^تنزيل%s+")
            local rank_word = (text:gsub("^%S+%s+","")):match("^(%S+)")
            local targets = msg.reply_to_message and msg.reply_to_message.from and msg.reply_to_message.from.id
            local rank_map = {
              ["مميز"]="special", ["ادمن"]="admin", ["أدمن"]="admin", ["مدير"]="manager",
              ["مالك"]="owner2", ["مالك%س*ثاني"]="owner2",
              ["منشئ"]="creator", ["منشئ%س*أساسي"]="super_creator", ["منشى"]="creator", ["منشى%س*اساسي"]="super_creator",
              ["مطور"]="developer"
            }

            -- تحديد الرتبة
            local sel
            for k,v in pairs(rank_map) do
              if rank_word and rank_word:match("^"..k.."$") then sel = v end
            end
            if not sel then
              sendMessage(cid, "اكتب: رفع/تنزيل <مميز|أدمن|مدير|مالك ثاني|منشئ|منشئ أساسي|مطور> وبالرد أو ID.")
            else
              local uid = targets or tonumber(text:match("(%d+)$"))
              if not uid then sendMessage(cid, "رد على المستخدم أو اكتب ID.") else
                if is_up then set_rank(st, sel, uid, true)
                elseif is_down then set_rank(st, sel, uid, false) end
                save_state(cid, st)
                sendMessage(cid, (is_up and "✅ تم رفع الرتبة: " or "✅ تم تنزيل الرتبة: ")..(RANKS_TITLES[sel] or sel))
                -- لو رفعناه أدمن حقيقي
                if is_up and sel=="admin" then
                  local c,_ = promote_to_admin(cid, uid)
                  if c==200 then
                    local kb = { inline_keyboard = { { {text="تعديل صلاحيات المستخدم", callback_data="rights:"..tostring(uid)} } } }
                    sendMessage(cid, "✅ تم منحه صلاحيات أدمن.", kb)
                  else
                    sendMessage(cid, "⚠️ تعذر منحه صلاحيات أدمن عبر API — تأكد صلاحيات البوت.")
                  end
                end
                if is_down and sel=="admin" then demote_from_admin(cid, uid) end
              end
            end

          -- قوائم الرتب
          elseif text:match("^قائمة%s+") then
            local which = text:gsub("^قائمة%s+","")
            local back = {
              ["المميزين"]="special", ["الادمنيه"]="admin", ["الأدمنية"]="admin", ["المدراء"]="manager",
              ["المالكين"]="owner2", ["المنشئين"]="creator", ["المنشئين الاساسيين"]="super_creator",
              ["المطورين"]="developer"
            }
            local sel = back[which]
            if not sel then
              sendMessage(cid, "اكتب: قائمة المميزين/الادمنيه/المدراء/المالكين/المنشئين/المنشئين الاساسيين/المطورين")
            else
              sendMessage(cid, rank_list_text(st, sel), list_keyboard(sel), "HTML")
            end

          -- حظر/طرد/كتم وإدارتهم
          elseif text:match("^حظر") or text:match("^طرد") or text:match("^كتم") or text:match("^الغاء%s+كتم") or text:match("^الغاء%s+حظر") then
            if not isAdmin(cid, msg.from.id) and not inRank(st,"admin",msg.from.id) then
              sendMessage(cid, "⚠️ للمشرفين فقط"); goto nextmsg
            end
            local target = msg.reply_to_message and msg.reply_to_message.from and msg.reply_to_message.from.id
            target = target or tonumber(text:match("(%d+)$"))
            if not target then sendMessage(cid, "رد على المستخدم أو اكتب ID."); goto nextmsg end

            if text:match("^حظر") then
              st.banned[tostring(target)] = true; save_state(cid, st)
              kick(cid, target); sendMessage(cid, "⛔ تم حظر <code>"..target.."</code>", nil, "HTML")
            elseif text:match("^طرد") then
              kick(cid, target); unban(cid, target); sendMessage(cid, "🚪 تم طرد <code>"..target.."</code>", nil, "HTML")
            elseif text:match("^كتم") then
              st.muted[tostring(target)] = true; save_state(cid, st)
              restrictMute(cid, target, true); sendMessage(cid, "🔇 تم كتم <code>"..target.."</code>", nil, "HTML")
            elseif text:match("^الغاء%s+كتم") then
              st.muted[tostring(target)] = nil; save_state(cid, st)
              restrictMute(cid, target, false); sendMessage(cid, "🔊 تم إلغاء كتم <code>"..target.."</code>", nil, "HTML")
            elseif text:match("^الغاء%s+حظر") then
              st.banned[tostring(target)] = nil; save_state(cid, st)
              unban(cid, target); sendMessage(cid, "✅ تم إلغاء حظر <code>"..target.."</code>", nil, "HTML")
            end

          elseif text=="قائمة المكتومين" then
            local keys = {}; for k,_ in pairs(st.muted) do table.insert(keys, k) end
            table.sort(keys)
            local out = {"قائمة المكتومين:"}; for _,k in ipairs(keys) do table.insert(out, "• <code>"..k.."</code>") end
            if #keys==0 then out = {"لا يوجد مكتومين"} end
            sendMessage(cid, table.concat(out, "\n"), wipe_keyboard("muted"), "HTML")

          elseif text=="قائمة المحظورين" then
            local keys = {}; for k,_ in pairs(st.banned) do table.insert(keys, k) end
            table.sort(keys)
            local out = {"قائمة المحظورين:"}; for _,k in ipairs(keys) do table.insert(out, "• <code>"..k.."</code>") end
            if #keys==0 then out = {"لا يوجد محظورين"} end
            sendMessage(cid, table.concat(out, "\n"), wipe_keyboard("banned"), "HTML")

          -- أوامر مضافة
          elseif text:match("^اضف%s+امر%s+") then
            if not isAdmin(cid, msg.from.id) then sendMessage(cid, "للمشرفين فقط"); goto nextmsg end
            local name, reply = text:match("^اضف%s+امر%s+(.+)%s*=%s*(.+)$")
            if name and reply then
              st.custom_cmds[name] = reply; save_state(cid, st)
              sendMessage(cid, "✅ تمت إضافة الأمر: "..name)
            else
              sendMessage(cid, "الصيغة: اضف امر <النص> = <الرد>")
            end

          elseif text:match("^حذف%s+امر%s+") then
            if not isAdmin(cid, msg.from.id) then sendMessage(cid, "للمشرفين فقط"); goto nextmsg end
            local name = text:gsub("^حذف%s+امر%s+","")
            if st.custom_cmds[name] then st.custom_cmds[name]=nil; save_state(cid, st); sendMessage(cid, "✅ تم حذف الأمر: "..name)
            else sendMessage(cid, "❌ الأمر غير موجود: "..name) end

          elseif text=="الاوامر المضافة" then
            sendMessage(cid, list_map_text(st.custom_cmds, "الأوامر المضافة"), wipe_keyboard("custom_cmds"))

          -- الردود
          elseif text:match("^اضف%s+رد%s+") then
            if not isAdmin(cid, msg.from.id) then sendMessage(cid, "للمشرفين فقط"); goto nextmsg end
            local key, val = text:match("^اضف%s+رد%s+(.+)%s*=%s*(.+)$")
            if key and val then
              st.replies[key] = val; save_state(cid, st)
              sendMessage(cid, "✅ تم إضافة رد.")
            else
              sendMessage(cid, "الصيغة: اضف رد <الكلمة> = <الرد>")
            end

          elseif text:match("^حذف%s+رد%s+") then
            if not isAdmin(cid, msg.from.id) then sendMessage(cid, "للمشرفين فقط"); goto nextmsg end
            local key = text:gsub("^حذف%s+رد%s+","")
            if st.replies[key] then st.replies[key]=nil; save_state(cid, st); sendMessage(cid, "✅ تم حذف الرد.")
            else sendMessage(cid, "❌ الرد غير موجود.") end

          elseif text=="قائمة الردود" then
            sendMessage(cid, list_map_text(st.replies, "الردود"), wipe_keyboard("replies"))

          -- تفعيل/تعطيل قفل الدردشة كأمر اختصار
          elseif text=="قفل الدردشة" then
            if isAdmin(cid, msg.from.id) then
              st.locks.chat = true; save_state(cid, st); setChatPermissions(cid, false)
              sendMessage(cid, "✅ تم قفل الدردشة")
            end
          elseif text=="فتح الدردشة" then
            if isAdmin(cid, msg.from.id) then
              st.locks.chat = false; save_state(cid, st); setChatPermissions(cid, true)
              sendMessage(cid, "✅ تم فتح الدردشة")
            end
          end
          ::nextmsg::
        end

        -- حذف تعديل إذا قفل التعديل
        if u.edited_message then
          local em = u.edited_message
          if st.locks.edit and not isAdmin(cid, em.from.id) and not isImmune(st, em.from.id) then
            deleteMessage(cid, em.message_id)
          end
        end
      end
    end
  end
end