require "import"
import "android.widget.*"
import "android.view.*"
import "android.media.*"
import "android.net.Uri"
import "android.content.Intent"
import "android.content.ContentUris"
import "android.content.Context"
import "android.provider.MediaStore"
import "android.app.AlertDialog"
import "android.graphics.Color"
import "android.os.Handler"
import "android.os.Looper"
import "java.lang.Runnable"
import "java.io.File"
import "android.os.Build"

activity.setTheme(android.R.style.Theme_Material_Light_NoActionBar)
-- پورٹریٹ میں لاک: گھمانے سے اسکرین دوبارہ نہیں بنتی، اس لیے بٹن غائب یا کریش نہیں ہوتے
pcall(function() activity.setRequestedOrientation(1) end)

allPlayers = {}
playToken = 0
uiHandlers = {}
function newPlayer()
  local p = MediaPlayer()
  allPlayers[#allPlayers + 1] = p
  return p
end
function safeFn(f)
  return function(...)
    local ok, e = pcall(f, ...)
    if not ok then pcall(function() service.speak("Error. " .. string.sub(tostring(e), 1, 100)) end) end
  end
end
player = newPlayer()
audioList, audioNames = {}, {}
videoList, videoNames = {}, {}
favoritesMap = {}

local prefs = activity.getSharedPreferences("MediaPlayerProPrefs", Context.MODE_PRIVATE)

function getAutoRepeatState()
  local state = false
  pcall(function()
    state = prefs.getBoolean("isAutoRepeatOn", false)
  end)
  return state
end

function saveAutoRepeatState(val)
  pcall(function()
    local editor = prefs.edit()
    editor.putBoolean("isAutoRepeatOn", val)
    editor.commit()
  end)
end

function savePosition(keyStr, pos)
  pcall(function()
    local editor = prefs.edit()
    editor.putLong(tostring(keyStr), pos)
    editor.commit()
  end)
end

function getSavedPosition(keyStr)
  local pos = 0
  pcall(function()
    pos = prefs.getLong(tostring(keyStr), 0)
  end)
  return pos
end

function saveLastPlayedInfo(name, uri, path, mediaType)
  pcall(function()
    local editor = prefs.edit()
    editor.putString("lastPlayedName", tostring(name))
    editor.putString("lastPlayedUri", tostring(uri))
    editor.putString("lastPlayedPath", tostring(path))
    editor.putString("lastPlayedType", tostring(mediaType))
    editor.commit()
  end)
end

function getLastPlayedInfo()
  local info = {}
  pcall(function()
    info.name = prefs.getString("lastPlayedName", "")
    info.uri = prefs.getString("lastPlayedUri", "")
    info.path = prefs.getString("lastPlayedPath", "")
    info.type = prefs.getString("lastPlayedType", "")
  end)
  return info
end

function saveJumpSetting(timeVal, timeText)
  pcall(function()
    local editor = prefs.edit()
    editor.putLong("savedJumpTime", timeVal)
    editor.putString("savedJumpText", timeText)
    editor.commit()
  end)
end

function loadJumpSetting()
  pcall(function()
    local tVal = prefs.getLong("savedJumpTime", -1)
    local tText = prefs.getString("savedJumpText", "")
    if tVal ~= -1 and tText ~= "" then
      globalJumpTime = tVal
      globalJumpText = tText
    end
  end)
end

globalJumpTime = 30000 
globalJumpText = "30 Seconds"
loadJumpSetting() 

sleepHandler = Handler(Looper.getMainLooper())
sleepRunnable = nil

function formatTime(ms)
  if not ms or tostring(ms)=="nan" or ms<0 then return "00:00" end
  local s=math.floor(ms/1000)
  local m=math.floor(s/60)
  s=s%60
  return string.format("%02d:%02d",m,s)
end

function speak(t) 
  pcall(function() 
    service.speak(t) 
  end) 
end

-- ہر بنا ہوا پلیئر روکتا اور چھوڑتا ہے، تاکہ کوئی پیچھے چلتا نہ رہ جائے
function releasePlayer()
  playToken = playToken + 1
  pcall(function()
    if sleepRunnable then sleepHandler.removeCallbacks(sleepRunnable) end
  end)
  for _, h in ipairs(uiHandlers) do
    pcall(function() h.removeCallbacksAndMessages(nil) end)
  end
  uiHandlers = {}
  for _, p in ipairs(allPlayers) do
    pcall(function() p.setOnPreparedListener(nil) end)
    pcall(function() p.setOnCompletionListener(nil) end)
    pcall(function() p.setOnErrorListener(nil) end)
    pcall(function() p.stop() end)
    pcall(function() p.reset() end)
    pcall(function() p.release() end)
  end
  allPlayers = {}
  player = newPlayer()
end

function stopMedia(currentKey)
  if not player then player = newPlayer() end
  pcall(function()
    if currentKey and player.isPlaying() then
      savePosition(currentKey, player.getCurrentPosition())
    end
  end)
  pcall(function() player.stop() end)
  pcall(function() player.reset() end)
end

function sortMediaAlphabetically(names, list)
  pcall(function()
    local combined = {}
    for i = 1, #names do
      table.insert(combined, {name = names[i], uri = list[i]})
    end
    table.sort(combined, function(a, b)
      local numA = tonumber(string.match(a.name, "%d+"))
      local numB = tonumber(string.match(b.name, "%d+"))
      
      if numA and numB and numA ~= numB then
        return numA < numB
      else
        return string.lower(a.name) < string.lower(b.name)
      end
    end)
    for i = 1, #combined do
      names[i] = combined[i].name
      list[i] = combined[i].uri
    end
  end)
end

function getStorageFolders(storageType)
  local folders = {}
  local folderMap = {}
  local uris = { MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, MediaStore.Video.Media.EXTERNAL_CONTENT_URI }
  local projection = { MediaStore.MediaColumns.DATA }
  local sortOrder = MediaStore.MediaColumns.DISPLAY_NAME .. " ASC"
  
  pcall(function()
    for _, uri in ipairs(uris) do
      local cursor = activity.getContentResolver().query(uri, projection, nil, nil, sortOrder)
      if cursor ~= nil then
        if cursor.moveToFirst() then
          local columnIndex = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATA)
          repeat
            local path = cursor.getString(columnIndex)
            if path then
              local isSD = path:find("/extsd/") or path:find("/sdcard1/") or path:find("/storage/extSdCard") or (path:find("/storage/") and not path:find("/storage/emulated/"))
              
              local matchStorage = false
              if storageType == "internal" and not isSD then
                matchStorage = true
              elseif storageType == "sdcard" and isSD then
                matchStorage = true
              end
              
              if matchStorage then
                local file = File(path)
                local parentDir = file.getParent()
                if parentDir then
                  if not folderMap[parentDir] then
                    folderMap[parentDir] = true
                    local dirName = File(parentDir).getName()
                    table.insert(folders, { name = dirName, path = parentDir })
                  end
                end
              end
            end
          until not cursor.moveToNext()
        end
        cursor.close()
      end
    end
  end)
  table.sort(folders, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
  return folders
end

function getFilesInSpecificFolder(folderPath)
  local list, names = {}, {}
  local uris = { MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, MediaStore.Video.Media.EXTERNAL_CONTENT_URI }
  local projection = { MediaStore.MediaColumns._ID, MediaStore.MediaColumns.DISPLAY_NAME, MediaStore.MediaColumns.DATA }
  local sortOrder = MediaStore.MediaColumns.DISPLAY_NAME .. " ASC"
  
  pcall(function()
    for _, uri in ipairs(uris) do
      local cursor = activity.getContentResolver().query(uri, projection, nil, nil, sortOrder)
      if cursor ~= nil then
        if cursor.moveToFirst() then
          local dataIndex = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATA)
          local nameIndex = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
          local idIndex = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
          repeat
            local path = cursor.getString(dataIndex)
            if path then
              local file = File(path)
              if file.getParent() == folderPath then
                local name = cursor.getString(nameIndex)
                local id = cursor.getLong(idIndex)
                table.insert(names, name)
                table.insert(list, ContentUris.withAppendedId(uri, id))
              end
            end
          until not cursor.moveToNext()
        end
        cursor.close()
      end
    end
  end)
  sortMediaAlphabetically(names, list)
  return names, list
