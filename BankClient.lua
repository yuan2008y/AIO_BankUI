-- AIO for TrinityCore 3.3.5 with WoW client 3.3.5
local AIO = AIO or require("AIO")

if AIO.AddAddon() then
    return
end

local BankSystemHandler = AIO.AddHandlers("BankSystem", {})
-- 主背景界面UI
local BankAddon = CreateFrame("Frame", "BankAddonFrame", UIParent)
BankAddon:SetSize(350, 450)
BankAddon:SetPoint("CENTER")
BankAddon:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
BankAddon:SetBackdropBorderColor(0.4, 0.4, 0.4)
BankAddon:SetBackdropColor(0.5, 0.5, 0.5)
BankAddon:Hide()

-- 标题背景图UI
BankAddon.titleBg = BankAddon:CreateTexture(nil, "ARTWORK")
BankAddon.titleBg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
BankAddon.titleBg:SetSize(350, 64)
BankAddon.titleBg:SetPoint("TOP", 0, 12)

-- 标题文本
BankAddon.title = BankAddon:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
BankAddon.title:SetPoint("TOP", BankAddon.titleBg, "TOP", 0, -14)
BankAddon.title:SetText("帐号金币银行")
BankAddon.title:SetTextColor(1, 0.82, 0)

-- 金币余额显示
BankAddon.goldText = BankAddon:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
BankAddon.goldText:SetPoint("TOP", BankAddon.title, "BOTTOM", 0, -30)
BankAddon.goldText:SetText("余额: 0 金")
BankAddon.goldText:SetTextColor(1, 1, 0)

-- 关闭按钮
BankAddon.closeButton = CreateFrame("Button", nil, BankAddon, "UIPanelCloseButton")
BankAddon.closeButton:SetPoint("TOPRIGHT", BankAddon, "TOPRIGHT", -8, -8)
BankAddon.closeButton:SetSize(32, 32)

BankAddon.closeButton:SetScript("OnClick", function()
    BankAddon.loadingBar:SetScript("OnUpdate", nil)
    BankAddon.loadingBar:Reset()
    BankAddon.actionButton:Enable()
    BankAddon:Hide()
end)

-- 存取下拉菜单，默认存放
local action = "存放"
BankAddon.actionDropdown = CreateFrame("Frame", "DepWith", BankAddon, "UIDropDownMenuTemplate")
BankAddon.actionDropdown:SetPoint("TOP", BankAddon.goldText, "BOTTOM", 0, -30)
UIDropDownMenu_SetWidth(BankAddon.actionDropdown, 150)
UIDropDownMenu_Initialize(BankAddon.actionDropdown, function(self, level, menuList)
    local info = UIDropDownMenu_CreateInfo()
    info.func = function(self)
        action = self.value
        UIDropDownMenu_SetSelectedValue(BankAddon.actionDropdown, self.value)
    end

    info.text, info.value = "存放", "存放"
    info.checked = action == "存放"
    UIDropDownMenu_AddButton(info)

    info.text, info.value = "取出", "取出"
    info.checked = action == "取出"
    UIDropDownMenu_AddButton(info)
end)
UIDropDownMenu_SetSelectedValue(BankAddon.actionDropdown, "存放")

-- 数量输入框
BankAddon.amountBox = CreateFrame("EditBox", nil, BankAddon, "InputBoxTemplate")
BankAddon.amountBox:SetSize(150, 32)
BankAddon.amountBox:SetPoint("TOP", BankAddon.actionDropdown, "BOTTOM", 0, -20)
BankAddon.amountBox:SetAutoFocus(false)
BankAddon.amountBox:SetNumeric(true)
BankAddon.amountBox:SetMaxLetters(10)
BankAddon.amountBox:SetTextInsets(5, 5, 0, 0)

-- 数量输入框后面的金币图标
BankAddon.goldIcon = BankAddon.amountBox:CreateTexture(nil, "OVERLAY")
BankAddon.goldIcon:SetTexture("Interface\\MoneyFrame\\UI-MoneyIcons")
BankAddon.goldIcon:SetTexCoord(0, 0.25, 0, 1)
BankAddon.goldIcon:SetSize(16, 16)
BankAddon.goldIcon:SetPoint("LEFT", BankAddon.amountBox, "RIGHT", 5, 0)

