--[[
	RoShout Client
	By @WhosJat
	Last Updated 4/27/2026
]]

print("Successfully Loaded RoShout Client!")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cmdr = require(ReplicatedStorage:WaitForChild("CmdrClient"))

Cmdr:SetActivationKeys({Enum.KeyCode.F2}) --Change this to whatever you want

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local TextService = game:GetService("TextService")

local player = Players.LocalPlayer
local Event = ReplicatedStorage.Events:WaitForChild("GlobalAnnouncement")

-- CONFIG
local FRAME_HEIGHT = 44
local SPACING = 8
local FADE_TIME = 0.45
local DEFAULT_DISPLAY = 10
local VISIBLE_SLOTS = 5
local SEND_TO_CHAT = true

-- VISUAL
local AVATAR_W = 32
local AVATAR_H = 32
local PADDING = 8
local RIGHT_MARGIN = 10
local TEXT_SIZE = 24
local FONT = Enum.Font.GothamBold
local HOLDER_POSITION = UDim2.new(0.5, 0, 0.106, 0)
local HOLDER_ANCHOR = Vector2.new(0.5, 0)

-- STATE
local screenGui
local holder
local active = {}
local pending = {}
local topRunning = false

-- HELPERS
local function RichEscape(s)
	if not s then
		return ""
	end
	s = tostring(s)
	s = s:gsub("&", "&amp;")
	s = s:gsub("<", "&lt;")
	s = s:gsub(">", "&gt;")
	return s
end


local function MaxTextWidth()
	if not holder or holder.AbsoluteSize.X == 0 then
		return 400
	end
	local total = holder.AbsoluteSize.X
	local max = math.max(100, math.floor(total * 0.5))
	return math.max(80, math.min(max, total - (AVATAR_W + PADDING + RIGHT_MARGIN + 40)))
end


local function MeasureTextWidth(text)
	local maxW = MaxTextWidth()
	local size = TextService:GetTextSize(text, TEXT_SIZE, FONT, Vector2.new(maxW, FRAME_HEIGHT * 4))
	local w = math.min(size.X, maxW)
	return math.max(24, math.ceil(w)), size.Y
end


local function EnsureGui()
	if screenGui and screenGui.Parent then
		return screenGui
	end
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AnnouncementUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = player:WaitForChild("PlayerGui")
	holder = Instance.new("Frame")
	holder.Name = "AnnouncementHolder"
	holder.AnchorPoint = HOLDER_ANCHOR
	holder.Size = UDim2.new(1, 0, 0, VISIBLE_SLOTS * (FRAME_HEIGHT + SPACING))
	holder.Position = HOLDER_POSITION
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Parent = screenGui
	
	local layout = Instance.new("UIListLayout")
	layout.Name = "AnnouncementList"
	layout.Padding = UDim.new(0, SPACING)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder
	
	holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		for _,child in ipairs(holder:GetChildren()) do
			if child:IsA("Frame") and child.Name == "AnnounceEntry" then
				local content = child:FindFirstChild("Content")
				local textLabel = child:FindFirstChild("TextLabel")
				local avatar = child:FindFirstChild("Avatar")
				if content and textLabel and avatar then
					local textW,_ = MeasureTextWidth(textLabel.Text)
					local contentW = AVATAR_W + PADDING + textW + RIGHT_MARGIN
					content.Size = UDim2.new(0, contentW, 1, 0)
					avatar.Position = UDim2.new(0, 0, 0.5, -AVATAR_H/2)
					textLabel.Position = UDim2.new(0, AVATAR_W + PADDING, 0, 0)
					textLabel.Size = UDim2.new(0, textW, 1, 0)
				end
			end
		end
	end)
	return screenGui
end


local function NextLayoutOrder()
	if not holder then
		return 1
	end
	local count = 0
	for _,child in ipairs(holder:GetChildren()) do
		if child:IsA("Frame") and child.Name == "AnnounceEntry" then
			count = count + 1
		end
	end
	return count + 1
end


local function TrimActive()
	while #active > VISIBLE_SLOTS do
		local entry = table.remove(active, 1)
		if entry and entry.Container and entry.Container.Parent then
			entry.Container:Destroy()
		end
	end
end


local function RemoveEntry(entry)
	if not entry then
		return
	end
	if entry._fading then
		return
	end
	entry._fading = true

	local tweenText = TweenService:Create(entry.TextLabel, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {TextTransparency = 1})
	local tweenAvatar = TweenService:Create(entry.Avatar, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {ImageTransparency = 1})

	if entry.HoverInfo then
		entry.HoverInfo:Destroy()
	end
	tweenText:Play(); tweenAvatar:Play()
	task.spawn(function()
		tweenText.Completed:Wait()
		for i,v in ipairs(active) do
			if v == entry then
				table.remove(active, i)
				break
			end
		end
		if entry.Container and entry.Container.Parent then
			entry.Container:Destroy()
		end
	end)
