% calibration_leaderboard.m
% Fetch Firebase once on startup, then click plot to toggle 1-second live updates.
% Ranks student fits by SSE, plots top student lines, and tracks persistent
% (m, b, SSE) points on a separate 3D history figure.

clear;
clc;
close all;

% Calibration data: Y = height (cm), X = voltage
voltages = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.4, 2.9, 3.1];
heights = [0, 1, 5, 9, 13, 15, 16, 17, 20.5, 21];

% TODO: Replace with your Firebase Realtime DB URL from firebase-config.js
% Example: https://my-project-default-rtdb.firebaseio.com
firebaseBaseUrl = "https://ew202-interactive-default-rtdb.firebaseio.com";
endpoint = firebaseBaseUrl + "/submissions.json";

pollSeconds = 1;
ssePlotUpdateSeconds = 5;

% Fallback line color for submissions that do not include a valid hex color.
defaultColor = '#6c757d';

% Build two figures:
% 1) 2D calibration + student fit lines
% 2) 3D SSE search history (m, b, SSE)
f = figure('Name', 'Range Sensor Calibration Plot', 'Color', 'w', ...
    'WindowButtonDownFcn', @toggleLiveUpdates);
f3d = figure('Name', 'SSE Search History', 'Color', 'w');

% Store script state in figure appdata so callbacks/functions can share it.
setappdata(f, 'liveUpdates', false);
setappdata(f, 'needsRefresh', true);
setappdata(f, 'last3dRefreshTime', -inf);
setappdata(f, 'ssePlotUpdateSeconds', ssePlotUpdateSeconds);
setappdata(f, 'sseHistory', struct('name', {}, 'm', {}, 'b', {}, 'sse', {}, 'color', {}, 'updatedAt', {}));
setappdata(f, 'seenHistoryKeys', containers.Map('KeyType', 'char', 'ValueType', 'logical'));
setappdata(f, 'peerFigure', f3d);
setappdata(f3d, 'liveUpdates', false);
setappdata(f3d, 'needsRefresh', true);

