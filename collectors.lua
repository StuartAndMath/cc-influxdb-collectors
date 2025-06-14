local collectors = {}

-- Big Reactor Collector

collectors.bigreactor = function(peripheral_name)

  local function build_stats(reactor)
    local stats = {}
    -- Direct values
    stats.casing_temperature = reactor.getCasingTemperature()
    stats.active = reactor.getActive()
    stats.number_of_control_rods = reactor.getNumberOfControlRods()

    -- Control rod levels as individual stats
    local levels = reactor.getControlRodsLevels and reactor.getControlRodsLevels()
    if type(levels) == "table" then
      for i, v in ipairs(levels) do
        stats["control_rod_level_" .. i] = v
      end
    end

    -- Fuel stats
    local fuel = reactor.getFuelStats and reactor.getFuelStats()
    if type(fuel) == "table" then
      stats.fuel_temperature = fuel.fuelTemperature
      stats.fuel_amount = fuel.fuelAmount
      stats.fuel_capacity = fuel.fuelCapacity
      stats.waste_amount = fuel.wasteAmount
      stats.fuel_consumed_last_tick = fuel.fuelConsumedLastTick
      stats.fuel_reactivity = fuel.fuelReactivity
    end

    -- Energy stats
    local energy = reactor.getEnergyStats and reactor.getEnergyStats()
    if type(energy) == "table" then
      stats.energy_stored = energy.energyStored
      stats.energy_produced_last_tick = energy.energyProducedLastTick
      stats.energy_capacity = energy.energyCapacity
      stats.energy_system = energy.energySystem
    end

    -- Hot fluid stats
    local hot = reactor.getHotFluidStats and reactor.getHotFluidStats()
    if type(hot) == "table" then
      stats.hot_fluid_produced_last_tick = hot.fluidProducedLastTick
      stats.hot_fluid_amount = hot.fluidAmount
      stats.hot_fluid_capacity = hot.fluidCapacity
    end

    -- Coolant fluid stats
    local coolant = reactor.getCoolantFluidStats and reactor.getCoolantFluidStats()
    if type(coolant) == "table" then
      stats.coolant_fluid_amount = coolant.fluidAmount
      stats.coolant_fluid_capacity = coolant.fluidCapacity
    end
    return stats
  end

  return {
    collect = function()
      if not peripheral.isPresent(peripheral_name) then
        return nil, "No peripheral found with name: " .. tostring(peripheral_name)
      end
      local reactor = peripheral.wrap(peripheral_name)
      local ok, stats_or_err = pcall(build_stats, reactor)
      if not ok then
        return nil, "Error collecting reactor stats: " .. tostring(stats_or_err)
      end
      return stats_or_err, nil
    end
  }
end

-- out_only is a special flag to only collect output stats. Usage is that
-- there are two ports connected to the pc, one in input mode and one in output mode.
-- When collecting stats, the input port should collect everything, and the output port
-- should only collect output stats, to avoid double counting.
collectors.inductionport = function(peripheral_name, out_only)

  local function build_stats(port)
    local stats = {}
    if out_only then
      stats.last_output = port.getLastOutput()
      return stats
    end

    stats.max_energy = port.getMaxEnergy()
    stats.energy_filled_percentage = port.getEnergyFilledPercentage()
    stats.last_input = port.getLastInput()
    stats.energy_needed = port.getEnergyNeeded()
    stats.height = port.getHeight()
    stats.installed_cells = port.getInstalledCells()
    stats.installed_providers = port.getInstalledProviders()
    stats.energy = port.getEnergy()
    stats.mode = port.getMode()
    stats.width = port.getWidth()
    stats.transfer_cap = port.getTransferCap()
    return stats
  end

  return {
    collect = function()
      if not peripheral.isPresent(peripheral_name) then
        return nil, "No peripheral found with name: " .. tostring(peripheral_name)
      end
      local port = peripheral.wrap(peripheral_name)
      local ok, stats_or_err = pcall(build_stats, port)
      if not ok then
        return nil, "Error collecting inductionport stats: " .. tostring(stats_or_err)
      end
      return stats_or_err, nil
    end
  }
