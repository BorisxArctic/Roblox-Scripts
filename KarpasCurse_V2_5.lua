-- KARPA'S CURSE | V2.5
-- Roblox DOORS | Client-side utility UI (speed persistence + survival tools)
-- No HTTP requests, remote code, or hidden downloads.
-- NOTE: Server-authoritative mechanics (health, badges, entity damage, room
-- loading) cannot be guaranteed or bypassed by a client-side script.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")

local player = Players.LocalPlayer
if not player then return end
local playerGui = player:WaitForChild("PlayerGui")

-- Proper re-execution cleanup. Works in ordinary LocalScripts as well as
-- environments exposing getgenv(); without getgenv(), use _G.
local environment = _G
if type(getgenv) == "function" then
    local ok, result = pcall(getgenv)
    if ok and type(result) == "table" then
        environment = result
    end
end
if type(environment.KarpasCurseCleanup) == "function" then
    pcall(environment.KarpasCurseCleanup)
end
local oldGui = playerGui:FindFirstChild("KarpaCurse")
if oldGui then oldGui:Destroy() end

local alive = true
local connections = {}
local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

local C = {
    bg = Color3.fromRGB(9, 11, 17),
    panel = Color3.fromRGB(14, 19, 27),
    surface = Color3.fromRGB(22, 29, 41),
    hover = Color3.fromRGB(30, 40, 56),
    blue = Color3.fromRGB(33, 162, 255),
    blueDark = Color3.fromRGB(16, 65, 98),
    text = Color3.fromRGB(245, 248, 255),
    muted = Color3.fromRGB(143, 159, 181),
    red = Color3.fromRGB(255, 102, 111),
    green = Color3.fromRGB(76, 223, 165)
}

local state = {
    walkSpeed = 16,
    effectiveWalkSpeed = 16,
    speedLock = false,
    godmode = false,
    noclip = false,
    thirdPerson = false,
    autoGold = false,
    doorESP = false,
    entityESP = false,
    hiddenEntities = false,
    frozenEntities = false,
    fullbright = false,
    lowGravity = false,
    autoLoot = false,
    autoDoors = false,
    autoSwitches = false,
    autoHide = false
}

local collisionBackup = setmetatable({}, {__mode = "k"})
local walkSpeedBackup = setmetatable({}, {__mode = "k"})
local healthBackup = setmetatable({}, {__mode = "k"})
local transparencyBackup = setmetatable({}, {__mode = "k"})
local anchorBackup = setmetatable({}, {__mode = "k"})
local doorHighlights = {}
local entityHighlights = {}
local originalLighting = {
    Brightness = Lighting.Brightness,
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    GlobalShadows = Lighting.GlobalShadows
}
local originalGravity = Workspace.Gravity
local originalFov = Workspace.CurrentCamera and Workspace.CurrentCamera.FieldOfView or 70

local function rounded(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 8)
    corner.Parent = parent
    return corner
end
local function stroked(parent, color, thickness, transparency)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color or C.blue
    stroke.Thickness = thickness or 1
    stroke.Transparency = transparency or 0
    stroke.Parent = parent
    return stroke
end
local function create(class, properties, parent)
    local obj = Instance.new(class)
    for name, value in pairs(properties) do
        obj[name] = value
    end
    -- Preserve insertion order inside scrolling pages even when multiple UI
    -- children share the same Roblox class/name.
    if parent and parent:IsA("ScrollingFrame") and obj:IsA("GuiObject") then
        local order = (parent:GetAttribute("KarpaNextOrder") or 0) + 1
        parent:SetAttribute("KarpaNextOrder", order)
        obj.LayoutOrder = order
    end
    obj.Parent = parent
    return obj
end
local function animate(instance, values, duration)
    TweenService:Create(instance, TweenInfo.new(duration or 0.16, Enum.EasingStyle.Quad), values):Play()
end

local gui = create("ScreenGui", {
    Name = "KarpaCurse",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 25
}, playerGui)

-- protect_gui must happen AFTER the ScreenGui exists.
local protectFunction
if type(syn) == "table" and type(syn.protect_gui) == "function" then
    protectFunction = syn.protect_gui
elseif type(protect_gui) == "function" then
    protectFunction = protect_gui
end
if protectFunction then pcall(protectFunction, gui) end

local main = create("Frame", {
    Name = "Main",
    Size = UDim2.fromOffset(690, 520),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    BackgroundColor3 = C.bg,
    BorderSizePixel = 0,
    Active = true
}, gui)
rounded(main, 12)
stroked(main, C.blue, 1.4, 0.22)

local scale = create("UIScale", {Scale = 1}, main)
local function rescale()
    local camera = Workspace.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    scale.Scale = math.clamp(math.min((viewport.X - 24) / 690, (viewport.Y - 30) / 520), 0.5, 1)
end
local cameraConnection
local function bindCamera()
    if cameraConnection then cameraConnection:Disconnect() end
    local camera = Workspace.CurrentCamera
    if camera then
        cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
        if state.fov then camera.FieldOfView = state.fov end
    end
    rescale()
end
bindCamera()
connect(Workspace:GetPropertyChangedSignal("CurrentCamera"), bindCamera)

local header = create("Frame", {
    Name = "Header",
    Size = UDim2.new(1, 0, 0, 57),
    BackgroundColor3 = C.panel,
    BorderSizePixel = 0,
    Active = true
}, main)
rounded(header, 12)
create("Frame", {
    Size = UDim2.new(1, 0, 0, 10),
    Position = UDim2.new(0, 0, 1, -10),
    BackgroundColor3 = C.panel,
    BorderSizePixel = 0
}, header)
create("TextLabel", {
    Text = "KARPA'S CURSE",
    Font = Enum.Font.GothamBold,
    TextSize = 20,
    TextColor3 = C.text,
    BackgroundTransparency = 1,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.fromOffset(18, 8),
    Size = UDim2.new(1, -130, 0, 25)
}, header)
create("TextLabel", {
    Text = "V2.5   /   ENTITY LAB  ·  DOORS",
    Font = Enum.Font.GothamMedium,
    TextSize = 10,
    TextColor3 = C.blue,
    BackgroundTransparency = 1,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.fromOffset(19, 32),
    Size = UDim2.new(1, -130, 0, 15)
}, header)

local function headerButton(label, offset)
    local button = create("TextButton", {
        Text = label,
        Font = Enum.Font.GothamBold,
        TextSize = 19,
        TextColor3 = C.muted,
        BackgroundColor3 = C.surface,
        AutoButtonColor = false,
        Size = UDim2.fromOffset(34, 30),
        Position = UDim2.new(1, offset, 0, 13),
        BorderSizePixel = 0
    }, header)
    rounded(button, 6)
    return button
end
local minimizeButton = headerButton("−", -85)
local closeButton = headerButton("×", -43)

local sidebar = create("ScrollingFrame", {
    Size = UDim2.new(0, 152, 1, -95),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    CanvasSize = UDim2.fromOffset(0, 0),
    ScrollBarThickness = 2,
    ScrollBarImageColor3 = C.blue,
    Position = UDim2.fromOffset(0, 57),
    BackgroundColor3 = C.panel,
    BorderSizePixel = 0
}, main)
create("UIPadding", {
    PaddingTop = UDim.new(0, 12),
    PaddingLeft = UDim.new(0, 9),
    PaddingRight = UDim.new(0, 9)
}, sidebar)
create("UIListLayout", {
    FillDirection = Enum.FillDirection.Vertical,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 7)
}, sidebar)

local content = create("Frame", {
    Size = UDim2.new(1, -170, 1, -100),
    Position = UDim2.fromOffset(164, 63),
    BackgroundTransparency = 1,
    ClipsDescendants = true
}, main)

local footer = create("Frame", {
    Position = UDim2.new(0, 0, 1, -38),
    Size = UDim2.new(1, 0, 0, 38),
    BorderSizePixel = 0,
    BackgroundColor3 = C.panel
}, main)
rounded(footer, 10)
local footerCover = create("Frame", {
    Size = UDim2.new(1, 0, 0, 12),
    BorderSizePixel = 0,
    BackgroundColor3 = C.panel
}, footer)
local status = create("TextLabel", {
    Text = "Ready  •  RightShift to hide/show",
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextColor3 = C.muted,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(15, 7),
    Size = UDim2.new(1, -24, 0, 22)
}, footer)
local statusIndex = 0
local function notify(message, bad)
    if not alive then return end
    statusIndex = statusIndex + 1
    local index = statusIndex
    status.Text = message
    status.TextColor3 = bad and C.red or C.green
    task.delay(4, function()
        if alive and index == statusIndex and status.Parent then
            status.Text = "Ready  •  RightShift to hide/show"
            status.TextColor3 = C.muted
        end
    end)
end

local tabButtons, pages = {}, {}
local activeTab
local function addPage(id, label, order)
    local button = create("TextButton", {
        Name = id .. "Tab",
        Text = "  " .. label,
        Font = Enum.Font.GothamSemibold,
        TextSize = 12,
        TextColor3 = C.muted,
        TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(1, 0, 0, 40),
        LayoutOrder = order,
        BackgroundColor3 = C.surface,
        AutoButtonColor = false,
        BorderSizePixel = 0
    }, sidebar)
    rounded(button, 7)
    local page = create("ScrollingFrame", {
        Name = id,
        Size = UDim2.fromScale(1, 1),
        Visible = false,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.fromOffset(0, 0),
        ScrollBarThickness = 3,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ScrollBarImageColor3 = C.blue
    }, content)
    create("UIPadding", {
        PaddingTop = UDim.new(0, 6),
        PaddingBottom = UDim.new(0, 12),
        PaddingLeft = UDim.new(0, 3),
        PaddingRight = UDim.new(0, 9)
    }, page)
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 9)
    }, page)
    tabButtons[id], pages[id] = button, page
    connect(button.MouseButton1Click, function()
        activeTab = id
        for name, other in pairs(tabButtons) do
            local active = name == id
            pages[name].Visible = active
            animate(other, {
                BackgroundColor3 = active and C.blueDark or C.surface,
                TextColor3 = active and C.text or C.muted
            })
        end
    end)
    return page
end

local dashPage = addPage("Dashboard", "OVERVIEW", 1)
local navPage = addPage("Navigation", "TELEPORTS", 2)
local morphPage = addPage("Morphs", "ENTITY MORPHS", 3)
local itemPage = addPage("Items", "ITEM LAB", 4)
local entityPage = addPage("Entities", "ENTITY TOOLS", 5)
local visualPage = addPage("Visuals", "VISUALS", 6)
local playerPage = addPage("Player", "PLAYER", 7)
local achievementPage = addPage("Achievements", "ACHIEVEMENTS", 8)
local toolsPage = addPage("Tools", "SETTINGS", 9)

-- Dashboard accent stripe and header ambience
local topEdge = create("Frame", {
    Name = "ElectricLine",
    Size = UDim2.new(1, -30, 0, 2),
    Position = UDim2.fromOffset(15, 0),
    BorderSizePixel = 0,
    BackgroundColor3 = C.blue,
    ZIndex = 4
}, header)
create("UIGradient", {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(8, 48, 77)),
        ColorSequenceKeypoint.new(0.35, C.blue),
        ColorSequenceKeypoint.new(0.7, Color3.fromRGB(164, 79, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(11, 46, 89))
    })
}, topEdge)

local function label(parent, value, height, color, font)
    return create("TextLabel", {
        Text = value,
        Font = font or Enum.Font.Gotham,
        TextSize = 12,
        TextColor3 = color or C.muted,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, height or 32)
    }, parent)
end
local function section(parent, value)
    label(parent, string.upper(value), 22, C.blue, Enum.Font.GothamBold)
