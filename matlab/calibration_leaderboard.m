% calibration_leaderboard.m
% Fetch Firebase once on startup, then click plot to toggle 1-second live updates.
% Ranks student fits by SSE and plots top student lines against calibration points.

clear;
clc;
close all;

% Calibration data: Y = height (cm), X = voltage
heights = [0, 1, 5, 9, 13, 15, 16, 17, 20.5, 21];
voltages = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.4, 2.9, 3.1];

% TODO: Replace with your Firebase Realtime DB URL from firebase-config.js
% Example: https://my-project-default-rtdb.firebaseio.com
firebaseBaseUrl = "https://ew202-interactive-default-rtdb.firebaseio.com";
endpoint = firebaseBaseUrl + "/submissions.json";

pollSeconds = 1;

f = figure('Name', 'Range Sensor Calibration Plot', 'Color', 'w', ...
    'WindowButtonDownFcn', @toggleLiveUpdates);
setappdata(f, 'liveUpdates', false);
setappdata(f, 'needsRefresh', true);

while ishandle(f)
    liveUpdates = getappdata(f, 'liveUpdates');
    needsRefresh = getappdata(f, 'needsRefresh');

    if needsRefresh || liveUpdates
        clf(f);
        set(f, 'WindowButtonDownFcn', @toggleLiveUpdates);
        hold on;

        % Plot measured points as thick X markers (no connecting lines)
        scatter(voltages, heights, 260, 'x', 'LineWidth', 3.6, 'MarkerEdgeColor', [0 0 0]);

        titleColor = [0 0 0];
        if liveUpdates
            titleColor = [0 0.5 0];
        end

        title('Ping Pong Ball Sensor Calibration', 'FontWeight', 'bold', 'FontSize', 18, 'Color', titleColor);
        xlabel('Sensor Voltage (V)', 'FontSize', 15);
        ylabel('Ball Height (cm)', 'FontSize', 15);
        set(gca, 'FontSize', 16);
        xlim([0, max(voltages) * 1.05]);
        ylim([0, max(heights) * 1.05]);
        xt = xticks;
        yt = yticks;
        if ~ismember(0, xt)
            xticks(unique([0, xt]));
        end
        if ~ismember(0, yt)
            yticks(unique([0, yt]));
        end
        grid on;

        studentRows = fetchAndRank(endpoint, voltages, heights);

        if ~isempty(studentRows)
            topN = min(10, numel(studentRows));
            cmap = lines(topN);

            % Sort already ascending by SSE; legend should match this order.
            legendItems = cell(1, topN + 1);
            legendItems{1} = 'Collected Data';

            xFit = linspace(min(voltages), max(voltages), 200);
            for i = 1:topN
                row = studentRows(i);
                yFit = row.m .* xFit + row.b;
                lineColor = cmap(i, :) * 0.55 + 0.45;
                plot(xFit, yFit, 'LineWidth', 2.2, 'Color', lineColor);
                legendItems{i + 1} = sprintf('%s: %.1f', row.name, row.sse);
            end

            % Replot measured points on top so they remain visible over lines.
            scatter(voltages, heights, 260, 'x', 'LineWidth', 3.6, 'MarkerEdgeColor', [0 0 0]);
            legend(legendItems, 'Location', 'northwest', 'FontSize', 13);
        else
            legend('Collected Data', 'Location', 'northwest', 'FontSize', 12);
        end

        setappdata(f, 'needsRefresh', false);
    end

    drawnow;

    if ~ishandle(f)
        break;
    end

    liveUpdates = getappdata(f, 'liveUpdates');
    if liveUpdates
        pause(pollSeconds);
    else
        pause(0.1);
    end
end

function toggleLiveUpdates(src, ~)
    if ~ishandle(src)
        return;
    end

    liveUpdates = getappdata(src, 'liveUpdates');
    if isempty(liveUpdates)
        liveUpdates = false;
    end

    liveUpdates = ~liveUpdates;
    setappdata(src, 'liveUpdates', liveUpdates);
    setappdata(src, 'needsRefresh', true);

    if liveUpdates
        fprintf('\n[%s] Live updates ON (1 second).\n', datestr(now, 'HH:MM:SS'));
    else
        fprintf('\n[%s] Live updates OFF.\n', datestr(now, 'HH:MM:SS'));
    end
end

function rows = fetchAndRank(endpoint, voltages, heights)
    rows = struct('name', {}, 'm', {}, 'b', {}, 'sse', {});

    try
        raw = webread(endpoint);
    catch err
        fprintf('\n[%s] Firebase request failed: %s\n', datestr(now, 'HH:MM:SS'), err.message);
        return;
    end

    if isempty(raw)
        fprintf('\n[%s] No submissions found.\n', datestr(now, 'HH:MM:SS'));
        return;
    end

    keys = fieldnames(raw);

    for i = 1:numel(keys)
        item = raw.(keys{i});

        if ~isstruct(item)
            continue;
        end

        if ~isfield(item, 'name') || ~isfield(item, 'm') || ~isfield(item, 'b')
            continue;
        end

        mVal = str2double(string(item.m));
        bVal = str2double(string(item.b));

        if isnan(mVal) || isnan(bVal)
            continue;
        end

        predicted = mVal .* voltages + bVal;
        sseVal = sum((heights - predicted) .^ 2);

        rows(end + 1).name = char(string(item.name)); %#ok<AGROW>
        rows(end).m = mVal;
        rows(end).b = bVal;
        rows(end).sse = sseVal;
    end

    if isempty(rows)
        fprintf('\n[%s] Submissions exist but no valid m/b records found.\n', datestr(now, 'HH:MM:SS'));
        return;
    end

    [~, order] = sort([rows.sse], 'ascend');
    rows = rows(order);

    clc;
    fprintf('\n[%s] Student SSE ranking:\n', datestr(now, 'HH:MM:SS'));
    for i = 1:numel(rows)
        fprintf('%2d. %-20s SSE = %.3f (m=%.4f, b=%.4f)\n', i, rows(i).name, rows(i).sse, rows(i).m, rows(i).b);
    end
end
