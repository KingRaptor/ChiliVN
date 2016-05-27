--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
function widget:GetInfo()
  return {
    name      = "Chili VN",
    desc      = "Displays pink-haired anime babes",
    author    = "KingRaptor",
    date      = "2016.05.20",
    license   = "GNU GPL, v2 or later",
    layer     = 0,
    enabled   = false,
  }
end
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
local function GetDirectory(filepath) 
    return filepath and filepath:gsub("(.*/)(.*)", "%1") 
end 

local config = VFS.Include(LUAUI_DIRNAME.."Configs/vn_config.lua")

local Chili
local Window
local Panel
local Button
local StackPanel
local ScrollPanel
local Image
local Label
local TextBox
local screen0

-- Chili elements
local mainWindow
local textPanel
local textbox, nameLabel
local background
local menuButton, menuStack
local buttonSave, buttonLoad, buttonLog, buttonQuit
local logPanel

-- TODO: external config
local LOG_PANEL_HEIGHT = 80
local MENU_BUTTON_HEIGHT = 32
local MENU_BUTTON_WIDTH = 64
local MENU_BUTTON_HEIGHT_LARGE = 36
local MENU_BUTTON_WIDTH_LARGE = 72
local DEFAULT_FONT_SIZE = 16
local TEXT_INTERVAL = 0.05

options_path = 'Settings/HUD Panels/Visual Novel'
options = {
  textSpeed = {
    name = "Text Speed",
    type = 'number',
    min = 0, 
    max = 100, 
    step = 5,
    value = 30,
    desc = 'Characters/second (0 = instant)',
  },
  waitTime = {
    name = "Wait time",
    type = 'number',
    min = 0, 
    max = 4, 
    step = 0.5,
    value = 1.5,
    desc = 'Wait time at end of each script line before auto-advance',
  },
}

local waitTime = nil -- tick down in Update()
local waitAction  -- will we actually care what this is?

-- {[1]} = {target = target, type = type, startX = x, startY = y, endX = x, endY = y, startColor = color, endColor = color, time = time, timeElapsed = time ...}}
-- every Update(dt), increment time by dt and move stuff accordingly
-- elements are removed from table once timeElapsed >= time
local animations = {} 

local defs = {
  storyInfo = {}, -- entire contents of story_info.lua
  storyDir = "",
  scripts = {}, -- {[scriptName] = {list of actions}}
  characters = {},  -- {[charactername] = {data}}
  images = {} -- {[image name] = {data}}
}

local data = {
  storyID = "",
  images = {},  -- {[id] = Chili.Image}
  subscreens = {},
  vars = {},
  textLog = {}, -- {[1] = <AddText args table>, [2] = ...}
  backgroundFile = "",  -- path as specified in script (before prepending dir)
  currentText = "", -- the full line (textbox will not contain the full line until text writing has reached the end)
  currentMusic = {},  -- PlayMusic arg

  currentScript = "",

  currentLine = 1,
}

local scriptFunctions = {}

local menuVisible = false
local uiHidden = false
local autoAdvance = false
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
local function CountElements(tbl)
  local num = 0
  for i,v in pairs(tbl) do
    num = num + 1
  end
  return num
end

-- hax for parent directory syntax
local function GetFilePath(givenPath)
  if string.find(givenPath, "../../", 1, true) == 1 then
    return string.sub(givenPath, 7)
  elseif string.find(givenPath, "../", 1, true) == 1 then
    return config.VN_DIR .. string.sub(givenPath, 4)
  else
    return defs.storyDir .. givenPath
  end
end
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
function AdvanceScript() end  -- redefined in a bit

local function PlayScriptLine(line)
  local item = defs.scripts[data.currentScript][line]
  if item then
    local action = item[1]
    local args = item[2]
    if (type(args) == 'table') then
      args = Spring.Utilities.CopyTable(item[2], true)
    elseif args == nil then
      args = {}
    end
    scriptFunctions[action](args)
    if config.autoAdvanceActions[action] and (type(args) == 'table' and (not args.pause)) then
      AdvanceScript()
    end
    if (action ~= "AddText" and type(args) == 'table' and args.pause) then
      waitTime = waitTime or options.waitTime.value
    end
    
  elseif line > #defs.scripts[data.currentScript] then
    Spring.Log(widget:GetInfo().name, LOG.WARNING, "Reached end of script " .. data.currentScript)
  end
