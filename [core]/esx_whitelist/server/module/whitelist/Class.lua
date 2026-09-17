local Enum <const> = xLib.require "@esx_whitelist.server.module.whitelist.Enum"

local WhitelistRule = {}
WhitelistRule.__index = WhitelistRule

local function parseTime(value)
    if type(value) ~= "string" then return 0 end
    local h, m = value:match("^(%d%d?):(%d%d?)$")
    h, m = tonumber(h), tonumber(m)
    if not h or not m or h < 0 or h > 23 or m < 0 or m > 59 then
        return 0
    end
    return h * 60 + m
end

local function compare(count, operator, target)
    if operator == "<" then return count < target end
    if operator == ">" then return count > target end
    if operator == "<=" then return count <= target end
    if operator == ">=" then return count >= target end
    if operator == "==" then return count == target end
    return false
end

function WhitelistRule.new(data)
    data = type(data) == "table" and data or {}
    local self = setmetatable({}, WhitelistRule)
    self.id = tostring(data.id or ("rule_" .. math.random(100000, 999999)))
    self.type = data.type or Enum.RuleType.ADMIN_PRESENCE
    self.enabled = data.enabled == true
    self.priority = tonumber(data.priority) or 1
    self.operator = data.operator or Enum.RuleOperator.LESS_THAN
    self.value = tonumber(data.value) or 0
    self.action = data.action == Enum.RuleAction.DISABLE and Enum.RuleAction.DISABLE or Enum.RuleAction.ENABLE
    self.startTime = data.startTime or "00:00"
    self.endTime = data.endTime or "23:59"
    self.startMinutes = parseTime(self.startTime)
    self.endMinutes = parseTime(self.endTime)
    return self
end

function WhitelistRule:evaluate(onlineCount, adminCount, currentMinutes)
    if not self.enabled then return false, nil end

    if self.type == Enum.RuleType.ADMIN_PRESENCE then
        if compare(adminCount, self.operator, self.value) then
            return true, self.action == Enum.RuleAction.ENABLE
        end
    elseif self.type == Enum.RuleType.PLAYER_COUNT then
        if compare(onlineCount, self.operator, self.value) then
            return true, self.action == Enum.RuleAction.ENABLE
        end
    elseif self.type == Enum.RuleType.SCHEDULED then
        currentMinutes = currentMinutes or ((tonumber(os.date("%H")) or 0) * 60 + (tonumber(os.date("%M")) or 0))
        local inRange
        if self.startMinutes <= self.endMinutes then
            inRange = currentMinutes >= self.startMinutes and currentMinutes <= self.endMinutes
        else
            inRange = currentMinutes >= self.startMinutes or currentMinutes <= self.endMinutes
        end
        if inRange then
            return true, self.action == Enum.RuleAction.ENABLE
        end
    end

    return false, nil
end

return { WhitelistRule = WhitelistRule }
