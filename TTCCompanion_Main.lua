local LAM = LibAddonMenu2
local OriginalSetupPendingPost

function TTCCompanion:GetMeetsRequirements(itemLink)
  if (not WritWorthy) then return false end
  local hasKnowledge = true
  local hasMaterials = true
  local parser = WritWorthy.CreateParser(itemLink)
  if (not parser or not parser:ParseItemLink(itemLink) or not parser.ToKnowList) then
    return false
  end
  local knowList = parser:ToKnowList()
  if (knowList) then
    for _, know in ipairs(knowList) do
      if (not know.is_known) then
        hasKnowledge = false
      end
    end
  end

  local matList = parser:ToMatList()
  if (matList) then
    for _, mat in ipairs(matList) do
      if (WritWorthy.Util.MatHaveCt(mat.link) < mat.ct) then
        hasMaterials = false
      end
    end
  end

  return hasKnowledge, hasMaterials
end

function TTCCompanion:ToggleWritMarker(rowControl, slot)
  local markerControl = rowControl:GetNamedChild(TTCCompanion.name .. "Writ")
  local rData = rowControl.dataEntry and rowControl.dataEntry.data or nil
  local itemLink = rData and rData.itemLink or nil
  local hasKnowledge, hasMaterials = TTCCompanion:GetMeetsRequirements(itemLink)

  if (not markerControl) then
    if not hasKnowledge then return end
    markerControl = WINDOW_MANAGER:CreateControl(rowControl:GetName() .. TTCCompanion.name .. "Writ", rowControl, CT_TEXTURE)
    markerControl:SetDimensions(22, 22)
    markerControl:SetInheritScale(false)
    markerControl:SetAnchor(LEFT, rowControl, LEFT)
    markerControl:SetDrawTier(DT_HIGH)
  end

  if hasKnowledge and hasMaterials then
    markerControl:SetTexture("TamrielTradeCentreCompanion/img/does_meet.dds")
    markerControl:SetColor(0.17, 0.93, 0.17, 1)
    markerControl:SetHidden(false)
  elseif hasKnowledge and not hasMaterials then
    markerControl:SetTexture("esoui/art/miscellaneous/help_icon.dds")
    markerControl:SetColor(1, 0.99, 0, 1)
    markerControl:SetHidden(false)
  else markerControl:SetHidden(true) end
end

function TTCCompanion:ToggleVendorMarker(rowControl, slot)
  local markerControl = rowControl:GetNamedChild(TTCCompanion.name .. "Warn")
  local relativeToPoint = rowControl:GetNamedChild("SellPrice")
  local showVendorWarning = false
  local vendorWarningPricing = nil
  local rData = rowControl.dataEntry and rowControl.dataEntry.data or nil
  local itemLink = rData and rData.itemLink or nil
  local purchasePrice = rData and rData.purchasePrice or nil
  local stackCount = rData and rData.stackCount or nil
  local itemType = GetItemLinkItemType(itemLink)
  local itemId = GetItemLinkItemId(itemLink)

  if TTCCompanion["vendor_price_table"][itemType] then
    if TTCCompanion["vendor_price_table"][itemType][itemId] then vendorWarningPricing = TTCCompanion["vendor_price_table"][itemType][itemId] end
  end
  if purchasePrice and stackCount and vendorWarningPricing then
    local storeItemUnitPrice = purchasePrice / stackCount
    if storeItemUnitPrice > vendorWarningPricing then showVendorWarning = true end
  end

  if (not markerControl) then
    if not showVendorWarning then return end
    markerControl = WINDOW_MANAGER:CreateControl(rowControl:GetName() .. TTCCompanion.name .. "Warn", rowControl, CT_TEXTURE)
    markerControl:SetDimensions(22, 22)
    markerControl:SetInheritScale(false)
    markerControl:SetAnchor(LEFT, relativeToPoint, LEFT)
    markerControl:SetDrawTier(DT_HIGH)
  end

  if (showVendorWarning) then
    markerControl:SetTexture("/esoui/art/inventory/newitem_icon.dds")
    markerControl:SetColor(0.9, 0.3, 0.2, 1)
    markerControl:SetHidden(false)
  else
    markerControl:SetHidden(true)
  end
end

do
  SecurePostHook(TRADING_HOUSE, "OpenTradingHouse", function()
    if (not TTCCompanion.markersHooked) then
      local oldCallback = ZO_TradingHouseBrowseItemsRightPaneSearchResults.dataTypes[1].setupCallback
      TTCCompanion.markersHooked = true
      ZO_TradingHouseBrowseItemsRightPaneSearchResults.dataTypes[1].setupCallback = function(rowControl, slot)
        oldCallback(rowControl, slot)
        TTCCompanion:ToggleVendorMarker(rowControl, slot)
        if TTCCompanion.wwDetected and not TTCCompanion.mwimDetected then
          TTCCompanion:ToggleWritMarker(rowControl, slot)
        end
      end
    end
  end)
end

function TTCCompanion:RemoveItemTooltip()
  -- TTCCompanion:dm("Debug", "RemoveItemTooltip")
  if ItemTooltip.tooltipTextPool then
    ItemTooltip.tooltipTextPool:ReleaseAllObjects()
  end
  ItemTooltip.warnText = nil
  ItemTooltip.vendorWarnText = nil
  ItemTooltip.mmMatText = nil
  TTCCompanion.tippingControl = nil
end

function TTCCompanion:RemovePopupTooltip(Popup)
  -- TTCCompanion:dm("Debug", "RemovePopupTooltip")
  if Popup.tooltipTextPool then
    Popup.tooltipTextPool:ReleaseAllObjects()
  end

  Popup.warnText = nil
  Popup.vendorWarnText = nil
  Popup.mmMatText = nil
  Popup.ttccActiveTip = nil
