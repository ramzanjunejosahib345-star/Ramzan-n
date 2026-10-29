-- KSR_PLUGIN_ID: voice_cleaner
-- KSR_VERSION: 2
-- ضروری: اپنی گِٹ ہب فائل کا Raw لنک نیچے لکھیں
VCL_UPDATE_URL = ""
require "import"
import "android.app.*"
import "android.widget.*"
import "android.view.*"
import "android.content.*"
import "android.os.Build"
import "android.net.Uri"

-- ================= Voice Cleaner (آواز صاف کرنے والا) v1.0 =================
-- Developer: Mohammad Ramzan Qadri
-- کسی بھی آڈیو سے شور اور خاموشی ہٹا کر صرف آپ کی آواز صاف کرتا ہے۔

local sdk = 0
pcall(function() sdk = Build.VERSION.SDK_INT end)
local function say(t) pcall(function() service.speak(t) end) end

local LINK_GROUP    = "https://chat.whatsapp.com/D6xZRT6trDk1mOJctpYopl"
local LINK_CHANNEL  = "https://youtube.com/@junejaproduction9565"
local LINK_FEEDBACK = "https://wa.me/923000144024"

local Array     = luajava.bindClass("java.lang.reflect.Array")
local ByteC     = luajava.bindClass("java.lang.Byte")
local ShortC    = luajava.bindClass("java.lang.Short")
local FileC     = luajava.bindClass("java.io.File")
local ByteBuf   = luajava.bindClass("java.nio.ByteBuffer")
local MC        = luajava.bindClass("android.media.MediaCodec")
local BI        = luajava.bindClass("android.media.MediaCodec$BufferInfo")
local MFmt      = luajava.bindClass("android.media.MediaFormat")
local MEx       = luajava.bindClass("android.media.MediaExtractor")
local MMux      = luajava.bindClass("android.media.MediaMuxer")
local MMR       = luajava.bindClass("android.media.MediaMetadataRetriever")
local NO        = luajava.bindClass("java.nio.ByteOrder").nativeOrder()
local Env       = luajava.bindClass("android.os.Environment")
local Handler   = luajava.bindClass("android.os.Handler")
local Looper    = luajava.bindClass("android.os.Looper")

local uiHandler = Handler(Looper.getMainLooper())
local function later(ms, fn)
  local ok = pcall(function()
    uiHandler.postDelayed(luajava.createProxy("java.lang.Runnable", {run = function() pcall(fn) end}), ms)
  end)
  if not ok then pcall(fn) end
end
local function post_ui(fn) later(0, fn) end

local function nowMs()
  local ok, v = pcall(function() return luajava.bindClass("java.lang.System").currentTimeMillis() end)
  if ok and v then return tonumber(v) end
  return os.time() * 1000
end

local function showDlg(d)
  pcall(function()
    if sdk >= 22 then d.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
    else d.getWindow().setType(WindowManager.LayoutParams.TYPE_SYSTEM_ALERT) end
  end)
  local ok = pcall(function() d.show() end)
  if not ok then
    pcall(function()
      if sdk >= 26 then d.getWindow().setType(WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY)
      else d.getWindow().setType(WindowManager.LayoutParams.TYPE_SYSTEM_ALERT) end
      d.show()
    end)
  end
end

local function deviceInfo()
  local s = ""
  pcall(function() s = tostring(Build.MANUFACTURER) .. " " .. tostring(Build.MODEL) .. " Android " .. tostring(Build.VERSION.RELEASE) .. " SDK " .. tostring(sdk) end)
  return s
end

local lastAction = "-"
local function copyText(t)
  pcall(function()
    local cm = service.getSystemService(Context.CLIPBOARD_SERVICE)
    cm.setPrimaryClip(luajava.bindClass("android.content.ClipData").newPlainText("report", t))
  end)
end

-- خرابی کا ڈائیلاگ: نیچے "کاپی کریں" سے پوری رپورٹ کاپی ہوتی ہے
local function showFail(msg)
  local report = "Voice Cleaner v1.0\n" .. deviceInfo() .. "\nبٹن: " .. tostring(lastAction) .. "\nخرابی: " .. tostring(msg)
  pcall(function()
    local b = AlertDialog.Builder(service)
    b.setTitle("کام ناکام")
    b.setMessage(tostring(msg))
    b.setPositiveButton("بند کریں", nil)
    b.setNeutralButton("خرابی کاپی کریں", DialogInterface.OnClickListener({onClick = function(d, w)
      copyText(report)
      say("خرابی کی تفصیل کاپی ہو گئی")
    end}))
    showDlg(b.create())
  end)
end

local function isUri(s) return tostring(s):sub(1, 10) == "content://" end

-- فائل کا راستہ ہو یا content:// پتہ، دونوں پر کام کرتا ہے
local function setSrc(obj, src, kind)
  if isUri(src) then
    if kind == "ex" then obj.setDataSource(service, Uri.parse(src), nil)
    else obj.setDataSource(service, Uri.parse(src)) end
  else
    obj.setDataSource(src)
  end
end

local function sizeOf(p)
  local n = 0
  pcall(function()
    if isUri(p) then
      local afd = service.getContentResolver().openAssetFileDescriptor(Uri.parse(p), "r")
      n = tonumber(afd.getLength()) or 0
      afd.close()
    else
      n = tonumber(FileC(p).length()) or 0
    end
  end)
  return n
end

local function geti(f, key, def)
  local v = def
  pcall(function() if f.containsKey(key) then v = tonumber(f.getInteger(key)) or def end end)
  return v
end

-- ---------------- فائلوں کی فہرست ----------------
local ROOT = ""
pcall(function() ROOT = tostring(Env.getExternalStorageDirectory().getAbsolutePath()) end)
if ROOT == "" then ROOT = "/sdcard" end

local function extOf(n)
  local e = tostring(n):match("%.([%w]+)$")
  return e and e:lower() or ""
end