-- 进度条
local function CreateLoadingBar(parent)
    local loadingBarFrame = CreateFrame("Frame", "LoadingBarFrame", parent)
    loadingBarFrame:SetSize(200, 20)  -- 调整大小
    loadingBarFrame:SetPoint("TOP", parent.amountBox, "BOTTOM", 0, -30)
    loadingBarFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    loadingBarFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.9)  -- 背景颜色

    -- 创建进度条前景
    local loadingBarTexture = loadingBarFrame:CreateTexture(nil, "OVERLAY")
    loadingBarTexture:SetTexture("Interface\\Buttons\\BLUEGRAD64")  -- 使用蓝色渐变材质
    loadingBarTexture:SetPoint("LEFT", loadingBarFrame, "LEFT", 4, 0)
    loadingBarTexture:SetSize(0, 10)  -- 初始宽度为0
    loadingBarTexture:SetTexCoord(0, 0, 0, 1)  -- 确保纹理从最左侧开始

    -- 百分比文字
    local loadingBarPercentage = loadingBarFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    loadingBarPercentage:SetPoint("CENTER", loadingBarFrame, "CENTER", 0, 0)
    loadingBarPercentage:SetText("0%")

    -- 火花效果
    local loadingBarSpark = loadingBarFrame:CreateTexture(nil, "OVERLAY")
    loadingBarSpark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    loadingBarSpark:SetBlendMode("ADD")
    loadingBarSpark:SetWidth(20)
    loadingBarSpark:SetHeight(loadingBarFrame:GetHeight() * 2)
    loadingBarSpark:SetPoint("LEFT", loadingBarTexture, "RIGHT", -10, 0)

    -- 设置进度
    function loadingBarFrame:SetProgress(progress)
        local width = (loadingBarFrame:GetWidth() - 8) * progress
        loadingBarTexture:SetWidth(width)
        loadingBarPercentage:SetText(math.floor(progress * 100) .. "%")
        loadingBarSpark:SetPoint("LEFT", loadingBarTexture, "RIGHT", -10, 0)
        if progress > 0 and progress < 1 then
            loadingBarSpark:Show()
        else
            loadingBarSpark:Hide()
        end
    end

    -- 重置进度条
    function loadingBarFrame:Reset()
        loadingBarTexture:SetWidth(-1)
        loadingBarTexture:SetTexCoord(0, 0, 0, 1)  -- 重置纹理坐标
        loadingBarPercentage:SetText("0%")
        loadingBarSpark:Hide()
    end

    -- 将元素赋值给loadingBarFrame对象
    loadingBarFrame.texture = loadingBarTexture
    loadingBarFrame.percentage = loadingBarPercentage
    loadingBarFrame.spark = loadingBarSpark

    return loadingBarFrame
end

BankAddon.loadingBar = CreateLoadingBar(BankAddon)

-- 提交按钮
BankAddon.actionButton = CreateFrame("Button", nil, BankAddon, "UIPanelButtonTemplate")
BankAddon.actionButton:SetSize(150, 30)
BankAddon.actionButton:SetPoint("TOP", BankAddon.loadingBar, "BOTTOM", 0, -20)
BankAddon.actionButton:SetText("提交")
BankAddon.actionButton:SetNormalFontObject("GameFontNormalLarge")
BankAddon.actionButton:SetHighlightFontObject("GameFontHighlightLarge")

BankAddon.actionButton:SetScript("OnClick", function()
    local amount = BankAddon.amountBox:GetNumber()
    if amount > 0 then
        BankAddon.actionButton:Disable()
        BankAddon.loadingBar:Reset()
        BankAddon.amountBox:ClearFocus()

        local duration = 2
        local startTime = GetTime()
        BankAddon.loadingBar:SetScript("OnUpdate", function()
            local progress = (GetTime() - startTime) / duration
            if progress >= 1 then
                progress = 1
                BankAddon.loadingBar:SetScript("OnUpdate", nil)
                BankAddon.actionButton:Enable()
                if action == "存放" then
                    AIO.Handle("BankSystem", "DepositGold", amount)
                elseif action == "取出" then
                    AIO.Handle("BankSystem", "WithdrawGold", amount)
                end
            end
            BankAddon.loadingBar:SetProgress(progress)
        end)
    else
        UIErrorsFrame:AddMessage("请输入有效的金币数", 1.0, 0.1, 0.1, 1.0)
    end
end)

-- 更新余额金额
function BankAddon:UpdateGold(amount)
    print("Updating gold amount: " .. amount)  -- 调试信息

    BankAddon.goldText:SetText("余额: " .. amount .. " 金")
	
end

-- 注册呼出界面命令
SLASH_BANK1 = "/bank"
SlashCmdList["BANK"] = function()
    AIO.Handle("BankSystem", "RequestGoldAmount")
    BankAddon:Show()
    BankAddon.loadingBar:Reset()
end

-- 注册更新金币数量
function BankSystemHandler.UpdateGoldAmount(player, amount)
    print("Received update gold amount message: " .. amount)  -- 调试信息
    BankAddon:UpdateGold(amount)
end
-----------------------------------------以下为注册迷你地图图标代码-----------------------------------
-- 创建迷你地图按钮
local minimapButton = CreateFrame("Button", "BankMinimapButton", Minimap)
minimapButton:SetSize(32, 32)  -- 按钮大小
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 10, -10)  -- 初始位置

-- 设置按钮图标（金币样式）
minimapButton.icon = minimapButton:CreateTexture(nil, "BACKGROUND")
minimapButton.icon:SetTexture("Interface\\MoneyFrame\\UI-MoneyIcons")  -- 魔兽内置金币图标
minimapButton.icon:SetTexCoord(0, 0.25, 0, 1)  -- 截取金币部分
minimapButton.icon:SetAllPoints()  -- 填充整个按钮

-- 悬停高亮效果
minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

-- 点击事件：打开银行UI（和/bank命令相同）
minimapButton:SetScript("OnClick", function()
    AIO.Handle("BankSystem", "RequestGoldAmount")  -- 请求最新余额
    BankAddon:Show()  -- 显示银行窗口
    BankAddon.loadingBar:Reset()
end)

-- 悬停提示
minimapButton:SetScript("OnEnter", function()
    GameTooltip:SetOwner(minimapButton, "ANCHOR_LEFT")
    GameTooltip:SetText("账号金币银行", 1, 1, 1)
    GameTooltip:AddLine("点击打开银行界面", 0.6, 0.8, 1, true)
    GameTooltip:Show()
end)
minimapButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- 允许拖动调整位置
minimapButton:SetMovable(true)
minimapButton:RegisterForDrag("LeftButton")
minimapButton:SetScript("OnDragStart", function()
    minimapButton:StartMoving()
end)
minimapButton:SetScript("OnDragStop", function()
    minimapButton:StopMovingOrSizing()
end)