% Main loop: runs until either figure is closed.
while ishandle(f) && ishandle(f3d)
    liveUpdates = getappdata(f, 'liveUpdates');
    needsRefresh = getappdata(f, 'needsRefresh');

    % Refresh on-demand or continuously while live mode is enabled.
    if needsRefresh || liveUpdates
        % ----- 2D plot redraw -----
        clf(f);
        set(f, 'WindowButtonDownFcn', @toggleLiveUpdates);
        ax2d = axes(f);
        hold(ax2d, 'on');

        % Plot measured points as thick X markers (no connecting lines)
        scatter(ax2d, voltages, heights, 260, 'x', 'LineWidth', 3.6, 'MarkerEdgeColor', [0 0 0]);

        titleColor = [0 0 0];
        if liveUpdates
            titleColor = [0 0.5 0];
        end

        title(ax2d, 'Ping Pong Ball Sensor Calibration', 'FontWeight', 'bold', 'FontSize', 18, 'Color', titleColor);
        xlabel(ax2d, 'Sensor Voltage (V)', 'FontSize', 15);
        ylabel(ax2d, 'Ball Height (cm)', 'FontSize', 15);
        set(ax2d, 'FontSize', 16);
        xlim(ax2d, [0, max(voltages) * 1.05]);
        ylim(ax2d, [0, max(heights) * 1.05]);

        xt = xticks(ax2d);
        yt = yticks(ax2d);
        if ~ismember(0, xt)
            xticks(ax2d, unique([0, xt]));
        end
        if ~ismember(0, yt)
            yticks(ax2d, unique([0, yt]));
        end
        grid(ax2d, 'on');

        % Pull current submissions and compute SSE ranking.
        studentRows = fetchAndRank(endpoint, voltages, heights, defaultColor);

        % Add any new submissions/resubmissions to persistent 3D history.
        history = getappdata(f, 'sseHistory');
        seenHistoryKeys = getappdata(f, 'seenHistoryKeys');
        [history, seenHistoryKeys] = appendHistoryPoints(history, seenHistoryKeys, studentRows);
        setappdata(f, 'sseHistory', history);
        setappdata(f, 'seenHistoryKeys', seenHistoryKeys);

        if ~isempty(studentRows)
            % Show best fits first (lowest SSE at top).
            topN = min(20, numel(studentRows));
            cmap = lines(topN);

            % Sort already ascending by SSE; legend should match this order.
            legendItems = cell(1, topN + 1);
            legendItems{1} = 'Collected Data';

            xFit = linspace(0, max(voltages) * 1.05, 250);
            for i = 1:topN
                row = studentRows(i);
                yFit = row.m .* xFit + row.b;

                % Prefer each student's chosen color; fallback to palette.
                [customColor, validColor] = parseHexColor(row.color);
                if validColor
                    lineColor = customColor;
                else
                    lineColor = cmap(i, :) * 0.55 + 0.45;
                end

                plot(ax2d, xFit, yFit, 'LineWidth', 1.5, 'Color', lineColor);
                legendItems{i + 1} = sprintf('%s: %.2f', row.name, row.sse);
            end

            % Replot measured points on top so they remain visible over lines.
            scatter(ax2d, voltages, heights, 260, 'x', 'LineWidth', 3.6, 'MarkerEdgeColor', [0 0 0]);
            legend(ax2d, legendItems, 'Location', 'northwest', 'FontSize', 13);
        else
            legend(ax2d, 'Collected Data', 'Location', 'northwest', 'FontSize', 12);
        end

        % ----- 3D plot redraw (throttled) -----
        nowSeconds = posixtime(datetime('now'));
        last3dRefreshTime = getappdata(f, 'last3dRefreshTime');
        shouldRefresh3d = needsRefresh || (liveUpdates && (nowSeconds - last3dRefreshTime >= ssePlotUpdateSeconds));

        if shouldRefresh3d
            % Preserve camera position so manual pan/rotate is not lost.
            camState = get3dCameraState(f3d);

            clf(f3d);
            ax3d = axes(f3d);
            hold(ax3d, 'on');
            grid(ax3d, 'on');

            title(ax3d, 'SSE Search History', 'FontWeight', 'bold', 'FontSize', 16);
            xlabel(ax3d, 'm (slope)', 'FontSize', 13);
            ylabel(ax3d, 'b (intercept)', 'FontSize', 13);
            zlabel(ax3d, 'SSE', 'FontSize', 13);
            set(ax3d, 'FontSize', 12);
            view(ax3d, 46, 26);

            if ~isempty(history)
                for i = 1:numel(history)
                    point = history(i);
                    [rgb, validColor] = parseHexColor(point.color);
                    if ~validColor
                        rgb = [0.35 0.35 0.35];
                    end

                    plot3(ax3d, point.m, point.b, point.sse, 'o', ...
                        'MarkerSize', 6, 'MarkerFaceColor', rgb, 'MarkerEdgeColor', rgb, 'LineStyle', 'none');
                end

            end

            % Keep fixed search bounds for consistent comparison over time.
            xlim(ax3d, [0, 15]);    % m (slope)
            ylim(ax3d, [-10, 10]);  % b (intercept)
            zlim(ax3d, [0, 800]);   % SSE

            apply3dCameraState(ax3d, camState);
            rotate3d(f3d, 'on');
            setappdata(f, 'last3dRefreshTime', nowSeconds);
        end

        % Current frame is now up to date.
        setappdata(f, 'needsRefresh', false);
    end

    drawnow;

    if ~ishandle(f)
        break;
    end

    % Run faster when live mode is active; idle slowly otherwise.
    liveUpdates = getappdata(f, 'liveUpdates');
    if liveUpdates
        pause(pollSeconds);
    else
        pause(0.1);
    end
end

% Toggle live polling on mouse click and sync this state to the peer figure.
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

    peerFigure = getappdata(src, 'peerFigure');
    if ~isempty(peerFigure) && ishandle(peerFigure)
        setappdata(peerFigure, 'liveUpdates', liveUpdates);
        setappdata(peerFigure, 'needsRefresh', true);
    end

    if liveUpdates
        refreshSeconds = getappdata(src, 'ssePlotUpdateSeconds');
        if isempty(refreshSeconds) || ~isnumeric(refreshSeconds)
            refreshSeconds = 30;
        end
        fprintf('\n[%s] Live updates ON (2D: 1 second, 3D: %d seconds).\n', ...
            datestr(now, 'HH:MM:SS'), refreshSeconds);
    else
        fprintf('\n[%s] Live updates OFF.\n', datestr(now, 'HH:MM:SS'));
    end
end