end

function TTCCompanion:GenerateTooltip(tooltip, itemLink, purchasePrice, stackCount)
  if not TTCCompanion.isInitialized then return end
  -- TTCCompanion:dm("Debug", "GenerateTooltip")

  local function GetVendorPricing(itemType, itemId)
    if TTCCompanion["vendor_price_table"][itemType] then
      if TTCCompanion["vendor_price_table"][itemType][itemId] then return TTCCompanion["vendor_price_table"][itemType][itemId] end
    end
    return nil
  end

  local itemType = GetItemLinkItemType(itemLink)
  local itemId = GetItemLinkItemId(itemLink)
  local materialCostLine = nil
  local removedWarningTipline = nil
  local vendorWarningTipline = nil
  local vendorWarningPricing = GetVendorPricing(itemType, itemId)
  -- the removedItemIdTable table has only true values, no function needed
  local showRemovedWarning = TTCCompanion.removedItemIdTable[itemId]
  local showVendorWarning = false

  if purchasePrice and stackCount and vendorWarningPricing then
    local storeItemUnitPrice = purchasePrice / stackCount
    if storeItemUnitPrice > vendorWarningPricing then showVendorWarning = true end
  end
  if showVendorWarning then
    vendorWarningTipline = string.format(GetString(TTCC_VENDOR_ITEM_WARN), vendorWarningPricing) .. TTCCompanion.coinIcon
  end
  if showRemovedWarning ~= nil then
    removedWarningTipline = GetString(TTCC_REMOVED_ITEM_WARN)
  end
  if itemType == ITEMTYPE_MASTER_WRIT then
    materialCostLine = TTCCompanion:MaterialCostPriceTip(itemLink, purchasePrice)
  end

  if not tooltip.tooltipTextPool then
    tooltip.tooltipTextPool = ZO_ControlPool:New("TTCCTooltipText", tooltip, "TTCCTooltipLine")
  end

  local hasTiplineOrGraph = vendorWarningTipline or removedWarningTipline or materialCostLine
  local hasTiplineControls = tooltip.vendorWarnText or tooltip.warnText or tooltip.mmMatText

  if hasTiplineOrGraph and not hasTiplineControls then
    tooltip:AddVerticalPadding(2)
    ZO_Tooltip_AddDivider(tooltip)
  end

  if removedWarningTipline then
    if not tooltip.warnText then
      tooltip:AddVerticalPadding(2)
      tooltip.warnText = tooltip.tooltipTextPool:AcquireObject()
      tooltip:AddControl(tooltip.warnText)
      tooltip.warnText:SetAnchor(CENTER)
    end

    if tooltip.warnText then
      tooltip.warnText:SetText(removedWarningTipline)
      tooltip.warnText:SetColor(0.87, 0.11, 0.14, 1)
    end

  end

  if vendorWarningTipline then
    if not tooltip.vendorWarnText then
      tooltip:AddVerticalPadding(2)
      tooltip.vendorWarnText = tooltip.tooltipTextPool:AcquireObject()
      tooltip:AddControl(tooltip.vendorWarnText)
      tooltip.vendorWarnText:SetAnchor(CENTER)
    end

    if tooltip.vendorWarnText then
      tooltip.vendorWarnText:SetText(vendorWarningTipline)
    end

  end

  if materialCostLine and TTCCompanion.savedVariables.showMaterialCost then

    if not tooltip.mmMatText then
      tooltip:AddVerticalPadding(2)
      tooltip.mmMatText = tooltip.tooltipTextPool:AcquireObject()
      tooltip:AddControl(tooltip.mmMatText)
      tooltip.mmMatText:SetAnchor(CENTER)
    end

    if tooltip.mmMatText then
      tooltip.mmMatText:SetText(materialCostLine)
      tooltip.mmMatText:SetColor(1, 1, 1, 1)
    end

  end

end

function TTCCompanion:GeneratePopupTooltip(Popup)
  local showTooltipInformation = (TTCCompanion.savedVariables.showMaterialCost)

  if Popup == ZO_ProvisionerTopLevelTooltip then
    local recipeListIndex, recipeIndex = PROVISIONER:GetSelectedRecipeListIndex(), PROVISIONER:GetSelectedRecipeIndex()
    Popup.lastLink = GetRecipeResultItemLink(recipeListIndex, recipeIndex)
  end

  --Make sure Info Tooltip and Context Menu is on top of the popup
  --InformationTooltip:GetOwningWindow():BringWindowToTop()
  --[[TODO: Is this needed for TTCC? ]]--
  Popup:GetOwningWindow():SetDrawTier(ZO_Menus:GetDrawTier() - 1)

  -- Make sure we don't double-add stats (or double-calculate them if they bring
  -- up the same link twice) since we have to call this on Update rather than Show
  if not showTooltipInformation or Popup.lastLink == nil or (Popup.ttccActiveTip and Popup.ttccActiveTip == Popup.lastLink) then
    -- thanks Garkin
    return
  end

  if Popup.ttccActiveTip ~= Popup.lastLink then
    if Popup.tooltipTextPool then
      Popup.tooltipTextPool:ReleaseAllObjects()
    end
    Popup.warnText = nil
    Popup.vendorWarnText = nil
    Popup.mmMatText = nil
  end
  Popup.ttccActiveTip = Popup.lastLink

  TTCCompanion:GenerateTooltip(Popup, Popup.ttccActiveTip)
end