end
local function button(parent, text, callback)
    local item = create("TextButton", {
        Text = text,
        Font = Enum.Font.GothamSemibold,
        TextColor3 = C.text,
        TextSize = 12,
        AutoButtonColor = false,
        BorderSizePixel = 0,
        BackgroundColor3 = C.surface,
        Size = UDim2.new(1, 0, 0, 37)
    }, parent)
    rounded(item, 6)
    stroked(item, C.blue, 1, 0.76)
    connect(item.MouseEnter, function() animate(item, {BackgroundColor3 = C.hover}) end)
    connect(item.MouseLeave, function() animate(item, {BackgroundColor3 = C.surface}) end)
    if callback then
        connect(item.MouseButton1Click, function()
            local ok, errorText = pcall(callback)
            if not ok then
                warn("[Karpa's Curse V2.5] " .. tostring(errorText))
                notify("Action failed; see client console", true)
            end
        end)
    end
    return item
end
local function toggle(parent, text, initial, callback)
    local line = create("Frame", {
        BackgroundColor3 = C.surface,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 39)
    }, parent)
    rounded(line, 6)
    label(line, text, 39, C.text).Size = UDim2.new(1, -64, 1, 0)
    local textLabel = line:FindFirstChildOfClass("TextLabel")
    textLabel.Position = UDim2.fromOffset(10, 0)
    local switch = create("TextButton", {
        Text = "",
        Size = UDim2.fromOffset(43, 23),
        Position = UDim2.new(1, -51, 0.5, -11),
        BackgroundColor3 = C.hover,
        BorderSizePixel = 0,
        AutoButtonColor = false
    }, line)
    rounded(switch, 12)
    local knob = create("Frame", {
        Size = UDim2.fromOffset(17, 17),
        Position = UDim2.fromOffset(3, 3),
        BackgroundColor3 = C.text,
        BorderSizePixel = 0
    }, switch)
    rounded(knob, 9)
    local value = not not initial
    local function set(newValue)
        newValue = not not newValue
        if newValue == value then return end
        value = newValue
        animate(switch, {BackgroundColor3 = value and C.blue or C.hover})
        animate(knob, {Position = value and UDim2.fromOffset(23, 3) or UDim2.fromOffset(3, 3)})
        local ok, errorText = pcall(callback, value)
        if not ok then
            warn("[Karpa's Curse V2.5] " .. tostring(errorText))
            notify("Toggle failed; see client console", true)
        end
    end
    connect(switch.MouseButton1Click, function() set(not value) end)
    return {set = set, get = function() return value end}
end
local function slider(parent, text, minimum, maximum, initial, callback)
    local frame = create("Frame", {
        Size = UDim2.new(1, 0, 0, 64),
        BackgroundColor3 = C.surface,
        BorderSizePixel = 0
    }, parent)
    rounded(frame, 6)
    local textLabel = label(frame, text, 25, C.text)
    textLabel.Position = UDim2.fromOffset(10, 3)
    textLabel.Size = UDim2.new(1, -20, 0, 25)
    local bar = create("Frame", {
        Size = UDim2.new(1, -24, 0, 7),
        Position = UDim2.fromOffset(12, 43),
        BackgroundColor3 = C.hover,
        BorderSizePixel = 0
    }, frame)
    rounded(bar, 4)
    local fill = create("Frame", {
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = C.blue,
        BorderSizePixel = 0
    }, bar)
    rounded(fill, 4)
    local hitbox = create("TextButton", {
        Text = "",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 27),
        Position = UDim2.fromOffset(0, -10)
    }, bar)
    local value
    local function set(newValue)
        local nextValue = math.clamp(math.floor(newValue + 0.5), minimum, maximum)
        if nextValue == value then return end
        value = nextValue
        local fraction = (value - minimum) / (maximum - minimum)
        fill.Size = UDim2.fromScale(fraction, 1)
        textLabel.Text = text .. "   " .. tostring(value)
        local ok, errorText = pcall(callback, value)
        if not ok then warn("[Karpa's Curse V2.5] " .. tostring(errorText)) end
    end
    set(initial)
    local sliding = false
    local activeTouch
    local function fromPointer(input)
        local width = math.max(bar.AbsoluteSize.X, 1)
        local fraction = math.clamp((input.Position.X - bar.AbsolutePosition.X) / width, 0, 1)
        set(minimum + (maximum - minimum) * fraction)
    end
    connect(hitbox.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            sliding = true
            activeTouch = input.UserInputType == Enum.UserInputType.Touch and input or nil
            fromPointer(input)
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if not sliding then return end
        if activeTouch then
            if input == activeTouch then fromPointer(input) end
        elseif input.UserInputType == Enum.UserInputType.MouseMovement then
            fromPointer(input)
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if (activeTouch and input == activeTouch) or (not activeTouch and input.UserInputType == Enum.UserInputType.MouseButton1) then
            sliding = false
            activeTouch = nil
        end
    end)
    return {set = set, get = function() return value end}
end

-- ═══════════════════════════════════════════════════════════════
-- CONTROL CENTER
-- ═══════════════════════════════════════════════════════════════
local hero = create("Frame", {
    Size = UDim2.new(1, 0, 0, 118),
    BackgroundColor3 = Color3.fromRGB(9, 37, 67),
    BorderSizePixel = 0
}, dashPage)
rounded(hero, 10)
create("UIGradient", {
    Rotation = 15,
    Color = ColorSequence.new(Color3.fromRGB(9, 45, 78), Color3.fromRGB(42, 20, 69))
}, hero)
local heroTitle = label(hero, "KARPA'S CURSE  /  ENTITY LAB", 34, C.text, Enum.Font.GothamBlack)
heroTitle.Position = UDim2.fromOffset(17, 13)
heroTitle.Size = UDim2.new(1, -30, 0, 34)
heroTitle.TextSize = 18
local heroSub = label(hero, "ORIGINAL-ASSET MORPHS · ROOM NAVIGATION · CLIENT TOOLS", 48, Color3.fromRGB(190, 219, 245))
heroSub.Position = UDim2.fromOffset(17, 49)
heroSub.Size = UDim2.new(1, -35, 0, 48)
heroSub.TextSize = 11
section(dashPage, "Live session")
local dashRoom = label(dashPage, "Current room: scanning...", 28, C.text)
local dashMorph = label(dashPage, "Morph: human", 28, C.text)
local dashAssets = label(dashPage, "Real-model assets: press Scan in Entity Morphs", 40, C.muted)
section(dashPage, "What works")
label(dashPage, "Teleport to loaded geometry; authentic entity-model visual morphs when those models are accessible; local tools and visual effects. All resettable.", 65, C.text)
section(dashPage, "Server-controlled")
label(dashPage, "This script cannot grant real Knobs, server inventory, real entity powers or permanent achievements. A morph is visible on your own client only.", 75, C.muted)

-- Doors dynamically create rooms. Room n-1 normally owns the door leading
-- to room n. Local teleport attempts may be corrected by the game server.
local function loadedRooms()
    return Workspace:FindFirstChild("CurrentRooms")
end
local function getRoom(number)
    local container = loadedRooms()
    return container and container:FindFirstChild(tostring(number)) or nil
end
local function getDoorObject(room)
    if not room then return nil end
    local direct = room:FindFirstChild("Door")
    if direct and (direct:IsA("Model") or direct:IsA("BasePart")) then
        return direct
    end
    for _, obj in ipairs(room:GetDescendants()) do
        if obj.Name == "Door" and (obj:IsA("Model") or obj:IsA("BasePart")) then
            return obj
        end
    end
    return nil
end
local function getDoorCFrame(room)
    local door = getDoorObject(room)
    if not door then return nil end
    if door:IsA("BasePart") then return door.CFrame end
    local part = door:FindFirstChild("Door") or door.PrimaryPart
    if part and part:IsA("BasePart") then return part.CFrame end
    return door:GetPivot()
end
local function getDoorForNumber(number)
    -- The exit door in room 49 is generally Door 50.
    return getDoorCFrame(getRoom(number - 1)) or getDoorCFrame(getRoom(number))
end
local function newestRoomNumber()
    local rooms = loadedRooms()
    if not rooms then return nil end
    local latest
    for _, room in ipairs(rooms:GetChildren()) do
        local number = tonumber(room.Name)
        if number and (not latest or number > latest) then latest = number end
    end
    return latest
end
local function rootPart()
    local char = player.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end
local function currentProgressRoom()
    local data = ReplicatedStorage:FindFirstChild("GameData")
    local latest = data and data:FindFirstChild("LatestRoom")
    if latest and (latest:IsA("IntValue") or latest:IsA("NumberValue")) then
        return math.floor(latest.Value)
    end
    local root = rootPart()
    local rooms = loadedRooms()
    if root and rooms then
        local nearest, nearestDist
        for _, room in ipairs(rooms:GetChildren()) do
            local number = tonumber(room.Name)
            if number and room:IsA("Model") then
                local distance = (root.Position - room:GetPivot().Position).Magnitude
                if not nearestDist or distance < nearestDist then
                    nearest, nearestDist = number, distance
                end
            end
        end
        if nearest then return nearest end
    end
    return newestRoomNumber()
end
local queuedDoorNumber
local teleportIgnoreUntil = 0
local function teleportToRoom(number)
    number = tonumber(number)
    if not number or number < 1 or number > 1000 or number % 1 ~= 0 then
        notify("Enter a valid door number (1-1000)", true)
        return false
    end
    local doorCf = getDoorForNumber(number)
    if not doorCf then return false end
    local root = rootPart()
    local character = player.Character
    if not root or not character then
        notify("Character not ready", true)
        return false
    end
    local direction = (root.Position - doorCf.Position):Dot(doorCf.LookVector) >= 0 and 1 or -1
    local destination = doorCf.Position + doorCf.LookVector * (direction * 4.5) + Vector3.new(0, 2.5, 0)
    teleportIgnoreUntil = os.clock() + 3
    character:PivotTo(CFrame.new(destination, destination + doorCf.LookVector))
    notify("Door " .. number .. ": local teleport attempted")
    task.delay(1.4, function()
        if not alive or not root.Parent then return end
        if (root.Position - destination).Magnitude > 22 then
            queuedDoorNumber = number
            notify("DOORS corrected the teleport; switching to walking route", true)
        end
    end)
    return true
end
local function requestDoor(number)
    number = tonumber(number)
    if not number or number < 1 or number > 1000 or number % 1 ~= 0 then
        notify("Enter a valid door number (1-1000)", true)
        return
    end
    if getDoorForNumber(number) then
        queuedDoorNumber = nil
        teleportToRoom(number)
    else
        queuedDoorNumber = number
        notify("Door " .. number .. " not generated yet; route queued")
    end
end

section(navPage, "Door navigation")
local roomDisplay = label(navPage, "Current room: scanning...", 28, C.text, Enum.Font.GothamSemibold)
local routeStatus = label(navPage, "Route: none", 35, C.muted)
label(navPage, "Instant teleport is attempted only for loaded doors. Other destinations start a walking route through rooms as they generate.", 82, C.muted)
button(navPage, "Teleport to newest loaded door", function()
    local number = newestRoomNumber()
    if number then requestDoor(number + 1) else notify("No loaded rooms found", true) end
end)
button(navPage, "Teleport to previous loaded door", function()
    local number = currentProgressRoom()
    if number and getDoorForNumber(number) then
        teleportToRoom(number)
    else
        notify("Previous door is not accessible right now", true)
    end
end)
local roomInput = create("TextBox", {
    Text = "",
    PlaceholderText = "Door number (e.g. 50 or 100)",
    ClearTextOnFocus = false,
    Font = Enum.Font.Gotham,
    TextSize = 12,
    TextColor3 = C.text,
    PlaceholderColor3 = C.muted,
    BackgroundColor3 = C.surface,
    BorderSizePixel = 0,
    Size = UDim2.new(1, 0, 0, 37)
}, navPage)
rounded(roomInput, 6)
button(navPage, "GO TO DOOR / queue route", function()
    requestDoor(tonumber(roomInput.Text))
end)
section(navPage, "Quick destinations")
for _, doorNumber in ipairs({1, 50, 100}) do
    button(navPage, "Door " .. doorNumber .. "  /  Go or queue", function()
        requestDoor(doorNumber)
    end)