end

local function StartScript(scriptName)
  data.currentScript = scriptName
  data.currentLine = 1
  PlayScriptLine(1)
end

local function AdvanceText(time, toEnd)
  local wantedLength = string.len(data.currentText or "")
  local currLength = string.len(textbox.text or "")
  if currLength < wantedLength then
    if (toEnd) then
      textbox:SetText(data.currentText)
    else
      local charactersToAdd = math.floor(time * options.textSpeed.value + 0.5)
      local newLength = currLength + charactersToAdd
      if newLength > wantedLength then newLength = wantedLength end
      local newText = string.sub(data.currentText, 1, newLength)
      textbox:SetText(newText)
    end
  else
    if toEnd then
      AdvanceScript()
    else
      local wantAutoAdvance = autoAdvance	-- TODO
      if not wantAutoAdvance then
        local item = defs.scripts[data.currentScript][line]
        if item then
          local args = item[2]
          if (type(args) == 'table') and args.pause == false then
            wantAutoAdvance = true
          end
        end
      end
      if wantAutoAdvance then
        waitTime = waitTime or options.waitTime.value
      end
    end
  end
end

AdvanceScript = function()
  --Spring.Echo("Advancing script")
  --AdvanceText(0, true)
  waitTime = nil
  data.currentLine = data.currentLine + 1
  PlayScriptLine(data.currentLine)
end