function TTCCompanion:GenerateItemTooltip()
  if not TTCCompanion.isInitialized then return end
  -- TTCCompanion:dm("Debug", "GenerateItemTooltip")
  local showTooltipInformation = (TTCCompanion.savedVariables.showMaterialCost)
  local skMoc = moc()
  -- Make sure we don't double-add stats or try to add them to nothing
  -- Since we call this on Update rather than Show it gets called a lot
  -- even after the tip appears
  if not showTooltipInformation or (not skMoc or not skMoc:GetParent()) or (skMoc == TTCCompanion.tippingControl) then
    return
  end

  local itemLink = nil
  local purchasePrice = nil
  local stackCount = nil
  local mocParent = skMoc:GetParent():GetName()

  -- Store screen
  if mocParent == 'ZO_StoreWindowListContents' then
    itemLink = GetStoreItemLink(skMoc.index)
    -- Store buyback screen
  elseif mocParent == 'ZO_BuyBackListContents' then
    itemLink = GetBuybackItemLink(skMoc.index)
    -- Guild store posted items
  elseif mocParent == 'ZO_TradingHousePostedItemsListContents' then
    local mocData = skMoc.dataEntry and skMoc.dataEntry.data or nil
    if not mocData then return end
    itemLink = GetTradingHouseListingItemLink(mocData.slotIndex)
    purchasePrice = mocData.purchasePrice
    stackCount = mocData.stackCount
    -- Guild store search
  elseif mocParent == 'ZO_TradingHouseItemPaneSearchResultsContents' then
    local rData = skMoc.dataEntry and skMoc.dataEntry.data or nil
    -- The only thing with 0 time remaining should be guild tabards, no
    -- stats on those!
    if not rData or rData.timeRemaining == 0 then return end
    itemLink = GetTradingHouseSearchResultItemLink(rData.slotIndex)
    -- Guild store item posting
  elseif mocParent == 'ZO_TradingHouseLeftPanePostItemFormInfo' then
    if skMoc.slotIndex and skMoc.bagId then itemLink = GetItemLink(skMoc.bagId, skMoc.slotIndex) end
    -- Player bags (and bank) (and crafting tables)
  elseif mocParent == 'ZO_PlayerInventoryBackpackContents' or
    mocParent == 'ZO_PlayerInventoryListContents' or
    mocParent == 'ZO_CraftBagListContents' or
    mocParent == 'ZO_QuickSlotListContents' or
    mocParent == 'ZO_PlayerBankBackpackContents' or
    mocParent == 'ZO_HouseBankBackpackContents' or
    mocParent == 'ZO_SmithingTopLevelImprovementPanelInventoryBackpackContents' or
    mocParent == 'ZO_SmithingTopLevelDeconstructionPanelInventoryBackpackContents' or
    mocParent == 'ZO_SmithingTopLevelRefinementPanelInventoryBackpackContents' or
    mocParent == 'ZO_EnchantingTopLevelInventoryBackpackContents' or
    mocParent == 'ZO_GuildBankBackpackContents' or
    mocParent == 'ZO_CompanionEquipment_Panel_KeyboardListContents' then
    if skMoc and skMoc.dataEntry then
      local rData = skMoc.dataEntry.data
      itemLink = GetItemLink(rData.bagId, rData.slotIndex)
    end
    -- Worn equipment
  elseif mocParent == 'ZO_Character' or
    mocParent == 'ZO_CompanionCharacterWindow_Keyboard_TopLevel' then
    itemLink = GetItemLink(skMoc.bagId, skMoc.slotIndex)
    -- Furniture Catalogue
  elseif mocParent == 'FurCGui_ListHolder' then
    itemLink = skMoc.itemLink
    -- Loot window if autoloot is disabled
  elseif mocParent == 'ZO_LootAlphaContainerListContents' then
    if not skMoc.dataEntry then return end
    local data = skMoc.dataEntry.data
    itemLink = GetLootItemLink(data.lootId, LINK_STYLE_BRACKETS)
  elseif mocParent == 'ZO_MailInboxMessageAttachments' then itemLink = GetAttachedItemLink(MAIL_INBOX:GetOpenMailId(),
    skMoc.id, LINK_STYLE_DEFAULT)
  elseif mocParent == 'ZO_MailSendAttachments' then itemLink = GetMailQueuedAttachmentLink(skMoc.id, LINK_STYLE_DEFAULT)
  elseif mocParent == 'IIFA_GUI_ListHolder' then itemLink = skMoc.itemLink
  elseif mocParent == 'ZO_TradingHouseBrowseItemsRightPaneSearchResultsContents' then
    local rData = skMoc.dataEntry and skMoc.dataEntry.data or nil
    -- The only thing with 0 time remaining should be guild tabards, no
    -- stats on those!
    if not rData or rData.timeRemaining == 0 then return end
    purchasePrice = rData.purchasePrice
    stackCount = rData.stackCount
    itemLink = GetTradingHouseSearchResultItemLink(rData.slotIndex)
    --elseif mocParent == 'ZO_SmithingTopLevelImprovementPanelSlotContainer' then itemLink
    --d(skMoc)
  end

  if itemLink then
    if TTCCompanion.tippingControl ~= skMoc then
      if ItemTooltip.tooltipTextPool then
        ItemTooltip.tooltipTextPool:ReleaseAllObjects()
      end

      ItemTooltip.warnText = nil
      ItemTooltip.vendorWarnText = nil
      ItemTooltip.mmMatText = nil
    end

    TTCCompanion.tippingControl = skMoc
    TTCCompanion:GenerateTooltip(ItemTooltip, itemLink, purchasePrice, stackCount)
  end

end

