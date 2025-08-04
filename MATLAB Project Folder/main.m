%% main.m

%% Section 1: Header
% Evaristo Campos de Abreu Ribeiro

% MATLAB and Simulink Challenge Projects:
% Techno-Economic Assessment of Green Hydrogen Production

%% Section 2: Loading Data

clc; % clear command windows
clear all; % clear workspace
close all; % close tabs

averageIrradianceTable = readtable("averageIrradianceData.xlsx", 'VariableNamingRule', 'preserve');
electricityCostTable = readtable("electricityCostData.xlsx", 'VariableNamingRule', 'preserve'); % cost in $ / kWh
bottledWaterTable = readtable("bottledWaterData.xlsx", 'VariableNamingRule', 'preserve'); % cost in $ / 0.33L bottle

%% Section 3: Data Structure and Manipulation
% The production of Hydrogen with the model used requires water
% There is no publicly avaiable data with average tap water price by
% country, but I could find a table with average tap water price.

% To compute the water usage into the operational cost for this model, I am
% adjusting the bottled water price in our table (every ountry) with an
% interpolation of the ratio tap water/bottled water prices for a few base
% countries. This way, we have an average tap water price by country
% that varies according to the bottled water price.

bottledWaterBrazil = 0.69; % USD $0.69 / 0.33L bottle
tapWaterBrazil = 0.35; % USD $1.5 / 1000L or 1000kg or 1m^3 tap
waterRatioBrazil = tapWaterBrazil / bottledWaterBrazil;

bottledWaterSwitzerland = 4.88; % USD $4.88 / 0.33L bottle
tapWaterSwitzerland = 2.5; % USD $2.5 / 1000L or 1000kg or 1m^3 tap
waterRatioSwitzerland = tapWaterSwitzerland / bottledWaterSwitzerland;

bottledWaterBangladesh = 0.16; % USD $0.16 / 0.33L bottle
tapWaterBangladesh = 0.11; % USD $0.1 / 1000L or 1000kg or 1m^3 tap
waterRatioBangladesh = tapWaterBangladesh / bottledWaterBangladesh;

meanWaterRatio = (waterRatioBrazil + waterRatioSwitzerland + waterRatioBangladesh) / 3;

tapWaterTable = bottledWaterTable(:,2) .* meanWaterRatio; % cost in $ / 1000L or 1000kg or 1m^3 tap

for i = 1:height(averageIrradianceTable)
    Data(i).country=averageIrradianceTable{i,1};
    Data(i).irradiance=averageIrradianceTable{i,2};
    Data(i).electricity=electricityCostTable{i,2};
    Data(i).water=tapWaterTable{i,1};
end

%% Section 4: Running Model (Parallelized and Fixed)

open_system('greenHydrogenProductionModel');
n = height(averageIrradianceTable);
DataTemp = repmat(struct( ...
    'country', "", ...
    'irradiance', 0, ...
    'electricity', 0, ...
    'water', 0, ...
    'electricityCost', 0, ...
    'waterCost', 0, ...
    'maintenanceCost', 0, ...
    'operationalCost', 0, ...
    'totalCost', 0, ...
    'H2_kg_per_year', 0, ...
    'LCOH', 0 ...
    ), n, 1);  % Preallocate with fixed fields

