local AIO = AIO or require("AIO")

local BankSystemHandler = AIO.AddHandlers("BankSystem", {})

local config = {
    debug = true
}

-- 服务器控制台输出dubug信息

local function debugMessage(...)
    if config.debug then
        print("DEBUG:", ...)
    end
end

--存钱
function BankSystemHandler.DepositGold(player, amount)
    local accountId = player:GetAccountId()
    local playerGold = player:GetCoinage() / 10000 -- 将铜币转换为金币
	
	
    -- 直接从数据库查询余额
    local query = string.format("SELECT gold_amount FROM account_bank WHERE account_id = %d", accountId)
    local result = AuthDBQuery(query)
    local goldAmount = result and result:GetInt32(0) or 0
    -- 检查存款后是否会超过上限
    if goldAmount + amount > 2147483647 then
        player:SendBroadcastMessage("存款失败：存款后余额将超过上限21亿。")
        return
    end
	

    if playerGold >= amount then--判断玩家身上的钱大于输入的存款数值
	
        local query = string.format(
            "INSERT INTO account_bank (account_id, gold_amount) VALUES (%d, %d) ON DUPLICATE KEY UPDATE gold_amount = gold_amount + %d",
            accountId, amount, amount)
        AuthDBExecute(query)
        player:ModifyMoney(-amount * 10000)
        player:SendBroadcastMessage("你存储了 " .. amount .. " 金到你的金币银行.")

        -- 直接查询数据库并发送最新余额
        BankSystemHandler.SendGoldAmount(player)
    else--玩家输入了大于身上金币数值的情况
        player:SendBroadcastMessage("别捣乱，我的朋友，你的钱不够.")
    end
end

--取钱
function BankSystemHandler.WithdrawGold(player, amount)
    local accountId = player:GetAccountId()
    local totalCopper = player:GetCoinage() -- 读取玩家现有铜币数量

    -- 直接从数据库查询余额
    local query = string.format("SELECT gold_amount FROM account_bank WHERE account_id = %d", accountId)
    local result = AuthDBQuery(query)
    local goldAmount = result and result:GetInt32(0) or 0

    if goldAmount >= amount and (amount * 10000 + totalCopper) <= 2147483647 then
        local updateQuery = string.format(
            "UPDATE account_bank SET gold_amount = gold_amount - %d WHERE account_id = %d", amount, accountId)
        AuthDBExecute(updateQuery)
        player:ModifyMoney(amount * 10000)
        player:SendBroadcastMessage("你从金币银行取了 " .. amount .. " 金.")

        -- 直接查询数据库并发送最新余额
        BankSystemHandler.SendGoldAmount(player)
    else
        player:SendBroadcastMessage("限额导致失败，余额不足或背包上限了，请降低取现金额.")
    end
end

function BankSystemHandler.SendGoldAmount(player)
    local accountId = player:GetAccountId()

    -- 直接从数据库查询余额
    local query = string.format("SELECT gold_amount FROM account_bank WHERE account_id = %d", accountId)
    local result = AuthDBQuery(query)
    local goldAmount = result and result:GetInt32(0) or 0

    AIO.Msg():Add("BankSystem", "UpdateGoldAmount", goldAmount):Send(player)
end

function BankSystemHandler.RequestGoldAmount(player)
    BankSystemHandler.SendGoldAmount(player)
end
