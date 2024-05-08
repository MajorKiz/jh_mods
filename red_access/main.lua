nova.require "data/lua/core/common"

-- Needed for code that will be run when each level is created. 
nova.require "data/lua/core/world"
nova.require "data/lua/jh/data/generator"

--[[
	Learnings:
	~= is "not equal"
	-- is comment
	- - [ [    ] ] - -  for multiline comments. 
	If you change a piece of text, it'll likely go blank in any existing save-games. Or get replaced by the wrong text. 
	The terminal code allows you to say that something requires a red card, but it won't actually delete one unless you implement that in the "on_activate". 
	There are 2 "common.lua" files, one in core and one not. 
	"uitk" governs terminal interactions. 
	Game makes a log.txt as it runs, saves it as "crash####.txt" if the game goes down.
	Always save right before testing something new; a crash here can force you to restart the level or lose the save game entirely. 
	Be careful when to use : and ., who:pickup() is very different from who.pickup(). 
	Terminal commands can delete themselves to ensure that they are only used once. 

	
	To-dos:
		[DONE] Change the code to find and modify stations instead of having to override them here. I don't want this to stomp on any other mods that change stations. 
			Might be able to hook into the "on level created" event to search for stations and associate "station_unlock_feature" with them. 
		Any way to support grenades/mods from workshop mods? If nothing else, leave a way to support my own mods, since I'd like to do more than one. 
		What does the return value in an on_activate do? Maybe it's the time consumed? 
		Add an unlock to manufacturing station? Be very nice to allow you to unlock a "build AV1 utility" or similar. Unfortunately, since it can be used to CREATE red cards, it's kind of weird to let it also immediately use one to unlock something.
			Perhaps a second mod with a new type of manufacturing station would be better. Build weapon, armor, or utility. Or maybe things like Utility, Add slots, Reroll ADV. Could also have some stations replace "manufacture base items" with manufacture utility items.
]]--


register_blueprint "station_unlock_feature"
{
	text = {
		entry = "::RESTRICTED::",
		desc  = "Use a red keycard to access restricted feature",
		success = "Red keycard used - restricted feature enabled!",
		failure = "You don't have the required keycard!",
	},
	data = {
		terminal = {
			priority = 8000,
		},
		tier = 1,
	},
    attributes = {
		tool_cost = 0,
		hacking_mod = 0,
		redcard_cost = 1,
    },
	callbacks = {
		on_create = [=[
			function( self, _, tier )
				self.data.tier = tier   -- record the station's tier for later.
			end
		]=],

		on_activate = [=[
		function( self, who, level )
			if who == world:get_player() then			
				local parent = self:parent()
				local parent_id = world:get_id(parent)
				local tier = self.data.tier
				if tier == null then tier = 0 end

				if who:attribute( "redpass" ) < 1 and world:remove_items( who, "keycard_red", 1) ~= 1 then
					ui:set_hint( self.text.failure, 2001, 0 )
					world:play_voice( "vo_keycard" )	
					return 1
				end

				ui:set_hint( self.text.success, 2001, 0 )

				-- Determine what the unlockable features are, based on the terminal type and tier. Restrict it to valuable ones. 
				local list = {}

				if parent_id == "medical_station" then
					if tier <= 1 then
						list = { "station_medical_bonus_medkit", "station_medical_bonus_health" }
					else
						list = { "station_adrenal_increase", "station_create_mod_vampiric", "station_medical_bonus_health" }
					end
				elseif parent_id == "technical_station" then
					if tier <= 1 then
						list = { "station_create_mod_cold", "station_create_mod_vampiric", "station_create_mod_emp", "station_create_mod_sustain" }
					else
						list = { "station_create_mod_cold", "station_create_mod_vampiric", "station_create_mod_emp", "station_create_mod_onyx", "station_create_mod_nano", "station_create_mod_sustain" }
					end
				elseif parent_id == "terminal_ammo" then
					list = { "terminal_extract_plasma_grenade" }
				else 
					nova.log("station_unlock_feature: unrecognized parent id ", parent_id)
				end
				
				-- Remove any elements on the list that are already on the station.
				
				local approved_list = {}
					
				for i = 1, #list do
					local c = list[i]
					local bad = false
					for e in ecs:children( parent ) do
						if c == world:get_id( e ) then
							bad = true  -- Option already present.
						end
					end
					if bad == false then
						approved_list[#approved_list+1] = c
					end						
				end

				if #approved_list > 0 then
					local chosen = approved_list[math.random(#approved_list)]
					local thing = parent:attach( chosen )
					thing.data.terminal.priority = 8000  -- put it at the same location as this option was. 
				else
					nova.log("station_unlock_feature: approved list had no elements?")
				end
					
				-- Can only be done once. Destroy self, then update the terminal.
				world:destroy( self )
				uitk.station_activate( who, parent, true )
				return 100
			end
		end
		]=],
	}, 
}

register_blueprint "station_create_mod_sustain"
{
	text = {
		entry = "Create sustain pack",
		desc  = "Create a sustain mod pack for future use.",
	},
	data = {
		terminal = {
			priority = 42,
		},
	},
    attributes = {
        charge_cost = 3,
    },
	callbacks = {
		on_activate = [=[
			function( self, who, level )
				local parent = self:parent()
				uitk.station_use_charges( self )
				who:pickup( "adv_pack_sustain", true )
				world:destroy( self )
				uitk.station_activate( who, parent, true )
				return 100
			end	
		]=]
	}, 
}

register_blueprint "terminal_extract_plasma_grenade"
{
	text = {
		entry = "Plasma Grenade",
		desc  = "Extract a military plasma grenade.",
	},
	data = {
		terminal = {
			priority = 20,
		},
	},
    attributes = {
        charge_cost = 2,
    },
	callbacks = {
		on_activate = [=[
			function( self, who, level )
                local parent = self:parent()
				uitk.station_use_charges( self )
				who:pickup( "plasma_grenade", true )
				uitk.station_activate( who, parent, true )
				return 100
			end	
		]=]
	}, 
}

-- The rest of this code finds and adds the new option to the appropriate stations when first entering a level.
-- This enables us to avoid stomping on any other mods that modify those stations. So rather than copying them and
-- adding only a single new entry, we just find them and add the new option on the fly. 

register_blueprint "unlock_feature_mod_manager"
{
    flags = { EF_NOPICKUP },
    callbacks = {
		on_enter_level = [=[
            function ( self, entity, reenter )
                if reenter then return end
                local level = world:get_level()
				local level_id = world:get_id( level )
				
				if level == null then return end

				local function add( id )
					local list = find_all_matching_entity_ids( id )
					for i = 1, #list do
						local thing = list[i]
						thing:attach("station_unlock_feature")
					end
				end
				
				add("medical_station")
				add("technical_station")
				add("terminal_ammo")				
            end
        ]=],
    }
}

ufmm = {}
function ufmm.on_entity( entity )
    if entity.data and entity.data.ai and entity.data.ai.group == "player" then
        entity:attach( "unlock_feature_mod_manager" )
    end 
end

world.register_on_entity( ufmm.on_entity )

function find_all_matching_entity_ids( id )
	local output_list = {}
	local level = world:get_level()
	for e in level:entities() do 
		if world:get_id( e ) == id then
			output_list[#output_list + 1] = e
		end
	end
	return output_list
end