end

collectors.me_bridge = function(peripheral_name, blockreader_name)

  local function build_stats(bridge, blockreader)
    local stats = {}
    stats.total_item_storage = bridge.getTotalItemStorage()
    stats.used_item_storage = bridge.getUsedItemStorage()
    stats.available_item_storage = bridge.getAvailableItemStorage()

    stats.total_fluid_storage = bridge.getTotalFluidStorage()
    stats.used_fluid_storage = bridge.getUsedFluidStorage()
    stats.available_fluid_storage = bridge.getAvailableFluidStorage()

    stats.energy_storage = bridge.getEnergyStorage()
    stats.max_energy_storage = bridge.getMaxEnergyStorage()
    stats.energy_usage = bridge.getEnergyUsage()
    stats.avg_power_injection = bridge.getAvgPowerInjection()
    stats.avg_power_usage = bridge.getAvgPowerUsage()

    -- Crafting CPUs
    local cpus = bridge.getCraftingCPUs()
    if type(cpus) == "table" then
      local name_count = {}
      for i, cpu in ipairs(cpus) do
        local name = (cpu.name or "unnamed"):lower()
        local base = "crafting_cpu_" .. name
        local field = base
        if stats[field .. "_coprocessors"] then
          local n = name_count[name] or 1
          repeat
            n = n + 1
            field = base .. "_" .. n
          until not stats[field .. "_coprocessors"]
          name_count[name] = n
          base = field
        else
          name_count[name] = 1
        end
        stats[base .. "_coprocessors"] = cpu.coProcessors
        stats[base .. "_busy"] = cpu.isBusy
        stats[base .. "_storage"] = cpu.storage
      end
    end

    -- If blockreader is present, try to extract item names from lectern book (NBT structure)
    if blockreader then
      local ok, blockdata = pcall(function() return blockreader.getBlockData() end)
      if ok and type(blockdata) == "table" and blockdata.Book and type(blockdata.Book) == "table" then
        local components = blockdata.Book.components
        if type(components) == "table" then
          local book_content = components["minecraft:writable_book_content"]
          if type(book_content) == "table" and type(book_content.pages) == "table" then
            local item_names = {}
            for _, page in ipairs(book_content.pages) do
              if type(page) == "table" and type(page.raw) == "string" then
                -- Remove the first two characters from the page (to skip color codes or weirdness)
                local page_text = page.raw:sub(3)
                for line in page_text:gmatch("[^\r\n]+") do
                  table.insert(item_names, line)
                end
              end
            end
            for _, item_name in ipairs(item_names) do
              -- Query ME Bridge for item count
              local item = bridge.getItem and bridge.getItem({name=item_name})
              if type(item) == "table" and type(item.count) == "number" then
                -- Replace colons with underscores for InfluxDB stat name
                local safe_name = item_name:gsub(":", "_")
                stats["item_count_" .. safe_name] = item.count
              else
                -- If item not found, don't report, because the name might be wrong and dirty the data
                print("Item not found in ME Bridge: " .. item_name)
              end
            end
          end
        end
      end
    end
    return stats
  end

  return {
    collect = function()
      if not peripheral.isPresent(peripheral_name) then
        return nil, "No peripheral found with name: " .. tostring(peripheral_name)
      end
      local bridge = peripheral.wrap(peripheral_name)
      local blockreader = nil
      if blockreader_name then
        if not peripheral.isPresent(blockreader_name) then
          return nil, "No blockReader found with name: " .. tostring(blockreader_name)
        end
        blockreader = peripheral.wrap(blockreader_name)
      end
      local ok, stats_or_err = pcall(build_stats, bridge, blockreader)
      if not ok then
        return nil, "Error collecting me_bridge stats: " .. tostring(stats_or_err)
      end
      return stats_or_err, nil
    end
  }
end

return collectors