end

function playCurrentMedia(list,names,index, mediaTypeTag)
  local handler=Handler(Looper.getMainLooper())
  uiHandlers[#uiHandlers + 1] = handler
  local myToken = playToken
  local ui={}
  local isSeeking = false
  local currentUri = list[index]
  local currentPath = tostring(currentUri)
  
  pcall(function()
    local projection = { MediaStore.MediaColumns.DATA }
    local cursor = activity.getContentResolver().query(currentUri, projection, nil, nil, nil)
    if cursor then
      if cursor.moveToFirst() then
        local idx = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
        if idx ~= -1 then
          local p = cursor.getString(idx)
          if p then currentPath = p end
        end
      end
      cursor.close()
    end
  end)

  local isExplicitClose = false

  if not player then
    pcall(function() player = newPlayer() end)
  end

  local runnable
  local function update()
    pcall(function()
      if myToken ~= playToken then return end
      if player and player.isPlaying() then
        local current = player.getCurrentPosition()
        local duration = player.getDuration()
        ui.txtTime.setText(formatTime(current).." / "..formatTime(duration))
        savePosition(currentPath, current)
        if not isSeeking and duration > 0 then
          ui.seekBar.setMax(duration)
          ui.seekBar.setProgress(current)
        end
        handler.postDelayed(runnable,1000)
      end
    end)
  end
  runnable=Runnable({run=update})

  local function loadPlay()
    stopMedia(currentPath)
    currentUri = list[index]
    
    pcall(function()
      local projection = { MediaStore.MediaColumns.DATA }
      local cursor = activity.getContentResolver().query(currentUri, projection, nil, nil, nil)
      if cursor then
        if cursor.moveToFirst() then
          local idx = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
          if idx ~= -1 then
            local p = cursor.getString(idx)
            if p then currentPath = p end
          end
        end
        cursor.close()
      end
    end)

    saveLastPlayedInfo(names[index], tostring(currentUri), currentPath, mediaTypeTag or "media")
    
    local okL, errL = pcall(function()
      if not player then player = newPlayer() end
      player.setDataSource(activity, currentUri)

      player.setOnPreparedListener(MediaPlayer.OnPreparedListener{
        onPrepared=function(mp)
          pcall(function()
            if myToken ~= playToken then return end
            local savedPos = getSavedPosition(currentPath)
            if savedPos and savedPos > 500 then
              mp.seekTo(savedPos)
            end
            mp.start()
            ui.txtTitle.setText(names[index])
            ui.bPlay.setText("Pause")
            pcall(function()
              ui.seekBar.setMax(mp.getDuration())
              ui.seekBar.setProgress(savedPos or 0)
            end)
            update()
          end)
        end
      })

      player.setOnCompletionListener(MediaPlayer.OnCompletionListener{
        onCompletion=function(mp)
          pcall(function()
            if myToken ~= playToken then return end
            if getAutoRepeatState() then
              mp.seekTo(0)
              mp.start()
              ui.bPlay.setText("Pause")
              update()
            else
              savePosition(currentPath, mp.getDuration())
              ui.bPlay.setText("Play")
            end
          end)
        end
      })

      player.setOnErrorListener(MediaPlayer.OnErrorListener{
        onError=function(mp, what, extra)
          pcall(function() speak("This file could not be played") end)
          return true
        end
      })

      player.prepareAsync()
    end)
    if not okL then
      pcall(function() speak("This file could not be opened") end)
    end
  end

  local lay={
    ScrollView, layout_width="match_parent", layout_height="match_parent",
    {LinearLayout,orientation="vertical",padding="10dp",gravity="center",layout_width="match_parent",layout_height="wrap_content",
      {TextView,id="txtTitle",gravity="center",padding="8dp",textSize="16sp",textStyle="bold"},
      {TextView,id="txtTime",text="00:00 / 00:00",textSize="14sp",padding="4dp",gravity="center"},
      {SeekBar,id="seekBar",layout_width="match_parent",padding="8dp"},

      {LinearLayout,orientation="horizontal",gravity="center",layout_width="match_parent",padding="2dp",
        {Button,text="Speed",id="bSpeed",layout_weight=1},
        {Button,text="Timer",id="bTimer",layout_weight=1},
        {Button,text="Previous",id="bPrev",layout_weight=1},
        {Button,text="Rewind\n["..globalJumpText.."]",id="bRew",layout_weight=1},
      },

      {LinearLayout,orientation="horizontal",gravity="center",layout_width="match_parent",padding="2dp",
        {Button,text="Pause",id="bPlay",layout_width="110dp",layout_height="70dp"},
        {Button,text="Forward\n["..globalJumpText.."]",id="bFast",layout_weight=1},
        {Button,text="Next",id="bNext",layout_weight=1},
      },

      {LinearLayout,orientation="horizontal",gravity="center",layout_width="match_parent",padding="2dp",
        {Button,text="Favorite",id="bFav",layout_weight=1},
        {Button,text="Rename",id="bRename",layout_weight=1},
        {Button,text="Share",id="bShare",layout_weight=1},
        {Button,text="Delete",id="bDel",textColor=Color.RED,layout_weight=1},
        {Button,text="Close",id="bClose",layout_weight=1},
      },

      {LinearLayout,orientation="horizontal",gravity="center",layout_width="match_parent",padding="2dp",
        {Button,text="Stop Background Media and Close",id="bStopBg",layout_weight=1},
      },

      {TextView,text="Developer: Mohammad Ramzan Qadri",gravity="center",textSize="12sp",padding="8dp",textColor=Color.GRAY}
    }
  }

  local view=loadlayout(lay,ui)
  
  pcall(function()
    if ui.bSpeed and ui.bSpeed.setImportantForAccessibility then ui.bSpeed.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES) end
    if ui.bTimer and ui.bTimer.setImportantForAccessibility then ui.bTimer.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES) end
    if ui.bPrev and ui.bPrev.setImportantForAccessibility then ui.bPrev.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES) end
    if ui.bRew and ui.bRew.setImportantForAccessibility then ui.bRew.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES) end
    if ui.bPlay and ui.bPlay.setImportantForAccessibility then ui.bPlay.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES) end
    if ui.bFast and ui.bFast.setImportantForAccessibility then ui.bFast.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES) end
    if ui.bNext and ui.bNext.setImportantForAccessibility then ui.bNext.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES) end
    if ui.bFav and ui.bFav.setImportantForAccessibility then ui.bFav.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES) end
    if ui.bRename and ui.bRename.setImportantForAccessibility then ui.bRename.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES) end
    if ui.bShare and ui.bShare.setImportantForAccessibility then ui.bShare.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES) end
    if ui.bDel and ui.bDel.setImportantForAccessibility then ui.bDel.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES) end
    if ui.bClose and ui.bClose.setImportantForAccessibility then ui.bClose.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES) end
    if ui.bStopBg and ui.bStopBg.setImportantForAccessibility then ui.bStopBg.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES) end
  end)

  local dlg=AlertDialog.Builder(activity).setView(view).create()
  
  dlg.setOnDismissListener({
    onDismiss=function()
      pcall(function()
        if isExplicitClose then
          stopMedia(currentPath)
        else
          if player and player.isPlaying() then
            savePosition(currentPath, player.getCurrentPosition())
          end
        end
      end)
    end
  })

  pcall(function() dlg.show() end)
  loadPlay()
  
  ui.seekBar.setOnSeekBarChangeListener(SeekBar.OnSeekBarChangeListener{
    onStartTrackingTouch=function(seekBar)
      isSeeking = true
    end,
    onStopTrackingTouch=function(seekBar)
      isSeeking = false
      pcall(function()
        player.seekTo(seekBar.getProgress())
        savePosition(currentPath, seekBar.getProgress())
      end)
    end,
    onProgressChanged=function(seekBar, progress, fromUser)
      pcall(function()
        if fromUser then
          ui.txtTime.setText(formatTime(progress).." / "..formatTime(player.getDuration()))
        end
      end)
    end
  })

  ui.bPlay.onClick=safeFn(function()
    pcall(function()
      if player and player.isPlaying() then 
        savePosition(currentPath, player.getCurrentPosition())
        player.pause() 
        ui.bPlay.setText("Play")
      else 
        if player then
          player.start() 
          ui.bPlay.setText("Pause") 
          update() 
        end
      end
    end)
  end)

  ui.bFast.onClick=safeFn(function()
    pcall(function()
      local current = player.getCurrentPosition()
      local duration = player.getDuration()
      local target = current + globalJumpTime
      if target > duration then target = duration end
      player.seekTo(target)
      savePosition(currentPath, target)
    end)
  end)

  ui.bRew.onClick=safeFn(function()
    pcall(function()
      local current = player.getCurrentPosition()
      local target = current - globalJumpTime
      if target < 0 then target = 0 end
      player.seekTo(target)
      savePosition(currentPath, target)
    end)
  end)

  ui.bTimer.onClick=safeFn(function()
    local timerOpts={"15 Minutes", "30 Minutes", "1 Hour", "2 Hours", "Cancel Timer"}
    local timerVals={900000, 1800000, 3600000, 7200000, 0}
    AlertDialog.Builder(activity).setTitle("Sleep Timer").setItems(timerOpts,function(d,i)
      if sleepRunnable then
        pcall(function() sleepHandler.removeCallbacks(sleepRunnable) end)
      end
      if i < 4 then
        local ms = timerVals[i+1]
        sleepRunnable = Runnable({run=function()
          pcall(function()
            isExplicitClose = true
            releasePlayer()
            pcall(function() dlg.dismiss() end)
            speak("Sleep timer reached. Media stopped.")
          end)
        end})
        sleepHandler.postDelayed(sleepRunnable, ms)
        speak("Sleep timer set for " .. timerOpts[i+1])
      else
        speak("Sleep timer cancelled")
      end
    end).show()
  end)

  ui.bFav.onClick=safeFn(function()
    local key = names[index] .. ":" .. tostring(list[index])
    if favoritesMap[key] then
      favoritesMap[key] = nil
      Toast.makeText(activity, "Removed from Favorites", Toast.LENGTH_SHORT).show()
      speak("Removed from Favorites")
    else
      favoritesMap[key] = {name=names[index], uri=list[index]}
      Toast.makeText(activity, "Added to Favorites", Toast.LENGTH_SHORT).show()
      speak("Added to Favorites")
    end
  end)

  ui.bNext.onClick=safeFn(function()
    stopMedia(currentPath)
    index=(index%#list)+1 
    loadPlay() 
  end)

  ui.bPrev.onClick=safeFn(function()
    stopMedia(currentPath)
    index=(index<=1) and #list or index-1 
    loadPlay() 
  end)

  ui.bClose.onClick=safeFn(function()
    isExplicitClose = true
    stopMedia(currentPath)
    dlg.dismiss() 
  end)

  local speedVals = {1.0, 1.25, 1.5, 1.75, 2.0}
  local speedIdx = 1
  ui.bSpeed.onClick=safeFn(function()
    if android.os.Build.VERSION.SDK_INT>=23 then
      speedIdx = (speedIdx % #speedVals) + 1
      local sp = speedVals[speedIdx]
      local p=player.getPlaybackParams()
      p.setSpeed(sp)
      player.setPlaybackParams(p)
      pcall(function() if not player.isPlaying() then player.pause() end end)
      ui.bSpeed.setText("Speed " .. sp .. "x")
      speak("Speed " .. sp .. " times")
    else
      speak("Speed change is not supported on this Android version")
    end
  end)

  ui.bStopBg.onClick=safeFn(function()
    isExplicitClose = true
    releasePlayer()
    pcall(function() dlg.dismiss() end)
    speak("Background media stopped")
  end)

  ui.bRename.onClick=safeFn(function()
    pcall(function()
      local edt=EditText(activity) edt.setText(names[index])
      AlertDialog.Builder(activity).setTitle("Rename").setView(edt)
      .setPositiveButton("Save",function() names[index]=edt.getText().toString() ui.txtTitle.setText(names[index]) end).show()
    end)
  end)

  ui.bShare.onClick=safeFn(function()
    pcall(function()
      if player.isPlaying() then 
        savePosition(currentPath, player.getCurrentPosition())
        player.pause() 
        ui.bPlay.setText("Play") 
      end
      local it=Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM,list[index]).setType("*/*")
      activity.startActivityForResult(Intent.createChooser(it,"Share"), 101)
    end)
  end)

  ui.bDel.onClick=safeFn(function()
    AlertDialog.Builder(activity).setTitle("Delete").setMessage("Delete File?")
    .setPositiveButton("Yes",function() 
      isExplicitClose = true
      local okD, eD = pcall(function() activity.getContentResolver().delete(list[index],nil,nil) end)
      if not okD then
        isExplicitClose = false
        speak("Could not delete this file. Android did not allow it")
        return
      end
      table.remove(list, index)
      table.remove(names, index)
      if #list > 0 then
        if index > #list then index = 1 end
        loadPlay() 
      else
        dlg.dismiss() 
      end
    end).show()
  end)
end

function showMediaList(n,u,t, mediaTypeTag)
  pcall(function()
    local lv=ListView(activity)
    lv.setAdapter(ArrayAdapter(activity,android.R.layout.simple_list_item_1,String(n)))
    local d=AlertDialog.Builder(activity).setTitle(t).setView(lv).show()
    lv.onItemClick=function(l,v,p) d.dismiss() playCurrentMedia(u,n,p+1, mediaTypeTag) end
  end)
end

function scanAllMedia()
  pcall(function()
    audioList,audioNames,videoList,videoNames={}, {}, {}, {}
    local r=activity.getContentResolver()
    local sortOrder = MediaStore.MediaColumns.DISPLAY_NAME .. " ASC"
    
    local ac=r.query(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,nil,nil,nil,sortOrder)
    if ac then 
      while ac.moveToNext() do
        table.insert(audioNames,ac.getString(ac.getColumnIndex(MediaStore.Audio.Media.DISPLAY_NAME)))
        table.insert(audioList,ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,ac.getLong(ac.getColumnIndex(MediaStore.Audio.Media._ID))))
      end 
      ac.close() 
    end
    
    local vc=r.query(MediaStore.Video.Media.EXTERNAL_CONTENT_URI,nil,nil,nil,sortOrder)
    if vc then 
      while vc.moveToNext() do
        table.insert(videoNames,vc.getString(vc.getColumnIndex(MediaStore.Video.Media.DISPLAY_NAME)))
        table.insert(videoList,ContentUris.withAppendedId(MediaStore.Video.Media.EXTERNAL_CONTENT_URI,vc.getLong(vc.getColumnIndex(MediaStore.Video.Media._ID))))
      end 
      vc.close() 
    end
    
    sortMediaAlphabetically(audioNames, audioList)
    sortMediaAlphabetically(videoNames, videoList)
  end)
