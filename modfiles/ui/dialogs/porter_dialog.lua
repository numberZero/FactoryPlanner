import_dialog = {}
export_dialog = {}
porter_dialog = {}  -- table containing functionality shared between both dialogs

-- ** TOP LEVEL **
function import_dialog.open(flow_modal_dialog)
    flow_modal_dialog.parent.caption = {"", {"fp.import"}, " ", {"fp.subfactories"}}

end



function export_dialog.open(flow_modal_dialog)
    flow_modal_dialog.parent.caption = {"", {"fp.export"}, " ", {"fp.subfactories"}}

    local player = game.get_player(flow_modal_dialog.player_index)
    local player_table = get_table(player)

    local content_frame = flow_modal_dialog.add{type="frame", name="frame_content", direction="vertical",
      style="inside_shallow_frame_with_padding"}

    local label_text = content_frame.add{type="label", caption="Select the subfactories that you'd like to export:"}
    label_text.style.bottom_margin = 6

    local table_subfactories = content_frame.add{type="table", name="table_subfactories",
      column_count=2, style="mods_table"}
    table_subfactories.style.column_alignments[1] = "center"

    table_subfactories.add{type="checkbox", name="fp_checkbox_porter_master", state=false}

    local label_subfactories_title = table_subfactories.add{type="label", caption={"fp.csubfactories"}}
    label_subfactories_title.style.font = "heading-3"
    label_subfactories_title.style.margin = {6, 150, 6, 4}

    for _, factory_name in ipairs{"factory", "archive"} do
        for _, subfactory in pairs(Factory.get_in_order(player_table[factory_name], "Subfactory")) do
            table_subfactories.add{type="checkbox", name=("fp_checkbox_porter_subfactory_" .. subfactory.id),
              state=false, enabled=subfactory.valid}

            local subfactory_icon = (subfactory.icon) and "[" .. subfactory.icon.type .. "="
              .. subfactory.icon.name .. "]   " or ""
            table_subfactories.add{type="label", caption=subfactory_icon .. subfactory.name}
        end
    end
end



-- ** SHARED **
-- Sets all slave checkboxes to the given state
function porter_dialog.set_all_checkboxes(player, checkbox_state)
    local table_subfactories = player.gui.screen["fp_frame_modal_dialog"]["flow_modal_dialog"]
      ["frame_content"]["table_subfactories"]

    for _, element in pairs(table_subfactories.children) do
        if element.type == "checkbox" and string.find(element.name, "^fp_checkbox_porter_subfactory_%d+$") then
            element.state = checkbox_state
        end
    end
end

-- Sets the master checkbox to the appropriate state after a slave one is changed
function porter_dialog.adjust_master_checkbox(player)
    local table_subfactories = player.gui.screen["fp_frame_modal_dialog"]["flow_modal_dialog"]
      ["frame_content"]["table_subfactories"]

      for _, element in pairs(table_subfactories.children) do
        if element.type == "checkbox" and string.find(element.name, "^fp_checkbox_porter_subfactory_%d+$") then
            -- If any element is not checked, the master checkbox should be unchecked
            if element.state == false then
                table_subfactories["fp_checkbox_porter_master"].state = false
                return
            end
        end
    end

    -- If no unchecked checkbox is found, the master one should be checked as well
    table_subfactories["fp_checkbox_porter_master"].state = true
end