end
button(navPage, "Cancel active door route", function()
    queuedDoorNumber = nil
    local root = rootPart()
    local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if root and hum then hum:MoveTo(root.Position) end
    notify("Route cancelled")
end)
local savedSpot
button(navPage, "Set personal waypoint here", function()
    local root = rootPart()
    if not root then notify("Character not ready", true) return end
    savedSpot = root.CFrame
    notify("Waypoint stored for this session")
end)
button(navPage, "Return to personal waypoint", function()
    if not savedSpot then notify("No waypoint saved", true) return end
    local char = player.Character
    if not char then notify("Character not ready", true) return end
    teleportIgnoreUntil = os.clock() + 3
    char:PivotTo(savedSpot)
    notify("Waypoint teleport attempted (server may correct)")
end)
label(navPage, "Rooms 50/100 do NOT exist at the start of a normal DOORS run. Route assistance follows regular progression; keys, puzzles and hazards can stop it.", 90, C.muted)

-- Known DOORS entity names; this is deliberately a best-effort detector,
-- not a promise that every game update or entity will be recognized.
local entityNames = {
    RushMoving = true, AmbushMoving = true, FigureRig = true,
    SeekMoving = true, Eyes = true, Screech = true, Halt = true,
    Dread = true, Grumble = true, A60 = true, A90 = true, A120 = true,
    Rush = true, Ambush = true, Figure = true, Seek = true
}
local function findEntities()
    local result = {}
    local seen = {}
    local function consider(obj)
        if entityNames[obj.Name] and (obj:IsA("Model") or obj:IsA("BasePart")) and not seen[obj] then
            seen[obj] = true
            table.insert(result, obj)
        end
    end
    for _, obj in ipairs(Workspace:GetChildren()) do
        consider(obj)
    end
    local entityFolder = Workspace:FindFirstChild("Entities")
    if entityFolder then
        for _, obj in ipairs(entityFolder:GetDescendants()) do consider(obj) end
    end
    local rooms = loadedRooms()
    if rooms then
        for _, obj in ipairs(rooms:GetDescendants()) do consider(obj) end
    end
    return result
end
local function ensureHighlight(object, map, color)
    if map[object] and map[object].Parent then return end
    local highlight = Instance.new("Highlight")
    highlight.Name = "KarpaCurseHighlight"
    highlight.Adornee = object
    highlight.FillColor = color
    highlight.OutlineColor = color
    highlight.FillTransparency = 0.85
    highlight.OutlineTransparency = 0
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    -- World highlights are more reliable when parented to Workspace.
    highlight.Parent = Workspace
    map[object] = highlight
end
local function clearHighlights(map)
    for obj, highlight in pairs(map) do
        highlight:Destroy()
        map[obj] = nil
    end
end
local function refreshHighlights(map, desired, color)
    local currentlyVisible = {}
    for _, object in ipairs(desired) do
        if object.Parent then
            currentlyVisible[object] = true
            ensureHighlight(object, map, color)
        end
    end
    for obj, highlight in pairs(map) do
        if not currentlyVisible[obj] or not obj.Parent then
            highlight:Destroy()
            map[obj] = nil
        end
    end
end
local function restoreEntities()
    for part, original in pairs(transparencyBackup) do
        if part.Parent then part.LocalTransparencyModifier = original end
        transparencyBackup[part] = nil
    end
    for part, original in pairs(anchorBackup) do
        if part.Parent then part.Anchored = original end
        anchorBackup[part] = nil
    end
end
local function applyEntityVisuals(entities)
    if not state.hiddenEntities and not state.frozenEntities then return end
    for _, entity in ipairs(entities) do
        local parts = entity:IsA("BasePart") and {entity} or entity:GetDescendants()
        for _, part in ipairs(parts) do
            if part:IsA("BasePart") then
                if state.hiddenEntities then
                    if transparencyBackup[part] == nil then
                        transparencyBackup[part] = part.LocalTransparencyModifier
                    end
                    part.LocalTransparencyModifier = 1
                end
                if state.frozenEntities then
                    if anchorBackup[part] == nil then
                        anchorBackup[part] = part.Anchored
                    end
                    part.Anchored = true
                end
            end
        end
    end
end

