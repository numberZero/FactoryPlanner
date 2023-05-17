-- Assembles event handlers from all the relevant files and calls them when needed

local event_listener_names = {"ui.base.main_dialog", "ui.base.compact_dialog", "ui.base.modal_dialog",
    "ui.base.view_state", "ui.main.title_bar", "ui.main.subfactory_list", "ui.main.subfactory_info",
    "ui.main.item_boxes", "ui.main.production_box", "ui.main.production_table", "ui.main.production_handler",
    "ui.elements.module_configurator", "ui.dialogs.beacon_dialog", "ui.dialogs.generic_dialogs",
    "ui.dialogs.machine_dialog", "ui.dialogs.matrix_dialog", "ui.dialogs.picker_dialog",
    "ui.dialogs.picker_dialog", "ui.dialogs.porter_dialog", "ui.dialogs.preferences_dialog",
    "ui.dialogs.recipe_dialog", "ui.dialogs.subfactory_dialog", "ui.dialogs.tutorial_dialog",
    "ui.dialogs.utility_dialog"}

local event_listeners = {}
for _, listener_path in ipairs(event_listener_names) do
    for _, listener in pairs(require(listener_path)) do
        table.insert(event_listeners, listener)
    end
end


local function guarded_event(handler, arguments)
    if DEV_ACTIVE and not DEBUGGER_ACTIVE then
        local status, ret = xpcall(handler, debug.traceback, table.unpack(arguments))
        if status then
            return ret
        else
            llog(ret)
            game.print(util.split(ret, "\n")[1])
            game.reload_mods()
        end
    else
        return handler(table.unpack(arguments))
    end
end


-- Returns whether rate limiting is active for the given action, stopping it from proceeding
-- This is essentially to prevent duplicate commands in quick succession, enabled by lag
local function rate_limiting_active(player, tick, action_name, timeout)
    local ui_state = data_util.ui_state(player)

    -- If this action has no timeout, reset the last action and allow it
    if timeout == nil or game.tick_paused then
        ui_state.last_action = nil
        return false
    end

    local last_action = ui_state.last_action
    -- Only disallow action under these specific circumstances
    if last_action and last_action.action_name == action_name and (tick - last_action.tick) < timeout then
        return true

    else  -- set the last action if this action will actually be carried out
        ui_state.last_action = {
            action_name = action_name,
            tick = tick
        }
        return false
    end
end


