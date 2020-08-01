--[[
Copyright (c) 2020 Martin Hassman

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
--]]


local addonName, NS = ...;

local cYellow = "\124cFFFFFF00";
local cWhite = "\124cFFFFFFFF";
local cRed = "\124cFFFF0000";
local cLightBlue = "\124cFFadd8e6";
local cGreen1 = "\124cFF38FFBE";


-- IDs for professions
-- data from Classic db, ID are in URL eg. https://classicdb.ch/?spell=3413

NS.professions = {  -- from appretince, journeyman, expert, artisan
	["Cooking"]        = { 2550, 3102, 3413, 18260 },
	["First Aid"]      = { 3273, 3274, 7924, 10846 },
	["Fishing"]        = { 7620, 7731, 7732, 18248 },
	["Alchemy"]        = { 2259, 3101, 3464, 11611 },
	["Blacksmithing"]  = { 2018, 3100, 3538, 9785  }, 
	["Enchanting"]     = { 7411, 7412, 7413, 13920 },
	["Engineering"]    = { 4036, 4037, 4038, 12656 },
	["Herbalism"]      = {                         }, -- no icon
	["Leatherworking"] = { 2108, 3104, 3811, 10662 },
	["Mining"]         = { 2575, 2576, 3564, 10248, 2656 }, -- last is for smelting spell
	["Skinning"]       = { 8613, 8617, 8613, 10768 },
	["Tailoring"]      = { 3908, 3909, 3910, 12180 },
};

-- Colors for all skillTypes, based on Blizzard_TradeSkillUI.lua: TradeSkillTypeColor
NS.skillTypes = {};
NS.skillTypes["optimal"] = { r = 1.00, g = 0.50, b = 0.25}; -- orange
NS.skillTypes["medium"]  = { r = 1.00, g = 1.00, b = 0.00}; -- yellow
NS.skillTypes["easy"]    = { r = 0.25, g = 0.75, b = 0.25}; -- green
NS.skillTypes["trivial"] = { r = 0.50, g = 0.50, b = 0.50}; -- grey


-- Grab known recipes from currently opened window of one tradeskill
-- return: { "recipe name 1" = { "reagent1" = count, "reagent2" = count }, "recipe name 2" = {...}, ... }
function NS.getKnownTradeSkillRecipes()
		local recipes = {};

		-- iterate all lines, some are recipes some are headers
		for i = 1, GetNumTradeSkills() do
			local recipeName, skillType = GetTradeSkillInfo(i); -- https://wowwiki.fandom.com/wiki/API_GetTradeSkillInfo
			-- skillType can be "trivial", "easy", "medium", "optimal", "difficult" ..or "header"
			-- see NS.skillTypes

			local numReagents = GetTradeSkillNumReagents(i);

			if skillType ~= "header" and numReagents > 0 then

				local reagents = NS.getReagentsForSkill(i);

				if reagents ~= nil then
					recipes[recipeName] = { reagents = reagents, skillType = skillType };
				end
			end
		end

		return recipes;
end


-- get reagents fokk skill-th line from opened skill window
function NS.getReagentsForSkill(skill)
	local numReagents = GetTradeSkillNumReagents(skill);
	local recipe = {};

	for reagent = 1,numReagents do
		-- https://wowwiki.fandom.com/wiki/API_GetTradeSkillReagentInfo
		-- reagentName, reagentTexture, reagentCount, playerReagentCount = GetTradeSkillReagentInfo()
		local reagentName, _, reagentCount = GetTradeSkillReagentInfo(skill, reagent);

		if reagentName == nil or reagentCount == nil or tonumber(reagentCount) == nil then
			-- sometimes data for all items are not loaded yet and GetTradeSkillReagentInfo fails
			-- we can retrieve information during some next call, now just log message
			NS.logDebug("In getReagentsForSkill(). ReagentName is nil, ignoring recipe: ", recipeName);
			recipe = nil; -- if there is info about other reagents, delete it
			break;
		else
			recipe[reagentName] = tonumber(reagentCount);
		end
	end

	return recipe;
end

-- check all recepies and ingredients
-- list what can player create from them now
function NS.whatCanPlayerCreateNow(knownRecipes)

	local allReagents = NS.listAllReagentNames(knownRecipes);
	local foundReagents = NS.countReagentsInBags(allReagents);
	local doableRecipes = NS.checkDoableRecipes(knownRecipes, foundReagents);

	-- TODO: only for trade skill, now craft skills yet (eg. enchanting)
	return doableRecipes;