section(entityPage, "Entity tools")
local entityEspToggle = toggle(entityPage, "Highlight known entities", false, function(value)
    state.entityESP = value
    if not value then clearHighlights(entityHighlights) end
end)
local hideToggle = toggle(entityPage, "Hide entity models locally", false, function(value)
    state.hiddenEntities = value
    if not value then
        for part, original in pairs(transparencyBackup) do
            if part.Parent then part.LocalTransparencyModifier = original end
            transparencyBackup[part] = nil
        end
    end
end)
local freezeToggle = toggle(entityPage, "Freeze entity visuals locally", false, function(value)
    state.frozenEntities = value
    if not value then
        for part, original in pairs(anchorBackup) do
            if part.Parent then part.Anchored = original end
            anchorBackup[part] = nil
        end
    end
end)
label(entityPage, "These two visual options do NOT disable damage, enemy AI, or server-side death checks.", 70, C.muted)
button(entityPage, "Scan currently recognized entities", function()
    local entities = findEntities()
    notify("Recognized loaded entities: " .. tostring(#entities))
end)

local function setFullbright(enabled)
    if enabled then
        Lighting.Brightness = 3
        Lighting.Ambient = Color3.fromRGB(195, 195, 205)
        Lighting.OutdoorAmbient = Color3.fromRGB(195, 195, 205)
        Lighting.GlobalShadows = false
    else
        for property, original in pairs(originalLighting) do
            Lighting[property] = original
        end
    end
end
section(visualPage, "Visual helpers")
local doorEspToggle = toggle(visualPage, "Highlight loaded doors", false, function(value)
    state.doorESP = value
    if not value then clearHighlights(doorHighlights) end
end)
local fullbrightToggle = toggle(visualPage, "Fullbright", false, function(value)
    state.fullbright = value
    setFullbright(value)
end)
local fovSlider = slider(visualPage, "Camera FOV", 60, 110, originalFov, function(value)
    state.fov = value
    local camera = Workspace.CurrentCamera
    if camera then camera.FieldOfView = value end
end)
label(visualPage, "Outlines can help locate doors and detected entities. Not every model uses the same naming scheme.", 57)

local function humanoid()
    local character = player.Character
    return character and character:FindFirstChildOfClass("Humanoid")
end
-- Safe-ish adaptive speed: DOORS may correct even small increases.
-- Never keep raising movement speed against a server correction.
local MAX_SPEED_ATTEMPT = 24
local speedSnapCount = 0
local function resetEffectiveSpeed()
    speedSnapCount = 0
    state.effectiveWalkSpeed = math.min(state.walkSpeed, MAX_SPEED_ATTEMPT)
end
local function applySpeed(hum)
    if not hum or not hum.Parent or hum.Health <= 0 then return end
    if walkSpeedBackup[hum] == nil then
        walkSpeedBackup[hum] = hum.WalkSpeed
    end
    if hum.WalkSpeed ~= state.effectiveWalkSpeed then
        hum.WalkSpeed = state.effectiveWalkSpeed
    end
end
local function restoreSpeeds()
    for hum, oldSpeed in pairs(walkSpeedBackup) do
        if hum.Parent then hum.WalkSpeed = oldSpeed end
        walkSpeedBackup[hum] = nil
    end
end

-- A local survival attempt. Only DOORS' server can provide true invulnerability.
-- We make this explicit in the UI rather than promising impossible godmode.
local HEALTH_TARGET = 100000000
local DEAD_STATE = Enum.HumanoidStateType.Dead
local function applySurvivalGuard(hum)
    if not hum or not hum.Parent then return end
    if not healthBackup[hum] then
        local ok, wasEnabled = pcall(function()
            return hum:GetStateEnabled(DEAD_STATE)
        end)
        healthBackup[hum] = {
            maxHealth = hum.MaxHealth,
            breakJointsOnDeath = hum.BreakJointsOnDeath,
            deadStateEnabled = ok and wasEnabled or true
        }
    end
    if hum.BreakJointsOnDeath then hum.BreakJointsOnDeath = false end
    if hum.MaxHealth < HEALTH_TARGET then hum.MaxHealth = HEALTH_TARGET end
    if hum.Health > 0 and hum.Health < HEALTH_TARGET then
        hum.Health = HEALTH_TARGET
    end
    pcall(function()
        if hum:GetStateEnabled(DEAD_STATE) then
            hum:SetStateEnabled(DEAD_STATE, false)
        end
    end)
end
local function restoreHealth()
    for hum, old in pairs(healthBackup) do
        if hum.Parent then
            pcall(function()
                hum.BreakJointsOnDeath = old.breakJointsOnDeath
                hum:SetStateEnabled(DEAD_STATE, old.deadStateEnabled)
                hum.MaxHealth = old.maxHealth
                if hum.Health > hum.MaxHealth then hum.Health = hum.MaxHealth end
            end)
        end
        healthBackup[hum] = nil
    end
end

-- Experimental collision shield. Some DOORS builds check client hitboxes,
-- but server-authoritative damage cannot be disabled by this.
local collisionGuardBackup = setmetatable({}, {__mode = "k"})
local function applyCollisionGuard()
    if not state.godmode then return end
    local char = player.Character
    local hitbox = char and (char:FindFirstChild("Collision") or char:FindFirstChild("CollisionPart"))
    if not hitbox or not hitbox:IsA("BasePart") then return end
    if not collisionGuardBackup[hitbox] then
        collisionGuardBackup[hitbox] = {
            size = hitbox.Size, canTouch = hitbox.CanTouch, canQuery = hitbox.CanQuery
        }
    end
    pcall(function()
        hitbox.Size = Vector3.new(0.55, 0.55, 0.55)
        hitbox.CanTouch = false
        hitbox.CanQuery = false
    end)
end
local function restoreCollisionGuard()
    for hitbox, saved in pairs(collisionGuardBackup) do
        if hitbox.Parent then
            pcall(function()
                hitbox.Size = saved.size
                hitbox.CanTouch = saved.canTouch
                hitbox.CanQuery = saved.canQuery
            end)
        end
        collisionGuardBackup[hitbox] = nil
    end
end

local function restoreCollisions()
    for part, original in pairs(collisionBackup) do
        if part.Parent then part.CanCollide = original end
        collisionBackup[part] = nil
    end
end
section(playerPage, "Movement")
-- The first slider callback is its initialization, not a user edit.
local initializedSpeedSlider = false
local speedLockToggle
local speedSlider = slider(playerPage, "WalkSpeed", 8, 100, 16, function(value)
    state.walkSpeed = value
    resetEffectiveSpeed()
    if not initializedSpeedSlider then return end
    if speedLockToggle then
        -- Automatically turn persistence on when the user moves the slider.
        speedLockToggle.set(true)
    end
    if state.speedLock then applySpeed(humanoid()) end
end)
initializedSpeedSlider = true
speedLockToggle = toggle(playerPage, "Keep selected speed active", false, function(enabled)
    state.speedLock = enabled
    if enabled then
        resetEffectiveSpeed()
        applySpeed(humanoid())
        notify("Speed requested: " .. tostring(state.walkSpeed) .. " / active: " .. tostring(state.effectiveWalkSpeed))
    else
        restoreSpeeds()
        notify("Speed lock off; previous speed restored")
    end
end)
local noclipToggle = toggle(playerPage, "Noclip", false, function(value)
    state.noclip = value
    if not value then restoreCollisions() end
end)
local gravityToggle = toggle(playerPage, "Low gravity (local)", false, function(value)
    state.lowGravity = value
    Workspace.Gravity = value and 65 or originalGravity
end)
local speedStatus = label(playerPage, "Active speed: 16 / Requested: 16", 29, C.text)
label(playerPage, "Adaptive: attempts at most 24 speed; snap-back detection reduces it to 16 if needed. No client script can guarantee faster speed against server movement limits.", 99, C.muted)

section(playerPage, "Survival")
local godmodeToggle = toggle(playerPage, "Godmode (local attempt)", false, function(enabled)
    state.godmode = enabled
    if enabled then
        applySurvivalGuard(humanoid())
        applyCollisionGuard()
        notify("Experimental health and collision shield on; not guaranteed")
    else
        restoreHealth()
        restoreCollisionGuard()
        notify("Survival and collision shield off")
    end
end)
label(playerPage, "Continuously attempts to protect local Humanoid health and death state. DOORS' server can still damage, kill or respawn you.", 82)


-- Third-person view uses a local scriptable follow-camera, because DOORS
-- can re-enable LockFirstPerson during gameplay.
local cameraBackup = {
    mode = player.CameraMode,
    minZoom = player.CameraMinZoomDistance,
    maxZoom = player.CameraMaxZoomDistance,
    cameraType = Workspace.CurrentCamera and Workspace.CurrentCamera.CameraType or Enum.CameraType.Custom
}
local thirdPersonDistance = 9
local function restoreThirdPerson()
    state.thirdPerson = false
    pcall(function()
        player.CameraMode = cameraBackup.mode
        player.CameraMinZoomDistance = cameraBackup.minZoom
        player.CameraMaxZoomDistance = cameraBackup.maxZoom
        local camera = Workspace.CurrentCamera
        if camera then
            camera.CameraType = cameraBackup.cameraType
            if humanoid() then camera.CameraSubject = humanoid() end
        end
    end)
end
local function thirdPersonFrame()
    if not alive or not state.thirdPerson then return end
    local camera = Workspace.CurrentCamera
    local root = rootPart()
    if not camera or not root then return end
    local center = root.Position + Vector3.new(0, 2, 0)
    local requested = center - root.CFrame.LookVector * thirdPersonDistance + Vector3.new(0, 2, 0)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = player.Character and {player.Character} or {}
    params.IgnoreWater = true
    local hit = Workspace:Raycast(center, requested - center, params)
    local cameraPosition = hit and (hit.Position + hit.Normal * 0.65) or requested
    camera.CameraType = Enum.CameraType.Scriptable
    camera.CFrame = CFrame.lookAt(cameraPosition, center)
    camera.Focus = CFrame.new(center)
end
section(visualPage, "Camera controls")
local thirdPersonToggle = toggle(visualPage, "Third-person view", false, function(enabled)
    state.thirdPerson = enabled
    if enabled then
        pcall(function()
            player.CameraMode = Enum.CameraMode.Classic
            player.CameraMinZoomDistance = 0.5
            player.CameraMaxZoomDistance = 20
        end)
        notify("Third person enabled - follows avatar")
    else
        restoreThirdPerson()
        notify("Default camera restored")
    end
end)
slider(visualPage, "Camera distance", 4, 16, 9, function(value)
    thirdPersonDistance = value
end)
label(visualPage, "Local follow camera, controlled by character direction. Disable to return to the normal DOORS camera.", 80, C.muted)
connect(RunService.RenderStepped, thirdPersonFrame)

-- ═══════════════════════════════════════════════════════════════
-- TRUE-ASSET VISUAL MORPH LAB
-- Catalog names reflect DOORS entities. Only actual *accessible game
-- instances* are copied. We never synthesize a fake Rush/Figure model or
-- claim this changes the player's entity identity server-side.
-- ═══════════════════════════════════════════════════════════════
local morphCatalog = {
    {"Rush", "Hotel", {"Rush", "RushMoving", "RushNew", "RushEntity"}},
    {"Ambush", "Hotel", {"Ambush", "AmbushMoving", "AmbushEntity"}},
    {"Figure", "Hotel", {"Figure", "FigureRig", "FigureModel", "FigureRagdoll"}},
    {"Seek", "Hotel", {"Seek", "SeekMoving", "SeekRig", "SeekMonster", "SeekRagdoll"}},
    {"Eyes", "Hotel", {"Eyes", "EyesEntity"}},
    {"Screech", "Hotel", {"Screech", "ScreechRig"}},
    {"Halt", "Hotel", {"Halt", "HaltEntity"}},
    {"Dupe", "Hotel", {"Dupe", "DupeRig"}},
    {"Jack", "Hotel", {"Jack", "JackEntity"}},
    {"Hide", "Hotel", {"Hide", "HideEntity"}},
    {"Timothy", "Hotel", {"Timothy", "TimothySpider"}},
    {"Dread", "Hotel", {"Dread", "DreadEntity"}},
    {"Snare", "Hotel", {"Snare", "SnareEntity"}},
    {"Sally", "Hotel", {"Sally", "SallyRig"}},
    {"Void", "Hotel", {"Void", "VoidEntity"}},
    {"Glitch", "Hotel", {"Glitch", "GlitchEntity"}},
    {"Shadow", "Hotel", {"Shadow", "ShadowEntity"}},
    {"Guiding Light", "Hotel", {"GuidingLight", "GuidingLightEntity"}},
    {"Curious Light", "Hotel", {"CuriousLight", "CuriousLightEntity"}},
    {"Bob", "Hotel", {"Bob", "BobRig"}},
    {"Jeff", "Hotel", {"Jeff", "JeffRig"}},
    {"El Goblino", "Hotel", {"ElGoblino", "ElGoblinoRig"}},
    {"Giggle", "Mines", {"Giggle", "GiggleRig"}},
    {"Grumble", "Mines", {"Grumble", "GrumbleRig"}},
    {"Queen Grumble", "Mines", {"QueenGrumble", "QueenGrumbleRig"}},
    {"Gloombats", "Mines", {"Gloombats", "Gloombat"}},
    {"Louie", "Mines", {"Louie", "LouieRig"}},
    {"Blitz", "Backdoor", {"Blitz", "BlitzMoving"}},
    {"Lookman", "Backdoor", {"Lookman", "TheLookman"}},
    {"Haste", "Backdoor", {"Haste", "HasteMoving"}},
    {"A-60", "Rooms", {"A60", "A-60", "A60Moving"}},
    {"A-90", "Rooms", {"A90", "A-90", "A90Model"}},
    {"A-120", "Rooms", {"A120", "A-120", "A120Moving"}},
    {"Groundskeeper", "Outdoors", {"Groundskeeper", "GroundskeeperSonny"}},
    {"Eyestalk", "Outdoors", {"Eyestalk", "EyestalkEntity"}},
    {"Bramble", "Outdoors", {"Bramble", "BrambleEntity"}},
    {"Surge", "Outdoors", {"Surge", "SurgeEntity"}},
    {"Mandrake", "Outdoors", {"Mandrake", "MandrakeEntity"}},
    {"Monument", "Outdoors", {"Monument", "MonumentEntity"}},
    {"Caws", "Outdoors", {"Caws", "Caw", "CawsRig"}},
    {"Grampy", "Outdoors", {"Grampy", "GrampyRig"}},
    {"Red Light", "Other", {"RedLight", "RedLightEntity"}},
    {"World Lotus", "Other", {"WorldLotus", "WorldLotusEntity"}},
    {"Greed", "Other", {"Greed", "GreedEntity"}},
    {"Jeff the Killer", "Other", {"JeffTheKiller"}}
}
local function normalizedName(name)
    return tostring(name or ""):lower():gsub("[^%w]", "")
end
local aliases = {}
for _, item in ipairs(morphCatalog) do
    for _, alias in ipairs(item[3]) do
        local key = normalizedName(alias)
        aliases[key] = aliases[key] or {}
        table.insert(aliases[key], item[1])
    end
end
local catalogByName = {}
for _, item in ipairs(morphCatalog) do catalogByName[item[1]] = item end
local sourceMap = {}
local cachedSources = {}
local morphVisual
local morphCurrent
local morphScale = 1
local morphFollowOffset = 0
local morphHidden = setmetatable({}, {__mode = "k"})
local morphAura = false
local morphGlow
local morphRows = {}
local scanningAssets = false
local cacheObservedEntity
local morphSelectedLabel
local morphScanLabel

-- Check whether a source is an actual visible model or part with geometry.
local function visualParts(source)
    if source:IsA("BasePart") then return 1 end
    if not source:IsA("Model") then return 0 end
    local count = 0
    for _, d in ipairs(source:GetDescendants()) do
        if d:IsA("BasePart") then
            count = count + 1
            if count >= 300 then break end
        end
    end
    return count
end
local function candidateScore(obj, root)
    local score = visualParts(obj)
    if score == 0 then return -1 end
    score = math.min(score, 40)
    if root == ReplicatedStorage then score = score + 60 end
    if obj:IsA("Model") then score = score + 10 end
    local par = obj.Parent
    if par and normalizedName(par.Name):match("rig") then score = score + 5 end
    return score
end
local function scanEntitySources()
    if scanningAssets then return end
    scanningAssets = true
    morphScanLabel.Text = "Scanning accessible assets..."
    local found = {}
    local count = 0
    for _, root in ipairs({ReplicatedStorage, Workspace, Lighting}) do
        for _, obj in ipairs(root:GetDescendants()) do
            if not alive then break end
            count = count + 1
            if count % 900 == 0 then task.wait() end
            if (obj:IsA("BasePart") or obj:IsA("Model"))
                and not (player.Character and obj:IsDescendantOf(player.Character))
                and not (morphVisual and obj:IsDescendantOf(morphVisual)) then
                local targets = aliases[normalizedName(obj.Name)]
                if targets then
                    local score = candidateScore(obj, root)
                    for _, name in ipairs(targets) do
                        local current = found[name]
                        if score > 0 and (not current or score > current.score) then
                            found[name] = {source = obj, score = score}
                        end
                    end
                end
            end
        end
        if not alive then break end
    end
    -- Keep previously encountered ORIGINAL models available after they
    -- despawn locally. Never confuse a cached original with a fake mesh.
    for name, originalCopy in pairs(cachedSources) do
        if originalCopy then
            local hit = found[name]
            if not hit or not hit.source.Parent then
                found[name] = {source = originalCopy, score = 2, cached = true}
            end
        end
    end
    sourceMap = found
    if cacheObservedEntity then
        for _, hit in pairs(found) do
            if not hit.cached and hit.source:IsDescendantOf(Workspace) then
                cacheObservedEntity(hit.source)
            end
        end
    end
    local available = 0
    for _, spec in ipairs(morphCatalog) do
        local name = spec[1]
        local match = found[name]
        local exists = match and (match.cached or match.source.Parent ~= nil)
        if exists then available = available + 1 end
        if morphRows[name] then
            morphRows[name].Text = (exists and "●  " or "○  ") .. name .. "  /  " .. spec[2] .. ((exists and match.cached) and "  ·  SAVED" or "")
            morphRows[name].TextColor3 = exists and C.green or C.text
        end
    end
    morphScanLabel.Text = tostring(available) .. " of " .. tostring(#morphCatalog) .. " entity assets available in this session"
    dashAssets.Text = "Real-model assets available: " .. available .. "/" .. #morphCatalog
    scanningAssets = false
    notify("Entity asset scan: " .. available .. " model(s) available")
end
local function stopMorph(showNotice)
    if morphGlow then morphGlow:Destroy(); morphGlow = nil end
    if morphVisual then morphVisual:Destroy(); morphVisual = nil end
    for part, old in pairs(morphHidden) do
        if part.Parent then part.LocalTransparencyModifier = old end
        morphHidden[part] = nil
    end
    morphCurrent = nil
    dashMorph.Text = "Morph: human"
    if morphSelectedLabel then morphSelectedLabel.Text = "ACTIVE: HUMAN" end
    if showNotice then notify("Entity morph removed") end
end
local function hideRealAvatar()
    if not morphVisual then return end
    local char = player.Character
    if not char then return end
    for _, child in ipairs(char:GetDescendants()) do
        if child:IsA("BasePart") then
            if morphHidden[child] == nil then morphHidden[child] = child.LocalTransparencyModifier end
            child.LocalTransparencyModifier = 1
        end
    end
end
-- Retain real models seen during a run, even if DOORS removes the live
-- instance afterward. Cached clones have no parent and cannot execute scripts.
cacheObservedEntity = function(obj)
    if not alive or not obj or not obj.Parent then return end
    if not (obj:IsA("Model") or obj:IsA("BasePart")) then return end
    if player.Character and obj:IsDescendantOf(player.Character) then return end
    if morphVisual and obj:IsDescendantOf(morphVisual) then return end
    local targets = aliases[normalizedName(obj.Name)]
    if not targets then return end
    if visualParts(obj) < 1 then return end
    for _, name in ipairs(targets) do
        if not cachedSources[name] then
            local ok, saved = pcall(function() return obj:Clone() end)
            if ok and saved then
                saved.Parent = nil
                cachedSources[name] = saved
                if not sourceMap[name] or not sourceMap[name].source.Parent then
                    sourceMap[name] = {source = saved, cached = true, score = 2}
                    if morphRows[name] then
                        morphRows[name].Text = "●  " .. name .. "  /  " .. catalogByName[name][2] .. "  ·  SAVED"
                        morphRows[name].TextColor3 = C.green
                    end
                end
            end
        end
    end
end
connect(Workspace.DescendantAdded, function(obj)
    if aliases[normalizedName(obj.Name)] then
        task.delay(0.25, function() cacheObservedEntity(obj) end)
    end
end)

local function refreshMorphGlow()
    if morphGlow then morphGlow:Destroy(); morphGlow = nil end
    if not (morphAura and morphVisual) then return end
    local glow = Instance.new("Highlight")
    glow.Name = "KarpaMorphCursedOutline"
    glow.Adornee = morphVisual
    glow.FillColor = Color3.fromRGB(130, 14, 36)
    glow.OutlineColor = Color3.fromRGB(255, 53, 83)
    glow.FillTransparency = 0.92
    glow.OutlineTransparency = 0.15
    glow.DepthMode = Enum.HighlightDepthMode.Occluded
    glow.Parent = morphVisual
    morphGlow = glow
end


-- Rendered fallback for entities whose original model is not replicated.
-- Clearly labelled as an interpretation, never as an original DOORS mesh.
local allowThemedFallback = true
local function buildThemedMorph(name)
    local rig = Instance.new("Model")
    rig.Name = "KarpaThemed_" .. normalizedName(name)
    local humanoidShape = name == "Figure" or name == "Seek"
        or name == "Grumble" or name == "Queen Grumble"
    local color = name == "Seek" and Color3.fromRGB(10, 10, 14)
        or name == "Ambush" and Color3.fromRGB(40, 140, 95)
        or humanoidShape and Color3.fromRGB(121, 52, 50)
        or Color3.fromRGB(132, 18, 36)
    local function block(label, shape, size, position, color3)
        local p = Instance.new("Part")
        p.Name = label
        p.Shape = shape
        p.Size = size
        p.CFrame = CFrame.new(position)
        p.Anchored = true
        p.CanCollide = false
        p.CanTouch = false
        p.CanQuery = false
        p.Color = color3
        p.Material = Enum.Material.Neon
        p.Parent = rig
        return p
    end
    if humanoidShape then
        block("Body", Enum.PartType.Block, Vector3.new(2, 3, 1.2), Vector3.new(0, 1, 0), color)
        block("Head", Enum.PartType.Ball, Vector3.new(1.55, 1.55, 1.55), Vector3.new(0, 3.1, 0), color)
        for _, side in ipairs({-1, 1}) do
            block("Arm", Enum.PartType.Block, Vector3.new(0.65, 3.5, 0.6), Vector3.new(side*1.55, 0.5, 0), color)
            block("Leg", Enum.PartType.Block, Vector3.new(0.75, 3, 0.75), Vector3.new(side*0.6, -2.1, 0), color)
        end
        block("Eye", Enum.PartType.Ball, Vector3.new(0.8, 0.8, 0.3),
            Vector3.new(0, 3.3, -0.7), Color3.fromRGB(255, 255, 245))
    else
        block("Main", Enum.PartType.Ball, Vector3.new(4, 4, 3.6), Vector3.new(0, 1.5, 0), color)
        for _, side in ipairs({-1, 1}) do
            block("Eye", Enum.PartType.Ball, Vector3.new(0.85, 0.85, 0.35),
                Vector3.new(side*0.9, 2.1, -1.5), Color3.fromRGB(255, 255, 245))
        end
        block("Mouth", Enum.PartType.Block, Vector3.new(1.65, 0.4, 0.3),
            Vector3.new(0, 0.8, -1.7), Color3.fromRGB(0, 0, 0))
    end
    return rig
end
local function morphInto(name)
    local entry = sourceMap[name]
    local source = entry and entry.source
    local available = source and (source.Parent or entry.cached)
    local cloned
    if available then
        local originalArchivable = source.Archivable
        pcall(function() source.Archivable = true end)
        local ok, result = pcall(function() return source:Clone() end)
        pcall(function() source.Archivable = originalArchivable end)
        if ok then cloned = result end
    end
    local fallback = not cloned
    if fallback then
        if not allowThemedFallback then
            notify("No accessible original model for " .. name .. "; enable themed fallback", true)
            return
        end
        cloned = buildThemedMorph(name)
    elseif not cachedSources[name] then
        cacheObservedEntity(source)
    end
    stopMorph(false)
    local rig = Instance.new("Model")
    rig.Name = "KarpaEntityVisual_LocalOnly"
    cloned.Parent = rig
    for _, child in ipairs(rig:GetDescendants()) do
        if child:IsA("Script") or child:IsA("LocalScript") or child:IsA("ModuleScript") then
            child:Destroy()
        elseif child:IsA("BasePart") then
            child.Anchored = true
            child.CanCollide = false
            child.CanTouch = false
            child.CanQuery = false
            child.Massless = true
            child.CastShadow = false
        elseif child:IsA("ProximityPrompt") then
            child:Destroy()
        end
    end
    morphVisual = rig
    morphCurrent = name
    pcall(function() rig:ScaleTo(morphScale) end)
    rig.Parent = Workspace
    refreshMorphGlow()
    local mode = fallback and "THEMED LOCAL" or "ORIGINAL LOCAL"
    dashMorph.Text = "Morph: " .. name .. " (" .. mode .. ")"
    morphSelectedLabel.Text = "ACTIVE: " .. string.upper(name) .. " / " .. mode
    notify(name .. " model applied: " .. mode .. ". Enable third person to view.")
end

section(morphPage, "Authentic entity morphs")
label(morphPage, "Copies original DOORS model instances only when accessible in your current client. Your player is not changed on the server. Models without accessible geometry cannot be used.", 75)
morphSelectedLabel = label(morphPage, "ACTIVE: HUMAN", 28, C.green, Enum.Font.GothamBold)
morphScanLabel = label(morphPage, "Press Scan to find accessible original models", 42, C.muted)
toggle(morphPage, "Use themed fallback if an original is unavailable", true, function(value)
    allowThemedFallback = value
end)
button(morphPage, "SCAN ORIGINAL ENTITY ASSETS", function()
    if scanningAssets then notify("Scan already in progress") return end
    task.spawn(scanEntitySources)
end)
button(morphPage, "REMOVE MORPH  /  HUMAN", function() stopMorph(true) end)
local morphGlowToggle = toggle(morphPage, "Red cursed outline (local)", false, function(enabled)
    morphAura = enabled
    refreshMorphGlow()
end)
local morphScaleSlider = slider(morphPage, "Entity visual size %", 40, 200, 100, function(v)
    morphScale = v / 100
    if morphVisual then pcall(function() morphVisual:ScaleTo(morphScale) end) end
end)
local morphOffsetSlider = slider(morphPage, "Visual vertical offset", -10, 10, 0, function(v)
    morphFollowOffset = v / 2
end)
local morphSearch = create("TextBox", {
    Text = "",
    PlaceholderText = "Search: Rush, Figure, Grumble, A-90...",
    ClearTextOnFocus = false,
    Font = Enum.Font.Gotham,
    TextSize = 12,
    TextColor3 = C.text,
    PlaceholderColor3 = C.muted,
    BackgroundColor3 = C.surface,
    BorderSizePixel = 0,
    Size = UDim2.new(1, 0, 0, 38)
}, morphPage)
rounded(morphSearch, 8)
local zones = {"All", "Hotel", "Mines", "Backdoor", "Rooms", "Outdoors", "Other"}
local zoneIndex = 1
local zoneBtn
local function updateMorphFilter()
    local query = normalizedName(morphSearch.Text)
    local zone = zones[zoneIndex]
    for _, spec in ipairs(morphCatalog) do
        local row = morphRows[spec[1]]
        if row then
            local nameMatch = query == "" or normalizedName(spec[1]):find(query, 1, true) ~= nil
            row.Visible = nameMatch and (zone == "All" or spec[2] == zone)
        end
    end
end
zoneBtn = button(morphPage, "ZONE FILTER: ALL  ·  click to change", function()
    zoneIndex = zoneIndex % #zones + 1
    zoneBtn.Text = "ZONE FILTER: " .. string.upper(zones[zoneIndex]) .. "  ·  click to change"
    updateMorphFilter()
end)
connect(morphSearch:GetPropertyChangedSignal("Text"), updateMorphFilter)
section(morphPage, "Entity catalog  ·  tap to morph")
for _, spec in ipairs(morphCatalog) do
    local name, zone = spec[1], spec[2]
    local row = button(morphPage, "○  " .. name .. "  /  " .. zone, function()
        morphInto(name)
    end)
    morphRows[name] = row
end
label(morphPage, "● = original model found. ○ = unavailable until that model loads. Rush/Figure/Seek can have rigs, effects or scripts that never replicate to clients; this tool won't create substitutes.", 90)

-- Morph uses the actual loaded rig, following the player each frame. The
-- original avatar becomes invisible locally and is fully restored on exit.
connect(RunService.RenderStepped, function()
    if not alive or not morphVisual then return end
    local root = rootPart()
    if not root then return end
    hideRealAvatar()
    local follow = root.CFrame * CFrame.new(0, morphFollowOffset, 0)
    pcall(function() morphVisual:PivotTo(follow) end)
end)

-- ═══════════════════════════════════════════════════════════════
-- ITEM LAB + KNOBS SANDBOX
-- No server-side currency mutation or external remote events.
-- ═══════════════════════════════════════════════════════════════
local givenTools = {}
local hotbarEnabled = true
local hotbarFrame = create("Frame", {
    Name = "KarpaItemHotbar",
    AnchorPoint = Vector2.new(0.5, 1),
    Position = UDim2.new(0.5, 0, 1, -72),
    Size = UDim2.fromOffset(536, 59),
    BackgroundColor3 = C.panel,
    BackgroundTransparency = 0.12,
    BorderSizePixel = 0
}, gui)
rounded(hotbarFrame, 9)
stroked(hotbarFrame, C.blue, 1, 0.46)
create("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
    VerticalAlignment = Enum.VerticalAlignment.Center,
    Padding = UDim.new(0, 5),
    SortOrder = Enum.SortOrder.LayoutOrder
}, hotbarFrame)
local function equipLocalSlot(index)
    local tool = givenTools[index]
    if not tool or not tool.Parent then return end
    local hum = humanoid()
    if not hum then return end
    if tool.Parent == player.Character then
        hum:UnequipTools()
    else
        pcall(function() hum:EquipTool(tool) end)
    end
end
local function refreshLocalHotbar()
    if not hotbarFrame or not hotbarFrame.Parent then return end
    for _, child in ipairs(hotbarFrame:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    hotbarFrame.Visible = hotbarEnabled and #givenTools > 0
    for i = 1, math.min(#givenTools, 8) do
        local tool = givenTools[i]
        if tool and tool.Parent then
            local shortName = tool.Name:gsub("%s*%[LOCAL%]","")
            if #shortName > 12 then shortName = shortName:sub(1, 11) .. "…" end
            local slot = create("TextButton", {
                Name = "Slot" .. i,
                LayoutOrder = i,
                Size = UDim2.fromOffset(60, 46),
                Text = tostring(i) .. "\n" .. shortName,
                TextWrapped = true,
                Font = Enum.Font.GothamSemibold,
                TextSize = 10,
                TextColor3 = C.text,
                AutoButtonColor = true,
                BackgroundColor3 = tool.Parent == player.Character and C.blueDark or C.surface,
                BorderSizePixel = 0
            }, hotbarFrame)
            rounded(slot, 6)
            connect(slot.MouseButton1Click, function() equipLocalSlot(i) end)
        end
    end
end
connect(UserInputService.InputBegan, function(input, consumed)
    if consumed or UserInputService:GetFocusedTextBox() then return end
    local slotCodes = {
        [Enum.KeyCode.One]=1, [Enum.KeyCode.Two]=2, [Enum.KeyCode.Three]=3,
        [Enum.KeyCode.Four]=4, [Enum.KeyCode.Five]=5, [Enum.KeyCode.Six]=6,
        [Enum.KeyCode.Seven]=7, [Enum.KeyCode.Eight]=8
    }
    local slot = slotCodes[input.KeyCode]
    if slot and hotbarEnabled then equipLocalSlot(slot) end
end)
section(itemPage, "LOCAL inventory hotbar")
label(itemPage, "Items created here appear in Karpa's own bottom-screen hotbar. Tap their slot or press 1-8 to equip. This does NOT inject server-issued DOORS inventory.", 94, C.muted)
toggle(itemPage, "Show Karpa hotbar", true, function(v)
    hotbarEnabled = v
    refreshLocalHotbar()
end)
local function cleanTools()
    for _, tool in ipairs(givenTools) do
        if tool and tool.Parent then tool:Destroy() end
    end
    table.clear(givenTools)
    refreshLocalHotbar()
end
local function createLocalToy(display, color, lightType)
    local backpack = player:FindFirstChildOfClass("Backpack")
    if not backpack then notify("Backpack unavailable", true) return end
    local tool = Instance.new("Tool")
    tool.Name = display .. "  [LOCAL]"
    tool.ToolTip = "Karpa's Curse client-side toy. Not an official DOORS inventory item."
    tool.RequiresHandle = true
    tool.CanBeDropped = false
    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Size = Vector3.new(0.5, 1.35, 0.5)
    handle.Material = Enum.Material.Neon
    handle.Color = color
    handle.CanCollide = false
    handle.Massless = true
    handle.Parent = tool
    local light
    if lightType == "SpotLight" then
        light = Instance.new("SpotLight")
        light.Angle = 95
        light.Range = 35
        light.Brightness = 3
    else
        light = Instance.new("PointLight")
        light.Range = 22
        light.Brightness = 1.9
    end
    light.Color = color
    if light:IsA("SpotLight") then light.Face = Enum.NormalId.Front end
    light.Enabled = true
    light.Parent = handle
    connect(tool.Activated, function()
        light.Enabled = not light.Enabled
        handle.Material = light.Enabled and Enum.Material.Neon or Enum.Material.SmoothPlastic
    end)
    tool.Parent = backpack
    table.insert(givenTools, tool)
    refreshLocalHotbar()
    notify(display .. " added to Karpa hotbar (client-only)")
end
local function findOriginalTool(name)
    local wanted = normalizedName(name)
    for _, root in ipairs({ReplicatedStorage, Workspace}) do
        for i, obj in ipairs(root:GetDescendants()) do
            if i % 800 == 0 then task.wait() end
            if obj:IsA("Tool") and normalizedName(obj.Name) == wanted
                and not (player.Character and obj:IsDescendantOf(player.Character))
                and not obj:IsDescendantOf(playerGui) then
                return obj
            end
        end
    end
    return nil
end
local fetchingItem = false
local function grantLocalItem(name)
    if fetchingItem then notify("Item search already active", true) return end
    fetchingItem = true
    task.spawn(function()
        local source = findOriginalTool(name)
        if not alive then fetchingItem = false return end
        if not source then
            notify("Original template unavailable; creating a local " .. name .. " prop")
            local color = normalizedName(name) == "crucifix" and Color3.fromRGB(220, 180, 75) or C.blue
            createLocalToy(name, color, "PointLight")
            fetchingItem = false
            return
        end
        local backpack = player:FindFirstChildOfClass("Backpack")
        if not backpack then
            notify("Your Backpack is not available", true)
            fetchingItem = false
            return
        end
        local success, copy = pcall(function() return source:Clone() end)
        if not success or not copy then
            notify("Found " .. name .. " but it cannot be copied", true)
        else
            copy:SetAttribute("KarpaLocalCopy", true)
            copy.Parent = backpack
            table.insert(givenTools, copy)
            refreshLocalHotbar()
            notify("Local " .. name .. " copied into Karpa hotbar; server might ignore it")
        end
        fetchingItem = false
    end)
end

section(itemPage, "Original item templates")
label(itemPage, "Copies an original DOORS Tool only if your client has access to a template. It is NOT a server-issued item and may lack gameplay effects or be removed.", 70)
local itemInput = create("TextBox", {
    Text = "",
    PlaceholderText = "DOORS item name (e.g. Crucifix)",
    Font = Enum.Font.Gotham, TextSize = 12, ClearTextOnFocus = false,
    TextColor3 = C.text, PlaceholderColor3 = C.muted,
    BackgroundColor3 = C.surface, BorderSizePixel = 0,
    Size = UDim2.new(1, 0, 0, 38)
}, itemPage)
rounded(itemInput, 7)
button(itemPage, "FIND & COPY LOCAL TOOL TEMPLATE", function()
    if itemInput.Text == "" then notify("Enter an item name", true) return end
    grantLocalItem(itemInput.Text)
end)
section(itemPage, "Quick-search item names")
for _, name in ipairs({"Flashlight", "Crucifix", "Vitamins", "Lockpick", "Lighter", "Candle", "Lantern", "Skeleton Key", "Shears", "Bandage", "Glowstick", "Bulklight", "Shakelight"}) do
    button(itemPage, "Try original  /  " .. name, function() grantLocalItem(name) end)
end
section(itemPage, "Guaranteed local toys")
button(itemPage, "Create cursed red lantern", function()
    createLocalToy("Cursed Lantern", Color3.fromRGB(255, 44, 75), "PointLight")
end)
button(itemPage, "Create electric blue flashlight", function()
    createLocalToy("Spectral Flashlight", C.blue, "SpotLight")
end)
button(itemPage, "Create toxic green glowstick", function()
    createLocalToy("Toxic Glowstick", Color3.fromRGB(61, 255, 107), "PointLight")
end)
button(itemPage, "Clear items made by Karpa's Curse", function()
    cleanTools()
    notify("Locally issued tools cleared")
end)

section(itemPage, "REAL run Gold helper")
label(itemPage, "Attempts collection of existing nearby GoldPile loot prompts. It cannot create spendable Gold or Knobs; only the game server can credit real purchases at Jeff's Shop.", 96, C.muted)
local goldAttempted = setmetatable({}, {__mode = "k"})
local goldAttempts = 0
local goldStatus = label(itemPage, "Nearby gold attempts: 0", 28, C.text)
local function collectNearbyGold()
    local root = rootPart()
    local rooms = loadedRooms()
    if not root or not rooms then return end
    local now = os.clock()
    local tried = 0
    for _, room in ipairs(rooms:GetChildren()) do
        if tonumber(room.Name) then
            for _, obj in ipairs(room:GetDescendants()) do
                if normalizedName(obj.Name) == "goldpile" and (obj:IsA("Model") or obj:IsA("BasePart")) then
                    for _, prompt in ipairs(obj:GetDescendants()) do
                        if prompt:IsA("ProximityPrompt") and prompt.Enabled then
                            local parent = prompt.Parent
                            local position = parent and (parent:IsA("Attachment") and parent.WorldPosition or
                                parent:IsA("BasePart") and parent.Position or
                                parent:IsA("Model") and parent:GetPivot().Position)
                            if position and (root.Position-position).Magnitude < math.min(12, prompt.MaxActivationDistance)
                                and now - (goldAttempted[prompt] or -100) >= 3.5 then
                                goldAttempted[prompt] = now
                                pcall(function()
                                    prompt:InputHoldBegin()
                                    task.delay(math.clamp(prompt.HoldDuration, 0, 8) + 0.15, function()
                                        if prompt.Parent then pcall(function() prompt:InputHoldEnd() end) end
                                    end)
                                end)
                                goldAttempts = goldAttempts + 1
                                tried = tried + 1
                                if tried >= 5 then return end
                            end
                        end
                    end
                end
            end
        end
    end
end
toggle(itemPage, "Auto collect nearby GoldPiles", false, function(enabled)
    state.autoGold = enabled
    notify(enabled and "Nearby gold collection attempts enabled" or "Gold auto-collect disabled")
end)
button(itemPage, "Try collecting nearby Gold now", function()
    collectNearbyGold()
    goldStatus.Text = "Gold pickup attempts: " .. goldAttempts .. " (not verified purchases)"
end)
task.spawn(function()
    while alive do
        if state.autoGold then
            pcall(collectNearbyGold)
            if goldStatus and goldStatus.Parent then
                goldStatus.Text = "Gold pickup attempts: " .. goldAttempts .. " (server verifies balance)"
            end
        end
        task.wait(1.2)
    end
end)

section(itemPage, "Knobs  /  sandbox only")
label(itemPage, "DOORS stores real Knobs server-side. These counters are an isolated local simulator, not spendable currency or a shop bypass.", 64)
local sandboxKnobs = 0
local knobText = label(itemPage, "SIMULATED KNOBS: 0", 36, C.green, Enum.Font.GothamBold)
local function addSandboxKnobs(amount)
    sandboxKnobs = math.clamp(sandboxKnobs + amount, 0, 999999999)
    knobText.Text = "SIMULATED KNOBS: " .. tostring(sandboxKnobs)
    notify("Sandbox counter only — real Knobs unchanged")
end
button(itemPage, "+50 simulated Knobs", function() addSandboxKnobs(50) end)
button(itemPage, "+500 simulated Knobs", function() addSandboxKnobs(500) end)
button(itemPage, "+10,000 simulated Knobs", function() addSandboxKnobs(10000) end)
button(itemPage, "Reset sandbox Knobs", function()
    sandboxKnobs = 0
    knobText.Text = "SIMULATED KNOBS: 0"
end)

-- Red entity atmosphere effect: entirely local, removable.
local redVisionEffect
section(visualPage, "Curse atmosphere")
local redVisionToggle = toggle(visualPage, "Red entity vision", false, function(enabled)
    if redVisionEffect then redVisionEffect:Destroy(); redVisionEffect = nil end
    if enabled then
        local fx = Instance.new("ColorCorrectionEffect")
        fx.Name = "KarpaLocalRedEntityVision"
        fx.TintColor = Color3.fromRGB(255, 135, 143)
        fx.Saturation = -0.12
        fx.Contrast = 0.2
        fx.Parent = Lighting
        redVisionEffect = fx
    end
end)
label(visualPage, "Visual-only effects: no entity abilities, damage or other-player appearance changes.", 47)

section(toolsPage, "Interaction")
button(toolsPage, "Trigger up to 5 nearby prompts", function()
    if type(fireproximityprompt) ~= "function" then
        notify("Your environment does not provide fireproximityprompt", true)
        return
    end
    local root = rootPart()
    if not root then notify("Character not ready", true) return end
    local eligible = {}
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and obj.Enabled then
            local parent = obj.Parent
            local position
            if parent and parent:IsA("BasePart") then
                position = parent.Position
            elseif parent and parent:IsA("Attachment") and parent.Parent and parent.Parent:IsA("BasePart") then
                position = parent.Parent.Position
            end
            if position and (root.Position - position).Magnitude <= obj.MaxActivationDistance then
                table.insert(eligible, obj)
                if #eligible >= 5 then break end
            end
        end
    end
    for _, prompt in ipairs(eligible) do pcall(fireproximityprompt, prompt) end
    notify("Sent " .. #eligible .. " nearby prompt activation(s)")
end)
label(toolsPage, "This does not automatically grant achievements or bypass proximity checks enforced by the server.", 62)
section(toolsPage, "DOORS achievements")
label(toolsPage, "Use the Achievements tab for goal guidance and in-range interaction automation. Only the DOORS server decides whether an achievement is unlocked.", 76)
-- =========================================
-- DOORS ACHIEVEMENT ASSISTANT (V2.5)
-- No server remotes, BadgeService award calls, or fake completed badges.
-- The auto actions can only attempt nearby, currently visible prompts.
-- Actual achievements and progress are controlled by DOORS.
-- =========================================
section(achievementPage, "Real achievement helper")
label(achievementPage, "Automates selected nearby interactions, not achievement awards. Rare, discontinued, social and modifier badges still need their real objectives.", 73)

local goals = {
    {"Welcome Back", "Join DOORS on another day. This cannot be accelerated in one session."},
    {"Buddy System", "Start a run together with a Roblox friend."},
    {"Out Of My Way", "Survive Rush. Optional Auto Hide attempts a visible nearby hiding prompt."},
    {"Rebound", "Survive Ambush. Auto Hide is best-effort and may not handle repeated passes."},
    {"You Can Run", "Complete the Seek chase. Automatic pathfinding is not included."},
    {"Sshh!", "Successfully complete the Library encounter with Figure."},
    {"In Plain Sight", "Stay out of an entity's line of sight without using a hiding spot."},
    {"Not Five Stars", "Escape the Hotel with at least a +50% modifier bonus."},
    {"Hotel Hell", "Escape the Hotel with at least a +150% modifier bonus."},
    {"Going Down", "Enter the Stairwell during a real run."},
    {"Going Up", "Escape the Stairwell during a real run."},
}
local goalIndex = 1
local goalTitle = label(achievementPage, "", 26, C.text, Enum.Font.GothamBold)
local goalDescription = label(achievementPage, "", 69)
local function showGoal()
    local goal = goals[goalIndex]
    goalTitle.Text = goal[1] .. " (" .. goalIndex .. "/" .. #goals .. ")"
    goalDescription.Text = goal[2]
end
showGoal()
button(achievementPage, "Next achievement goal  >", function()
    goalIndex = goalIndex % #goals + 1
    showGoal()
end)
button(achievementPage, "<  Previous achievement goal", function()
    goalIndex = (goalIndex - 2) % #goals + 1
    showGoal()
end)

section(achievementPage, "Display achievement above head")
label(achievementPage, "Enter a DOORS achievement's internal ID or name. First try the game's official selection remote (if available and allowed); the local title preview works for any text but does not unlock the achievement.", 115, C.muted)
local selectedFlexTitle = ""
local localFlexBillboard
local flexEntry = create("TextBox", {
    Text = "Hotel Hell", PlaceholderText = "Achievement name or internal ID",
    TextColor3 = C.text, PlaceholderColor3 = C.muted,
    Font = Enum.Font.Gotham, TextSize = 13,
    BackgroundColor3 = C.surface, BorderSizePixel = 0,
    ClearTextOnFocus = false, Size = UDim2.new(1, 0, 0, 39)
}, achievementPage)
rounded(flexEntry, 7)
local function refreshFlexDisplay()
    if localFlexBillboard then localFlexBillboard:Destroy(); localFlexBillboard = nil end
    if selectedFlexTitle == "" then return end
    local char = player.Character
    local head = char and char:FindFirstChild("Head")
    if not head then return end
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "KarpaLocalAchievementDisplay"
    billboard.Size = UDim2.fromOffset(250, 50)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.7, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 130
    billboard.Adornee = head
    billboard.Parent = gui
    local textLabel = Instance.new("TextLabel")
    textLabel.BackgroundColor3 = Color3.fromRGB(10, 12, 20)
    textLabel.BackgroundTransparency = 0.17
    textLabel.Size = UDim2.fromScale(1, 1)
    textLabel.Text = "✦ " .. selectedFlexTitle .. " ✦"
    textLabel.TextWrapped = true
    textLabel.Font = Enum.Font.GothamBold
    textLabel.TextSize = 16
    textLabel.TextColor3 = Color3.fromRGB(255, 210, 90)
    textLabel.Parent = billboard
    rounded(textLabel, 8)
    local stroke = Instance.new("UIStroke")
    stroke.Color = C.blue
    stroke.Thickness = 1
    stroke.Parent = textLabel
    localFlexBillboard = billboard
end
local function chooseFlexDisplay()
    selectedFlexTitle = flexEntry.Text:sub(1, 65)
    if selectedFlexTitle == "" then notify("Enter an achievement name", true) return end
    refreshFlexDisplay()
    local info = ReplicatedStorage:FindFirstChild("EntityInfo")
    local remote = info and info:FindFirstChild("FlexAchievement")
    if remote and remote:IsA("RemoteEvent") then
        local ok = pcall(function() remote:FireServer(selectedFlexTitle) end)
        notify(ok and "Official achievement selection requested; local title shown" or "Only local title was applied")
    else
        notify("Local title applied; official selection remote unavailable")
    end
end
button(achievementPage, "DISPLAY SELECTED ACHIEVEMENT", chooseFlexDisplay)
button(achievementPage, "Remove custom title", function()
    selectedFlexTitle = ""
    refreshFlexDisplay()
    notify("Local title removed")
end)
connect(player.CharacterAdded, function()
    task.delay(1, function()
        if alive then refreshFlexDisplay() end
    end)
end)

section(achievementPage, "Auto interactions")
label(achievementPage, "Uses Roblox's normal ProximityPrompt input API, with original hold times and activation distances. Leave options off for challenge runs that ban certain actions.", 85)
local autoLootToggle = toggle(achievementPage, "Auto collect nearby items", false, function(v)
    state.autoLoot = v
    notify(v and "Auto-loot armed (nearby prompts only)" or "Auto-loot disabled")
end)
local autoDoorToggle = toggle(achievementPage, "Auto open nearby doors", false, function(v)
    state.autoDoors = v
end)
local autoSwitchToggle = toggle(achievementPage, "Auto use nearby switches", false, function(v)
    state.autoSwitches = v
end)
local autoHideToggle = toggle(achievementPage, "Auto hide on Rush/Ambush alert", false, function(v)
    state.autoHide = v
    notify(v and "Auto-hide armed: only visible, nearby hiding prompts" or "Auto-hide disabled")
end)
label(achievementPage, "Auto Hide may fail if the hiding prompt isn't visible, a closet is occupied, or DOORS overrides the interaction. Do not enable it for no-hiding challenges.", 86, C.muted)

section(achievementPage, "Run activity")
local achievementRoomLabel = label(achievementPage, "Current progress: scanning...", 28, C.text)
local achievementEntityLabel = label(achievementPage, "Last entity detected: none", 32, C.text)
local achievementActionsLabel = label(achievementPage, "Confirmed prompt activations: 0", 28, C.text)
label(achievementPage, "These are observations, NOT awarded achievements. Confirm real unlocks in the game's Achievements menu, ideally after rejoining.", 73)

local activePrompts = setmetatable({}, {__mode = "k"})
local promptBusy = setmetatable({}, {__mode = "k"})
local promptLastAttempt = setmetatable({}, {__mode = "k"})
local promptActivationCount = 0
local lastThreatAt = 0
local lastThreatName = "none"

local function promptDescription(prompt)
    local ancestor = prompt.Parent
    local parentName = ancestor and ancestor.Name or ""
    local grandName = ancestor and ancestor.Parent and ancestor.Parent.Name or ""
    return (prompt.Name .. " " .. prompt.ActionText .. " " .. prompt.ObjectText .. " " .. parentName .. " " .. grandName):lower()
end
local function hasAny(s, terms)
    for _, part in ipairs(terms) do
        if string.find(s, part, 1, true) then return true end
    end
    return false
end
local function promptCategory(prompt)
    local name = promptDescription(prompt)
    -- Never auto-buy, revive, donate, use paid items, or start/quit runs.
    if hasAny(name, {"buy", "purchase", "shop", "robux", "donate", "revive", "trade", "exit", "elevator", "reset", "teleport", "sell"}) then
        return nil
    end
    if hasAny(name, {"hide", "closet", "wardrobe", "locker", "hiding"}) then
        return "hide"
    end
    if hasAny(name, {"key", "gold", "coin", "collect", "pickup", "pick up", "grab", "loot", "item", "book", "battery", "bandage", "lighter", "vitamin", "drawer", "chest", "scanner", "module"}) then
        return "loot"
    end
    if hasAny(name, {"lever", "switch", "breaker", "fuse", "button", "activate", "generator"}) then
        return "switch"
    end
    if hasAny(name, {"door", "unlock", "open"}) then
        return "door"
    end
    return nil
end
local function promptPosition(prompt)
    local parent = prompt.Parent
    if not parent then return nil end
    if parent:IsA("Attachment") then return parent.WorldPosition end
    if parent:IsA("BasePart") then return parent.Position end
    if parent:IsA("Model") then return parent:GetPivot().Position end
    return nil
end
local function isPromptAvailable(prompt)
    if not alive or not prompt.Parent or not prompt.Enabled or not activePrompts[prompt] then return false end
    local root = rootPart()
    local pos = promptPosition(prompt)
    if not root or not pos then return false end
    return (root.Position - pos).Magnitude <= math.max(0, prompt.MaxActivationDistance - 0.15)
end
local function tryPrompt(prompt, category)
    if promptBusy[prompt] or not isPromptAvailable(prompt) then return end
    local now = os.clock()
    local previous = promptLastAttempt[prompt] or -999
    -- Prevent repeated accidental toggling of doors/levers/closets.
    if now - previous < (category == "hide" and 9 or 5) then return end
    promptLastAttempt[prompt] = now
    promptBusy[prompt] = true
    task.spawn(function()
        -- Standard Roblox prompt input; preserves the game's hold duration.
        local began = pcall(function() prompt:InputHoldBegin() end)
        if began then
            task.wait(math.clamp(prompt.HoldDuration, 0, 15) + 0.12)
            pcall(function() prompt:InputHoldEnd() end)
        end
        promptBusy[prompt] = nil
    end)
end

connect(ProximityPromptService.PromptShown, function(prompt)
    activePrompts[prompt] = true
end)
connect(ProximityPromptService.PromptHidden, function(prompt)
    activePrompts[prompt] = nil
end)
connect(ProximityPromptService.PromptTriggered, function(prompt, who)
    if who == player then
        promptActivationCount = promptActivationCount + 1
        achievementActionsLabel.Text = "Confirmed prompt activations: " .. promptActivationCount
    end
end)

local hideThreatNames = {
    RushMoving = true, Rush = true, AmbushMoving = true,
    Ambush = true, A60 = true, A120 = true
}
local function detectThreat(obj)
    if not obj or not hideThreatNames[obj.Name] then return end
    if not (obj:IsA("Model") or obj:IsA("BasePart")) then return end
    lastThreatName = obj.Name
    lastThreatAt = os.clock()
    if achievementEntityLabel.Parent then
        achievementEntityLabel.Text = "Last entity detected: " .. lastThreatName
    end
end
connect(Workspace.DescendantAdded, detectThreat)

local lastPromptCycle = 0
connect(RunService.Heartbeat, function()
    if not alive or os.clock() - lastPromptCycle < 0.3 then return end
    lastPromptCycle = os.clock()
    local threatActive = state.autoHide and (os.clock() - lastThreatAt < 4)
    if not (state.autoLoot or state.autoDoors or state.autoSwitches or threatActive) then return end
    for prompt in pairs(activePrompts) do
        if prompt:IsA("ProximityPrompt") then
            local category = promptCategory(prompt)
            if (category == "loot" and state.autoLoot)
                or (category == "door" and state.autoDoors)
                or (category == "switch" and state.autoSwitches)
                or (category == "hide" and threatActive) then
                tryPrompt(prompt, category)
            end
        end
    end
end)

-- Read-only run progress from known DOORS state when present.
local function readCurrentRoom()
    local data = ReplicatedStorage:FindFirstChild("GameData")
    local latest = data and data:FindFirstChild("LatestRoom")
    if latest and latest:IsA("ValueBase") then return tostring(latest.Value) end
    local attribute = player:GetAttribute("CurrentRoom")
    if type(attribute) == "number" then return tostring(attribute) end
    local newest = newestRoomNumber()
    return newest and tostring(newest) .. " (loaded)" or "unknown"
end

task.spawn(function()
    while alive do
        achievementRoomLabel.Text = "Current room/progress: " .. readCurrentRoom()
        dashRoom.Text = "Current room: " .. readCurrentRoom()
        task.wait(1.4)
    end
end)

section(toolsPage, "Lifecycle")
local resetButton = button(toolsPage, "Reset all toggles and movement")
local unloadButton = button(toolsPage, "Unload Karpa's Curse")
label(toolsPage, "No remote code, web requests, external assets, or credential access.  •  V2.5", 61)

local function resetAll()
    queuedDoorNumber = nil
    stopMorph(false)
    morphGlowToggle.set(false)
    morphScaleSlider.set(100)
    morphOffsetSlider.set(0)
    cleanTools()
    sandboxKnobs = 0
    knobText.Text = "SIMULATED KNOBS: 0"
    redVisionToggle.set(false)
    noclipToggle.set(false)
    entityEspToggle.set(false)
    doorEspToggle.set(false)
    hideToggle.set(false)
    freezeToggle.set(false)
    fullbrightToggle.set(false)
    gravityToggle.set(false)
    godmodeToggle.set(false)
    thirdPersonToggle.set(false)
    selectedFlexTitle = ""
    refreshFlexDisplay()
    speedSlider.set(16)
    speedLockToggle.set(false)
    autoLootToggle.set(false)
    autoDoorToggle.set(false)
    autoSwitchToggle.set(false)
    autoHideToggle.set(false)
    restoreHealth()
    fovSlider.set(originalFov)
    restoreCollisions()
    restoreEntities()
    notify("Client settings reset")
end

-- Reset/unload buttons have their own named click connections so they don't
-- depend on rebinding or destroying UI elements.
connect(resetButton.MouseButton1Click, function() resetAll() end)

local function cleanup()
    if not alive then return end
    queuedDoorNumber = nil
    stopMorph(false)
    morphGlowToggle.set(false)
    cleanTools()
    thirdPersonToggle.set(false)
    restoreThirdPerson()
    selectedFlexTitle = ""
    refreshFlexDisplay()
    redVisionToggle.set(false)
    for _, saved in pairs(cachedSources) do if saved then saved:Destroy() end end
    table.clear(cachedSources)
    -- Restore the client effects before destroying the interface.
    state.noclip = false
    state.speedLock = false
    state.godmode = false
    state.doorESP = false
    state.entityESP = false
    state.hiddenEntities = false
    state.frozenEntities = false
    state.fullbright = false
    state.lowGravity = false
    state.autoLoot = false
    state.autoDoors = false
    state.autoSwitches = false
    state.autoHide = false
    state.autoGold = false
    restoreCollisions()
    restoreEntities()
    clearHighlights(doorHighlights)
    clearHighlights(entityHighlights)
    setFullbright(false)
    Workspace.Gravity = originalGravity
    if Workspace.CurrentCamera then Workspace.CurrentCamera.FieldOfView = originalFov end
    restoreSpeeds()
    restoreHealth()
    restoreCollisionGuard()
    if cameraConnection then cameraConnection:Disconnect() end
    alive = false
    for _, connection in ipairs(connections) do connection:Disconnect() end
    if gui then gui:Destroy() end
    if environment.KarpasCurseCleanup == cleanup then
        environment.KarpasCurseCleanup = nil
    end
end
environment.KarpasCurseCleanup = cleanup
connect(unloadButton.MouseButton1Click, cleanup)
connect(closeButton.MouseButton1Click, cleanup)

local launcher = create("TextButton", {
    Name = "Launcher",
    Text = "K",
    Font = Enum.Font.GothamBlack,
    TextSize = 20,
    TextColor3 = C.blue,
    BackgroundColor3 = C.bg,
    Size = UDim2.fromOffset(42, 42),
    Position = UDim2.fromOffset(12, 52),
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Visible = true
}, gui)
rounded(launcher, 9)
stroked(launcher, C.blue, 1.4, 0.1)
connect(launcher.MouseButton1Click, function() main.Visible = not main.Visible end)
connect(minimizeButton.MouseButton1Click, function() main.Visible = false end)
connect(UserInputService.InputBegan, function(input, processed)
    if not processed and input.KeyCode == Enum.KeyCode.RightShift then
        main.Visible = not main.Visible
    end
end)

-- Drag only the header; don't rely on deprecated GuiObject.Draggable.
local dragging, dragOrigin, frameOrigin, touchId = false, nil, nil, nil
connect(header.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragOrigin = input.Position
        frameOrigin = main.AbsolutePosition + main.AbsoluteSize / 2
        touchId = input.UserInputType == Enum.UserInputType.Touch and input or nil
    end
end)
connect(UserInputService.InputChanged, function(input)
    if not dragging then return end
    if touchId then
        if input ~= touchId then return end
    elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then
        return
    end
    local delta = input.Position - dragOrigin
    local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
    local half = main.AbsoluteSize / 2
    local center = frameOrigin + delta
    center = Vector2.new(
        math.clamp(center.X, half.X, math.max(half.X, viewport.X - half.X)),
        math.clamp(center.Y, half.Y, math.max(half.Y, viewport.Y - half.Y))
    )
    main.Position = UDim2.fromOffset(center.X, center.Y)
end)
connect(UserInputService.InputEnded, function(input)
    if (touchId and input == touchId) or (not touchId and input.UserInputType == Enum.UserInputType.MouseButton1) then
        dragging = false
        touchId = nil
    end
end)

-- One movement connection rather than stacking another every time the UI runs.
connect(RunService.Stepped, function()
    if not state.noclip then return end
    local char = player.Character
    if not char then return end
    for _, descendant in ipairs(char:GetDescendants()) do
        if descendant:IsA("BasePart") then
            if collisionBackup[descendant] == nil then
                collisionBackup[descendant] = descendant.CanCollide
            end
            descendant.CanCollide = false
        end
    end
end)
connect(player.CharacterAdded, function(character)
    local hum = character:WaitForChild("Humanoid", 6)
    if alive and hum then
        if state.speedLock then applySpeed(hum) end
        if state.godmode then applySurvivalGuard(hum); applyCollisionGuard() end
    end
end)

-- Reapply after other local scripts have had an opportunity to change WalkSpeed.
-- One shared connection handles both the speed and survival toggles.
connect(RunService.RenderStepped, function()
    if not alive then return end
    local hum = humanoid()
    if state.speedLock then applySpeed(hum) end
    if state.godmode then applySurvivalGuard(hum); applyCollisionGuard() end
end)

-- Detect sudden movement opposite to the held walking direction. This is
-- a best-effort sign of server snap-back, not an anti-cheat bypass.
local speedLastPosition
local speedLastDirection
local speedLastSample = 0
connect(RunService.Heartbeat, function()
    if not alive then return end
    local now = os.clock()
    if now - speedLastSample < 0.12 then return end
    speedLastSample = now
    local root = rootPart()
    local hum = humanoid()
    if root and hum then
        local position = root.Position
        local move = hum.MoveDirection
        local flatDirection = Vector3.new(move.X, 0, move.Z)
        if state.speedLock and now > teleportIgnoreUntil and speedLastPosition and speedLastDirection then
            local displacement = position - speedLastPosition
            local flatDisplacement = Vector3.new(displacement.X, 0, displacement.Z)
            if flatDirection.Magnitude > 0.65 and speedLastDirection:Dot(flatDirection) > 0.7
                and flatDisplacement.Magnitude > 3.5 and flatDisplacement:Dot(flatDirection.Unit) < -2.5 then
                speedSnapCount = speedSnapCount + 1
                local baseline = math.min(16, state.walkSpeed)
                state.effectiveWalkSpeed = math.max(baseline, state.effectiveWalkSpeed - (speedSnapCount >= 2 and 8 or 4))
                applySpeed(hum)
                notify("Snap-back detected; active speed reduced to " .. tostring(state.effectiveWalkSpeed), true)
            end
        end
        speedLastPosition, speedLastDirection = position, flatDirection
    else
        speedLastPosition, speedLastDirection = nil, nil
    end
end)

-- When the requested door has not generated, follow real doors in sequence.
-- This does NOT create rooms, bypass locked puzzles or guarantee progression.
local lastRouteMoveAt = 0
local function advanceDoorRoute()
    if not queuedDoorNumber then return end
    local root = rootPart()
    local hum = humanoid()
    if not root or not hum or hum.Health <= 0 then return end
    local progress = currentProgressRoom()
    if not progress then return end
    local desired = queuedDoorNumber
    local destinationDoor = getDoorForNumber(desired)
    local targetCf
    if destinationDoor and (root.Position - destinationDoor.Position).Magnitude < 10 then
        queuedDoorNumber = nil
        notify("Reached Door " .. desired .. " area")
        return
    end
    if destinationDoor and (root.Position - destinationDoor.Position).Magnitude < 90 then
        targetCf = destinationDoor
    else
        targetCf = getDoorCFrame(getRoom(progress))
            or getDoorForNumber(progress + 1)
    end
    if not targetCf then
        routeStatus.Text = "Route: Door " .. desired .. " / next door unavailable or puzzle"
        return
    end
    local distance = (root.Position - targetCf.Position).Magnitude
    if distance < 11 then
        -- Interact only with a normally visible and reachable door prompt.
        local room = getRoom(progress)
        local door = getDoorObject(room)
        if door then
            for _, obj in ipairs(door:GetDescendants()) do
                if obj:IsA("ProximityPrompt") and promptCategory(obj) == "door" then
                    tryPrompt(obj, "door")
                end
            end
        end
        return
    end
    local now = os.clock()
    if now - lastRouteMoveAt < 1.5 then return end
    lastRouteMoveAt = now
    local goalPosition = targetCf.Position
    local path = PathfindingService:CreatePath({
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = false,
        WaypointSpacing = 5
    })
    local ok = pcall(function() path:ComputeAsync(root.Position, goalPosition) end)
    if ok and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()
        local point = waypoints[math.min(2, #waypoints)]
        if point then
            hum:MoveTo(point.Position)
            return
        end
    end
    hum:MoveTo(goalPosition)
end
task.spawn(function()
    while alive do
        if queuedDoorNumber then
            local ok, err = pcall(advanceDoorRoute)
            if not ok then warn("[Karpa's Curse] Route: " .. tostring(err)) end
        end
        task.wait(0.85)
    end
end)

-- Low-frequency refresh: handles new/removed rooms and entities while avoiding
-- thousands of GUI connections or an ESP scan on every render frame.
task.spawn(function()
    while alive do
        if state.fullbright then setFullbright(true) end
        if speedStatus and speedStatus.Parent then
            speedStatus.Text = "Active speed: " .. tostring(state.speedLock and state.effectiveWalkSpeed or "default") .. " / Requested: " .. tostring(state.walkSpeed)
        end
        local latest = newestRoomNumber()
        if roomDisplay and roomDisplay.Parent then
            roomDisplay.Text = "Current: " .. tostring(currentProgressRoom() or "?") .. "  /  newest generated: " .. tostring(latest or "?")
            routeStatus.Text = queuedDoorNumber and ("Auto-route to Door " .. queuedDoorNumber .. " (regular progression)") or "Route: none"
        end
        if state.doorESP then
            local candidates = {}
            local rooms = loadedRooms()
            if rooms then
                for _, room in ipairs(rooms:GetChildren()) do
                    local door = getDoorObject(room)
                    if door then table.insert(candidates, door) end
                end
            end
            refreshHighlights(doorHighlights, candidates, C.blue)
        end
        if state.entityESP or state.hiddenEntities or state.frozenEntities then
            local entities = findEntities()
            if state.entityESP then
                refreshHighlights(entityHighlights, entities, C.red)
            end
            applyEntityVisuals(entities)
        end
        task.wait(1.3)
    end
end)

-- Show the navigation page by default.
activeTab = "Dashboard"
for id, page in pairs(pages) do
    local active = id == activeTab
    page.Visible = active
    tabButtons[id].BackgroundColor3 = active and C.blueDark or C.surface
    tabButtons[id].TextColor3 = active and C.text or C.muted
end
notify("V2.5 / Entity Lab ready  ·  scan models in MORPHS")
