local AIO = AIO or require("AIO")

local BankSystemHandler = AIO.AddHandlers("BankSystem", {})

local config = {
    debug = true
}

-- Function to display debug messages
local function debugMessage(...)
    if config.debug then
        print("DEBUG:", ...)
    end
end

-- Cache table for storing gold amounts reduce database queries hopefully
local goldCache = {}

function BankSystemHandler.DepositGold(player, amount)
    local accountId = player:GetAccountId()
    local playerGold = player:GetCoinage() / 10000 -- Convert copper to gold will just do gold

    -- print("Debug: Player gold: " .. tostring(playerGold))
    -- print("Debug: Amount to deposit: " .. tostring(amount))

    if playerGold >= amount then
        print("Debug: Depositing gold.")
        local query = string.format(
            "INSERT INTO x_auth.account_bank (account_id, gold_amount) VALUES (%d, %d) ON DUPLICATE KEY UPDATE gold_amount = gold_amount + %d",
            accountId, amount, amount)
        AuthDBExecute(query)
        player:ModifyMoney(-amount * 10000)
        player:SendBroadcastMessage("你存储了 " .. amount .. " 金到你的金币银行.")

        -- Update the cache
        goldCache[accountId] = (goldCache[accountId] or 0) + amount

        BankSystemHandler.SendGoldAmount(player)
    else
        print("Debug: Not enough gold to deposit.")
        player:SendBroadcastMessage("别捣乱，我的朋友，你的钱不够.")
    end
end

function BankSystemHandler.WithdrawGold(player, amount)
    local accountId = player:GetAccountId()
    local goldAmount = goldCache[accountId]
	local totalCopper = player:GetCoinage()--读取玩家现有铜币数量

    if goldAmount == nil then  --判断金币银行是否为空
        local query = string.format("SELECT gold_amount FROM x_auth.account_bank WHERE account_id = %d", accountId)
        local result = AuthDBQuery(query)
        if result then
            goldAmount = result:GetInt32(0)
            goldCache[accountId] = goldAmount
        else
            player:SendBroadcastMessage("你还没有金币银行余额.")
            return
        end
    end

   if goldAmount >= amount and (amount * 10000+totalCopper) <=2147483647     then  --判断金币银行金额大于输入的金额

        local updateQuery = string.format(
            "UPDATE x_auth.account_bank SET gold_amount = gold_amount - %d WHERE account_id = %d", amount, accountId)
        AuthDBExecute(updateQuery)
        player:ModifyMoney(amount * 10000)
        player:SendBroadcastMessage("你从金币银行取了 " .. amount .. " 金.")

        -- Update the cache
        goldCache[accountId] = goldAmount - amount

        BankSystemHandler.SendGoldAmount(player)
    else
        player:SendBroadcastMessage("限额导致失败，余额不足或背包上限了，请降低取现金额.")
    end
end

function BankSystemHandler.SendGoldAmount(player)
    local accountId = player:GetAccountId()
    local goldAmount = goldCache[accountId]

    if goldAmount == nil then
        local query = string.format("SELECT gold_amount FROM x_auth.account_bank WHERE account_id = %d", accountId)
        local result = AuthDBQuery(query)
        if result then
            goldAmount = result:GetInt32(0)
            goldCache[accountId] = goldAmount
        else
            goldAmount = 0
            goldCache[accountId] = goldAmount
        end
    end

    AIO.Msg():Add("BankSystem", "UpdateGoldAmount", goldAmount):Send(player)
end

function BankSystemHandler.RequestGoldAmount(player)
    BankSystemHandler.SendGoldAmount(player)
end

-- 下面可以忽略是创建表单

-- CREATE TABLE `account_bank` (
-- 	`account_id` INT(10) UNSIGNED NOT NULL,
-- 	`gold_amount` BIGINT(20) UNSIGNED NOT NULL DEFAULT '0',
-- 	PRIMARY KEY (`account_id`) USING BTREE
-- )
-- COLLATE='utf8mb4_unicode_ci'
-- ENGINE=InnoDB
-- ;
