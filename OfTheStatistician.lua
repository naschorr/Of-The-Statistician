local _;

-- Prints a string with a formatted 'OTS - ' in front of it.
local function otsPrint(string)
	print("OTS - ", string);
end

-- Handles the initialization checks before we do anything else.
local function startup(itemName)
	if(type(itemName) ~= "string") then 	-- Check to make sure we got a string.
		otsPrint("String not recieved. Did you call it with an item ID instead?")
		return nil;
	end

	if(not IsAddOnLoaded("Auctionator")) then 	-- Check to ensure that Auctionator is loaded (and thus have access to its API)
		otsPrint("Auctionator isn't loaded. Please make sure that it is working.");
		return nil;
	end

	return true;
end

-- Merges a given amount of tables together.
local function mergeTables(tables)
	if(#tables == 1) then
		return tables[1];
	else
		for iter = 1, #tables[2] do
			table.insert(tables[1], tables[2][iter]);
		end
		table.remove(tables, 2);
		return mergeTables(tables);
	end
end

-- Formats a supplied suffix by appending and prepending optional arguments.
-- Potential arguments include (suffixTable, prependString, appendString)
local function formatSuffixTable(args)
	local suffix = {};
	local prepend, append = "", "";

	if(not args.suffixTable) then
		otsPrint("Error with suffix table formatting -- No suffix table supplied.")
		return;
	else
		for iter = 1, #args.suffixTable do
			table.insert(suffix, args.suffixTable[iter]);
		end
	end
	if(args.prependString) then
		prepend = args.prependString;
	end
	if(args.appendString) then
		append = args.appendString;
	end

	for iter = 1, #suffix do
		suffix[iter] = prepend .. suffix[iter] .. append;
	end

	return suffix;
end

-- Picks out the appropriate suffixes for the given item's level requirement.
local function buildSuffixTable(reqLevel)
	local suffixes = {};
	if(reqLevel >= 1) then
		local oneAttr = formatSuffixTable{prependString=" of ", suffixTable=OTS_OneAttr_Suffixes};
		local resistances = formatSuffixTable{prependString=" of ", suffixTable=OTS_Resistance_Suffixes, appendString=" Resistance"};
		local twoAttrNonThe = formatSuffixTable{prependString=" of ", suffixTable=OTS_TwoAttr_Suffixes_nonThe};
		local twoAttr = formatSuffixTable{prependString=" of the ", suffixTable=OTS_TwoAttr_Suffixes};
		local bcNonThe = formatSuffixTable{prependString=" of ", suffixTable=OTS_BC_Suffixes_nonThe};
		local bc = formatSuffixTable{prependString=" of the ", suffixTable=OTS_BC_Suffixes};
		suffixes = mergeTables({oneAttr, resistances, twoAttrNonThe, twoAttr, bcNonThe, bc});
	end
	if(reqLevel >= 55) then
		local abyssal = formatSuffixTable{prependString=" of ", suffixTable=OTS_Abyssal_Suffixes};
		local protection = formatSuffixTable{prependString=" of ", suffixTable=OTS_Resistance_Suffixes, appendString=" Protection"};
		suffixes = mergeTables({suffixes, abyssal, protection});
	end
	if(reqLevel >= 70) then
		local wotlk = formatSuffixTable{prependString=" of the ", suffixTable=OTS_WOTLK_Suffixes};
		suffixes = mergeTables({suffixes, wotlk});
	end
	if(reqLevel >= 80) then
		local fourAttr = formatSuffixTable{prependString=" of the ", suffixTable=OTS_FourAttr_Suffixes};
		suffixes = mergeTables({suffixes, fourAttr});
	end
	if(reqLevel >= 90) then
		local wod = formatSuffixTable{prependString=" of the ", suffixTable=OTS_WOD_Suffixes};
		suffixes = mergeTables({suffixes, wod});
	end
	return suffixes;
end

-- Uses auctionator API to get the lowest, average, and highest price for a item-suffix combination.
local function getPriceStats(itemName, suffixTable)
	local prices = {};

	for iter = 1, #suffixTable do
		local price = Atr_GetAuctionBuyout(itemName .. suffixTable[iter]);
		if(price) then
			table.insert(prices, price);
		end
	end

	local min, avg, max = nil, nil, nil;

	if(#prices >= 1) then
		min = prices[1];
		avg = prices[1];
		max = prices[1];

		for iter = 2, #prices do
			local current = prices[iter];
			if(current < min) then
				min = current;
			end
			if(current > max) then
				max = current;
			end
			avg = avg + current;
		end

		avg = avg/#prices;
	end

	return min, avg, max;
end

-- Builds a string to display the gold, silver, and copper values for a given amount with the appropriate icons.
local function getGoldString(amount)
	local goldIcon = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:4:0|t"
	local silverIcon = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:4:0|t"
	local copperIcon = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:4:0|t"

	copper = math.floor(amount - math.floor(amount/100) * 100);
	silver = math.floor((amount - math.floor(amount/10000) * 10000)/100);
	gold = math.floor(amount/10000);

	return gold .. goldIcon .. "  " .. silver .. silverIcon .. "  " .. copper .. copperIcon;
end

-- When a tooltip for an item is generated, try to add the OTS data if possible. 
local lineAdded = false;
local function OnTooltipSetItem(tooltip, ...)
	if(not lineAdded) then
		local name, _ = tooltip:GetItem();
		local min, avg, max = OTS(name);
		if(min and avg and max) then
			-- Format it to look like Auctionator's tooltip output
			tooltip:AddDoubleLine("Minimum", "|cFFFFFFFF" .. getGoldString(min));
			tooltip:AddDoubleLine("Average", "|cFFFFFFFF" .. getGoldString(avg));
			tooltip:AddDoubleLine("Maximum", "|cFFFFFFFF" .. getGoldString(max));
			lineAdded = true;
		end
	end
end

-- Ensures that only a single line gets added to the tooltip.
local function OnTooltipCleared(tooltip, ...)
	lineAdded = false;
end

-- Hook into the tooltip, and call the previous functions when necessary.
GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem);
GameTooltip:HookScript("OnTooltipCleared", OnTooltipCleared);

-- Function alias for ease of use
function OTS(itemName)
	return OfTheStatistician(itemName);
end

-- Main
function OfTheStatistician(itemName)
	if(not startup(itemName)) then 	-- Ensure that Auctionator is working, and a string has been provided.
		return nil, nil, nil;
	end

	local name, reqLevel, class;
	name, _, _, _, reqLevel, class, _, _, _, _, _ = GetItemInfo(itemName);	-- Get the required level, and class of the given item.

	if(class ~= "Armor" and class ~= "Weapon") then 	-- Check to make sure that the item is a weapon or armor piece.
		return nil, nil, nil;
	end

	local suffixes = buildSuffixTable(reqLevel);	-- Build a list of possible suffixes based on the item's required level.

	if(#suffixes == 0) then
		return nil, nil, nil;
	end

	local low, avg, high = getPriceStats(name, suffixes);	-- Use the item's root name and the list of suffixes to determine pricing information.

	if(low and avg and high) then
		return low, avg, high;
	end

	return nil, nil, nil;
end