function TTCCompanion:initSellingAdvice()
  if TTCCompanion.originalSellingSetupCallback then return end

  if TRADING_HOUSE and TRADING_HOUSE.postedItemsList then

    local dataType = TRADING_HOUSE.postedItemsList.dataTypes[2]

    TTCCompanion.originalSellingSetupCallback = dataType.setupCallback
    if TTCCompanion.originalSellingSetupCallback then
      dataType.setupCallback = function(...)
        local row, data = ...
        TTCCompanion.originalSellingSetupCallback(...)
        zo_callLater(function() TTCCompanion.AddSellingAdvice(row, data) end, 1)
      end
    else
      TTCCompanion:dm("Warn", GetString(TTCC_ADVICE_ERROR))
    end
  end

  if TRADING_HOUSE_GAMEPAD then
  end
end

function TTCCompanion.AddSellingAdvice(rowControl, result)
  if not TTCCompanion.isInitialized then return end
  local sellingAdvice = rowControl:GetNamedChild('SellingAdvice')
  if (not sellingAdvice) then
    local controlName = rowControl:GetName() .. 'SellingAdvice'
    sellingAdvice = rowControl:CreateControl(controlName, CT_LABEL)

    local anchorControl = rowControl:GetNamedChild('TimeRemaining')
    local _, point, relTo, relPoint, offsX, offsY = anchorControl:GetAnchor(0)
    anchorControl:ClearAnchors()
    anchorControl:SetAnchor(point, relTo, relPoint, offsX, offsY - 10)

    sellingAdvice:SetAnchor(TOPLEFT, anchorControl, BOTTOMLEFT, 0, 0)
    sellingAdvice:SetFont('/esoui/common/fonts/univers67.otf|14|soft-shadow-thin')
  end

  --[[TODO make sure that the itemLink is not an empty string by mistake
  ]]--
  local itemLink = GetTradingHouseListingItemLink(result.slotIndex)
  if itemLink and itemLink ~= "" then
    local dealValue, margin, profit = TTCCompanion.GetDealInformation(itemLink, result.purchasePrice, result.stackCount)
    if dealValue then
      if dealValue > TTCC_DEAL_VALUE_DONT_SHOW then
        if TTCCompanion.savedVariables.showProfitMargin then
          sellingAdvice:SetText(TTCCompanion.LocalizedNumber(profit) .. ' |t16:16:EsoUI/Art/currency/currency_gold.dds|t')
        else
          sellingAdvice:SetText(string.format('%.2f', margin) .. '%')
        end
        -- TODO I think this colors the number in the guild store
        --[[
        ZO_Currency_FormatPlatform(CURT_MONEY, tonumber(stringPrice), ZO_CURRENCY_FORMAT_AMOUNT_ICON, {color: someColorDef})
        ]]--
        local r, g, b = GetInterfaceColor(INTERFACE_COLOR_TYPE_ITEM_QUALITY_COLORS, dealValue)
        if dealValue == TTCC_DEAL_VALUE_OVERPRICED then
          r = 0.98;
          g = 0.01;
          b = 0.01;
        end
        sellingAdvice:SetColor(r, g, b, 1)
        sellingAdvice:SetHidden(false)
      else
        sellingAdvice:SetHidden(true)
      end
    else
      sellingAdvice:SetHidden(true)
    end
  end
  sellingAdvice = nil
end

function TTCCompanion:initBuyingAdvice()
  --[[Keyboard Mode has a TRADING_HOUSE.searchResultsList
  that is set to
  ZO_TradingHouseBrowseItemsRightPaneSearchResults and
  then from there, there is a
  dataTypes[1].dataType.setupCallback.

  This does not exist in GamepadMode
  ]]--
  if TTCCompanion.originalSetupCallback then return end
  if TRADING_HOUSE and TRADING_HOUSE.searchResultsList then

    local dataType = TRADING_HOUSE.searchResultsList.dataTypes[1]

    TTCCompanion.originalSetupCallback = dataType.setupCallback
    if TTCCompanion.originalSetupCallback then
      dataType.setupCallback = function(...)
        local row, data = ...
        TTCCompanion.originalSetupCallback(...)
        zo_callLater(function() TTCCompanion.AddBuyingAdvice(row, data) end, 1)
      end
    else
      TTCCompanion:dm("Warn", GetString(TTCC_ADVICE_ERROR))
    end
  end

  if TRADING_HOUSE_GAMEPAD then
  end
end

--[[ TODO update this for the colors and the value so that when there
isn't any buying advice then it is blank or 0
]]--
function TTCCompanion.AddBuyingAdvice(rowControl, result)
  if not TTCCompanion.isInitialized then return end
  local buyingAdvice = rowControl:GetNamedChild('BuyingAdvice')
  if (not buyingAdvice) then
    local controlName = rowControl:GetName() .. 'BuyingAdvice'
    buyingAdvice = rowControl:CreateControl(controlName, CT_LABEL)

    if (not AwesomeGuildStore) then
      local anchorControl = rowControl:GetNamedChild('SellPricePerUnit')
      local _, point, relTo, relPoint, offsX, offsY = anchorControl:GetAnchor(0)
      anchorControl:ClearAnchors()
      anchorControl:SetAnchor(point, relTo, relPoint, offsX, offsY + 10)
    end

    local anchorControl = rowControl:GetNamedChild('TimeRemaining')
    local _, point, relTo, relPoint, offsX, offsY = anchorControl:GetAnchor(0)
    anchorControl:ClearAnchors()
    anchorControl:SetAnchor(point, relTo, relPoint, offsX, offsY - 10)
    buyingAdvice:SetAnchor(TOPLEFT, anchorControl, BOTTOMLEFT, 0, 0)
    buyingAdvice:SetFont('/esoui/common/fonts/univers67.otf|14|soft-shadow-thin')
  end

  local index = result.slotIndex
  if (AwesomeGuildStore) then index = result.itemUniqueId end
  local itemLink = GetTradingHouseSearchResultItemLink(index)
  local dealValue, margin, profit = TTCCompanion.GetDealInformation(itemLink, result.purchasePrice, result.stackCount)
  if dealValue then
    if dealValue > TTCC_DEAL_VALUE_DONT_SHOW then
      if TTCCompanion.savedVariables.showProfitMargin then
        buyingAdvice:SetText(TTCCompanion.LocalizedNumber(profit) .. ' |t16:16:EsoUI/Art/currency/currency_gold.dds|t')
      else
        buyingAdvice:SetText(string.format('%.2f', margin) .. '%')
      end
      -- TODO I think this colors the number in the guild store
      local r, g, b = GetInterfaceColor(INTERFACE_COLOR_TYPE_ITEM_QUALITY_COLORS, dealValue)
      if dealValue == TTCC_DEAL_VALUE_OVERPRICED then
        r = 0.98;
        g = 0.01;
        b = 0.01;
      end
      buyingAdvice:SetColor(r, g, b, 1)
      buyingAdvice:SetHidden(false)
    else
      buyingAdvice:SetHidden(true)
    end
  else
    buyingAdvice:SetHidden(true)
  end
  buyingAdvice = nil