scriptFunctions = {
  AddBackground = function(args)
    background.file = GetFilePath(args.image)
    data.backgroundFile = args.image
    background:Invalidate()
  end,
  
  AddImage = function(args)
    local image = data.images[args.id]
    if image then
      Spring.Log(widget:GetInfo().name, LOG.WARNING, "Image " .. args.id .. " already exists, modifying instead")
      return scriptFunctions.ModifyImage(args)
    end
    
    local imageDef = defs.images[args.defID] and Spring.Utilities.CopyTable(defs.images[args.defID], true) or {anchor = {}}
    args = Spring.Utilities.MergeTable(args, imageDef, false)
    
    local image = Image:New{
      parent = background,
      file = GetFilePath(args.file),
      height = args.height,
      width = args.width,
      animation = args.animation,
    }
    if (type(args.x) == 'string') then
      args.x = image.parent.width * tonumber(args.x)
    end
    if (type(args.y) == 'string') then
      args.y = image.parent.height * tonumber(args.y)
    end
    image.x = args.x - args.anchor[1]
    image.y = args.y - args.anchor[2]
    image.anchor = args.anchor or {}
    
    if (animation and animation.type == "dissolve") then
      --image.file2 = GetFilePath(args.file)
    end
    
    data.images[args.id] = image
    if (args.layer) then
      image:SetLayer(layer)
      image.layer = args.layer
    else
      image.layer = CountElements(data.images)
    end
    
    image:Invalidate()
  end,
  
  AddText = function(args)
    -- TODO get i18n string
    local instant = args.instant or options.textSpeed.value <= 0
    
    if (args.append) then
      args.text = data.currentText .. args.text
    end
    data.currentText = args.text
    
    args.size = args.size or DEFAULT_FONT_SIZE
    if args.size ~= textbox.font.size then
      textbox.font.size = args.size
      --textBox:Invalidate()
    end
    
    if instant then
      textbox:SetText(args.text)
    elseif (not args.append) then
      textbox:SetText("")
    end
    
    if (args.speaker) then
      local speaker = defs.characters[args.speaker]
      local color = speaker.color
      --nameLabel:SetCaption(string.char(color[4], color[1], color[2], color[3]).. speaker.name.."\008")
      nameLabel.font.color = color
      nameLabel:SetText(speaker.name)
    else
      --nameLabel:SetCaption("")
      nameLabel:SetText("")
    end
    nameLabel:Invalidate()
    if not args.noLog then
      if args.append and #data.textLog > 0 then
        data.textLog[#data.textLog] = args
      else
        data.textLog[#data.textLog + 1] = args
      end
    end
    if instant and (args.pause == false) then
      AdvanceScript()
    end
  end,
  
  ClearText = function()
    nameLabel:SetText("")
    nameLabel:Invalidate()
    textbox:SetText("")
    data.currentText = ""
  end,
  
  Exit = function()
    widgetHandler:RemoveWidget()
  end,
  
  JumpScript = function(script)
    StartScript(script)
  end,
  
  ModifyImage = function(args)
    local image = data.images[args.id]
    if not image then
      Spring.Log(widget:GetInfo().name, LOG.ERROR, "Attempt to modify nonexistent image " .. args.id)
      return
    end
    
    local imageDef = defs.images[args.defID] and Spring.Utilities.CopyTable(defs.images[args.defID], true) or {anchor = {}}
    args = Spring.Utilities.MergeTable(args, imageDef, false)
    
    if args.file then image.file = GetFilePath(args.file) end
    if args.height then image.height = args.height end
    if args.width then image.width = args.width end
    
    if (type(args.x) == 'string') then
      args.x = screen0.width * tonumber(args.x)
    end
    if (type(args.y) == 'string') then
      args.y = screen0.height * tonumber(args.y)
    end
    local anchor = args.anchor or image.anchor or {}
    image.anchor = anchor
    if args.x then image.x = args.x - anchor[1] end
    if args.y then image.y = args.y - anchor[2] end
    
    image:Invalidate()
  end,
  
  PlayMusic = function(args)
    if not args.track then return end
    
    local track = GetFilePath(args.track)
    local intro = args.intro and GetFilePath(args.intro) or track
    if args.loop and WG.Music and WG.Music.StartLoopingTrack then
      WG.Music.StartLoopingTrack(intro, track)
    elseif WG.Music then
      WG.Music.StartTrack(track)
    else
      Spring.StopSoundStream()
      Spring.PlaySoundStream(track, 1)
    end
    data.currentMusic = args
  end,
  
  PlaySound = function(args)
    Spring.PlaySoundFile(GetFilePath(args.file), args.volume or 1, args.channel)
  end,
  
  -- TODO: implement separate hideImage
  RemoveImage = function(args)
    local image = data.images[args.id]
    if not image then
      Spring.Log(widget:GetInfo().name, LOG.ERROR, "Attempt to modify nonexistent image " .. args.id)
      return
    end
    image:Dispose()
    data.images[args.id] = nil
  end,
  
  StopMusic = function(args)
    if WG.Music and WG.Music.StopTrack then
      WG.Music.StopTrack((not args.continue) or true)
    else
      Spring.StopSoundStream()
    end
    data.currentMusic = nil
  end,
  
  Wait = function(args)
    local time = (type(args) == 'number' and args) or (type(args) == 'table' and args.time)
    if time then
      waitTime = time
    end
  end,
}

local function ToggleMenu()
  if menuVisible then
    mainWindow:RemoveChild(menuStack)
  else
    mainWindow:AddChild(menuStack)
  end
  background:SetLayer(99999)
  --Spring.Echo("lol")
  menuVisible = not menuVisible
end

local function ResetMainLayers(force)
  --[[
  if force or (not uiHidden) then
    textPanel:SetLayer(1)
    menuButton:SetLayer(2)
    menuStack:SetLayer(3)
  end
  ]]--
  background:SetLayer(99)
end

local function ToggleUI()
  if uiHidden then
    mainWindow:AddChild(textPanel)
    mainWindow:AddChild(menuButton)
    if menuVisible then
      mainWindow:AddChild(menuStack)
    end
    ResetMainLayers(true)
  else
    mainWindow:RemoveChild(textPanel)
    mainWindow:RemoveChild(menuButton)
    if menuVisible then
      mainWindow:RemoveChild(menuStack)
    end
  end
  uiHidden = not uiHidden
end

local function RemoveLogPanel()
  if (logPanel == nil) then return end
  mainWindow:RemoveChild(logPanel)
  logPanel:Dispose()
  logPanel = nil
  ResetMainLayers()
end

local function CreateLogPanel()
  -- already have log panel, close it
  if (logPanel ~= nil) then
    RemoveLogPanel()
    return
  end
  
  logPanel = Panel:New {
    parent = mainWindow,
    name = "vn_logPanel",
    width = "80%",
    height = "80%",
    x = "10%",
    y = "10%",
    children = {
      Label:New {
        caption = "LOG",
        width = 64,
        height = 16,
        y = 4,
        x = 64,
        align = "center"
      }
    }
  }
  --Spring.Echo("wololo")
  logPanel:SetLayer(1)
  local logScroll = ScrollPanel:New {
    parent = logPanel,
    name = "vn_logScroll",
    x = 0,
    y = 24,
    width = "100%",
    bottom = 32,
  }
  --[[
  local logStack = StackPanel:New {
    parent = logscroll,
    name = "vn_logstack",
    orientation = 'vertical',
    autosize = true,
    resizeItems = true,
    centerItems = false,
    width = "100%",
    height = 500,
  }
  ]]--
  local logButtonClose = Button:New {
    parent = logPanel,
    name = "vn_logButtonClose",
    caption = "Close",
    right = 4,
    bottom = 4,
    width = 48,
    height = 28,
    OnClick = { function()
        RemoveLogPanel()
      end
    }
  }
  
  local count = 0
  for i=#data.textLog,#data.textLog-50,-1 do
    count = count + 1
    local entry = data.textLog[i]
    if (not entry) then
      break
    end
    local speaker = entry.speaker and defs.characters[entry.speaker]
    local color = speaker and speaker.color or nil
      
    logScroll:AddChild(Panel:New {
      width="100%",
      height = LOG_PANEL_HEIGHT,
      y = (LOG_PANEL_HEIGHT + 4)*(count-1),
      children = {
        TextBox:New {
          align = "left",
          text = speaker and speaker.name or "",  -- todo i18n
          x = 4,
          y = 4,
          width = 96,
          height = 20,
          font    = {
            size = 16;
            shadow = true;
            color = speaker and speaker.color
          },
        },
        TextBox:New {
          text = entry.text,
          align = "left",
          x = 4,
          y = 28,
          width = "100%",
          height = 32,
        }
      },
    })
  end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- save/load handling

local function ImageToTable(image)
  local imgTable = {
    file = image.file,
    height = image.height,
    width = image.width,
    x = image.x,
    y = image.y,
    anchor = image.anchor,
    layer = image.layer,
  }
  return imgTable
end

local function TableToImage(table)
  local image = Image:New {
    file = table.file,
    height = table.height,
    width = table.width,
    x = table.x,
    y = table.y,
    anchor = table.anchor,
    layer = table.layer,
  }
  return image
end

local function SaveGame(filename)
  filename = filename or "save.lua"
  local saveData = Spring.Utilities.CopyTable(data, true)
  
  -- we can't save userdata so change all the images to tables first
  local imagesSaved = {}
  for imageID, image in pairs(saveData.images) do
    imagesSaved[imageID] = ImageToTable(image)
  end
  saveData.imagesSaved = imagesSaved
  saveData.images = nil
  
  WG.SaveTable(saveData, defs.storyDir, filename, nil, {concise = true, prefixReturn = true, endOfFile = true})
  Spring.Log(widget:GetInfo().name, LOG.INFO, "Saved game to " .. filename)
end

local function LoadGame(filename)
  filename = filename or "save.lua"
  local path = defs.storyDir .. filename
  if not VFS.FileExists(path) then
    Spring.Log(widget:GetInfo().name, LOG.ERROR, "Unable to find save file " .. filename)
    return
  end
  
  for imageID, image in pairs(data.images) do
    image:Dispose()
  end
  --for screenID, screen in pairs(data.subscreens) do
  --  screen:Dispose()
  --end
  
  data = VFS.Include(path)
  scriptFunctions.AddBackground({image = data.backgroundFile, pause = true})
  
  -- readd images from saved data
  data.images = {}
  for imageID, imageSaved in pairs(data.imagesSaved) do
    local image = TableToImage(imageSaved)
    background:AddChild(image)
    data.images[imageID] = image
  end
  for imageID, image in pairs(data.images) do
    image:SetLayer(image.layer)
  end
  data.imagesSaved = nil
  
  local lastText = data.textLog[#data.textLog]
  if type(lastText) == 'table' then
    lastText = Spring.Utilities.CopyTable(lastText, true)
    lastText.noLog = true
    lastText.append = false
    lastText.instant = true
    scriptFunctions.AddText(lastText)
  end
  
  scriptFunctions.PlayMusic(data.currentMusic)
  
  --for screenID, screen in pairs(data.subscreens) do
  --  mainWindow:AddChild(screen)
  --end
end
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function LoadStory(storyID)
  defs.storyDir = config.VN_DIR .. storyID .. "/"
  local storyPath = defs.storyDir .. "story_info.lua"
  if not VFS.FileExists(storyPath, VFS.RAW_FIRST) then
    Spring.Log(widget:GetInfo().name, LOG.ERROR, "VN story " .. storyID .. " does not exist")
    --Spring.Echo("VN story " .. storyPath .. " does not exist")
    return
  end
  defs.storyInfo = VFS.Include(storyPath)
  data.storyID = storyID
  
  for _,scriptPath in ipairs(defs.storyInfo.scripts) do
    local path = defs.storyDir .. scriptPath
    if VFS.FileExists(path, VFS.RAW_FIRST) then
      local loadedScripts = VFS.Include(path)
      for scriptName,data in pairs(loadedScripts) do
        defs.scripts[scriptName] = data
      end
    else
      -- warning/error message
    end
  end
  for _,charDefPath in ipairs(defs.storyInfo.characterDefs) do
    local path = defs.storyDir .. charDefPath
    if VFS.FileExists(path, VFS.RAW_FIRST) then
      local loadedCharDefs = VFS.Include(path)	--Spring.Utilities.json.decode(VFS.LoadFile(path, VFS.ZIP))
      for charName,data in pairs(loadedCharDefs) do
        defs.characters[charName] = data
      end
    else
      -- warning/error message
    end
  end
  for _,imagesPath in ipairs(defs.storyInfo.imageDefs) do
    local path = defs.storyDir .. imagesPath
    if VFS.FileExists(path, VFS.RAW_FIRST) then
      local imageDefs = VFS.Include(path)	--Spring.Utilities.json.decode(VFS.LoadFile(path, VFS.ZIP))
      for imageName,data in pairs(imageDefs) do
        defs.images[imageName] = data
      end
    else
      -- warning/error message
    end
  end
  
  mainWindow.caption = defs.storyInfo.name
  mainWindow:Invalidate()
  
  Spring.Log(widget:GetInfo().name, LOG.INFO, "VN story " .. defs.storyInfo.name .. " loaded")
end


local function LoadTestStory()
  LoadStory("test")
  StartScript(defs.storyInfo.startScript)
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
local textTime = 0

function widget:Update(dt)
  if (waitTime) then
    waitTime = waitTime - dt
    if waitTime <= 0 then
      waitTime = nil
      AdvanceScript()
    end
  end
  for k,v in pairs(animations) do
     -- advance each animation 
  end
  textTime = textTime + dt
  if textTime > TEXT_INTERVAL then
    if Spring.GetPressedKeys()[306] then  -- ctrl
      AdvanceScript()
    else
      AdvanceText(textTime, false)
    end
    textTime = 0
  end
end

function widget:Initialize()
  -- chili stuff here
  if not (WG.Chili) then
    Spring.Log(widget:GetInfo().name, LOG.ERROR, "Chili not loaded")
    widgetHandler:RemoveWidget()
    return
  end

  -- chili setup
  Chili = WG.Chili
  Window = Chili.Window
  Panel = Chili.Panel
  ScrollPanel = Chili.ScrollPanel
  --Grid = Chili.Grid
  Label = Chili.Label
  TextBox = Chili.TextBox
  Image = Chili.Image
  Button = Chili.Button
  StackPanel = Chili.StackPanel
  screen0 = Chili.Screen0
  
  -- create windows
  mainWindow = Window:New{  
    name = "vn_mainWindow",
    caption = "Chili VN",
    --fontSize = 50,
    x = screen0.width*0.6 - 512,
    y = screen0.height/2 - 384 - 8,
    width  = 1024,
    height = 768 + 16,
    padding = {8, 8, 8, 8};
    --autosize   = true;
    parent = screen0,
    draggable = true,
    resizable = false,
  }
  
  menuButton = Button:New{
    parent = mainWindow,
    name = "vn_menuButton",
    caption = "MENU",
    y = 24,
    right = 4,
    width = MENU_BUTTON_WIDTH_LARGE,
    height = MENU_BUTTON_HEIGHT_LARGE,
    OnClick = {ToggleMenu}
  }
  
  buttonSave = Button:New{
    name = "vn_menuButton",
    caption = "SAVE",
    width = MENU_BUTTON_WIDTH,
    height = MENU_BUTTON_HEIGHT,
    OnClick = {function() SaveGame() end}
  }
  
  buttonLoad = Button:New{
    name = "vn_buttonLoad",
    caption = "LOAD",
    width = MENU_BUTTON_WIDTH,
    height = MENU_BUTTON_HEIGHT,
    OnClick = {function() LoadGame() end}
  }
  
  buttonAuto = Button:New{
    name = "vn_buttonAuto",
    caption = "AUTO",
    width = MENU_BUTTON_WIDTH,
    height = MENU_BUTTON_HEIGHT,
    OnClick = {function() autoAdvance = not autoAdvance end}
  }
  
  buttonLog = Button:New{
    name = "vn_buttonLog",
    caption = "LOG",
    width = MENU_BUTTON_WIDTH,
    height = MENU_BUTTON_HEIGHT,
    OnClick = {function() CreateLogPanel() end}
  }
  
  buttonOptions = Button:New{
    name = "vn_buttonOptions",
    caption = "OPT",
    width = MENU_BUTTON_WIDTH,
    height = MENU_BUTTON_HEIGHT,
    OnClick = {function() WG.crude.OpenPath(options_path); WG.crude.ShowMenu(); end}
  }
  
  buttonQuit = Button:New{
    name = "vn_buttonQuit",
    caption = "QUIT",
    width = MENU_BUTTON_WIDTH,
    height = MENU_BUTTON_HEIGHT,
    OnClick = {function() widgetHandler:RemoveWidget() end}
  }
  
  local menuChildren = {buttonSave, buttonLoad, buttonAuto, buttonLog, buttonOptions, buttonQuit}
  menuStack = StackPanel:New{
    parent = mainWindow,
    orientation = 'vertical',
    autosize = false,
    resizeItems = true,
    centerItems = false,
    y = MENU_BUTTON_HEIGHT_LARGE + 24 + 8,
    right = 4,
    height = #menuChildren * (MENU_BUTTON_HEIGHT + 4) + 4,
    width = MENU_BUTTON_WIDTH + 4,
    padding = {0, 0, 0, 0},
    children = menuChildren,
  }
  mainWindow:RemoveChild(menuStack)
  
  textPanel = Panel:New {
    parent = mainWindow,
    name = "vn_textPanel",
    width = "100%",
    height = "20%",
    x = 0,
    bottom = 0,
  }
  --function textPanel:HitTest() return self end
  
  nameLabel = TextBox:New{
    parent = textPanel,
    name = "vn_nameLabel",
    text = "Speaker",
    x = 8,
    y = 4,
    font = {
      size = 24;
      shadow = true;
    },
  }
  textbox = TextBox:New{
    parent = textPanel,
    name = "vn_textbox",
    text    = "",
    align   = "left",
    x = "5%",
    bottom = 0,
    width = "95%",
    height = "75%",
    padding = {5, 5, 5, 5},
    font    = {
      size = DEFAULT_FONT_SIZE;
      shadow = true;
    },
    
  }
  mainWindow:SetLayer(1)
  background = Image:New{
    parent = mainWindow,
    name = "vn_background",
    x = 0,
    y = 16,
    width = "100%",
    height = "100%",
        OnClick = {function(self, x, y, mouse)
        if mouse == 1 then
          if not uiHidden then
            AdvanceText(0, true)
          else
            ToggleUI()
          end
        elseif mouse == 3 then
          ToggleUI()
        end
      end
    },
    OnMouseDown = {function(self) return true end},
  }
  
  LoadTestStory()
end

function widget:Shutdown()

end
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------