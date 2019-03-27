Byproduct = {}

function Byproduct.init(item, amount_produced)
    return {
        id = 0,
        name = item.name,
        item_type = item.type or item.item_type,
        amount_produced = amount_produced,
        valid = true,
        gui_position = 0,
        type = "Byproduct"
    }
end

local function get_byproduct(player, subfactory_id, id)
    return global.players[player.index].factory.subfactories[subfactory_id].Byproduct.datasets[id]
end


function Byproduct.set_item(player, subfactory_id, item)
    local self = get_byproduct(player, subfactory_id, item)
    self.name = item.name
    self.item_type = item.type
end

function Byproduct.get_name(player, subfactory_id)
    return get_byproduct(player, subfactory_id, id).name
end

function Byproduct.get_item_type(player, subfactory_id)
    return get_byproduct(player, subfactory_id, id).item_type
end


function Byproduct.get_amount_produced(player, subfactory_id, id)
    return get_byproduct(player, subfactory_id, id).amount_produced
end


function Byproduct.is_valid(player, subfactory_id, id)
    return get_byproduct(player, subfactory_id, id).valid
end

-- Determines and sets the validity of given Byproduct
function Byproduct.check_validity(player, subfactory_id, id)
    local self = get_byproduct(player, subfactory_id, id)
    self.valid = (game.item_prototypes[self.name] or game.fluid_prototypes[self.name])
    return self.valid
end


function Byproduct.set_gui_position(player, subfactory_id, id, gui_position)
    get_byproduct(player, subfactory_id, id).gui_position = gui_position
end

function Byproduct.get_gui_position(player, subfactory_id, id)
    return get_byproduct(player, subfactory_id, id).gui_position
end