local function generate_tutorial_tooltip_lines(modifier_actions)
    local action_lines = {}

    for modifier_click, modifier_action in pairs(modifier_actions) do
        local split_modifiers = util.split(modifier_click, "-")

        local modifier_string = {""}
        for _, modifier in pairs(fancytable.slice(split_modifiers, 1, -1)) do
            table.insert(modifier_string, {"", {"fp.tut_" .. modifier}, " + "})
        end
        table.insert(modifier_string, {"fp.tut_" .. split_modifiers[#split_modifiers]})

        local action_string = {"fp.tut_action_line", modifier_string, {"fp.tut_" .. modifier_action.name}}
        table.insert(action_lines, {string=action_string, limitations=modifier_action.limitations})
    end

    return action_lines
end


local function apply_metadata_overrides(base, overrides)
    for k, v in pairs(overrides) do
        local base_v = base[k]
        if type(base_v) == "table" and type(v) == "table" then
            apply_metadata_overrides(base_v, v)
        else
            base[k] = v
        end
    end
end



-- ** GUI EVENTS **
-- These handlers go out to the first thing that it finds that registered for it.
-- They can register either by element name or by a pattern matching element names.
local gui_identifier_map = {
    [defines.events.on_gui_click] = "on_gui_click",
    [defines.events.on_gui_closed] = "on_gui_closed",
    [defines.events.on_gui_confirmed] = "on_gui_confirmed",
    [defines.events.on_gui_text_changed] = "on_gui_text_changed",
    [defines.events.on_gui_checked_state_changed] = "on_gui_checked_state_changed",
    [defines.events.on_gui_switch_state_changed] = "on_gui_switch_state_changed",
    [defines.events.on_gui_elem_changed] = "on_gui_elem_changed",
    [defines.events.on_gui_value_changed] = "on_gui_value_changed",
    [defines.events.on_gui_hover] = "on_gui_hover",
    [defines.events.on_gui_leave] = "on_gui_leave"
}

local gui_timeouts = {
    on_gui_click = 2,
    on_gui_confirmed = 20
}


-- ** SPECIAL HANDLERS **
local special_gui_handlers = {}

special_gui_handlers.on_gui_closed = (function(event, _, _)
    return (event.gui_type == defines.gui_type.custom and event.element.visible)
end)

special_gui_handlers.on_gui_confirmed = (function(_, player, action_name)
    if action_name then return true end  -- run the standard handler if one is found

    -- Otherwise, close the currently open modal dialog if possible
    if data_util.ui_state(player).modal_dialog_type ~= nil then
        ui_util.raise_close_dialog(player, "submit")
    end
    return false
end)


local gui_event_cache = {}
-- Create tables for all events that are being registered
for _, event_name in pairs(gui_identifier_map) do
    gui_event_cache[event_name] = {
        actions = {},
        special_handler = special_gui_handlers[event_name]
    }
end

-- Compile the list of GUI actions
for _, listener in pairs(event_listeners) do
    if listener.gui then
        for event_name, actions in pairs(listener.gui) do
            local event_table = gui_event_cache[event_name]

            for _, action in pairs(actions) do
                local timeout = action.timeout or gui_timeouts[event_name]  -- can be nil
                local action_table = {handler = action.handler, timeout = timeout}

                if event_name == "on_gui_click" and action.modifier_actions then
                    action_table.modifier_actions = {}
                    -- Transform modifier actions into a more useable form
                    for modifier_action_name, modifier_action in pairs(action.modifier_actions) do
                        local modifier_click = modifier_action[1]
                        action_table.modifier_actions[modifier_click] = {
                            name = modifier_action_name,
                            limitations = modifier_action[2] or {}
                        }
                    end

                    -- Generate all the tooltip lines for these modifier actions
                    TUTORIAL_TOOLTIPS[action.name] = generate_tutorial_tooltip_lines(action_table.modifier_actions)
                end

                event_table.actions[action.name] = action_table
            end
        end
    end
end

local mouse_click_map = {
    [defines.mouse_button_type.left] = "left",
    [defines.mouse_button_type.right] = "right",
    [defines.mouse_button_type.middle] = "middle"
}
local function convert_click_to_string(event)
    local modifier_click = mouse_click_map[event.button]
    if event.shift then modifier_click = "shift-" .. modifier_click end
    if event.alt then modifier_click = "alt-" .. modifier_click end
    if event.control then modifier_click = "control-" .. modifier_click end
    return modifier_click
end

local function handle_gui_event(event)
    if not event.element then return end

    local tags = event.element.tags
    if tags.mod ~= "fp" then return end

    -- Guard against an event being called before the player is initialized
    if not global.players[event.player_index] then return end

    -- GUI events always have an associated player
    local player = game.get_player(event.player_index)  ---@cast player -nil

    -- The event table actually contains its identifier, not its name
    local event_name = gui_identifier_map[event.name]
    local event_table = gui_event_cache[event_name]
    local action_name = tags[event_name]  -- could be nil

    -- If a special handler is set, it needs to return true before proceeding with the registered handlers
    local special_handler = event_table.special_handler
    if special_handler and guarded_event(special_handler, {event, player, action_name}) == false then return end

    -- Special handlers need to run even without an action handler, so we
    -- wait until this point to check whether there is an associated action
    if not action_name then return end  -- meaning this event type has no action on this element
    local action_table = event_table.actions[action_name]

    -- Check if rate limiting allows this action to proceed
    if rate_limiting_active(player, event.tick, action_name, action_table.timeout) then return end

    local third_parameter = event  -- all GUI events except on_gui_click have the event as the third parameter

    -- Special modifier handling for on_gui_click if configured
    if event_name == "on_gui_click" and action_table.modifier_actions then
        local modifier_action = action_table.modifier_actions[convert_click_to_string(event)]
        if not modifier_action then return end  -- meaning the used modifiers do not have an associated action

        local active_limitations = data_util.current_limitations(player)
        -- Check whether the selected action is allowed according to its limitations
        if not data_util.action_allowed(modifier_action.limitations, active_limitations) then return end

        third_parameter = modifier_action.name
    end

    -- Send the actual event, potentially guarding it if DEV_ACTIVE
    guarded_event(action_table.handler, {player, tags, third_parameter})

    ui_util.messages.refresh(player)  -- give messages a chance to update themselves
end

-- Register all the GUI events from the identifier map
for event_id, _ in pairs(gui_identifier_map) do script.on_event(event_id, handle_gui_event) end



-- ** DIALOG EVENTS **
-- These custom events handle opening and closing modal dialogs

OPEN_MODAL_DIALOG = script.generate_event_name()
CLOSE_MODAL_DIALOG = script.generate_event_name()

local dialog_event_cache = {}
-- Compile the list of dialog actions
for _, listener in pairs(event_listeners) do
    if listener.dialog then
        dialog_event_cache[listener.dialog.dialog] = listener.dialog
    end
end

local function handle_dialog_event(event)
    -- Guard against an event being called before the player is initialized
    if not global.players[event.player_index] then return end

    -- These custom events always have an associated player
    local player = game.get_player(event.player_index)  ---@cast player -nil
    local ui_state = data_util.ui_state(player)

    -- Check if the action is allowed to be carried out by rate limiting
    if rate_limiting_active(player, event.tick, event.name, 20) then return end

    if event.name == OPEN_MODAL_DIALOG then
        local listener = dialog_event_cache[event.metadata.dialog]

        local metadata = event.metadata
        ui_state.modal_data = metadata.modal_data or {}

        if listener.metadata ~= nil then  -- collect additional metadata
            local additional_metadata = listener.metadata(ui_state.modal_data)
            apply_metadata_overrides(metadata, additional_metadata)
        end

        modal_dialog.enter(player, metadata, listener.open, listener.early_abort_check)

    elseif event.name == CLOSE_MODAL_DIALOG then
        local modal_dialog_type = ui_state.modal_dialog_type
        if modal_dialog_type == nil then return end

        local listener = dialog_event_cache[modal_dialog_type]
        modal_dialog.exit(player, event.action, event.skip_opened, listener.close)
    end
end

-- Register all the misc events from the identifier map
for _, event_id in pairs({OPEN_MODAL_DIALOG, CLOSE_MODAL_DIALOG}) do script.on_event(event_id, handle_dialog_event) end



-- ** MISC EVENTS **
-- These events call every handler that has subscribed to it by id or name. The difference to GUI events
-- is that multiple handlers can be registered to the same event, and there is no standard handler.

BUILD_GUI_ELEMENT = script.generate_event_name()
REFRESH_GUI_ELEMENT = script.generate_event_name()
local internal_events = {BUILD_GUI_ELEMENT=true, REFRESH_GUI_ELEMENT=true}

local misc_identifier_map = {
    -- Standard events
    [defines.events.on_gui_opened] = "on_gui_opened",
    [defines.events.on_player_display_resolution_changed] = "on_player_display_resolution_changed",
    [defines.events.on_player_display_scale_changed] = "on_player_display_scale_changed",
    [defines.events.on_player_selected_area] = "on_player_selected_area",
    [defines.events.on_player_cursor_stack_changed] = "on_player_cursor_stack_changed",
    [defines.events.on_player_main_inventory_changed] = "on_player_main_inventory_changed",
    [defines.events.on_lua_shortcut] = "on_lua_shortcut",

    -- Keyboard shortcuts
    ["fp_toggle_interface"] = "fp_toggle_interface",
    ["fp_toggle_compact_view"] = "fp_toggle_compact_view",
    ["fp_toggle_pause"] = "fp_toggle_pause",
    ["fp_refresh_production"] = "fp_refresh_production",
    ["fp_up_floor"] = "fp_up_floor",
    ["fp_top_floor"] = "fp_top_floor",
    ["fp_cycle_production_views"] = "fp_cycle_production_views",
    ["fp_reverse_cycle_production_views"] = "fp_reverse_cycle_production_views",
    ["fp_confirm_dialog"] = "fp_confirm_dialog",
    ["fp_confirm_gui"] = "fp_confirm_gui",
    ["fp_focus_searchfield"] = "fp_focus_searchfield",

    [BUILD_GUI_ELEMENT] = "build_gui_element",
    [REFRESH_GUI_ELEMENT] = "refresh_gui_element"
}

local misc_timeouts = {
    fp_confirm_dialog = 20,
    fp_confirm_gui = 20,
    fp_refresh_production = 20
}

-- ** SPECIAL HANDLERS **
local special_misc_handlers = {}

special_misc_handlers.on_gui_opened = (function(event)
    -- This should only fire when a UI not associated with FP is opened, so FP's dialogs can close properly
    return (event.gui_type ~= defines.gui_type.custom or not event.element or event.element.tags.mod ~= "fp")
end)


local misc_event_cache = {}
-- Compile the list of misc handlers
for _, listener in pairs(event_listeners) do
    if listener.misc then
        for event_name, handler in pairs(listener.misc) do
            misc_event_cache[event_name] = misc_event_cache[event_name] or {
                registered_handlers = {},
                special_handler = special_misc_handlers[event_name],
                timeout = misc_timeouts[event_name]
            }

            table.insert(misc_event_cache[event_name].registered_handlers, handler)
        end
    end
end


local function handle_misc_event(event)
    local event_name = event.input_name or event.name -- also handles keyboard shortcuts
    local event_handlers = misc_event_cache[misc_identifier_map[event_name]]
    if not event_handlers then return end  -- make sure the given event is even handled

    -- Guard against an event being called before the player is initialized
    if not global.players[event.player_index] then return end

    -- We'll assume every one of the events has a player attached
    local player = game.get_player(event.player_index)   ---@cast player -nil

    -- Check if the action is allowed to be carried out by rate limiting
    if rate_limiting_active(player, event.tick, event_name, event_handlers.timeout) then return end

    -- If a special handler is set, it needs to return true before proceeding with the registered handlers
    local special_handler = event_handlers.special_handler
    if special_handler and guarded_event(special_handler, {event}) == false then return end

    -- Send the actual events, potentially guarding them if DEV_ACTIVE
    for _, registered_handler in pairs(event_handlers.registered_handlers) do
        guarded_event(registered_handler, {player, event})
    end

    if internal_events[event_name] then return end  -- don't refresh message for events inside other events
    ui_util.messages.refresh(player)  -- give messages a chance to update themselves
end

-- Register all the misc events from the identifier map
for event_id, _ in pairs(misc_identifier_map) do script.on_event(event_id, handle_misc_event) end
