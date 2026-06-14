local extmarks = require("easydap.ui.extmarks")

local M = {}

---@class easydap.ui.signs.Group
---@field define_sign fun(name:string, text:string, texthl:string)
---@field set_file_sign fun(id:number, file:string, lnum:number, name:string, user_data:any)
---@field remove_sign fun(id:number)
---@field remove_file_signs fun(file:string)
---@field remove_signs fun()
---@field get_signs fun(live:boolean): easydap.ui.signs.SignInfo[]
---@field get_file_signs fun(file:string, live:boolean): easydap.ui.signs.SignInfo[]
---@field get_sign_by_location fun(file:string, lnum:number, live:boolean): easydap.ui.signs.SignInfo?
---@field get_sign_by_id fun(id:number): easydap.ui.signs.SignInfo?
---@field refresh fun()

---@class easydap.ui.signs.SignInfo
---@field id number
---@field file string
---@field name string
---@field lnum number
---@field priority number
---@field user_data any
---@field source "live"|"stored"

---@param group string
---@param opts { priority:number }
---@return easydap.ui.signs.Group
function M.define_group(group, opts)
    assert(group, "group required")
    assert(opts and opts.priority, "priority required")

    local priority = opts.priority
    local sign_defs = {} ---@type table<string,{text:string,texthl:string}>

    local ext = extmarks.define_group(group, {
        priority = priority,
    })

    local function _convert_mark(mark)
        if not mark then return nil end

        local user = mark.user_data
        if not user or not user.name then
            return nil
        end

        return {
            id = mark.id,
            file = mark.file,
            name = user.name,
            lnum = mark.lnum,
            priority = priority,
            user_data = user.user_data,
            source = mark.source,
        }
    end

    return {
        define_sign = function(name, text, texthl)
            assert(name and text and texthl, "invalid sign definition")
            assert(not sign_defs[name], "sign already defined")

            sign_defs[name] = {
                text = text,
                texthl = texthl,
            }
        end,
        set_file_sign = function(id, file, lnum, name, user_data)
            assert(sign_defs[name], "sign not defined")
            assert(lnum >= 1, "lnum must be 1-based")

            local def = sign_defs[name]

            ext.set_file_extmark(
                id,
                file,
                lnum,
                0,
                {
                    sign_text = def.text,
                    sign_hl_group = def.texthl,
                },
                {
                    name = name,
                    user_data = user_data,
                }
            )
        end,
        remove_sign = function(id)
            ext.remove_extmark(id)
        end,
        remove_file_signs = function(file)
            ext.remove_file_extmarks(file)
        end,
        remove_signs = function()
            ext.remove_extmarks()
        end,
        get_signs = function(live)
            local marks = ext.get_extmarks(live)
            ---@type easydap.ui.signs.SignInfo[]
            local result = {}
            for _, mark in ipairs(marks) do
                local sign = _convert_mark(mark)
                if sign then
                    result[#result + 1] = sign
                end
            end
            return result
        end,
        get_file_signs = function(file, live)
            local marks = ext.get_file_extmarks(file, live)
            ---@type easydap.ui.signs.SignInfo[]
            local result = {}
            for _, mark in ipairs(marks) do
                local sign = _convert_mark(mark)
                if sign then
                    result[#result + 1] = sign
                end
            end
            return result
        end,
        get_sign_by_location = function(file, lnum, live)
            local mark = ext.get_extmark_by_location(file, lnum, live)
            return _convert_mark(mark)
        end,
        get_sign_by_id = function(id)
            local mark = ext.get_extmark_by_id(id)
            return _convert_mark(mark)
        end,
        refresh = function()
            ext.refresh()
        end,
    }
end

return M