end

function TTCCompanion.LocalizedNumber(amount)
  local function comma_value(amount)
    local formatted = amount
    while true do
      formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1' .. GetString(TTCC_THOUSANDS_SEP) .. '%2')
      if (k == 0) then
        break
      end
    end
    return formatted
  end

  if not amount then
    return tostring(0)
  end

  -- Round to two decimal values
  return comma_value(zo_roundToNearest(amount, .01))
end

TTCCompanion.dealCalcChoices = {
  GetString(TTCC_DEAL_CALC_TTC_SUGGESTED),
  GetString(TTCC_DEAL_CALC_TTC_AVERAGE),
}
TTCCompanion.dealCalcValues = {
  TTCCompanion.USE_TTC_SUGGESTED,
  TTCCompanion.USE_TTC_AVERAGE,
}
TTCCompanion.agsPercentSortChoices = {
  GetString(AGS_PERCENT_ORDER_ASCENDING),
  GetString(AGS_PERCENT_ORDER_DESCENDING),
}
TTCCompanion.agsPercentSortValues = {
  TTCCompanion.AGS_PERCENT_ASCENDING,
  TTCCompanion.AGS_PERCENT_DESCENDING,
}

local function CheckDealCalcValue()
  if TTCCompanion.savedVariables.dealCalcToUse ~= TTCCompanion.USE_TTC_SUGGESTED then
    TTCCompanion.savedVariables.modifiedSuggestedPriceDealCalc = false
  end
end

