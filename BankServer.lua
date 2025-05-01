local AIO = AIO or require("AIO")
local BankSystemHandler = AIO.AddHandlers("BankSystem", {})

local config = {
    debug = true,
    maxGold = 2147483647, -- 21亿金币上限
    logRetention = 100    -- 保留最近100条日志
}

-- 调试信息输出
local function debugMessage(...)
    if config.debug then
        print("DEBUG:", ...)
    end
end

-- 请求跟踪和日志记录
local pendingRequests = {}
local operationLog = {}

-- 生成唯一请求ID
local function GenerateRequestId(accountId)
    return string.format("%d-%d-%d", accountId, os.time(), math.random(1000, 9999))
end

-- 记录操作日志
local function LogOperation(accountId, operationType, amount, requestId, status)
    local logEntry = {
        time = os.time(),
        accountId = accountId,
        type = operationType,
        amount = amount,
        requestId = requestId,
        status = status or "SUCCESS"
    }
    table.insert(operationLog, logEntry)
    
    -- 日志清理
    if #operationLog > config.logRetention then
        table.remove(operationLog, 1)
    end
end

-- 存钱（DepositGold）
function BankSystemHandler.DepositGold(player, amount, clientRequestId)
    local accountId = player:GetAccountId()
    local requestId = clientRequestId or GenerateRequestId(accountId)
    
    -- 检查重复请求
    if pendingRequests[requestId] then
        debugMessage("重复存款请求被忽略:", requestId)
        return
    end
    pendingRequests[requestId] = true
    
    local playerCopper = player:GetCoinage()
    local amountCopper = amount * 10000

    -- 1. 检查输入金额是否有效
    if amount <= 0 then
        player:SendBroadcastMessage("存款失败：请输入有效的金额。")
        LogOperation(accountId, "DEPOSIT", amount, requestId, "INVALID_AMOUNT")
        pendingRequests[requestId] = nil
        return
    end

    -- 2. 检查玩家是否有足够的金币
    if playerCopper < amountCopper then
        player:SendBroadcastMessage(string.format("存款失败：您没有足够的金币。（需要：%d金，拥有：%.2f金）", 
            amount, playerCopper/10000))
        LogOperation(accountId, "DEPOSIT", amount, requestId, "INSUFFICIENT_FUNDS")
        pendingRequests[requestId] = nil
        return
    end

    -- 3. 查询当前银行余额
    local query = string.format("SELECT gold_amount FROM account_bank WHERE account_id = %d", accountId)
    local result = AuthDBQuery(query)
    if not result then
        player:SendBroadcastMessage("存款失败：无法查询银行余额。")
        LogOperation(accountId, "DEPOSIT", amount, requestId, "QUERY_FAILED")
        pendingRequests[requestId] = nil
        return
    end
    
    local currentBankGold = result:GetInt32(0) or 0

    -- 4. 检查银行上限
    if currentBankGold + amount > config.maxGold then
        player:SendBroadcastMessage("存款失败：超过银行上限 "..(config.maxGold/10000).." 金。")
        LogOperation(accountId, "DEPOSIT", amount, requestId, "EXCEED_LIMIT")
        pendingRequests[requestId] = nil
        return
    end

    -- 5. 计算新余额
    local newBankGold = currentBankGold + amount
    
    -- 6. 开始事务处理 - 先扣玩家金币
    local deductSuccess, deductError = pcall(function()
        player:ModifyMoney(-amountCopper)
        return true
    end)
    
    if not deductSuccess then
        player:SendBroadcastMessage("存款失败：无法扣除金币。")
        LogOperation(accountId, "DEPOSIT", amount, requestId, "DEDUCT_FAILED")
        pendingRequests[requestId] = nil
        return
    end
    
    -- 7. 更新数据库
    local updateSuccess, updateError = pcall(function()
        local query = string.format(
            "INSERT INTO account_bank (account_id, gold_amount) VALUES (%d, %d) ON DUPLICATE KEY UPDATE gold_amount = %d",
            accountId, newBankGold, newBankGold
        )
        return AuthDBExecute(query)
    end)
    
    if not updateSuccess then
        -- 数据库更新失败，回滚扣除的金币
        pcall(function() player:ModifyMoney(amountCopper) end)
        player:SendBroadcastMessage("存款失败：银行更新失败，已退还金币。")
        LogOperation(accountId, "DEPOSIT", amount, requestId, "DB_UPDATE_FAILED")
        pendingRequests[requestId] = nil
        return
    end

    -- 8. 更新客户端显示
    AIO.Msg():Add("BankSystem", "UpdateGoldAmount", newBankGold):Send(player)
    player:SendBroadcastMessage(string.format("成功存入 %d 金。当前余额: %d 金", amount, newBankGold))
    LogOperation(accountId, "DEPOSIT", amount, requestId, "SUCCESS")
    
    -- 清理请求标记
    pendingRequests[requestId] = nil
