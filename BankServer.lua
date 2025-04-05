local AIO = AIO or require("AIO")

local BankSystemHandler = AIO.AddHandlers("BankSystem", {})

local config = {
    debug = true
}

local function debugMessage(...)
    if config.debug then
        print("DEBUG:", ...)
    end
end



-- 存钱（DepositGold）
function BankSystemHandler.DepositGold(player, amount)
    local accountId = player:GetAccountId()
    local playerCopper = player:GetCoinage()  -- 获取玩家当前铜币数量
    local amountCopper = amount * 10000  -- 将金币转换为铜币

    -- 1. 检查输入金额是否有效
    if amount <= 0 then
        player:SendBroadcastMessage("存款失败：请输入有效的金额。")
        return
    end

    -- 2. 检查玩家是否有足够的金币（精确到铜币）
    if playerCopper < amountCopper then
        player:SendBroadcastMessage("存款失败：您没有足够的金币。（需要："..amount.."金，拥有："..(playerCopper/10000).."金）")
        return
    end

    -- 3. 查询当前银行余额
    local query = string.format("SELECT gold_amount FROM account_bank WHERE account_id = %d", accountId)
    local result = AuthDBQuery(query)
    local currentBankGold = result and result:GetInt32(0) or 0

    -- 4. 检查银行上限
    if currentBankGold + amount > 2147483647 then
        player:SendBroadcastMessage("存款失败：超过银行上限 21 亿金。")
        return
    end

    -- 5. 计算新余额
    local newBankGold = currentBankGold + amount

    -- 6. 更新数据库
    AuthDBExecute(string.format(
        "INSERT INTO account_bank (account_id, gold_amount) VALUES (%d, %d) ON DUPLICATE KEY UPDATE gold_amount = %d",
        accountId, newBankGold, newBankGold
    ))

    -- 7. 扣除玩家金币（精确到铜币）
    player:ModifyMoney(-amountCopper)

    -- 8. 更新客户端显示
    AIO.Msg():Add("BankSystem", "UpdateGoldAmount", newBankGold):Send(player)
    player:SendBroadcastMessage(string.format("成功存入 %d 金。当前余额: %d 金", amount, newBankGold))
end

-- 取钱（WithdrawGold）
function BankSystemHandler.WithdrawGold(player, amount)
    local accountId = player:GetAccountId()
    local playerCopper = player:GetCoinage()  -- 玩家当前铜币

    -- 1. 查询当前银行余额（旧值）
    local query = string.format("SELECT gold_amount FROM account_bank WHERE account_id = %d", accountId)
    local result = AuthDBQuery(query)
    local currentBankGold = result and result:GetInt32(0) or 0

    -- 2. 检查余额是否足够
    if currentBankGold < amount then
        player:SendBroadcastMessage("取款失败：银行余额不足。")
        return
    end

    -- 3. 检查玩家背包是否会超限（21亿铜币 = 21万金）
    if (amount * 10000) + playerCopper > 2147483647 then
        player:SendBroadcastMessage("取款失败：背包金币已达上限。")
        return
    end

    -- 4. 直接计算新余额（避免二次查询）
    local newBankGold = currentBankGold - amount

    -- 5. 更新数据库
    AuthDBExecute(string.format(
        "UPDATE account_bank SET gold_amount = %d WHERE account_id = %d",
        newBankGold, accountId
    ))

    -- 6. 给予玩家金币
    player:ModifyMoney(amount * 10000)

    -- 7. 直接发送计算后的新余额（不再查数据库！）
    AIO.Msg():Add("BankSystem", "UpdateGoldAmount", newBankGold):Send(player)
    player:SendBroadcastMessage("成功取出 " .. amount .. " 金。当前余额: " .. newBankGold .. " 金")
end

function BankSystemHandler.SendGoldAmount(player)
    local accountId = player:GetAccountId()

    local query = string.format("SELECT gold_amount FROM account_bank WHERE account_id = %d", accountId)
    local result = AuthDBQuery(query)
    local goldAmount = result and result:GetInt32(0) or 0

    print("Sending gold amount: " .. goldAmount)  -- 调试信息
    AIO.Msg():Add("BankSystem", "UpdateGoldAmount", goldAmount):Send(player)
end

function BankSystemHandler.RequestGoldAmount(player)
    BankSystemHandler.SendGoldAmount(player)
end