-- LibAddon init code
function TTCCompanion:LibAddonInit()
  TTCCompanion:dm("Debug", "TTCCompanion LibAddonInit")
  local panelData = {
    type = 'panel',
    name = 'TTCCompanion',
    displayName = "Tamriel Trade Centre Companion",
    author = "Sharlikran",
    version = TTCCompanion.version,
    website = "https://www.esoui.com/downloads/info3509-TamrielTradeCentreCompanion.html",
    feedback = "https://www.esoui.com/downloads/info3509-TamrielTradeCentreCompanion.html",
    donation = "https://sharlikran.github.io/",
    registerForRefresh = true,
    registerForDefaults = true,
  }
  LAM:RegisterAddonPanel('TTCCompanionOptions', panelData)

  local optionsData = {}
  -- Custom Deal Calc
  optionsData[#optionsData + 1] = {
    type = 'submenu',
    name = GetString(TTCC_DEALCALC_OPTIONS_NAME),
    tooltip = GetString(TTCC_DEALCALC_OPTIONS_TIP),
    helpUrl = "https://esouimods.github.io/3-master_merchant.html#CustomDealCalculator",
    controls = {
      -- Enable DealCalc
      [1] = {
        type = 'checkbox',
        name = GetString(TTCC_DEALCALC_ENABLE_NAME),
        tooltip = GetString(TTCC_DEALCALC_ENABLE_TIP),
        getFunc = function() return TTCCompanion.savedVariables.customDealCalc end,
        setFunc = function(value) TTCCompanion.savedVariables.customDealCalc = value end,
        default = TTCCompanion.systemDefault.customDealCalc,
      },
      -- custom customDealBuyIt
      [2] = {
        type = 'slider',
        name = GetString(TTCC_DEALCALC_BUYIT_NAME),
        tooltip = GetString(TTCC_DEALCALC_BUYIT_TIP),
        min = 0,
        max = 100,
        getFunc = function() return TTCCompanion.savedVariables.customDealBuyIt end,
        setFunc = function(value) TTCCompanion.savedVariables.customDealBuyIt = value end,
        default = TTCCompanion.systemDefault.customDealBuyIt,
        disabled = function() return not TTCCompanion.savedVariables.customDealCalc end,
      },
      -- customDealSeventyFive
      [3] = {
        type = 'slider',
        name = GetString(TTCC_DEALCALC_SEVENTYFIVE_NAME),
        tooltip = GetString(TTCC_DEALCALC_SEVENTYFIVE_TIP),
        min = 0,
        max = 100,
        getFunc = function() return TTCCompanion.savedVariables.customDealSeventyFive end,
        setFunc = function(value) TTCCompanion.savedVariables.customDealSeventyFive = value end,
        default = TTCCompanion.systemDefault.customDealSeventyFive,
        disabled = function() return not TTCCompanion.savedVariables.customDealCalc end,
      },
      -- customDealFifty
      [4] = {
        type = 'slider',
        name = GetString(TTCC_DEALCALC_FIFTY_NAME),
        tooltip = GetString(TTCC_DEALCALC_FIFTY_TIP),
        min = 0,
        max = 100,
        getFunc = function() return TTCCompanion.savedVariables.customDealFifty end,
        setFunc = function(value) TTCCompanion.savedVariables.customDealFifty = value end,
        default = TTCCompanion.systemDefault.customDealFifty,
        disabled = function() return not TTCCompanion.savedVariables.customDealCalc end,
      },
      -- customDealTwentyFive
      [5] = {
        type = 'slider',
        name = GetString(TTCC_DEALCALC_TWENTYFIVE_NAME),
        tooltip = GetString(TTCC_DEALCALC_TWENTYFIVE_TIP),
        min = 0,
        max = 100,
        getFunc = function() return TTCCompanion.savedVariables.customDealTwentyFive end,
        setFunc = function(value) TTCCompanion.savedVariables.customDealTwentyFive = value end,
        default = TTCCompanion.systemDefault.customDealTwentyFive,
        disabled = function() return not TTCCompanion.savedVariables.customDealCalc end,
      },
      -- customDealZero
      [6] = {
        type = 'slider',
        name = GetString(TTCC_DEALCALC_ZERO_NAME),
        tooltip = GetString(TTCC_DEALCALC_ZERO_TIP),
        min = 0,
        max = 100,
        getFunc = function() return TTCCompanion.savedVariables.customDealZero end,
        setFunc = function(value) TTCCompanion.savedVariables.customDealZero = value end,
        default = TTCCompanion.systemDefault.customDealZero,
        disabled = function() return not TTCCompanion.savedVariables.customDealCalc end,
      },
      [7] = {
        type = "description",
        text = GetString(TTCC_DEALCALC_OKAY_TEXT),
      },
    },
  }
  -- Deal Filter Price
  optionsData[#optionsData + 1] = {
    type = 'dropdown',
    name = GetString(TTCC_DEAL_CALC_TYPE_NAME),
    tooltip = GetString(TTCC_DEAL_CALC_TYPE_TIP),
    choices = TTCCompanion.dealCalcChoices,
    choicesValues = TTCCompanion.dealCalcValues,
    getFunc = function() return TTCCompanion.savedVariables.dealCalcToUse end,
    setFunc = function(value)
      TTCCompanion.savedVariables.dealCalcToUse = value
      ZO_ClearTable(TTCCompanion.dealInfoCache)
      CheckDealCalcValue()
    end,
    default = TTCCompanion.systemDefault.dealCalcToUse,
  }
  optionsData[#optionsData + 1] = {
    type = 'checkbox',
    name = GetString(TTCC_DEALCALC_MODIFIEDTTC_NAME),
    tooltip = GetString(TTCC_DEALCALC_MODIFIEDTTC_TIP),
    getFunc = function() return TTCCompanion.savedVariables.modifiedSuggestedPriceDealCalc end,
    setFunc = function(value) TTCCompanion.savedVariables.modifiedSuggestedPriceDealCalc = value end,
    default = TTCCompanion.systemDefault.modifiedSuggestedPriceDealCalc,
    disabled = function() return not (TTCCompanion.savedVariables.dealCalcToUse == TTCCompanion.USE_TTC_SUGGESTED) end,
  }
  -- ascending vs descending sort order with AGS
  optionsData[#optionsData + 1] = {
    type = 'dropdown',
    name = GetString(AGS_PERCENT_ORDER_NAME),
    tooltip = GetString(AGS_PERCENT_ORDER_DESC),
    choices = TTCCompanion.agsPercentSortChoices,
    choicesValues = TTCCompanion.agsPercentSortValues,
    getFunc = function() return TTCCompanion.savedVariables.agsPercentSortOrderToUse end,
    setFunc = function(value) TTCCompanion.savedVariables.agsPercentSortOrderToUse = value end,
    default = TTCCompanion.savedVariables.agsPercentSortOrderToUse,
    disabled = function() return not TTCCompanion.AwesomeGuildStoreDetected end,
  }
  -- Whether or not to show the material cost data in tooltips
  optionsData[#optionsData + 1] = {
    type = 'checkbox',
    name = GetString(TTCC_SHOW_MATERIAL_COST_NAME),
    tooltip = GetString(TTCC_SHOW_MATERIAL_COST_TIP),
    getFunc = function() return TTCCompanion.savedVariables.showMaterialCost end,
    setFunc = function(value) TTCCompanion.savedVariables.showMaterialCost = value end,
    default = TTCCompanion.systemDefault.showMaterialCost,
  }
  -- Should we show the stack price calculator in the Vanilla UI?
  optionsData[#optionsData + 1] = {
    type = 'checkbox',
    name = GetString(TTCC_CALC_NAME),
    tooltip = GetString(TTCC_CALC_TIP),
    getFunc = function() return TTCCompanion.savedVariables.showCalc end,
    setFunc = function(value) TTCCompanion.savedVariables.showCalc = value end,
    default = TTCCompanion.savedVariables.showCalc,
    disabled = function() return TTCCompanion.AwesomeGuildStoreDetected end,
  }

  -- And make the options panel
  LAM:RegisterOptionControls('TTCCompanionOptions', optionsData)
end

function TTCCompanion.GetPricingData(itemLink)
  local theIID = GetItemLinkItemId(itemLink)
  local itemIndex = TTCCompanion.GetOrCreateIndexFromLink(itemLink)
  local selectedGuildId = GetSelectedTradingHouseGuildId()
  local pricingData = TTCCompanion.savedVariables[TTCCompanion.pricingNamespace] and TTCCompanion.savedVariables[TTCCompanion.pricingNamespace][selectedGuildId] and TTCCompanion.savedVariables[TTCCompanion.pricingNamespace][selectedGuildId][theIID] and TTCCompanion.savedVariables[TTCCompanion.pricingNamespace][selectedGuildId][theIID][itemIndex] or nil
  return pricingData