end

scanAllMedia()
activity.setContentView(loadlayout({
  LinearLayout,orientation="vertical",
  {TextView,text="Media Player Pro\nDeveloper: Mohammad Ramzan Qadri",gravity="center",textSize="16sp",padding="12dp",backgroundColor="#1B5E20",textColor="#FFFFFF"},
  {ListView,id="mainList",layout_weight=1}
}))

function getTabsList()
  return {
    "Resume Last Played",
    "All Audio",
    "All Video",
    "Select Internal Storage",
    "Select SD Card",
    "Favorites",
    "Set Jump Time",
    "Sleep Timer",
    getAutoRepeatState() and "Toggle Auto-Repeat: ON" or "Toggle Auto-Repeat: OFF",
    "Stop Background Media",
    "About & Developer",
    "Refresh",
    "Exit"
  }
end

mainList.setAdapter(ArrayAdapter(activity,android.R.layout.simple_list_item_1,String(getTabsList())))

mainList.onItemClick=function(l,v,p)
  pcall(function()
    if p==0 then
      local lastInfo = getLastPlayedInfo()
      if lastInfo.path and lastInfo.path ~= "" and lastInfo.path ~= "nil" then
        local targetList, targetNames = {}, {}
        if lastInfo.type == "video" then
          targetList, targetNames = videoList, videoNames
        else
          targetList, targetNames = audioList, audioNames
        end
        
        local foundIndex = 1
        local foundUri = nil
        
        for idx, u in ipairs(targetList) do
          if tostring(u) == lastInfo.uri then
            foundIndex = idx
            foundUri = u
            break
          end
        end
        
        if not foundUri then
          pcall(function()
            local fileObj = File(lastInfo.path)
            if fileObj.exists() then
              local targetQueryUri = (lastInfo.type == "video") and MediaStore.Video.Media.EXTERNAL_CONTENT_URI or MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
              local cursor = activity.getContentResolver().query(targetQueryUri, {MediaStore.MediaColumns._ID}, MediaStore.MediaColumns.DATA .. "=?", {lastInfo.path}, nil)
              if cursor then
                if cursor.moveToFirst() then
                  local idCol = cursor.getColumnIndex(MediaStore.MediaColumns._ID)
                  if idCol ~= -1 then
                    local id = cursor.getLong(idCol)
                    foundUri = ContentUris.withAppendedId(targetQueryUri, id)
                    table.insert(targetList, foundUri)
                    table.insert(targetNames, lastInfo.name)
                    foundIndex = #targetList
                  end
                end
                cursor.close()
              end
            end
          end)
        end
        
        if foundUri and #targetList > 0 then
          speak("Resuming " .. lastInfo.name)
          playCurrentMedia(targetList, targetNames, foundIndex, lastInfo.type)
        else
          Toast.makeText(activity, "File not found on device or SD card.", Toast.LENGTH_SHORT).show()
          speak("File not found")
        end
      else
        Toast.makeText(activity, "No last played media found.", Toast.LENGTH_SHORT).show()
        speak("No last played media found")
      end
    elseif p==1 then showMediaList(audioNames,audioList,"Audio (A-Z)", "audio")
    elseif p==2 then showMediaList(videoNames,videoList,"Video (A-Z)", "video")
    elseif p==3 or p==4 then
      local storageType = (p == 3) and "internal" or "sdcard"
      local folders = getStorageFolders(storageType)
      
      if #folders == 0 then
        Toast.makeText(activity, "No folders found in " .. (p == 3 and "Internal Storage" or "SD Card"), Toast.LENGTH_LONG).show()
        speak("No folders found")
        return
      end
      
      local folderNames = {}
      for i, f in ipairs(folders) do
        table.insert(folderNames, f.name)
      end
      
      AlertDialog.Builder(activity).setTitle(p == 3 and "Internal Storage Folders" or "SD Card Folders").setItems(folderNames,function(dd, fIdx)
        local selectedFolder = folders[fIdx + 1]
        speak(selectedFolder.name .. " folder selected.")
        local fNames, fUris = getFilesInSpecificFolder(selectedFolder.path)
        if #fNames > 0 then
          showMediaList(fNames, fUris, selectedFolder.name, "media")
        else
          Toast.makeText(activity, "No media files found in this folder.", Toast.LENGTH_SHORT).show()
          speak("No files found")
        end
      end).show()
    elseif p==5 then
      local fNames, fUris = {}, {}
      for _, data in pairs(favoritesMap) do
        table.insert(fNames, data.name)
        table.insert(fUris, data.uri)
      end
      if #fNames > 0 then
        showMediaList(fNames, fUris, "Favorite Media", "audio")
      else
        Toast.makeText(activity, "No favorites added yet", Toast.LENGTH_SHORT).show()
        speak("No favorites added yet")
      end
    elseif p==6 then
      local jumpOptions = {"5 Seconds", "10 Seconds", "15 Seconds", "30 Seconds", "1 Minute", "2 Minutes", "5 Minutes"}
      local jumpValues = {5000, 10000, 15000, 30000, 60000, 120000, 300000}
      
      local checkedIndex = 0
      for idx, val in ipairs(jumpValues) do
        if val == globalJumpTime then
          checkedIndex = idx - 1
          break
        end
      end
      
      AlertDialog.Builder(activity).setTitle("Set Jump Time (Current: " .. globalJumpText .. ")").setSingleChoiceItems(jumpOptions, checkedIndex, function(d, i)
        globalJumpTime = jumpValues[i+1]
        globalJumpText = jumpOptions[i+1]
        saveJumpSetting(globalJumpTime, globalJumpText)
        speak("Jump time set to " .. globalJumpText)
        d.dismiss()
      end).show()
    elseif p==7 then
      local timerOpts={"15 Minutes", "30 Minutes", "1 Hour", "2 Hours", "Cancel Timer"}
      local timerVals={900000, 1800000, 3600000, 7200000, 0}
      AlertDialog.Builder(activity).setTitle("Sleep Timer").setItems(timerOpts,function(dd,i)
        if sleepRunnable then
          pcall(function() sleepHandler.removeCallbacks(sleepRunnable) end)
        end
        if i < 4 then
          local ms = timerVals[i+1]
          sleepRunnable = Runnable({run=function()
            pcall(function()
              releasePlayer()
              speak("Sleep timer reached. Media stopped.")
            end)
          end})
          sleepHandler.postDelayed(sleepRunnable, ms)
          speak("Sleep timer set for " .. timerOpts[i+1])
        else
          speak("Sleep timer cancelled")
        end
      end).show()
    elseif p==8 then
      local newState = not getAutoRepeatState()
      saveAutoRepeatState(newState)
      if newState then
        Toast.makeText(activity, "Repeat Loop Enabled (Same Track)", Toast.LENGTH_SHORT).show()
        speak("Repeat Loop ON")
      else
        Toast.makeText(activity, "Repeat Loop Disabled", Toast.LENGTH_SHORT).show()
        speak("Repeat Loop OFF")
      end
      mainList.setAdapter(ArrayAdapter(activity,android.R.layout.simple_list_item_1,String(getTabsList())))
    elseif p==9 then
      releasePlayer()
      pcall(function() favoritesMap = favoritesMap end)
      Toast.makeText(activity, "Background media stopped & cleared.", Toast.LENGTH_SHORT).show()
      speak("Background media stopped")
    elseif p==10 then
      local aboutOpts = {"Feedback / WhatsApp Developer", "Join Technology Guide Group", "Subscribe YouTube Official Channel", "How to Use Tutorial"}
      AlertDialog.Builder(activity).setTitle("About & Developer").setItems(aboutOpts,function(d,ii)
        if ii==0 then
          pcall(function() d.dismiss() end)
          local intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://wa.me/923000144024"))
          intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
          activity.startActivity(intent)
        elseif ii==1 then
          pcall(function() d.dismiss() end)
          local intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://chat.whatsapp.com/D6xZRT6trDk1mOJctpYopl"))
          intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
          activity.startActivity(intent)
        elseif ii==2 then
          pcall(function() d.dismiss() end)
          local intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://youtube.com/@junejaproduction9565?si=pb_bDA6mau9Jsx4D"))
          intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
          activity.startActivity(intent)
        elseif ii==3 then
          pcall(function() d.dismiss() end)
          local intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://youtu.be/9vUDNblBkpM?si=Ei0VFAgj6Wt9oRwt"))
          intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
          activity.startActivity(intent)
        end
      end).show()
    elseif p==11 then
      scanAllMedia()
      Toast.makeText(activity, "Media Refreshed", Toast.LENGTH_SHORT).show()
      speak("Refreshed")
    elseif p==12 then 
      releasePlayer()
      activity.finish() 
    end
  end)
end