parfor i = 1:n
    % Local variables (copies)
    country = averageIrradianceTable{i,1};
    irradiance = averageIrradianceTable{i,2};
    electricity = electricityCostTable{i,2};
    water = tapWaterTable{i,1};
    % Step 1: Create irradiance time series
    time = (0:8759)';
    irradiancePerHour = irradiance / 24;
    IrradianceTS = timeseries(irradiancePerHour * ones(length(time), 1), time);

    % Step 2: Build SimulationInput
    simIn = Simulink.SimulationInput('greenHydrogenProductionModel');
    simIn = simIn.setVariable('Irradiance', IrradianceTS);

    % Step 3: Run sim
    out = sim(simIn);

    % Capital Costs
    solarCPkw = 750;
    solarCapitalCost = mean(out.Psolarkw(end-24:end)) * solarCPkw;

    batteryCPkwh = 450;
    batteryCost = max(out.Estoragekwhr) * batteryCPkwh;

    electronicsCPkwh = 500;
    electronicsCost = max(abs([max(out.Pstoragekw), min(out.Pstoragekw)])) * electronicsCPkwh;
    batteryCapitalCost = batteryCost + electronicsCost;

    electrolyzerCPkW = 1000;
    Pelectrolyzer_kw = out.Velectrolyzer .* out.Ielectrolyzer / 1000;
    electrolyzerCapitalCost = mean(Pelectrolyzer_kw(end-24:end)) * electrolyzerCPkW;

    capitalCost = solarCapitalCost + batteryCapitalCost + electrolyzerCapitalCost;

    % Operational Costs
    electricityCost = sum(max(out.Pgridkw, 0)) * electricity;
    waterCost = (sum(out.H2O_kg_hr) / 1000) * water;
    maintenanceCost = 0.03 * capitalCost;
    operationalCost = electricityCost + waterCost + maintenanceCost;

    % Hydrogen Production
    totalH2_kg = sum(out.H2_kg_hr);
    LCOH = (capitalCost + operationalCost) / totalH2_kg;

    % Store in output struct
    DataTemp(i).country = country;
    DataTemp(i).irradiance = irradiance;
    DataTemp(i).electricity = electricity;
    DataTemp(i).water = water;
    DataTemp(i).electricityCost = electricityCost;
    DataTemp(i).waterCost = waterCost;
    DataTemp(i).maintenanceCost = maintenanceCost;
    DataTemp(i).operationalCost = operationalCost;
    DataTemp(i).totalCost = capitalCost + operationalCost;
    DataTemp(i).H2_kg_per_year = totalH2_kg;
    DataTemp(i).LCOH = LCOH;
end

Data = DataTemp;

% Print summary
for i = 1:n
    disp("[" + i + "/" + n + "] Completed simulation for " + Data(i).country + ...
        " (" + round(Data(i).LCOH, 2) + " $/kg H2)");
end

%% Section 5: Results
% Extract LCOH and countries
LCOH_values = [Data.LCOH];
countries = string({Data.country}); % ensure all are strings

% Sort for plotting
[sortedLCOH, sortIdx] = sort(LCOH_values);
sortedCountries = countries(sortIdx);

% Best and worst
[bestLCOH, bestIdx] = min(LCOH_values);
[worstLCOH, worstIdx] = max(LCOH_values);

% Display best and worst using disp with concatenation
disp("🌍 Best Location: " + string(Data(bestIdx).country));
disp("  - LCOH: $" + string(round(Data(bestIdx).LCOH, 2)) + "/kg");
disp("  - H2/year: " + string(round(Data(bestIdx).H2_kg_per_year, 1)) + " kg");
disp("  - Capital Cost: $" + string(round(Data(bestIdx).totalCost - Data(bestIdx).operationalCost)));
disp("  - Operational Cost: $" + string(round(Data(bestIdx).operationalCost)));

disp(" ");
disp("💸 Worst Location: " + string(Data(worstIdx).country));
disp("  - LCOH: $" + string(round(Data(worstIdx).LCOH, 2)) + "/kg");
disp("  - H2/year: " + string(round(Data(worstIdx).H2_kg_per_year, 1)) + " kg");
disp("  - Capital Cost: $" + string(round(Data(worstIdx).totalCost - Data(worstIdx).operationalCost)));
disp("  - Operational Cost: $" + string(round(Data(worstIdx).operationalCost)));

% Plot sorted LCOH
figure;
bar(sortedLCOH);
set(gca, 'xticklabel', sortedCountries, 'xtick', 1:length(sortedCountries));
xtickangle(45);
ylabel('LCOH ($/kg)');
title('Levelized Cost of Hydrogen by Country');
grid on;