end

function TTCCompanion.SetupPendingPost(self)
  OriginalSetupPendingPost(self)

  if (self.pendingItemSlot) then
    local itemLink = GetItemLink(BAG_BACKPACK, self.pendingItemSlot)
    local _, stackCount, _ = GetItemInfo(BAG_BACKPACK, self.pendingItemSlot)
    local pricingData = TTCCompanion.GetPricingData(itemLink)

    if pricingData then
      self:SetPendingPostPrice(math.floor(pricingData * stackCount))
    else
      local ttcPrice = TTCCompanion:GetTamrielTradeCentrePriceToUse(itemLink)
      if ttcPrice then
        self:SetPendingPostPrice(math.floor(ttcPrice * stackCount))
      end
    end
  end
end

function TTCCompanion.PostPendingItem(self)
  if self.pendingItemSlot and self.pendingSaleIsValid then
    local itemLink = GetItemLink(BAG_BACKPACK, self.pendingItemSlot)
    local _, stackCount, _ = GetItemInfo(BAG_BACKPACK, self.pendingItemSlot)

    local theIID = GetItemLinkItemId(itemLink)
    local itemIndex = TTCCompanion.GetOrCreateIndexFromLink(itemLink)
    local guildId, _ = GetCurrentTradingHouseGuildDetails()

    TTCCompanion.savedVariables[TTCCompanion.pricingNamespace] = TTCCompanion.savedVariables[TTCCompanion.pricingNamespace] or {}
    TTCCompanion.savedVariables[TTCCompanion.pricingNamespace][guildId] = TTCCompanion.savedVariables[TTCCompanion.pricingNamespace][guildId] or {}
    TTCCompanion.savedVariables[TTCCompanion.pricingNamespace][guildId][theIID] = TTCCompanion.savedVariables[TTCCompanion.pricingNamespace][guildId][theIID] or {}
    TTCCompanion.savedVariables[TTCCompanion.pricingNamespace][guildId][theIID][itemIndex] = self.invoiceSellPrice.sellPrice / stackCount

  end
end

function TTCCompanion:updateCalc()
  local stackSize = zo_strmatch(TTCCompanionPriceCalculatorStack:GetText(), 'x (%d+)')
  local unitPrice = TTCCompanionPriceCalculatorUnitCostAmount:GetText()
  if not stackSize or tonumber(stackSize) < 1 then
    TTCCompanion:dm("Info", string.format("%s is not a valid stack size", stackSize))
    return
  end
  if not unitPrice or tonumber(unitPrice) < 0.01 then
    TTCCompanion:dm("Info", string.format("%s is not a valid unit price", unitPrice))
    return
  end
  local totalPrice = math.floor(tonumber(unitPrice) * tonumber(stackSize))
  TTCCompanionPriceCalculatorTotal:SetText(GetString(TTCC_TOTAL_TITLE) .. TTCCompanion.LocalizedNumber(totalPrice) .. ' |t16:16:EsoUI/Art/currency/currency_gold.dds|t')
  TRADING_HOUSE:SetPendingPostPrice(totalPrice)
end

function TTCCompanion:SetupPriceCalculator()
  TTCCompanion:dm("Debug", "SetupPriceCalculator")
  local ttccCalc = CreateControlFromVirtual('TTCCompanionPriceCalculator', ZO_TradingHousePostItemPane, 'TTCCompanionPriceCalc')
  ttccCalc:SetAnchor(BOTTOM, ZO_TradingHouseBrowseItemsLeftPane, BOTTOM, 0, -4)
end

local function SetNamespace()
  TTCCompanion:dm("Debug", "SetNamespace")
  if GetWorldName() == 'NA Megaserver' then
    TTCCompanion.pricingNamespace = TTCCompanion.NA_PRICING_NAMESPACE
  else
    TTCCompanion.pricingNamespace = TTCCompanion.EU_PRICING_NAMESPACE
  end
end