% Read Firebase submissions, validate fields, compute SSE, and return rows sorted by SSE.
function rows = fetchAndRank(endpoint, voltages, heights, defaultColor)
    rows = struct('name', {}, 'm', {}, 'b', {}, 'sse', {}, 'color', {}, 'updatedAt', {}, 'submissionId', {});

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

        colorVal = defaultColor;
        if isfield(item, 'color')
            candidateColor = char(string(item.color));
            if isValidHexColor(candidateColor)
                colorVal = lower(candidateColor);
            end
        end

        updatedAtVal = 0;
        if isfield(item, 'updatedAt')
            updatedAtVal = str2double(string(item.updatedAt));
            if isnan(updatedAtVal)
                updatedAtVal = 0;
            end
        end

        predicted = mVal .* voltages + bVal;
        sseVal = sum((heights - predicted) .^ 2);

        rows(end + 1).name = char(string(item.name)); %#ok<AGROW>
        rows(end).m = mVal;
        rows(end).b = bVal;
        rows(end).sse = sseVal;
        rows(end).color = colorVal;
        rows(end).updatedAt = updatedAtVal;
        rows(end).submissionId = keys{i};
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
        fprintf('%2d. %-20s SSE = %.3f (m=%.4f, b=%.4f, color=%s)\n', ...
            i, rows(i).name, rows(i).sse, rows(i).m, rows(i).b, rows(i).color);
    end
end

% Append only unseen submission snapshots to history so 3D points persist over time.
function [history, seenHistoryKeys] = appendHistoryPoints(history, seenHistoryKeys, studentRows)
    if isempty(studentRows)
        return;
    end

    if isempty(history)
        history = struct('name', {}, 'm', {}, 'b', {}, 'sse', {}, 'color', {}, 'updatedAt', {});
    end

    if isempty(seenHistoryKeys) || ~isa(seenHistoryKeys, 'containers.Map')
        seenHistoryKeys = containers.Map('KeyType', 'char', 'ValueType', 'logical');
    end

    for i = 1:numel(studentRows)
        row = studentRows(i);
        historyKey = sprintf('%s|%.0f|%.12g|%.12g', row.submissionId, row.updatedAt, row.m, row.b);

        if ~isKey(seenHistoryKeys, historyKey)
            seenHistoryKeys(historyKey) = true;
            history(end + 1).name = row.name; %#ok<AGROW>
            history(end).m = row.m;
            history(end).b = row.b;
            history(end).sse = row.sse;
            history(end).color = row.color;
            history(end).updatedAt = row.updatedAt;
        end
    end
end

% Add symmetric padding around axis limits so points are not cramped.
function lims = paddedLimits(values)
    minVal = min(values);
    maxVal = max(values);

    if minVal == maxVal
        pad = max(1, abs(minVal) * 0.1);
    else
        pad = (maxVal - minVal) * 0.08;
    end

    lims = [minVal - pad, maxVal + pad];
end

% Validate '#RRGGBB' format.
function tf = isValidHexColor(color)
    tf = ~isempty(regexp(char(string(color)), '^#[0-9A-Fa-f]{6}$', 'once'));
end

% Convert '#RRGGBB' to MATLAB RGB triplet in [0,1].
function [rgb, valid] = parseHexColor(color)
    colorText = char(string(color));
    valid = isValidHexColor(colorText);

    if ~valid
        rgb = [0 0 0];
        return;
    end

    rgb = [hex2dec(colorText(2:3)), hex2dec(colorText(4:5)), hex2dec(colorText(6:7))] / 255;
end

% Capture current 3D camera settings from an existing figure.
function camState = get3dCameraState(figHandle)
    camState = struct('hasState', false);

    if ~ishandle(figHandle)
        return;
    end

    ax = findobj(figHandle, 'Type', 'axes', '-depth', 1);
    if isempty(ax) || ~isgraphics(ax(1), 'axes')
        return;
    end
    ax = ax(1);

    camState.hasState = true;
    camState.CameraPosition = ax.CameraPosition;
    camState.CameraTarget = ax.CameraTarget;
    camState.CameraUpVector = ax.CameraUpVector;
    camState.CameraViewAngle = ax.CameraViewAngle;
end

% Reapply prior camera settings after plot redraw.
function apply3dCameraState(ax, camState)
    if ~isgraphics(ax, 'axes')
        return;
    end

    if ~isfield(camState, 'hasState') || ~camState.hasState
        return;
    end

    ax.CameraPosition = camState.CameraPosition;
    ax.CameraTarget = camState.CameraTarget;
    ax.CameraUpVector = camState.CameraUpVector;
    ax.CameraViewAngle = camState.CameraViewAngle;
end
