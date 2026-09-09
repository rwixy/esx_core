local Enum <const> = xLib.require "@esx_whitelist.server.module.whitelist.Enum"

---@class WhitelistRuleData
---@field id string
---@field type "admin-presence" | "player-count" | "scheduled"
---@field enabled boolean
---@field priority number
---@field operator string?
---@field value number?
---@field action "enable" | "disable"?
---@field startTime string?
---@field endTime string?

---@class WhitelistRule
---@field id string
---@field type string
---@field enabled boolean
---@field priority number
---@field operator string
---@field value number
---@field action string
---@field startTime string
---@field endTime string
local WhitelistRule = {}
WhitelistRule.__index = WhitelistRule

---Creates a new WhitelistRule instance
---@param data WhitelistRuleData
---@return WhitelistRule
function WhitelistRule.new(data)
    local self = setmetatable({}, WhitelistRule)
    self.id = tostring(data.id or os.time())
    self.type = data.type or Enum.RuleType.ADMIN_PRESENCE
    self.enabled = data.enabled == true
    self.priority = tonumber(data.priority) or 1
    self.operator = data.operator or Enum.RuleOperator.LESS_THAN
    self.value = tonumber(data.value) or 0
    self.action = data.action or Enum.RuleAction.ENABLE
    self.startTime = data.startTime or "00:00"
    self.endTime = data.endTime or "23:59"
    return self
end

---Evaluates a numeric condition against an operator and target value
---@param count number
---@param operator string
---@param target number
---@return boolean
local function compareCondition(count, operator, target)
    if operator == Enum.RuleOperator.LESS_THAN then
        return count < target
    elseif operator == Enum.RuleOperator.GREATER_THAN then
        return count > target
    elseif operator == Enum.RuleOperator.LESS_OR_EQUAL then
        return count <= target
    elseif operator == Enum.RuleOperator.GREATER_OR_EQUAL then
        return count >= target
    elseif operator == Enum.RuleOperator.EQUALS then
        return count == target
    end
    return false
end

---Evaluates this rule against current server state
---@param onlineCount number
---@param adminCount number
---@return boolean? isApplicable, boolean? desiredState
function WhitelistRule:evaluate(onlineCount, adminCount)
    if not self.enabled then
        return false, nil
    end

    if self.type == Enum.RuleType.ADMIN_PRESENCE then
        local conditionMet = compareCondition(adminCount, self.operator, self.value)
        if conditionMet then
            return true, self.action == Enum.RuleAction.ENABLE
        end
    elseif self.type == Enum.RuleType.PLAYER_COUNT then
        local conditionMet = compareCondition(onlineCount, self.operator, self.value)
        if conditionMet then
            return true, self.action == Enum.RuleAction.ENABLE
        end
    elseif self.type == Enum.RuleType.SCHEDULED then
        local currentHour = tonumber(os.date("%H")) or 0
        local currentMin = tonumber(os.date("%M")) or 0
        local currentMinutes = currentHour * 60 + currentMin

        local startH, startM = self.startTime:match("(%d+):(%d+)")
        local endH, endM = self.endTime:match("(%d+):(%d+)")

        local startMinutes = (tonumber(startH) or 0) * 60 + (tonumber(startM) or 0)
        local endMinutes = (tonumber(endH) or 0) * 60 + (tonumber(endM) or 0)

        local inRange = false
        if startMinutes <= endMinutes then
            inRange = currentMinutes >= startMinutes and currentMinutes <= endMinutes
        else
            inRange = currentMinutes >= startMinutes or currentMinutes <= endMinutes
        end

        if inRange then
            return true, true
        end
    end

    return false, nil
end

---@class WhitelistClassContainer
local Class = {
    WhitelistRule = WhitelistRule
}

return Class