local function scanDir(dir, exts, out, depth)
  pcall(function()
    local l = FileC(dir).listFiles()
    if l == nil then return end
    local n = tonumber(Array.getLength(l))
    for i = 0, n - 1 do
      local f = l[i]
      local name = tostring(f.getName())
      if f.isDirectory() then
        if depth < 2 and name:sub(1, 1) ~= "." and name ~= "Android" then
          scanDir(tostring(f.getAbsolutePath()), exts, out, depth + 1)
        end
      elseif exts[extOf(name)] then
        local p = tostring(f.getAbsolutePath())
        out[#out + 1] = {path = p, src = p, name = name, t = tonumber(f.lastModified()) or 0}
      end
    end
  end)
end

local VEXT = {mp4 = true, m4v = true, mov = true, ["3gp"] = true, mkv = true, webm = true}
local AEXT = {mp3 = true, m4a = true, aac = true, wav = true, ogg = true, opus = true, amr = true, flac = true}

-- MediaStore سے فہرست (اندرونی میموری اور میموری کارڈ دونوں، ہر اینڈرائیڈ ورژن میں)
local function queryStore(isVideo, out)
  pcall(function()
    local coll
    if isVideo then coll = luajava.bindClass("android.provider.MediaStore$Video$Media").EXTERNAL_CONTENT_URI
    else coll = luajava.bindClass("android.provider.MediaStore$Audio$Media").EXTERNAL_CONTENT_URI end
    local cols = Array.newInstance(luajava.bindClass("java.lang.String"), 4)
    cols[0] = "_id"; cols[1] = "_display_name"; cols[2] = "_data"; cols[3] = "date_modified"
    local cur = service.getContentResolver().query(coll, cols, nil, nil, "date_modified DESC")
    if cur == nil then return end
    local n = 0
    while cur.moveToNext() and n < 400 do
      n = n + 1
      pcall(function()
        local id = tonumber(cur.getLong(0))
        local name = tostring(cur.getString(1))
        local data = cur.getString(2)
        local t = (tonumber(cur.getLong(3)) or 0) * 1000
        local ex = extOf(name)
        local ok = isVideo and VEXT[ex] or ((not isVideo) and AEXT[ex])
        if ok then
          local src = nil
          if data ~= nil then
            local p = tostring(data)
            local readable = false
            pcall(function() readable = FileC(p).canRead() end)
            if readable then src = p end
          end
          if src == nil then
            src = tostring(luajava.bindClass("android.content.ContentUris").withAppendedId(coll, id).toString())
          end
          out[#out + 1] = {path = data and tostring(data) or nil, src = src, name = name, t = t}
        end
      end)
    end
    cur.close()
  end)
end

local function collect(isVideo, exts, dirs)
  local out = {}
  queryStore(isVideo, out)
  if #out == 0 then
    for _, d in ipairs(dirs) do scanDir(ROOT .. "/" .. d, exts, out, 0) end
  end
  table.sort(out, function(a, b) return a.t > b.t end)
  local seen, res = {}, {}
  for _, f in ipairs(out) do
    local key = f.path or f.src
    if not seen[key] and #res < 120 then seen[key] = true; res[#res + 1] = f end
  end
  return res
end


-- ---------------- آڈیو سورس (ڈیکوڈ + چینل + ریٹ) ----------------
local function openSource(path)
  local S = {}
  local ex = MEx()
  S.ex = ex
  setSrc(ex, path, "ex")
  local ti, fmt, mime
  for i = 0, tonumber(ex.getTrackCount()) - 1 do
    local f = ex.getTrackFormat(i)
    local m = f.getString("mime")
    if m ~= nil and tostring(m):sub(1, 6) == "audio/" then ti = i; fmt = f; mime = tostring(m); break end
  end
  if not ti then pcall(function() ex.release() end); return nil end
  ex.selectTrack(ti)
  local rate = geti(fmt, "sample-rate", 44100)
  local ch = geti(fmt, "channel-count", 2)
  local rawMode = (mime == "audio/raw")
  local dec, info, rb
  if rawMode then
    if geti(fmt, "pcm-encoding", 2) ~= 2 then
      pcall(function() ex.release() end)
      error("یہ WAV فائل 16 بٹ نہیں ہے")
    end
    rb = ByteBuf.allocateDirect(65536)
  else
    dec = MC.createDecoderByType(mime)
    S.dec = dec
    dec.configure(fmt, nil, nil, 0)
    dec.start()
    info = BI()
  end

  local raw, rawN, rawPos = {}, 0, 1
  local arr, arrCap = nil, 0
  local inDone, outDone = false, false

  local function take(sb)
    local n = tonumber(sb.remaining())
    if n > arrCap then arr = Array.newInstance(ShortC.TYPE, n); arrCap = n end
    sb.get(arr, 0, n)
    for i = 0, n - 1 do raw[i + 1] = arr[i] end
    rawN = n; rawPos = 1
    return n
  end

  local function refill()
    if rawMode then
      while not outDone do
        rb.clear()
        local sz = tonumber(ex.readSampleData(rb, 0))
        if sz < 0 then outDone = true; return false end
        ex.advance()
        rb.position(0); rb.limit(sz)
        local n = take(rb.order(NO).asShortBuffer())
        if n > 0 then return true end
      end
      return false
    end
    local guard = 0
    while not outDone do
      guard = guard + 1
      if guard > 20000 then error("ڈیکوڈر جواب نہیں دے رہا") end
      if not inDone then
        local ii = tonumber(dec.dequeueInputBuffer(5000))
        if ii >= 0 then
          local ib = dec.getInputBuffer(ii)
          local sz = tonumber(ex.readSampleData(ib, 0))
          if sz < 0 then
            dec.queueInputBuffer(ii, 0, 0, 0, 4); inDone = true
          else
            dec.queueInputBuffer(ii, 0, sz, ex.getSampleTime(), 0); ex.advance()
          end
        end
      end
      local oi = tonumber(dec.dequeueOutputBuffer(info, 5000))
      if oi >= 0 then
        local size, flags = tonumber(info.size), tonumber(info.flags)
        local got = 0
        if size > 0 then
          local ob = dec.getOutputBuffer(oi)
          ob.position(info.offset); ob.limit(info.offset + size)
          got = take(ob.order(NO).asShortBuffer())
        end
        dec.releaseOutputBuffer(oi, false)
        if (flags & 4) ~= 0 then outDone = true end
        if got > 0 then return true end
      elseif oi == -2 then
        local nf = dec.getOutputFormat()
        rate = geti(nf, "sample-rate", rate)
        ch = geti(nf, "channel-count", ch)
      end
    end
    return false
  end

  -- پہلا ٹکڑا پڑھ کر اصلی ریٹ اور چینل معلوم کریں
  if not refill() then
    S.close = function() end
    pcall(function() if dec then dec.stop(); dec.release() end end)
    pcall(function() ex.release() end)
    error("آڈیو ڈیکوڈ نہیں ہو سکی")
  end
  S.rate = rate
  S.ch = ch

  local dr, dc, step, direct = rate, 2, 1, true
  local started, finished = false, false
  local pl, pr, cl, cr, acc = 0, 0, 0, 0, 0

  local function conv()
    while rawPos > rawN do
      if not refill() then return nil end
      S.rate = rate; S.ch = ch
    end
    local a = raw[rawPos]
    local b = raw[rawPos + 1] or a
    rawPos = rawPos + ch
    if dc == 1 then
      local m = (a + b) // 2
      return m, m
    end
    return a, b
  end

  function S.setTarget(r, c)
    dr = r; dc = c
    direct = (rate == r)
    step = rate / r
    started = false; finished = false; acc = 0
  end

  function S.getFrame()
    if finished then return nil end
    if direct then
      local a, b = conv()
      if a == nil then finished = true; return nil end
      return a, b
    end
    if not started then
      cl, cr = conv()
      if cl == nil then finished = true; return nil end
      pl, pr = cl, cr; acc = 0; started = true
    end
    local l = pl + (cl - pl) * acc
    local r = pr + (cr - pr) * acc
    acc = acc + step
    while acc >= 1 do
      pl, pr = cl, cr
      local a, b = conv()
      if a == nil then finished = true; break end
      cl, cr = a, b
      acc = acc - 1
    end
    return l, r
  end

  function S.close()
    pcall(function() if dec then dec.stop() end end)
    pcall(function() if dec then dec.release() end end)
    pcall(function() ex.release() end)
  end
  return S
end

local STEP_MS = 45

-- ---------------- فائل کاپی / محفوظ (قدم بہ قدم) ----------------
local function copyAsync(fi, fo, cb)
  local buf = Array.newInstance(ByteC.TYPE, 262144)
  local done = false
  local function finish(ok, err)
    if done then return end
    done = true
    pcall(function() fi.close() end)
    pcall(function() fo.close() end)
    cb(ok, err)
  end
  local function tick()
    if done then return end
    local t1 = nowMs()
    local ok, res = pcall(function()
      while nowMs() - t1 < 40 do
        local n = tonumber(fi.read(buf))
        if n == nil or n < 0 then return true end
        fo.write(buf, 0, n)
      end
      return false
    end)
    if not ok then finish(false, res)
    elseif res == true then finish(true)
    else later(1, tick) end
  end
  later(1, tick)
end

-- ڈاؤن لوڈ فولڈر یا شیئر کے لیے MediaStore میں محفوظ کرتا ہے (sdk 29+)
local function openStoreTarget(name, toDownloads, isAudio)
  if sdk >= 29 then
    local CV = luajava.newInstance("android.content.ContentValues")
    CV.put("_display_name", name)
    CV.put("mime_type", isAudio and "audio/mp4" or "video/mp4")
    local coll
    if toDownloads then
      CV.put("relative_path", "Download/")
      coll = luajava.bindClass("android.provider.MediaStore$Downloads").EXTERNAL_CONTENT_URI
    else
      if isAudio then
        CV.put("relative_path", "Music/Mohammad Ramzan Qadri")
        coll = luajava.bindClass("android.provider.MediaStore$Audio$Media").EXTERNAL_CONTENT_URI
      else
        CV.put("relative_path", "Movies/Mohammad Ramzan Qadri")
        coll = luajava.bindClass("android.provider.MediaStore$Video$Media").EXTERNAL_CONTENT_URI
      end
    end
    local res = service.getContentResolver()
    local uri = res.insert(coll, CV)
    if uri == nil then error("MediaStore نے فائل نہیں بنائی") end
    return uri, res.openOutputStream(uri)
  else
    local dir = ROOT .. (toDownloads and "/Download" or (isAudio and "/Music/Mohammad Ramzan Qadri" or "/Movies/Mohammad Ramzan Qadri"))
    FileC(dir).mkdirs()
    local dst = dir .. "/" .. name
    local fo = luajava.newInstance("java.io.FileOutputStream", dst)
    return luajava.bindClass("android.net.Uri").fromFile(FileC(dst)), fo
  end
end


-- ---------------- صفائی کا کام (دو مرحلے: جانچ، پھر صفائی) ----------------
local RATE = 16000
local FR = 320          -- 20 ملی سیکنڈ
local LOOK = 3          -- آگے دیکھنے والے فریم (60 ملی سیکنڈ)
local HANG = 10         -- آواز کے بعد 200 ملی سیکنڈ تک گیٹ کھلا رہے

local function startClean(path, tmp, st, opt, onFinish)
  local R = {}
  local finished = false
  local function cleanup()
    pcall(function() if R.src then R.src.close() end end)
    pcall(function() if R.enc then R.enc.stop() end end)
    pcall(function() if R.enc then R.enc.release() end end)
    pcall(function() if R.mux and R.muxStarted then R.mux.stop() end end)
    pcall(function() if R.mux then R.mux.release() end end)
  end
  local function finish(ok, err, info)
    if finished then return end
    finished = true
    cleanup()
    if not ok then
      pcall(function() FileC(tmp).delete() end)
      onFinish(false, tostring(err))
    else
      onFinish(true, info or "")
    end
  end

  local okSetup, errSetup = pcall(function()
    local HPA = 0.969
    local phase = 1
    local rmsList, nR = {}, 0
    local acc, cnt = 0, 0
    local hpX, hpY = 0, 0
    local totalIn = 0
    local bg = opt.bg or 0
    -- پس منظر کی آوازوں کے لیے اونچی آوازیں (پرندے وغیرہ) کاٹنے والا فلٹر
    local lpN = 0
    local lpC = {}
    if bg > 0 then
      local fc = (bg == 1) and 5000 or 3600
      lpN = (bg == 1) and 1 or 2
      local w0 = 2 * math.pi * fc / RATE
      local al = math.sin(w0) / (2 * 0.7071)
      local cw = math.cos(w0)
      local a0 = 1 + al
      local b0 = (1 - cw) / 2 / a0
      lpC = {b0, (1 - cw) / a0, b0, -2 * cw / a0, (1 - al) / a0}
    end
    local lpS = {}
    local function resetF()
      hpX, hpY = 0, 0
      for i = 1, 2 do lpS[i] = {0, 0, 0, 0} end
    end
    resetF()
    local function filt(a)
      local y = HPA * (hpY + a - hpX)
      hpX = a; hpY = y
      for i = 1, lpN do
        local s4 = lpS[i]
        local o = lpC[1] * y + lpC[2] * s4[1] + lpC[3] * s4[2] - lpC[4] * s4[3] - lpC[5] * s4[4]
        s4[2] = s4[1]; s4[1] = y
        s4[4] = s4[3]; s4[3] = o
        y = o
      end
      return y
    end

    local src = openSource(path)
    if not src then error("اس آڈیو میں آواز نہیں ملی") end
    src.setTarget(RATE, 1)
    R.src = src

    -- ---- مرحلہ 1: جانچ ----
    local function analyze(deadline)
      while nowMs() < deadline do
        for i = 1, 1500 do
          local a = src.getFrame()
          if a == nil then
            if cnt > 0 then nR = nR + 1; rmsList[nR] = math.sqrt(acc / cnt) end
            return true
          end
          local y = filt(a)
          acc = acc + y * y; cnt = cnt + 1; totalIn = totalIn + 1
          if cnt >= FR then nR = nR + 1; rmsList[nR] = math.sqrt(acc / cnt); acc = 0; cnt = 0 end
        end
      end
      return false
    end

    -- ---- مرحلہ 2 کے متغیر ----
    local thr, normG = 0, 1
    local Q, S = {}, {}
    local fiNext, kOut = 1, 1          -- کتنے فریم پڑھے، اگلا آؤٹ پٹ فریم
    local srcDone = false
    local gPrev = 0
    local silRun = 0
    local chunks, chunkHead, chunkTail = {}, 1, 0
    local framesOut = 0
    local binfo = BI()
    local enc, mux
    local inputDone, eos = false, false
    local audioTrack = -1
    local keepFrames = opt.keepFrames or 12
    local removeSil = opt.removeSil
    local droppedFrames = 0

    local function setupPass2()
      table.sort(rmsList)
      local m = nR
      if m < 5 then error("آڈیو بہت چھوٹی ہے") end
      local noise = rmsList[math.max(1, math.floor(m * 0.10))]
      local speech = rmsList[math.max(1, math.floor(m * 0.95))]
      if speech < 25 then error("آڈیو میں آواز بہت کم یا خاموش ہے") end
      local frac = ({0.12, 0.2, 0.32})[(opt.sens or 1) + 1] or 0.2
      thr = noise + frac * (speech - noise)
      if thr < noise * 1.4 then thr = noise * 1.4 end
      if thr < 10 then thr = 10 end
      if bg > 0 then
        local ratio = (bg == 1) and 0.2 or 0.33
        if speech * ratio > thr then thr = speech * ratio end
      end
      if opt.normalize then
        normG = 6500 / speech
        if normG < 0.7 then normG = 0.7 elseif normG > 6 then normG = 6 end
      end
      rmsList = nil
      -- دوبارہ کھولیں
      pcall(function() src.close() end)
      src = openSource(path)
      if not src then error("آڈیو دوبارہ نہیں کھل سکی") end
      src.setTarget(RATE, 1)
      R.src = src
      resetF()

      local efmt = MFmt.createAudioFormat("audio/mp4a-latm", RATE, 1)
      efmt.setInteger("aac-profile", 2)
      efmt.setInteger("bitrate", 48000)
      efmt.setInteger("max-input-size", 65536)
      enc = MC.createEncoderByType("audio/mp4a-latm"); R.enc = enc
      enc.configure(efmt, nil, nil, 1)
      enc.start()
      mux = MMux(tmp, 0); R.mux = mux
      phase = 2
    end

    -- ایک فریم پڑھ کر قطار میں ڈالنا
    local function produce()
      local fr, c, sum = {}, 0, 0
      while c < FR do
        local a = src.getFrame()
        if a == nil then srcDone = true; break end
        local y = filt(a)
        c = c + 1; fr[c] = y; sum = sum + y * y
      end
      if c == 0 then return false end
      for i = c + 1, FR do fr[i] = 0 end
      local rms = math.sqrt(sum / c)
      Q[fiNext] = fr
      S[fiNext] = (rms > thr)
      fiNext = fiNext + 1
      return true
    end

    local function activeAt(k)
      for j = k - HANG, k + LOOK do
        if S[j] then return true end
      end
      return false
    end

    -- ایک آؤٹ پٹ فریم تیار کر کے chunks میں ڈالنا
    local function emit(k)
      local fr = Q[k]
      local act = activeAt(k)
      local gT
      if act then gT = normG; silRun = 0 else gT = 0; silRun = silRun + 1 end
      Q[k - HANG - 2] = nil; S[k - HANG - 2] = nil
      if (not act) and removeSil and silRun > keepFrames then
        droppedFrames = droppedFrames + 1
        gPrev = 0
        return
      end
      local arr = Array.newInstance(ShortC.TYPE, FR)
      local g0 = gPrev
      local step = (gT - g0) / FR
      local g = g0
      for i = 1, FR do
        g = g + step
        local v = fr[i] * g
        if v > 24000 then v = 24000 + (v - 24000) * 0.3 elseif v < -24000 then v = -24000 + (v + 24000) * 0.3 end
        if v > 32767 then v = 32767 elseif v < -32768 then v = -32768 end
        arr[i - 1] = math.floor(v + 0.5)
      end
      gPrev = gT
      chunkTail = chunkTail + 1
      chunks[chunkTail] = arr
    end

    local function pending() return chunkTail - chunkHead + 1 end

    local function feed()
      if inputDone then return end
      local canEos = srcDone and kOut >= fiNext and pending() == 0
      if pending() == 0 and not canEos then return end
      local ii = tonumber(enc.dequeueInputBuffer(2000))
      if ii < 0 then return end
      local ib = enc.getInputBuffer(ii)
      ib.clear()
      local sb = ib.order(NO).asShortBuffer()
      local room = math.floor(tonumber(ib.capacity()) / 2)
      local total = 0
      while pending() > 0 and total + FR <= room do
        local arr = chunks[chunkHead]
        chunks[chunkHead] = nil
        chunkHead = chunkHead + 1
        sb.put(arr, 0, FR)
        total = total + FR
      end
      local pts = math.floor(framesOut * 1000000 / RATE)
      if total == 0 then
        enc.queueInputBuffer(ii, 0, 0, pts, 4); inputDone = true
      else
        enc.queueInputBuffer(ii, 0, total * 2, pts, 0)
        framesOut = framesOut + total
      end
    end

    local function drain()
      local first = true
      while true do
        local oi = tonumber(enc.dequeueOutputBuffer(binfo, (first and inputDone) and 5000 or 0))
        first = false
        if oi == -2 then
          if not R.muxStarted then
            audioTrack = tonumber(mux.addTrack(enc.getOutputFormat()))
            mux.start(); R.muxStarted = true
          end
        elseif oi >= 0 then
          local size, flags = tonumber(binfo.size), tonumber(binfo.flags)
          if size > 0 and (flags & 2) == 0 and R.muxStarted then
            local ob = enc.getOutputBuffer(oi)
            ob.position(binfo.offset); ob.limit(binfo.offset + size)
            mux.writeSampleData(audioTrack, ob, binfo)
          end
          enc.releaseOutputBuffer(oi, false)
          if (flags & 4) ~= 0 then eos = true; break end
        elseif oi ~= -3 then
          break
        end
      end
    end

    R.progress = function()
      if phase == 1 then return "جانچ: " .. math.floor(totalIn / RATE) .. " سیکنڈ پڑھے گئے" end
      return "صفائی: " .. math.floor(framesOut / RATE) .. " سیکنڈ تیار"
    end

    R.step = function()
      local t1 = nowMs()
      if st.cancel then error("منسوخ کر دیا گیا") end
      if phase == 1 then
        if analyze(t1 + STEP_MS) then setupPass2() end
        return false
      end
      while nowMs() - t1 < STEP_MS do
        if st.cancel then error("منسوخ کر دیا گیا") end
        if eos then
          if framesOut == 0 then error("صفائی کے بعد کوئی آواز نہیں بچی۔ حساسیت ہلکی کریں") end
          if not R.muxStarted then error("آڈیو انکوڈ نہیں ہو سکی") end
          R.infoDur = framesOut / RATE
          R.dropped = droppedFrames
          return true
        end
        -- فریم بنانا جب تک قطار چھوٹی ہے
        local guard = 0
        while pending() < 24 and guard < 4 do
          guard = guard + 1
          if not srcDone then produce() end
          -- جتنے فریم ممکن ہوں آؤٹ پٹ کریں
          while (fiNext - 1 >= kOut + LOOK) or (srcDone and kOut < fiNext) do
            emit(kOut); kOut = kOut + 1
          end
          if srcDone then break end
        end
        feed()
        drain()
      end
      return false
    end
    R.phaseOf = function() return phase end
    R.runAnalyze = true
  end)
  if not okSetup then finish(false, errSetup) return end

  local lastSay = 0
  local function tick()
    if finished then return end
    local ok, res = pcall(R.step)
    if not ok then finish(false, res) return end
    if res then
      local d = R.infoDur or 0
      finish(true, "", {dur = d, dropped = R.dropped or 0})
    else
      local t = nowMs()
      if t - lastSay > 15000 then
        lastSay = t
        pcall(function() if st.onProgress then st.onProgress(R.progress()) end end)
      end
      later(1, tick)
    end
  end
  later(1, tick)
end


-- ---------------- UI ----------------
local state = {running = false, cancel = false, outPath = nil, outName = nil}
local alist = {}
local dlg, tvStatus, spA, etA, spSens, spSil, spKeep, spNorm, spBg

local function mkSpinner(items, sel)
  local sp = Spinner(service)
  local list = luajava.newInstance("java.util.ArrayList")
  for _, s in ipairs(items) do list.add(s) end
  local RL = luajava.bindClass("android.R$layout")
  local ad = luajava.newInstance("android.widget.ArrayAdapter", service, RL.simple_spinner_item, list)
  pcall(function() ad.setDropDownViewResource(RL.simple_spinner_dropdown_item) end)
  sp.setAdapter(ad)
  if sel then sp.setSelection(sel) end
  return sp
end

local function label(parent, text)
  local tv = TextView(service)
  tv.setText(text)
  tv.setTextSize(16)
  tv.setPadding(0, 18, 0, 4)
  parent.addView(tv, LinearLayout.LayoutParams(-1, -2))
  return tv
end

local function addBtn(parent, text, fn)
  local b = Button(service)
  b.setText(text)
  b.setOnClickListener(View.OnClickListener({onClick = function(v)
    lastAction = text
    local ok, e = pcall(fn)
    if not ok then showFail(e) end
  end}))
  parent.addView(b, LinearLayout.LayoutParams(-1, -2))
  return b
end

local function setStatus(t)
  pcall(function() tvStatus.setText(t) end)
end

local function names(list)
  local t = {}
  for _, f in ipairs(list) do t[#t + 1] = f.name end
  if #t == 0 then t[1] = "(کوئی فائل نہیں ملی)" end
  return t
end

local function refreshLists()
  alist = collect(false, AEXT, {"Music", "Download", "Documents", "Recordings", "Voice Recorder", "Sounds", "Notifications", "Movies"})
end

local function pick(sp, list, et)
  local p = ""
  pcall(function() p = tostring(et.getText()):gsub("^%s+", ""):gsub("%s+$", "") end)
  if p ~= "" then return p end
  local i = tonumber(sp.getSelectedItemPosition()) or 0
  if list[i + 1] then return list[i + 1].src end
  return nil
end

local player, playingWhat = nil, nil
local function stopPreview()
  if player then
    pcall(function() player.stop() end)
    pcall(function() player.release() end)
    player = nil
  end
  playingWhat = nil
end

local function togglePreview(kind, path)
  if state.running then say("کام جاری ہے، مکمل ہونے دیں یا منسوخ کریں"); return end
  if player and playingWhat == kind then
    stopPreview(); say("رک گیا"); setStatus("پریویو بند"); return
  end
  stopPreview()
  if not path then say("پہلے فائل چنیں"); return end
  local nm = tostring(path):match("([^/]+)$") or path
  local ok, e = pcall(function()
    local mp = luajava.newInstance("android.media.MediaPlayer")
    player = mp
    setSrc(mp, path)
    mp.prepare()
    mp.setOnCompletionListener(luajava.createProxy("android.media.MediaPlayer$OnCompletionListener", {
      onCompletion = function(m) pcall(stopPreview); pcall(function() setStatus("پریویو ختم") end) end
    }))
    mp.start()
    playingWhat = kind
  end)
  if ok then
    setStatus("چل رہا ہے: " .. nm .. "۔ روکنے کے لیے یہی بٹن دوبارہ دبائیں")
    say("چل رہی ہے۔ " .. nm)
  else
    stopPreview()
    setStatus("چل نہیں سکی: " .. tostring(e)); say("یہ فائل چل نہیں سکی")
  end
end

local function cancelAll()
  stopPreview()
  if state.running then
    state.cancel = true
    setStatus("منسوخ کیا جا رہا ہے، چند لمحے")
    say("منسوخ کیا جا رہا ہے")
  else
    setStatus("منسوخ: کچھ نہیں چل رہا تھا")
    say("منسوخ")
  end
end

local function mbText(n) return string.format("%.1f", n / 1048576) end
local function minText(sec)
  sec = math.floor(sec)
  return string.format("%d منٹ %d سیکنڈ", sec // 60, sec % 60)
end

-- ---------------- خودکار اپڈیٹ (گِٹ ہب سے) ----------------
local PLUGIN_ID = "voice_cleaner"
local VERSION = 2
local UPDATE_URL = ""
pcall(function() if VCL_UPDATE_URL ~= nil then UPDATE_URL = tostring(VCL_UPDATE_URL) end end)

local prefs = nil
pcall(function() prefs = service.getSharedPreferences("ksr_vcl", Context.MODE_PRIVATE) end)
local function getPref(k, d)
  local v = d
  pcall(function() local r = prefs.getString(k, d) if r ~= nil then v = tostring(r) end end)
  return v
end
local function setPref(k, v) pcall(function() prefs.edit().putString(k, tostring(v)).apply() end) end

local function run_bg(fn)
  local T = luajava.bindClass("java.lang.Thread")
  T(luajava.createProxy("java.lang.Runnable", {run = function() pcall(fn) end})).start()
end

local function http_get_bytes(url)
  local u = luajava.newInstance("java.net.URL", url)
  local conn = u.openConnection()
  conn.setConnectTimeout(6000)
  conn.setReadTimeout(10000)
  pcall(function() conn.setRequestProperty("User-Agent", "Mozilla/5.0") end)
  local code = tonumber(conn.getResponseCode())
  if code ~= 200 then error("سرور سے جواب نہیں ملا (HTTP " .. tostring(code) .. ")") end
  local ins = conn.getInputStream()
  local bo = luajava.newInstance("java.io.ByteArrayOutputStream")
  local buf = Array.newInstance(ByteC.TYPE, 16384)
  local ok, e = pcall(function()
    while true do
      local n = tonumber(ins.read(buf))
      if n == nil or n < 0 then break end
      bo.write(buf, 0, n)
    end
  end)
  pcall(function() ins.close() end)
  if not ok then error(e) end
  return bo.toByteArray()
end

-- اپنی فائل پلگ ان فولڈر میں نشان (KSR_PLUGIN_ID) سے ڈھونڈنا
local function find_self()
  local base = ROOT
  local roots = {base .. "/解说/Plugins", base .. "/解说", base .. "/Download/AndroLua+", base .. "/AndroLua+", base .. "/Download", base .. "/Documents"}
  local marker = "KSR_PLUGIN_ID: " .. PLUGIN_ID
  local found = nil
  local function scan(dir, depth)
    if found then return end
    pcall(function()
      local l = FileC(dir).listFiles()
      if l == nil then return end
      for i = 0, tonumber(Array.getLength(l)) - 1 do
        local f = l[i]
        if f.isDirectory() then
          if depth < 2 then scan(tostring(f.getAbsolutePath()), depth + 1) end
        else
          local nm = tostring(f.getName()):lower()
          local len = tonumber(f.length()) or 0
          if (nm:match("%.txt$") or nm:match("%.lua$")) and len > 1000 and len < 3000000 then
            local okr, head = pcall(function()
              local fi = luajava.newInstance("java.io.FileInputStream", f)
              local b = Array.newInstance(ByteC.TYPE, 600)
              local n = tonumber(fi.read(b)) or 0
              fi.close()
              return tostring(luajava.newInstance("java.lang.String", b, 0, math.max(n, 0), "UTF-8"))
            end)
            if okr and head:find(marker, 1, true) then found = tostring(f.getAbsolutePath()) return end
          end
        end
      end
    end)
  end
  for _, r in ipairs(roots) do scan(r, 0); if found then break end end
  return found
end

local updating = false
local function check_update(manual)
  if UPDATE_URL == "" then
    if manual then say("اپڈیٹ کا لنک ابھی سیٹ نہیں ہوا۔") end
    return
  end
  if updating then if manual then say("اپڈیٹ کی جانچ جاری ہے۔") end return end
  updating = true
  setPref("lastcheck", nowMs())
  if manual then say("اپڈیٹ کی جانچ ہو رہی ہے، انتظار کریں۔") end
  run_bg(function()
    local ok, res = pcall(function()
      local bytes = http_get_bytes(UPDATE_URL)
      local text = tostring(luajava.newInstance("java.lang.String", bytes, "UTF-8"))
      local id = text:match("KSR_PLUGIN_ID:%s*([%w_]+)")
      local ver = tonumber(text:match("KSR_VERSION:%s*(%d+)"))
      if id ~= PLUGIN_ID or not ver then error("لنک والی فائل اس پلگ ان کی نہیں ہے") end
      if ver <= VERSION then return "latest" end
      local chunk = load(text)
      if not chunk then error("نئی فائل میں خرابی ملی، اپڈیٹ نہیں کی گئی") end
      local path = find_self()
      if not path then error("پلگ ان کی اپنی فائل پلگ ان فولڈر میں نہیں ملی") end
      -- بیک اپ ایپ کے اپنے فولڈر میں
      pcall(function()
        local bdir = service.getExternalFilesDir(nil) or service.getFilesDir()
        local fi = luajava.newInstance("java.io.FileInputStream", FileC(path))
        local fo = luajava.newInstance("java.io.FileOutputStream", FileC(bdir, PLUGIN_ID .. "_backup.txt"))
        local b = Array.newInstance(ByteC.TYPE, 16384)
        while true do
          local n = tonumber(fi.read(b))
          if n == nil or n < 0 then break end
          fo.write(b, 0, n)
        end
        fi.close(); fo.close()
      end)
      local fo = luajava.newInstance("java.io.FileOutputStream", FileC(path))
      local okw, ew = pcall(function() fo.write(bytes) fo.flush() end)
      pcall(function() fo.close() end)
      if not okw then error("نئی فائل لکھی نہیں جا سکی: " .. tostring(ew)) end
      local want = tonumber(Array.getLength(bytes))
      local got = tonumber(FileC(path).length())
      if want ~= got then error("فائل مکمل نہیں لکھی گئی، بیک اپ ایپ کے فولڈر میں موجود ہے") end
      return "updated:" .. ver
    end)
    post_ui(function()
      updating = false
      if ok and tostring(res):find("^updated") then
        local msg = "پلگ ان اپڈیٹ ہو گیا۔ نیا ورژن " .. tostring(res):sub(9) .. "۔ اب اسے بند کر کے دوبارہ چلائیں۔"
        setStatus(msg); say(msg)
      elseif ok then
        if manual then say("آپ کے پاس تازہ ترین ورژن ہے۔"); setStatus("آپ کے پاس تازہ ترین ورژن ہے۔") end
      else
        if manual then say("اپڈیٹ ناکام۔ " .. tostring(res)); setStatus("اپڈیٹ ناکام: " .. tostring(res)) end
      end
    end)
  end)
end


-- ---------------- اباؤٹ ----------------
local function openLink(url)
  local ok = pcall(function()
    local it = Intent(Intent.ACTION_VIEW, Uri.parse(url))
    it.addFlags(268435456)
    service.startActivity(it)
  end)
  if not ok then say("لنک نہیں کھل سکا") end
end

local function showAbout()
  local sv = ScrollView(service)
  local lay = LinearLayout(service)
  lay.setOrientation(1)
  lay.setPadding(30, 30, 30, 30)
  sv.addView(lay, LinearLayout.LayoutParams(-1, -2))
  local t = TextView(service)
  t.setText("آواز صاف کرنے والا (ورژن 1." .. tostring(VERSION) .. ")")
  t.setTextSize(22)
  lay.addView(t, LinearLayout.LayoutParams(-1, -2))
  label(lay, "کسی بھی آڈیو سے پس منظر کا شور اور بے فائدہ خاموشی ہٹاتا ہے، تاکہ آپ کی آواز صاف رہے۔")
  label(lay, "ڈویلپر: محمد رمضان قادری")
  local ad
  addBtn(lay, "Developer Feedback", function() openLink(LINK_FEEDBACK) end)
  addBtn(lay, "Join WhatsApp Group", function() openLink(LINK_GROUP) end)
  addBtn(lay, "Subscribe YouTube Channel", function() openLink(LINK_CHANNEL) end)
  addBtn(lay, "بند کریں", function() pcall(function() ad.dismiss() end) end)
  local b = AlertDialog.Builder(service)
  b.setView(sv)
  ad = b.create()
  showDlg(ad)
  say("اباؤٹ کھل گیا۔ اس میں ڈویلپر فیڈبیک، واٹس ایپ گروپ اور یوٹیوب چینل کے بٹن ہیں۔")
end



local function startClean_job()
  if state.running then say("پہلے کام جاری ہے، مکمل ہونے دیں یا منسوخ کریں"); return end
  local ap = pick(spA, alist, etA)
  if not ap then say("پہلے آڈیو چنیں"); setStatus("پہلے آڈیو چنیں"); return end
  local sens = tonumber(spSens.getSelectedItemPosition()) or 1
  local removeSil = (tonumber(spSil.getSelectedItemPosition()) or 0) == 0
  local keepFrames = ({10, 20, 40})[(tonumber(spKeep.getSelectedItemPosition()) or 0) + 1] or 10
  local normalize = (tonumber(spNorm.getSelectedItemPosition()) or 0) == 0
  local bg = tonumber(spBg.getSelectedItemPosition()) or 0

  local tdir
  pcall(function() tdir = tostring(service.getExternalFilesDir(nil).getAbsolutePath()) end)
  if not tdir then pcall(function() tdir = tostring(service.getCacheDir().getAbsolutePath()) end) end
  if not tdir then say("عارضی فولڈر نہیں ملا"); return end
  pcall(function() FileC(tdir).mkdirs() end)
  local name = "clean_" .. os.date("%Y%m%d_%H%M%S") .. ".m4a"
  local tmp = tdir .. "/" .. name

  stopPreview()
  state.cancel = false
  state.running = true
  setStatus("کام شروع ہو گیا ہے۔ آڈیو پہلے جانچی جاتی ہے، پھر صاف ہوتی ہے۔ لمبی آڈیو میں کئی منٹ لگ سکتے ہیں۔")
  say("صفائی شروع ہو گئی ہے۔ انتظار کریں۔")
  state.onProgress = function(t) setStatus(t); say(t) end

  local function showResult(ok, msg, final, where, info)
    state.running = false
    state.onProgress = nil
    if ok then
      state.outPath = final; state.outName = name
      local nOld, nNew = sizeOf(ap), sizeOf(final)
      local t = "آڈیو صاف ہو گئی۔ " .. where .. " محفوظ ہوئی: " .. name
      if info and info.dur then t = t .. "۔ صاف شدہ دورانیہ " .. minText(info.dur) end
      if info and info.dropped and info.dropped > 0 then t = t .. "۔ خاموش حصے ہٹائے گئے: " .. string.format("%.1f", info.dropped * 0.02) .. " سیکنڈ" end
      t = t .. "۔ سائز پہلے " .. mbText(nOld) .. " ایم بی، اب " .. mbText(nNew) .. " ایم بی"
      setStatus(t); say(t)
    else
      if tostring(msg):find("منسوخ", 1, true) then
        setStatus("منسوخ کر دیا گیا"); say("منسوخ کر دیا گیا")
      else
        setStatus("ناکام: " .. tostring(msg)); say("ناکام۔ " .. tostring(msg)); showFail(msg)
      end
    end
  end

  startClean(ap, tmp, state, {sens = sens, removeSil = removeSil, keepFrames = keepFrames, normalize = normalize, bg = bg}, function(ok, info)
    if not ok then
      pcall(function() FileC(tmp).delete() end)
      showResult(false, info)
      return
    end
    local dir = ROOT .. "/Documents/Mohammad Ramzan Qadri"
    local dst = dir .. "/" .. name
    local okO, fi, fo = pcall(function()
      FileC(dir).mkdirs()
      return luajava.newInstance("java.io.FileInputStream", tmp), luajava.newInstance("java.io.FileOutputStream", dst)
    end)
    if okO and fi and fo then
      copyAsync(fi, fo, function(okC)
        if okC and sizeOf(dst) > 0 and sizeOf(dst) == sizeOf(tmp) then
          pcall(function() FileC(tmp).delete() end)
          showResult(true, "", dst, "Documents/Mohammad Ramzan Qadri میں", info)
        else
          pcall(function() FileC(dst).delete() end)
          showResult(true, "", tmp, "ایپ کے فولڈر میں", info)
        end
      end)
    else
      showResult(true, "", tmp, "ایپ کے فولڈر میں", info)
    end
  end)
end

local function doStore(toDownloads, share)
  if state.running then say("کام جاری ہے، مکمل ہونے دیں"); return end
  if not state.outPath then say("ابھی کوئی صاف شدہ آڈیو نہیں ہے۔ پہلے صفائی کریں"); return end
  state.running = true
  setStatus("فائل کاپی ہو رہی ہے، انتظار کریں۔")
  local path, name = state.outPath, state.outName
  local okO, uri, fo = pcall(openStoreTarget, name, toDownloads, true)
  local okI, fi = pcall(function() return luajava.newInstance("java.io.FileInputStream", path) end)
  if not (okO and uri and fo and okI and fi) then
    state.running = false
    local why = (not okO) and tostring(uri) or tostring(fi)
    setStatus("ناکام: " .. why); say("ناکام۔ " .. why); showFail(why)
    return
  end
  copyAsync(fi, fo, function(ok, err)
    state.running = false
    if not ok then
      setStatus("ناکام: " .. tostring(err)); say("ناکام۔ " .. tostring(err)); showFail(err)
      return
    end
    if share then
      local ok2, e2 = pcall(function()
        local it = luajava.newInstance("android.content.Intent", "android.intent.action.SEND")
        it.setType("audio/mp4")
        it.putExtra("android.intent.extra.STREAM", uri)
        it.addFlags(1)
        local ch = Intent.createChooser(it, "Share")
        ch.addFlags(268435456)
        service.startActivity(ch)
      end)
      if ok2 then setStatus("شیئر کی کھڑکی کھل گئی") else setStatus("شیئر ناکام: " .. tostring(e2)); showFail(e2) end
    else
      setStatus("ڈاؤن لوڈ فولڈر میں محفوظ ہو گئی: " .. name)
      say("ڈاؤن لوڈ فولڈر میں محفوظ ہو گئی۔")
    end
  end)
end

local function buildUI()
  refreshLists()
  local sv = ScrollView(service)
  local lay = LinearLayout(service)
  lay.setOrientation(1)
  lay.setPadding(30, 30, 30, 30)
  sv.addView(lay, LinearLayout.LayoutParams(-1, -2))

  local title = TextView(service)
  title.setText("آواز صاف کرنے والا")
  title.setTextSize(22)
  lay.addView(title, LinearLayout.LayoutParams(-1, -2))

  tvStatus = TextView(service)
  tvStatus.setTextSize(16)
  tvStatus.setText("تیار ہے۔ آڈیو چنیں۔")
  tvStatus.setPadding(0, 12, 0, 12)
  lay.addView(tvStatus, LinearLayout.LayoutParams(-1, -2))

  label(lay, "پہلا قدم: آڈیو چنیں (" .. #alist .. " ملیں)")
  spA = mkSpinner(names(alist), 0)
  lay.addView(spA, LinearLayout.LayoutParams(-1, -2))
  label(lay, "یا آڈیو کا پورا راستہ لکھیں (اختیاری)")
  etA = EditText(service)
  lay.addView(etA, LinearLayout.LayoutParams(-1, -2))
  addBtn(lay, "🔊 چنی ہوئی اصل آڈیو سنیں (چلائیں/روکیں)", function() togglePreview("a", pick(spA, alist, etA)) end)

  label(lay, "دوسرا قدم: صفائی کے اختیارات")
  label(lay, "شور ہٹانے کی شدت")
  spSens = mkSpinner({"ہلکی (آواز کو کم چھیڑے)", "درمیانی (عام استعمال)", "سخت (بہت شور ہو تو)"}, 1)
  lay.addView(spSens, LinearLayout.LayoutParams(-1, -2))
  label(lay, "پس منظر کی آوازیں (بچے، پرندے، دور کے لوگ)")
  spBg = mkSpinner({"بند", "درمیانہ: دور کی ہلکی آوازیں کم کریں", "سخت: صرف قریب کی بلند آواز رکھیں"}, 1)
  lay.addView(spBg, LinearLayout.LayoutParams(-1, -2))
  label(lay, "خاموش اور شور والے وقفے")
  spSil = mkSpinner({"ہٹا دیں (دورانیہ کم ہو گا)", "رہنے دیں، صرف شور بند کریں"}, 0)
  lay.addView(spSil, LinearLayout.LayoutParams(-1, -2))
  label(lay, "ہٹاتے وقت جملوں کے درمیان کتنا وقفہ رکھیں")
  spKeep = mkSpinner({"چھوٹا (0.2 سیکنڈ)", "درمیانہ (0.4 سیکنڈ)", "لمبا (0.8 سیکنڈ)"}, 0)
  lay.addView(spKeep, LinearLayout.LayoutParams(-1, -2))
  label(lay, "آواز برابر کریں")
  spNorm = mkSpinner({"ہاں، آواز صاف اور برابر بلند کریں", "نہیں، اصل بلندی رہے"}, 0)
  lay.addView(spNorm, LinearLayout.LayoutParams(-1, -2))

  label(lay, "تیسرا قدم: صفائی")
  addBtn(lay, "▶ آواز صاف کریں", startClean_job)
  addBtn(lay, "⏹ منسوخ کریں", cancelAll)

  label(lay, "چوتھا قدم: نتیجہ سنیں، محفوظ اور شیئر کریں")
  addBtn(lay, "🔊 صاف شدہ آڈیو سنیں (چلائیں/روکیں)", function()
    if not state.outPath then say("ابھی کوئی صاف شدہ آڈیو نہیں ہے۔ پہلے صفائی کریں") return end
    togglePreview("c", state.outPath)
  end)
  addBtn(lay, "⬇ ڈاؤن لوڈ فولڈر میں محفوظ کریں", function() doStore(true, false) end)
  addBtn(lay, "📤 شیئر کریں", function() doStore(false, true) end)

  addBtn(lay, "🔄 فہرست تازہ کریں", function()
    refreshLists()
    pcall(function()
      local RL = luajava.bindClass("android.R$layout")
      local l = luajava.newInstance("java.util.ArrayList")
      for _, s in ipairs(names(alist)) do l.add(s) end
      local ad = luajava.newInstance("android.widget.ArrayAdapter", service, RL.simple_spinner_item, l)
      pcall(function() ad.setDropDownViewResource(RL.simple_spinner_dropdown_item) end)
      spA.setAdapter(ad)
    end)
    setStatus("فہرست تازہ ہو گئی۔ آڈیو: " .. #alist)
  end)
  addBtn(lay, "🔄 اپڈیٹ چیک کریں", function() check_update(true) end)
  addBtn(lay, "ℹ About / اباؤٹ", function() showAbout() end)
  addBtn(lay, "❌ بند کریں", function()
    stopPreview()
    if state.running then state.cancel = true end
    pcall(function() dlg.dismiss() end)
  end)

  local b = AlertDialog.Builder(service)
  b.setView(sv)
  dlg = b.create()
  pcall(function() dlg.setOnDismissListener(luajava.createProxy("android.content.DialogInterface$OnDismissListener", {onDismiss = function(d) pcall(stopPreview); if state.running then state.cancel = true end end})) end)
  showDlg(dlg)
  later(6000, function()
    if UPDATE_URL ~= "" and getPref("autoupd", "1") == "1" then
      local last = tonumber(getPref("lastcheck", "0")) or 0
      if nowMs() - last > 12 * 3600 * 1000 then check_update(false) end
    end
  end)
end

local ok, e = pcall(buildUI)
if ok then
  say("آواز صاف کرنے والا کھل گیا۔")
else
  say("ٹول نہیں کھل سکا۔ " .. tostring(e))
  showFail(e)
end
return true