end

-- 取钱（WithdrawGold） - 修复版
function BankSystemHandler.WithdrawGold(player, amount, clientRequestId)
    local accountId = player:GetAccountId()
    local requestId = clientRequestId or GenerateRequestId(accountId)
    
    -- 检查重复请求
    if pendingRequests[requestId] then
        debugMessage("重复取款请求被忽略:", requestId)
        return
    end
    pendingRequests[requestId] = true
    
    local playerCopper = player:GetCoinage()

    -- 1. 查询当前银行余额
    local query = string.format("SELECT gold_amount FROM account_bank WHERE account_id = %d", accountId)
    local result = AuthDBQuery(query)
    if not result then
        player:SendBroadcastMessage("取款失败：无法查询银行余额。")
        LogOperation(accountId, "WITHDRAW", amount, requestId, "QUERY_FAILED")
        pendingRequests[requestId] = nil
        return
    end
    
    local currentBankGold = result:GetInt32(0) or 0

    -- 2. 检查余额是否足够
    if currentBankGold < amount then
        player:SendBroadcastMessage("取款失败：银行余额不足。")
        LogOperation(accountId, "WITHDRAW", amount, requestId, "INSUFFICIENT_FUNDS")
        pendingRequests[requestId] = nil
        return
    end

    -- 3. 检查玩家背包是否会超限
    if (amount * 10000) + playerCopper > 2147483647 then
        player:SendBroadcastMessage("取款失败：背包金币已达上限。")
        LogOperation(accountId, "WITHDRAW", amount, requestId, "EXCEED_LIMIT")
        pendingRequests[requestId] = nil
        return
    end

    -- 4. 计算新余额
    local newBankGold = currentBankGold - amount
    
    -- 5. 更新数据库（使用乐观锁）
    local updateSuccess, rowsAffected = pcall(function()
        local query = string.format(
            "UPDATE account_bank SET gold_amount = %d WHERE account_id = %d AND gold_amount = %d",
            newBankGold, accountId, currentBankGold
        )
        return AuthDBExecute(query)
    end)
    
    if not updateSuccess or (rowsAffected and rowsAffected == 0) then
        player:SendBroadcastMessage("取款失败：银行余额更新失败。")
        LogOperation(accountId, "WITHDRAW", amount, requestId, "DB_UPDATE_FAILED")
        pendingRequests[requestId] = nil
        return
    end

    -- 6. 给予玩家金币
    local giveSuccess, giveError = pcall(function()
        player:ModifyMoney(amount * 10000)
        return true
    end)
    
    if not giveSuccess then
        -- 给予金币失败，需要回滚数据库
        pcall(function()
            AuthDBExecute(string.format(
                "UPDATE account_bank SET gold_amount = %d WHERE account_id = %d",
                currentBankGold, accountId
            ))
        end)
        
        player:SendBroadcastMessage("取款失败：金币发放出错，已恢复银行余额。")
        LogOperation(accountId, "WITHDRAW", amount, requestId, "GIVE_MONEY_FAILED")
        pendingRequests[requestId] = nil
        return
    end

    -- 7. 全部成功，更新客户端
    AIO.Msg():Add("BankSystem", "UpdateGoldAmount", newBankGold):Send(player)
    player:SendBroadcastMessage(string.format("成功取出 %d 金。当前余额: %d 金", amount, newBankGold))
    LogOperation(accountId, "WITHDRAW", amount, requestId, "SUCCESS")
    
    -- 清理请求标记
    pendingRequests[requestId] = nil
end

-- 查询余额
function BankSystemHandler.SendGoldAmount(player)
    local accountId = player:GetAccountId()

    local query = string.format("SELECT gold_amount FROM account_bank WHERE account_id = %d", accountId)
    local result = AuthDBQuery(query)
    if not result then
        debugMessage("查询余额失败:", accountId)
        return
    end
    
    local goldAmount = result:GetInt32(0) or 0

    debugMessage("发送余额给玩家:", accountId, goldAmount)
    AIO.Msg():Add("BankSystem", "UpdateGoldAmount", goldAmount):Send(player)
end

-- 余额请求
function BankSystemHandler.RequestGoldAmount(player)
    BankSystemHandler.SendGoldAmount(player)
end