end


local function GetThumbnail(userId)
	local ok,image = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
	end)
	if ok and type(image) == "string" and #image > 0 then
		return image
	end
	return ""
end


local function ResolveToUserId(value)
	if not value then
		return nil
	end
	if type(value) == "number" then
		return value
	end
	local n = tonumber(value)
	if n then
		return n
	end
	local p = Players:FindFirstChild(tostring(value))
	if p then
		return p.UserId
	end
	return nil
end

local function CreateEntry(senderIdOrName, senderName, message)
	EnsureGui()

	local displayText = "@" .. tostring(senderName) .. ": " .. tostring(message)

	local frame = Instance.new("Frame")
	frame.Name = "AnnounceEntry"
	frame.Size = UDim2.new(1, 0, 0, FRAME_HEIGHT)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.LayoutOrder = NextLayoutOrder()
	frame.Parent = holder

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.new(0.5, 0, 0.5, 0)
	local textW, textH = MeasureTextWidth(displayText)
	local contentW = AVATAR_W + PADDING + textW + RIGHT_MARGIN
	content.Size = UDim2.new(0, contentW, 1, 0)
	content.Parent = frame

	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.Size = UDim2.new(0, AVATAR_W, 0, AVATAR_H)
	avatar.Position = UDim2.new(0, 0, 0.5, -AVATAR_H/2)
	avatar.BackgroundTransparency = 1
	avatar.BorderSizePixel = 0
	avatar.ImageTransparency = 1
	avatar.ScaleType = Enum.ScaleType.Fit
	avatar.Parent = content

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = avatar

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "TextLabel"
	textLabel.BackgroundTransparency = 1
	textLabel.Position = UDim2.new(0, AVATAR_W + PADDING, 0, 0)
	textLabel.Size = UDim2.new(0, textW, 1, 0)
	textLabel.Font = FONT
	textLabel.TextSize = TEXT_SIZE
	textLabel.TextWrapped = true
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.TextYAlignment = Enum.TextYAlignment.Center
	textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	textLabel.TextTransparency = 1
	textLabel.TextStrokeTransparency = 0
	textLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	textLabel.RichText = true
	textLabel.Text = RichEscape(displayText)
	textLabel.Parent = content

	local hoverInfo = Instance.new("TextLabel")
	hoverInfo.Name = "HoverInfo"
	hoverInfo.BackgroundTransparency = 1
	hoverInfo.Size = UDim2.new(0, 150, 0, 18)
	hoverInfo.Position = UDim2.new(0.5, 0, 1, 2)
	hoverInfo.AnchorPoint = Vector2.new(0.5, 0)
	hoverInfo.Font = Enum.Font.Gotham
	hoverInfo.TextColor3 = Color3.fromRGB(200, 200, 200)
	hoverInfo.TextScaled = true
	hoverInfo.TextTransparency = 1
	hoverInfo.TextXAlignment = Enum.TextXAlignment.Center
	hoverInfo.Parent = avatar

	local resolvedUserId = ResolveToUserId(senderIdOrName)
	if resolvedUserId then
		local thumb = GetThumbnail(resolvedUserId)
		if thumb and #thumb > 0 then
			avatar.Image = thumb
		end
		local plr = Players:GetPlayerByUserId(resolvedUserId)
		if plr then
			hoverInfo.Text = string.format("%s (@%s)", plr.DisplayName, plr.Name)
		end
	end

	avatar.MouseEnter:Connect(function()
		TweenService:Create(hoverInfo, TweenInfo.new(0.25), {TextTransparency = 0}):Play()
	end)
	avatar.MouseLeave:Connect(function()
		TweenService:Create(hoverInfo, TweenInfo.new(0.25), {TextTransparency = 1}):Play()
	end)

	if holder and holder.AbsoluteSize and holder.AbsoluteSize.X == 0 then
		local conn
		conn = holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if holder.AbsoluteSize.X > 0 then
				local newTextW,_ = MeasureTextWidth(textLabel.Text)
				local newContentW = AVATAR_W + PADDING + newTextW + RIGHT_MARGIN
				content.Size = UDim2.new(0, newContentW, 1, 0)
				textLabel.Size = UDim2.new(0, newTextW, 1, 0)
				conn:Disconnect()
			end
		end)
	end
	return {
		Container = frame,
		ContainerFrame = frame,
		Content = content,
		TextLabel = textLabel,
		Avatar = avatar,
		HoverInfo = hoverInfo,
		remaining = DEFAULT_DISPLAY,
		_fading = false
	}