end

-- get table with all reagent names from table with recipes
-- return: { "reagent1" = 0, "reagent2" = 0, ... }
function NS.listAllReagentNames(recipes)
	local reagents = {};

	for skillName,recipesList in pairs(recipes) do

		for recipe,skillInfo in pairs(recipesList) do

			for reagentName, _ in pairs(skillInfo.reagents) do
				reagents[reagentName] = 0;
			end

		end

	end

	return reagents;
end

-- check all bags for given reagents
-- arg: { "reagent1" = 0, "reagent2" = 0, ... }
-- return: { "reagent1" = count, "reagent2" = count, ... } -- contain only reagents with non-zero count
function NS.countReagentsInBags(reagents)
	local foundReagents = {};

	for bag=0, NUM_BAG_SLOTS do
		for slot=1, GetContainerNumSlots(bag) do 
			if GetContainerItemID(bag,slot)~=nil then
				local itemName = GetItemInfo(GetContainerItemID(bag,slot));
				local _, itemCount = GetContainerItemInfo(bag,slot);

				if reagents[itemName] ~= nil then
					if foundReagents[itemName] == nill then
						foundReagents[itemName] = 0;
					end

					foundReagents[itemName] = foundReagents[itemName] + tonumber(itemCount);
				end
			end 
		end
	end

	return foundReagents;
end