function TTCCompanion:Initialize()
  TTCCompanion:dm("Debug", "TTCCompanion Initialize")
  local systemDefault = {
    dealCalcToUse = TTCCompanion.USE_TTC_AVERAGE,
    agsPercentSortOrderToUse = TTCCompanion.AGS_PERCENT_ASCENDING,
    customDealCalc = false,
    customDealBuyIt = 90,
    customDealSeventyFive = 75,
    customDealFifty = 50,
    customDealTwentyFive = 25,
    customDealZero = 0,
    modifiedSuggestedPriceDealCalc = false,
    showMaterialCost = true,
    showProfitMargin = false,
    showCalc = true,
    pricingData = {},
    pricingdatana = {},
    pricingdataeu = {},
  }
  TTCCompanion.systemDefault = systemDefault

  TTCCompanion.savedVariables = ZO_SavedVars:NewAccountWide('TTCCompanion_SavedVars', 1, nil, systemDefault, nil)

  SetNamespace()
  TTCCompanion:SetupPriceCalculator()
  TTCCompanion:BuildRemovedItemIdTable()
  TTCCompanion:LibAddonInit()

  if not AwesomeGuildStore then
    EVENT_MANAGER:RegisterForEvent(TTCCompanion.name, EVENT_TRADING_HOUSE_PENDING_ITEM_UPDATE,
      function(eventCode, slotId, isPending)
        if TTCCompanion.savedVariables.showCalc and isPending and GetSlotStackSize(1, slotId) > 1 then
          local theLink = GetItemLink(1, slotId, LINK_STYLE_DEFAULT)
          local priceData = nil
          priceData = TTCCompanion.GetPricingData(theLink)
          if not priceData then
            priceData = TTCCompanion:GetTamrielTradeCentrePriceToUse(theLink)
          end
          local floorPrice = 0
          if priceData then floorPrice = string.format('%.2f', priceData) end

          TTCCompanionPriceCalculatorStack:SetText(GetString(TTCC_APP_TEXT_TIMES) .. GetSlotStackSize(1, slotId))
          TTCCompanionPriceCalculatorUnitCostAmount:SetText(floorPrice)
          TTCCompanionPriceCalculatorTotal:SetText(GetString(TTCC_TOTAL_TITLE) .. TTCCompanion.LocalizedNumber(math.floor(floorPrice * GetSlotStackSize(1, slotId))) .. ' |t16:16:EsoUI/Art/currency/currency_gold.dds|t')
          TTCCompanionPriceCalculator:SetHidden(false)
        else TTCCompanionPriceCalculator:SetHidden(true) end
      end)
  end

  if AwesomeGuildStore then
    AwesomeGuildStore:RegisterCallback(AwesomeGuildStore.callback.GUILD_SELECTION_CHANGED,
      function(guildData)
        local selectedGuildId = GetSelectedTradingHouseGuildId()
        TTCCompanion.savedVariables.pricingData = TTCCompanion.savedVariables[TTCCompanion.pricingNamespace][selectedGuildId] or {}
      end)
  end

  EVENT_MANAGER:RegisterForEvent(TTCCompanion.name, EVENT_CLOSE_TRADING_HOUSE, function()
    ZO_ClearTable(TTCCompanion.dealInfoCache)
  end)

  EVENT_MANAGER:RegisterForEvent(TTCCompanion.name, EVENT_TRADING_HOUSE_RESPONSE_RECEIVED, function(_, responseType, result)
    if responseType == TRADING_HOUSE_RESULT_POST_PENDING and result == TRADING_HOUSE_RESULT_SUCCESS then TTCCompanionPriceCalculator:SetHidden(true) end
    -- Set up guild store buying advice
    TTCCompanion:initBuyingAdvice()
    TTCCompanion:initSellingAdvice()
  end)

  -- We'll add stats to tooltips for items we have data for, if desired
  ZO_PreHookHandler(PopupTooltip, 'OnUpdate', function() TTCCompanion:GeneratePopupTooltip(PopupTooltip) end)
  ZO_PreHookHandler(PopupTooltip, 'OnHide', function() TTCCompanion:RemovePopupTooltip(PopupTooltip) end)
  ZO_PreHookHandler(ItemTooltip, 'OnUpdate', function() TTCCompanion:GenerateItemTooltip() end)
  ZO_PreHookHandler(ItemTooltip, 'OnHide', function() TTCCompanion:RemoveItemTooltip() end)

  --[[ This is to save the sale price however AGS has its own routines and uses
  its value first so this is usually not seen, although it does save NA and EU
  separately
  ]]--
  if AwesomeGuildStore then
    AwesomeGuildStore:RegisterCallback(AwesomeGuildStore.callback.ITEM_POSTED,
      function(guildId, itemLink, price, stackCount)
        local theIID = GetItemLinkItemId(itemLink)
        local itemIndex = TTCCompanion.GetOrCreateIndexFromLink(itemLink)
        local selectedGuildId = GetSelectedTradingHouseGuildId()

        TTCCompanion.savedVariables[TTCCompanion.pricingNamespace] = TTCCompanion.savedVariables[TTCCompanion.pricingNamespace] or {}
        TTCCompanion.savedVariables[TTCCompanion.pricingNamespace][selectedGuildId] = TTCCompanion.savedVariables[TTCCompanion.pricingNamespace][selectedGuildId] or {}
        TTCCompanion.savedVariables[TTCCompanion.pricingNamespace][selectedGuildId][theIID] = TTCCompanion.savedVariables[TTCCompanion.pricingNamespace][selectedGuildId][theIID] or {}
        TTCCompanion.savedVariables[TTCCompanion.pricingNamespace][selectedGuildId][theIID][itemIndex] = price / stackCount

      end)
  else
    if TRADING_HOUSE then
      OriginalSetupPendingPost = TRADING_HOUSE.SetupPendingPost
      TRADING_HOUSE.SetupPendingPost = TTCCompanion.SetupPendingPost
      ZO_PreHook(TRADING_HOUSE, 'PostPendingItem', TTCCompanion.PostPendingItem)
    end
  end

  TTCCompanion.isInitialized = true
end

local function OnAddOnLoaded(eventCode, addOnName)
  if addOnName:find('^ZO_') then return end
  if addOnName == "MasterMerchant" then
    TTCCompanion:dm("Info", "MasterMerchant detected")
    return
  end
  if addOnName == TTCCompanion.addonName and addOnName ~= "MasterMerchant" then
    TTCCompanion:dm("Debug", "TTCCompanion Loaded")
    TTCCompanion:Initialize()
  elseif addOnName == "AwesomeGuildStore" and addOnName ~= "MasterMerchant" then
    -- Set up AGS integration, if it's installed
    TTCCompanion:initAGSIntegration()
  elseif addOnName == "WritWorthy" and addOnName ~= "MasterMerchant" then
    if WritWorthy and WritWorthy.CreateParser then TTCCompanion.wwDetected = true end
  elseif addOnName == "MasterWritInventoryMarker" and addOnName ~= "MasterMerchant" then
    if MWIM_SavedVariables then TTCCompanion.mwimDetected = true end
  end

end
EVENT_MANAGER:RegisterForEvent(TTCCompanion.name, EVENT_ADD_ON_LOADED, OnAddOnLoaded)