end


local function FillSlots()
	while #active < VISIBLE_SLOTS and #pending > 0 do
		local nextItem = table.remove(pending, 1)
		local entry = CreateEntry(
			nextItem.senderIdOrName,
			nextItem.senderName,
			nextItem.message
		)
		entry.remaining = tonumber(nextItem.displayTime) or DEFAULT_DISPLAY
		table.insert(active, entry)
		local tweenInText = TweenService:Create(entry.TextLabel, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency = 0})
		local tweenInAvatar = TweenService:Create(entry.Avatar, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {ImageTransparency = 0})
		tweenInText:Play(); tweenInAvatar:Play()
	end
	TrimActive()
end


local function StartTop()
	if topRunning then
		return
	end
	if #active == 0 then
		FillSlots()
		if #active == 0 then
			return
		end
	end
	topRunning = true
	task.spawn(function()
		local lastTick = tick()
		while true do
			FillSlots()
			if #active == 0 then
				break
			end
			local now = tick()
			local dt = now - lastTick
			lastTick = now
			for i = #active, 1, -1 do
				local entry = active[i]
				if not entry then
					table.remove(active, i)
				else
					if not entry._fading then
						entry.remaining = (entry.remaining or DEFAULT_DISPLAY) - dt
					end
					if i > 1 and entry.remaining <= 0 and not entry._fading then
						RemoveEntry(entry)
					end
				end
			end
			local top = active[1]
			if top and (top.remaining <= 0) and (not top._fading) then
				RemoveEntry(top)
				task.wait(.04)
				lastTick = tick()
				continue
			end
			task.wait(.1)
		end
		topRunning = false
	end)
end


local function SafeFireChat(message)
	local ok, channel = pcall(function()
		local chFolder = TextChatService:FindFirstChild("TextChannels")
		if not chFolder then
			return nil
		end
		return chFolder:FindFirstChild("RBXGeneral")
	end)
	if ok and channel and type(channel.DisplaySystemMessage) == "function" then
		local success = pcall(function()
			channel:DisplaySystemMessage(message)
		end)
		if success then
			return
		end
	end

	pcall(function()
		StarterGui:SetCore("ChatMakeSystemMessage", {
			Text = message;
			Color = Color3.fromRGB(180, 200, 255);
			Font = Enum.Font.SourceSansBold;
			FontSize = Enum.FontSize.Size18;
		})
	end)
end


local function EnqueueAnnouncement(...)
	local args = {...}
	local senderIdOrName, senderName, message, displayTime
	if #args == 1 and type(args[1]) == "table" then
		local t = args[1]
		senderIdOrName = t.userId or t.senderIdOrName or t.name or t.senderName or t.sender
		senderName = t.name or t.senderName or t.sender or tostring(senderIdOrName)
		message = t.message or ""
		displayTime = t.displayTime
	elseif #args >= 3 and type(args[1]) == "number" then
		senderIdOrName = args[1]
		senderName = tostring(args[2])
		message = tostring(args[3] or "")
		displayTime = args[4]
	else
		if #args >= 2 then
			senderIdOrName = tostring(args[1])
			senderName = tostring(args[1])
			message = tostring(args[2] or "")
			displayTime = args[3]
		else
			message = tostring(args[1] or "")
			senderIdOrName = "Server"
			senderName = "Server"
		end
	end

	local chatMsg = ("[ANNOUNCEMENT] @%s: %s"):format(tostring(senderName), tostring(message))
	
	if SEND_TO_CHAT then
		SafeFireChat(chatMsg)
	end
	if #active < VISIBLE_SLOTS then
		local entry = CreateEntry(senderIdOrName, senderName, message)
		entry.remaining = tonumber(displayTime) or DEFAULT_DISPLAY
		table.insert(active, entry)
		local tweenInText = TweenService:Create(entry.TextLabel, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency = 0})
		local tweenInAvatar = TweenService:Create(entry.Avatar, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {ImageTransparency = 0})
		tweenInText:Play(); tweenInAvatar:Play()
		TrimActive()
		StartTop()
	else
		table.insert(pending, {
			senderIdOrName = senderIdOrName,
			senderName = senderName,
			message = message,
			displayTime = displayTime or DEFAULT_DISPLAY
		})
	end
end


Event.OnClientEvent:Connect(function(...)
	local ok, err = pcall(EnqueueAnnouncement, ...)
	if not ok then
	end
end)