--[[
-- check for which recipes has player enough reagents

return: {
	["skillname1"] = {
		[0] = { recipeName = "recipe name 1", count = count, skillType = "skillType"},
		[1] = { recipeName = "recipe name 2", count = count, skillType = "skillType"},
	["skillname2"] = {...},
	... 
	}
]]--
function NS.checkDoableRecipes(recipes, reagents)
	local doable = {};

	for skillName, recipesList in pairs(recipes) do

		for recipeName,skillInfo in pairs(recipesList) do
			local howMany = 0; -- how many can create

			for reagentName, reagentCount in pairs(skillInfo.reagents) do
				if reagents[reagentName] == nil or reagents[reagentName] < reagentCount then
					howMany = 0;
					break; -- not enough of this reagent, we do not need to check any other
				end

				-- how many pieces can create? check for least available reagent
				local howManyWithThisReagent = math.floor(reagents[reagentName] / reagentCount);

				if howMany == 0 then
					howMany = howManyWithThisReagent;
				else 
					howMany = math.min(howMany, howManyWithThisReagent); -- get the lowest value
				end
			end

			if howMany > 0 then
				if doable[skillName] == nil then
					doable[skillName] = {};
				end

				table.insert(doable[skillName], { recipeName = recipeName, count = howMany, skillType = skillInfo.skillType });
			end
		end

	end

	return doable;
end

--[[
-- check in which recepies (known to player) is itemName used
-- return { [0] = {recipeName = name1, skillType = skillType1 }, ...}
eg.: { 
	[0] = { recipeName = "Linen Bandage", skillType = "trivial"},
	[1] = { recipeName = "Heavy Linen Bandage", skillType = "optimal"},
	...
}
--]]
function NS.whereIsItemUsed(itemName, knownRecipes)
	local itemIsUsedIn = {};

	for skillName,recipesList in pairs(knownRecipes) do

		for recipe,skillInfo in pairs(recipesList) do

			for reagentName, _ in pairs(skillInfo.reagents) do
				if reagentName == itemName then
					table.insert(itemIsUsedIn, { recipeName = recipe, skillType = skillInfo.skillType });
					break; -- do not need to check other reagents for this recipe
				end
			end

		end

	end

	return itemIsUsedIn;
end

-- Check skillTypes from list o items and return the best found skilltype
function NS.getBestCraftableSkillType(items)
	local skillTypes = { ["trivial"] = 1, ["easy"] = 2, ["medium"] = 3, ["optimal"] = 4 };
	local bestFoundSkillType = "trivial";

	for i,item in ipairs(items) do
		if skillTypes[item.skillType] > skillTypes[bestFoundSkillType] then
			bestFoundSkillType = item.skillType;
		end
	end

	return bestFoundSkillType;
end


-- caching NS.getActionButtons()
NS.actionButtonsCache = nil;

-- Create table that map action button ids to action button names
-- { [number1] = name1, [number2] = name2, ... }
-- Names are like: MultiBarBottomLeftButton1, MultiBarBottomLeftButton2...
function NS.getActionButtons()
	if NS.actionButtonsCache ~= nil then -- use cache if exist
		return NS.actionButtonsCache;
	end

	local bars = { "Action", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight","MultiBarLeft"};
	local buttons = {};

	for _, bar in pairs(bars) do
		for i = 1,NUM_ACTIONBAR_BUTTONS do -- NUM_ACTIONBAR_BUTTONS=12
			local buttonName = bar.."Button"..i; 
			local button = _G[buttonName];

			if button ~= nil then
				local buttonId = tonumber(button.action);				
				buttons[buttonId] = buttonName; -- button.action is index used in GetAction* API functions;
				--print(button.action, tonumber(button.action), buttons[buttonId]);
			end
		end
	end

	NS.actionButtonsCache = buttons; -- save to cache

	return buttons;
end


-- true if is belongs to some proffesion skill skillName
function NS.isIdOfProfession(professionIdList, actionId)
	local found = false;

	for _,id in ipairs(professionIdList) do
		if actionId == id then
			found = true;
			break;
		end
	end

	return found;
end

function NS.findSkillButtons(skillName, actionButtons)
	local foundButtons = {};

	for buttonId, buttonName in pairs(actionButtons) do -- cannot use ipairs,some indexes might be missing
		local actionType, actionId, subType = GetActionInfo(buttonId);

		if NS.isIdOfProfession(NS.professions[skillName], actionId) then
			table.insert(foundButtons, buttonId);
		end
	end

	-- TODO do not need to call this again all the time, can cache results, invalidate cache after multibar changes
	return foundButtons;	
end

-- thanks to https://gitlab.com/sigz/ColoredInventoryItems
local function createBorder(name, parent, r, g, b)
	local defaultWidth = 68;
	local defaultHeight = 68;

    local border = parent:CreateTexture(name .. 'MyBorder', 'OVERLAY');

    border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border");
    border:SetBlendMode('ADD');
    border:SetWidth(defaultWidth);
    border:SetHeight(defaultHeight);
    border:SetPoint("CENTER", parent, "CENTER", 0, 0);
    border:SetAlpha(0.9);
	border:SetVertexColor(r,g,b); -- rgb; 0-1.0, 0-1.0, 0-1.0
    border:Show();

    return border;
end

-- show border
-- if border does not exist yet, create one
local function showBorder(buttonName, r, g, b)
	if _G[buttonName].diyBorder == nil then
		local border = createBorder(buttonName.."Border", _G[buttonName], r, g, b);
		_G[buttonName].diyBorder = border;
	else
		_G[buttonName].diyBorder:SetVertexColor(r,g,b);
		_G[buttonName].diyBorder:Show(); --border exist, show it
	end
end

local function hideBorder(buttonName)
	if _G[buttonName].diyBorder ~= nil then
		-- TODO cannot delete border/texture in framexml, so only hide it, sure?
		_G[buttonName].diyBorder:Hide();
	end
end

function NS.updateActionButtonBorders()
	local actionButtons = NS.getActionButtons();
	local craftableItems = NS.whatCanPlayerCreateNow(NS.data.knownRecipes);

	--cycle over all professions
	for skillName,_ in pairs(NS.professions) do
		local skillBtns = NS.findSkillButtons(skillName, actionButtons); -- get all actionbuttons for skill skillName

		if craftableItems[skillName] ~= nil then -- something can be crafted for skill skillName
			local bestSkillType = NS.getBestCraftableSkillType(craftableItems[skillName]);

			-- show border for all actionbuttons of skill skillName
			if skillBtns ~= nil then
				for _,buttonId in pairs(skillBtns) do
					local buttonName = actionButtons[buttonId];
					showBorder(buttonName, NS.skillTypes[bestSkillType].r, NS.skillTypes[bestSkillType].g, NS.skillTypes[bestSkillType].b);
				end
			end
		else
			--no doable recepies, remove old border if exist for all actionbutton of skill skillName
			if skillBtns ~= nil then
				for _,buttonId in pairs(skillBtns) do
					local buttonName = actionButtons[buttonId];
					hideBorder(buttonName);
				end			
			end
		end	
	end

	-- TODO need to react to  toolbar change 
	-- know I put border to all new buttons after toolbar change,
	-- but need also to remove border from old buttons after change, can cycle all buttons and remove border?
	-- or just remember the old ones somewhere?
end
