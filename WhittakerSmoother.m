classdef WhittakerSmoother < matlab.apps.AppBase
% WHITTAKERSMOOTHER Interactive Whittaker smoothing GUI.
%
%   WhittakerSmoother produces a smooth line by balancing two requirements:
%   the result should stay close to the measured values, but should not change
%   rapidly between neighbouring channels. The parameter lambda controls this
%   balance, and the penalty always uses second differences. Rows are samples
%   and columns are channels.
%
%   The WhittakerSmoother app lets users choose lambda, inspect the
%   smoothed result, apply the calculation to all rows, and export it. The
%   calculation is also available through WhittakerSmootherCore.
%
%   USAGE:
%       app = WhittakerSmoother();
%       app = WhittakerSmoother(spectra);
%       app = WhittakerSmoother(struct('data', spectra, ...
%                                      'wavelength', wavelength));
%
%   INPUTS:
%       spectra     Nonempty, real, finite numeric matrix with at least three
%                   channels.
%       inputData   Scalar struct with a compatible data field and optional
%                   wavelength/wavelengths/xAxis/x/axis vector.
%
%   INPUT AND OUTPUT COMMANDS:
%       app.setInputData(inputData) Load data programmatically.
%       app.getData()                Return the current output struct.
%       delete(app)                  Close the application safely.
%
%   EXAMPLE:
%       Whittaker_test
%       app = WhittakerSmoother(struct('data', spectra, ...
%                                      'wavelength', wavelength));
%       % Set lambda in the GUI, then click Apply.
%       result = app.getData();
%
%   METHOD:
%       The core solves (I + lambda * D2' * D2) * z = y for each row, using
%       a cached Cholesky factorization. lambda must be positive; D2 is the
%       fixed second-difference operator.
%
%   SEE ALSO: WhittakerSmootherCore, DataValidator
%
%   Author: Lovelace's Square
%   Affiliation: Lovelace's Square
%   Date Created: 2026-03-16
%   License: MIT
%   Version: v 1.0

    properties (Access = public)
        UIFigure       matlab.ui.Figure
        HTMLComponent  matlab.ui.control.HTML
        OriginalData   double = []
        SmoothedData   double = []
        Wavelength     double = []
        DataLoaded     logical = false
    end

    properties (Access = private)
        Smoother
        Validator
        TimestampCounter double = 0
        UIReady logical = false
        PendingPayloads cell = {}
        LoadedVarName char = ''
        LoadedAxisName char = ''
        PlotOption char = 'mean'
        PlotSubsetN double = 50
        SelectedSampleIndex double = 1
        MaxPlotBytes double = 12 * 1024 * 1024
        MaxPreviewPlotElements double = 500000
        IsProcessing logical = false
        DataRevision double = 0
        ResultRevision double = 0
        LatestPreviewId double = 0
        AppliedLambda double = NaN
    end

    methods (Access = public)
        function app = WhittakerSmoother(inputData)
            createComponents(app);
            initializeBusinessLogic(app);
            registerApp(app, app.UIFigure);
            runStartupFcn(app, @(~) onStartup(app));

            if nargin >= 1 && ~isempty(inputData)
                try
                    setInputData(app, inputData);
                catch ME
                    delete(app);
                    rethrow(ME);
                end
            end
        end

        function delete(app)
            % DELETE Close the Whittaker window and release UI resources.
            try
                if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                    app.UIFigure.CloseRequestFcn = [];
                    delete(app.UIFigure);
                end
            catch
            end
        end
    end

    methods (Access = private)
        function createComponents(app)
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [100 100 1200 800];
            app.UIFigure.Name = 'Whittaker Smoother';
            app.UIFigure.Color = [0.91 0.92 0.93];
            app.UIFigure.AutoResizeChildren = 'off';
            app.UIFigure.CloseRequestFcn = createCallbackFcn(app, @closeRequest, true);
            app.UIFigure.SizeChangedFcn = createCallbackFcn(app, @figureResized, true);

            htmlPath = fullfile(fileparts(mfilename('fullpath')), ...
                'ui', 'whittaker_smoother_ui.html');
            app.HTMLComponent = uihtml(app.UIFigure);
            app.HTMLComponent.Position = [1 1 1200 800];
            app.HTMLComponent.HTMLSource = htmlPath;
            app.HTMLComponent.DataChangedFcn = createCallbackFcn(app, @HTMLDataChanged, true);
        end

        function initializeBusinessLogic(app)
            modulePath = fileparts(mfilename('fullpath'));
            addpath(fullfile(modulePath, 'business_logic'));
            app.Smoother = WhittakerSmootherCore();
            app.Validator = DataValidator();
        end

        function onStartup(app)
            movegui(app.UIFigure, 'center');
            app.UIFigure.Visible = 'on';
        end
    end

    methods (Access = private)
        function HTMLDataChanged(app, ~)
            data = app.HTMLComponent.Data;
            if isempty(data) || ~isstruct(data), return; end
            if isfield(data, 'source') && strcmp(data.source, 'matlab'), return; end
            if ~isfield(data, 'action'), return; end

            action = char(string(data.action));
            switch action
                case 'uiReady'
                    handleUiReady(app);
                case 'load_data'
                    handleLoadData(app);
                case 'load_variable'
                    handleLoadVariable(app, data);
                case 'preview'
                    handlePreview(app, data);
                case 'parameters_changed'
                    handleParametersChanged(app, data);
                case 'apply'
                    handleApply(app, data);
                case {'prepare_export', 'export'}
                    handlePrepareExport(app);
                case 'do_export'
                    handleDoExport(app, data);
                case 'plot_option'
                    handlePlotOption(app, data);
                case 'preview_plot_option'
                    handlePreviewPlotOption(app, data);
                otherwise
                    sendError(app, sprintf('Unknown action: %s', action));
            end
        end

        function handleUiReady(app)
            app.UIReady = true;
            if ~isempty(app.PendingPayloads)
                pendingPayloads = app.PendingPayloads;
                app.PendingPayloads = {};
                if isscalar(pendingPayloads)
                    payload = pendingPayloads{1};
                else
                    payload = struct('action', 'payload_batch', ...
                        'payloads', {pendingPayloads});
                end
                writeUIUpdate(app, payload);
            else
                payload = struct('action', 'ready', ...
                    'statusMessage', 'Ready. Load spectral data to begin.', ...
                    'statusType', 'success');
                writeUIUpdate(app, payload);
            end
        end

        function handleLoadData(app)
            matrices = collectWorkspaceMatrices(app);
            vectors = collectWorkspaceVectors(app);
            if isempty(matrices)
                sendError(app, 'No finite-compatible numeric matrices are available in the workspace.');
                return;
            end

            payload = struct();
            payload.action = 'show_variable_modal';
            payload.variables = matrices;
            payload.vectors = vectors;
            payload.statusMessage = 'Select a data matrix and optional x-axis.';
            payload.statusType = 'success';
            sendUIUpdate(app, payload);
        end

        function handleLoadVariable(app, request)
            varName = readTextField(app, request, 'varName');
            if isempty(varName) || ~isvarname(varName)
                sendError(app, 'Select a valid workspace matrix.');
                return;
            end
            if ~workspaceVariableExists(app, varName)
                sendError(app, sprintf('Workspace variable "%s" no longer exists.', varName));
                return;
            end

            raw = evalin('base', varName);
            axisName = readTextField(app, request, 'xAxisVar');
            axisData = [];
            if ~isempty(axisName)
                if ~isvarname(axisName) || ~workspaceVariableExists(app, axisName)
                    sendError(app, sprintf('X-axis variable "%s" is not available.', axisName));
                    return;
                end
                axisData = evalin('base', axisName);
            end

            inputData = struct('data', raw, 'varName', varName);
            if ~isempty(axisData)
                inputData.wavelength = axisData;
            end

            try
                [matrix, wavelength, normalizedName] = app.Validator.normalizeInput(inputData);
            catch ME
                sendError(app, ME.message);
                return;
            end

            loadDataIntoState(app, matrix, wavelength, normalizedName, axisName);
            payload = buildDataLoadedPayload(app);
            payload.statusMessage = sprintf('Loaded "%s" (%d x %d).', ...
                varName, size(matrix, 1), size(matrix, 2));
            payload.toastType = 'success';
            payload.toastTitle = 'Data Loaded';
            payload.toastMessage = payload.statusMessage;
            sendUIUpdate(app, payload);
        end

        function handlePreview(app, request)
            requestId = readOptionalFiniteScalar(app, request, 'requestId', 0);
            if ~app.DataLoaded
                sendError(app, 'Load data before previewing.', requestId);
                return;
            end

            requestRevision = readRequestRevision(app, request);
            if requestRevision ~= app.DataRevision || requestId < app.LatestPreviewId
                return;
            end
            app.LatestPreviewId = requestId;

            [valid, message, lambda] = readParameters(app, request);
            if ~valid
                resultInvalidated = invalidateResult(app);
                sendError(app, message, requestId, resultInvalidated);
                return;
            end
            resultInvalidated = invalidateResultForParameters(app, lambda);

            if app.IsProcessing
                sendError(app, 'Another operation is still running.', requestId, resultInvalidated);
                return;
            end

            app.IsProcessing = true;
            cleanup = onCleanup(@() releaseProcessing(app));
            try
                sampleIndex = round(readOptionalFiniteScalar(app, request, ...
                    'sampleIndex', app.SelectedSampleIndex));
                sampleIndex = max(1, min(size(app.OriginalData, 1), sampleIndex));
                app.SelectedSampleIndex = sampleIndex;
                sampleSpectrum = app.OriginalData(sampleIndex, :);
                smoothSample = app.Smoother.smooth(sampleSpectrum, lambda);
            catch ME
                sendError(app, ['Preview failed: ' ME.message], requestId, resultInvalidated);
                return;
            end

            payload = struct();
            payload.action = 'preview_result';
            payload.requestId = requestId;
            payload.dataRevision = app.DataRevision;
            showAll = readLogicalField(app, request, 'showAll', false) && ...
                numel(app.OriginalData) <= app.MaxPreviewPlotElements;
            if showAll
                plotColumns = 1:size(app.OriginalData, 2);
            else
                plotColumns = selectPayloadColumns(app, 3, 0);
            end
            payload.wavelength = app.Wavelength(plotColumns);
            payload.originalSample = sampleSpectrum(plotColumns);
            payload.smoothedSample = smoothSample(plotColumns);
            payload.sampleIndex = sampleIndex;
            payload.lambda = lambda;
            payload.resultInvalidated = resultInvalidated;
            payload.statusMessage = sprintf('Preview updated for sample %d: lambda=%.4g.', ...
                sampleIndex, lambda);
            payload.statusType = 'success';
            sendUIUpdate(app, payload);
        end

        function handleParametersChanged(app, request)
            if ~app.DataLoaded || readRequestRevision(app, request) ~= app.DataRevision
                return;
            end
            invalidateResult(app);
        end

        function handleApply(app, request)
            requestId = readOptionalFiniteScalar(app, request, 'requestId', 0);
            if ~app.DataLoaded
                sendError(app, 'Load data before applying smoothing.', requestId);
                return;
            end

            if readRequestRevision(app, request) ~= app.DataRevision
                sendError(app, 'The input changed. Apply the current parameters again.', requestId, true);
                return;
            end

            [valid, message, lambda] = readParameters(app, request);
            if ~valid
                invalidated = invalidateResult(app);
                sendError(app, message, requestId, invalidated);
                return;
            end
            invalidateResultForParameters(app, lambda);

            if app.IsProcessing
                sendError(app, 'Another operation is still running.', requestId);
                return;
            end

            app.IsProcessing = true;
            cleanup = onCleanup(@() releaseProcessing(app));
            revision = app.DataRevision;
            try
                smoothed = app.Smoother.smooth(app.OriginalData, lambda);
            catch ME
                invalidateResult(app);
                sendError(app, ['Smoothing failed: ' ME.message], requestId, true);
                return;
            end

            if revision ~= app.DataRevision
                invalidateResult(app);
                sendError(app, 'The input changed while smoothing. Apply again.', requestId, true);
                return;
            end

            app.SmoothedData = smoothed;
            app.ResultRevision = revision;
            app.AppliedLambda = lambda;

            message = sprintf('Smoothed %d spectra with lambda=%.4g.', ...
                size(smoothed, 1), lambda);
            payload = buildResultPayload(app, message);
            payload.requestId = requestId;
            payload.lambda = lambda;
            payload.toastType = 'success';
            payload.toastTitle = 'Smoothing Applied';
            payload.toastMessage = message;
            sendUIUpdate(app, payload);
        end

        function handlePrepareExport(app)
            if ~hasCurrentResult(app)
                sendError(app, 'Apply the current parameters before exporting.');
                return;
            end

            existingNames = evalin('base', 'who');
            payload = struct();
            payload.action = 'show_export_modal';
            payload.suggestedDataName = suggestName(app, existingNames, 'whittakerSmoothedData');
            payload.suggestedAxisName = suggestName(app, existingNames, 'whittakerWavelength');
            payload.existingNames = existingNames;
            payload.statusMessage = 'Choose workspace variable names.';
            payload.statusType = 'success';
            sendUIUpdate(app, payload);
        end

        function handleDoExport(app, request)
            if ~hasCurrentResult(app)
                sendError(app, 'The result is missing or stale. Apply smoothing again.');
                return;
            end

            dataName = readTextField(app, request, 'dataName');
            axisName = readTextField(app, request, 'axisName');
            allowOverwrite = readLogicalField(app, request, 'allowOverwrite', false);
            if isempty(dataName) || ~isvarname(dataName)
                sendError(app, 'The smoothed-data name is not a valid MATLAB variable name.');
                return;
            end
            if isempty(axisName) || ~isvarname(axisName)
                sendError(app, 'The x-axis name is not a valid MATLAB variable name.');
                return;
            end
            if strcmp(dataName, axisName)
                sendError(app, 'Use different names for the smoothed data and x-axis.');
                return;
            end
            if ~allowOverwrite && (workspaceVariableExists(app, dataName) || ...
                    workspaceVariableExists(app, axisName))
                sendError(app, 'A selected variable name already exists. Confirm overwrite or choose another name.');
                return;
            end

            try
                assignin('base', dataName, app.SmoothedData);
                assignin('base', axisName, app.Wavelength);
            catch ME
                sendError(app, ['Export failed: ' ME.message]);
                return;
            end

            message = sprintf('Exported "%s" and "%s".', dataName, axisName);
            payload = struct('action', 'export_complete', ...
                'exportedNames', {{dataName, axisName}}, ...
                'statusMessage', message, 'statusType', 'success', ...
                'toastType', 'success', 'toastTitle', 'Export Complete', ...
                'toastMessage', message);
            sendUIUpdate(app, payload);
        end

        function handlePlotOption(app, request)
            option = readTextField(app, request, 'option');
            if ~ismember(option, {'mean', 'subset', 'all'})
                sendError(app, 'Plot mode must be mean, subset, or all.');
                return;
            end
            app.PlotOption = option;

            subsetN = readOptionalFiniteScalar(app, request, 'subsetN', app.PlotSubsetN);
            if strcmp(option, 'subset') && (subsetN < 1 || mod(subsetN, 1) ~= 0)
                sendError(app, 'Subset size must be a positive integer.');
                return;
            end
            if subsetN >= 1
                app.PlotSubsetN = max(1, subsetN);
            end

            if hasCurrentResult(app)
                payload = buildResultPayload(app, sprintf('Plot mode: %s.', app.PlotOption));
                sendUIUpdate(app, payload);
            end
        end

        function handlePreviewPlotOption(app, request)
            if ~app.DataLoaded
                sendError(app, 'Load data before changing preview plot options.');
                return;
            end

            mode = lower(readTextField(app, request, 'mode'));
            if strcmp(mode, 'none')
                sendUIUpdate(app, struct('action', 'preview_plot_disabled', ...
                    'statusMessage', 'Showing the selected sample only.', ...
                    'statusType', 'success'));
                return;
            end
            if ~strcmp(mode, 'all')
                sendError(app, sprintf('Unknown preview plot option: %s', mode));
                return;
            end

            totalElements = double(numel(app.OriginalData));
            if totalElements > app.MaxPreviewPlotElements
                sendUIUpdate(app, struct( ...
                    'action', 'preview_plot_unavailable', ...
                    'statusMessage', sprintf(['Show all was not enabled because the dataset has ' ...
                        '%.0f points; the safe preview limit is %.0f.'], ...
                        totalElements, app.MaxPreviewPlotElements), ...
                    'statusType', 'warning', ...
                    'totalElements', totalElements, ...
                    'maxElements', app.MaxPreviewPlotElements));
                return;
            end

            sendUIUpdate(app, struct( ...
                'action', 'preview_plot_data', ...
                'spectra', app.OriginalData, ...
                'wavelength', app.Wavelength, ...
                'statusMessage', sprintf('Showing all %d input spectra.', size(app.OriginalData, 1)), ...
                'statusType', 'success'));
        end
    end

    methods (Access = private)
        function payload = buildDataLoadedPayload(app)
            nRows = size(app.OriginalData, 1);
            nCols = size(app.OriginalData, 2);
            meanSpectrum = mean(app.OriginalData, 1);
            plotColumns = selectPayloadColumns(app, 2, 0);
            payload = struct();
            payload.action = 'data_loaded';
            payload.dataRevision = app.DataRevision;
            payload.wavelength = app.Wavelength(plotColumns);
            payload.originalMean = meanSpectrum(plotColumns);
            payload.originalSample = app.OriginalData(1, plotColumns);
            payload.sampleIndex = 1;
            payload.nRows = nRows;
            payload.nCols = nCols;
            payload.varName = app.LoadedVarName;
            payload.axisName = app.LoadedAxisName;
            payload.lambda = 1e3;
            payload.plotOption = app.PlotOption;
            payload.statusType = 'success';
            if numel(plotColumns) < nCols
                payload.plotNotice = sprintf( ...
                    'Display downsampled from %d to %d channels to keep the UI payload bounded.', ...
                    nCols, numel(plotColumns));
            end
        end

        function payload = buildResultPayload(app, statusMessage)
            nRows = size(app.SmoothedData, 1);
            nCols = size(app.SmoothedData, 2);
            selectedMode = app.PlotOption;
            subsetIndices = [];
            notice = '';

            switch selectedMode
                case 'mean'
                    plotData = mean(app.SmoothedData, 1);
                case 'subset'
                    subsetIndices = selectEvenlySpacedRows(app, app.PlotSubsetN);
                    plotData = app.SmoothedData(subsetIndices, :);
                case 'all'
                    plotData = app.SmoothedData;
            end

            estimatedElements = (double(size(plotData, 1)) + 3) * double(nCols) + ...
                double(numel(subsetIndices));
            if 16 * estimatedElements > app.MaxPlotBytes && ~strcmp(selectedMode, 'mean')
                maxElements = floor(app.MaxPlotBytes / 16);
                maxRows = max(1, floor((maxElements - 3 * double(nCols)) / ...
                    (double(nCols) + 1)));
                if strcmp(selectedMode, 'all')
                    limitedRows = min([app.PlotSubsetN, maxRows, nRows]);
                    selectedMode = 'subset';
                    app.PlotOption = 'subset';
                    notice = sprintf( ...
                        'All-lines view exceeds %.1f MB; showing %d representative spectra.', ...
                        app.MaxPlotBytes / 1024 / 1024, limitedRows);
                else
                    limitedRows = min([numel(subsetIndices), maxRows, nRows]);
                    notice = sprintf( ...
                        'Subset view limited to %d representative spectra to keep the UI payload bounded.', ...
                        limitedRows);
                end
                subsetIndices = selectEvenlySpacedRows(app, limitedRows);
                plotData = app.SmoothedData(subsetIndices, :);
            end

            plotColumns = selectPayloadColumns(app, size(plotData, 1) + 3, ...
                numel(subsetIndices));
            if numel(plotColumns) < nCols
                columnNotice = sprintf( ...
                    'Display downsampled from %d to %d channels to keep the UI payload bounded.', ...
                    nCols, numel(plotColumns));
                if isempty(notice)
                    notice = columnNotice;
                else
                    notice = sprintf('%s %s', notice, columnNotice);
                end
            end

            originalMean = mean(app.OriginalData, 1);
            smoothedMean = mean(app.SmoothedData, 1);
            payload = struct();
            payload.action = 'apply_result';
            payload.dataRevision = app.DataRevision;
            payload.resultRevision = app.ResultRevision;
            payload.wavelength = app.Wavelength(plotColumns);
            payload.spectra = plotData(:, plotColumns);
            payload.originalMean = originalMean(plotColumns);
            payload.smoothedMean = smoothedMean(plotColumns);
            selectedIndex = max(1, min(nRows, app.SelectedSampleIndex));
            payload.originalSample = app.OriginalData(selectedIndex, plotColumns);
            payload.smoothedSample = app.SmoothedData(selectedIndex, plotColumns);
            payload.sampleIndex = selectedIndex;
            payload.nRows = nRows;
            payload.nCols = nCols;
            payload.plotOption = selectedMode;
            payload.subsetIndices = subsetIndices;
            payload.plotNotice = notice;
            payload.statusMessage = statusMessage;
            payload.statusType = 'success';
        end

        function indices = selectEvenlySpacedRows(app, requestedRows)
            nRows = size(app.SmoothedData, 1);
            count = min(nRows, max(1, round(requestedRows)));
            indices = unique(round(linspace(1, nRows, count)), 'stable');
        end

        function indices = selectPayloadColumns(app, seriesCount, reservedElements)
            nColumns = size(app.OriginalData, 2);
            availableBytes = max(32, app.MaxPlotBytes - 16 * double(reservedElements));
            maxColumns = max(2, floor(availableBytes / ...
                (16 * max(1, double(seriesCount)))));
            count = min(nColumns, maxColumns);
            if count == nColumns
                indices = 1:nColumns;
            else
                indices = unique(round(linspace(1, nColumns, count)), 'stable');
            end
        end

        function loadDataIntoState(app, matrix, wavelength, varName, axisName)
            app.OriginalData = double(matrix);
            app.Wavelength = double(wavelength(:).');
            app.SelectedSampleIndex = 1;
            app.LoadedVarName = char(varName);
            app.LoadedAxisName = char(axisName);
            app.DataLoaded = true;
            app.DataRevision = app.DataRevision + 1;
            app.LatestPreviewId = 0;
            invalidateResult(app);
        end

        function [valid, message, lambda] = readParameters(app, request)
            [lambdaOk, lambda] = readFiniteScalar(app, request, 'lambda');
            if ~lambdaOk
                valid = false;
                message = 'Lambda must be a finite numeric scalar.';
                lambda = NaN;
                return;
            end
            [valid, message] = app.Smoother.validateParams(lambda, size(app.OriginalData, 2));
        end

        function [ok, value] = readFiniteScalar(~, request, fieldName)
            ok = false;
            value = NaN;
            if ~isstruct(request) || ~isfield(request, fieldName), return; end
            raw = request.(fieldName);
            if ischar(raw) || (isstring(raw) && isscalar(raw))
                raw = str2double(raw);
            end
            if isnumeric(raw) && isreal(raw) && isscalar(raw) && isfinite(raw)
                value = double(raw);
                ok = true;
            end
        end

        function value = readOptionalFiniteScalar(app, request, fieldName, defaultValue)
            [ok, parsed] = readFiniteScalar(app, request, fieldName);
            if ok
                value = parsed;
            else
                value = defaultValue;
            end
        end

        function revision = readRequestRevision(app, request)
            revision = readOptionalFiniteScalar(app, request, 'dataRevision', NaN);
            if ~isfinite(revision)
                revision = readOptionalFiniteScalar(app, request, 'revision', app.DataRevision);
            end
        end

        function value = readTextField(~, request, fieldName)
            value = '';
            if ~isstruct(request) || ~isfield(request, fieldName), return; end
            raw = request.(fieldName);
            if ischar(raw)
                value = strtrim(raw);
            elseif isstring(raw) && isscalar(raw)
                value = strtrim(char(raw));
            end
        end

        function value = readLogicalField(~, request, fieldName, defaultValue)
            value = defaultValue;
            if ~isstruct(request) || ~isfield(request, fieldName), return; end
            raw = request.(fieldName);
            if islogical(raw) && isscalar(raw)
                value = raw;
            elseif isnumeric(raw) && isscalar(raw) && isfinite(raw)
                value = raw ~= 0;
            end
        end

        function invalidated = invalidateResultForParameters(app, lambda)
            invalidated = false;
            if isempty(app.SmoothedData), return; end
            if ~isequal(lambda, app.AppliedLambda)
                invalidated = invalidateResult(app);
            end
        end

        function invalidated = invalidateResult(app)
            invalidated = ~isempty(app.SmoothedData) || app.ResultRevision ~= 0;
            app.SmoothedData = [];
            app.ResultRevision = 0;
            app.AppliedLambda = NaN;
        end

        function tf = hasCurrentResult(app)
            tf = app.DataLoaded && ~isempty(app.SmoothedData) && ...
                app.ResultRevision == app.DataRevision;
        end

        function releaseProcessing(app)
            app.IsProcessing = false;
        end

        function matrices = collectWorkspaceMatrices(~)
            variables = evalin('base', 'whos');
            matrices = cell(1, numel(variables));
            matrixCount = 0;
            supported = {'double','single','int8','int16','int32','int64', ...
                'uint8','uint16','uint32','uint64'};
            for k = 1:numel(variables)
                item = variables(k);
                if item.global || ~ismember(item.class, supported), continue; end
                if numel(item.size) ~= 2 || item.size(1) < 1 || item.size(2) < 2, continue; end
                matrixCount = matrixCount + 1;
                matrices{matrixCount} = struct('name', item.name, ...
                    'rows', item.size(1), 'cols', item.size(2), ...
                    'size', sprintf('%d x %d', item.size(1), item.size(2)), ...
                    'className', item.class);
            end
            matrices = matrices(1:matrixCount);
        end

        function vectors = collectWorkspaceVectors(~)
            variables = evalin('base', 'whos');
            vectors = cell(1, numel(variables));
            vectorCount = 0;
            supported = {'double','single','int8','int16','int32','int64', ...
                'uint8','uint16','uint32','uint64'};
            for k = 1:numel(variables)
                item = variables(k);
                if item.global || ~ismember(item.class, supported), continue; end
                if numel(item.size) ~= 2 || ~(item.size(1) == 1 || item.size(2) == 1), continue; end
                vectorLength = max(item.size);
                if vectorLength < 2, continue; end
                vectorCount = vectorCount + 1;
                vectors{vectorCount} = struct('name', item.name, ...
                    'length', vectorLength, 'className', item.class);
            end
            vectors = vectors(1:vectorCount);
        end

        function tf = workspaceVariableExists(~, variableName)
            tf = logical(evalin('base', sprintf('exist(''%s'', ''var'')', variableName)));
        end

        function name = suggestName(~, existingNames, baseName)
            name = baseName;
            suffix = 1;
            while any(strcmp(existingNames, name))
                name = sprintf('%s_%d', baseName, suffix);
                suffix = suffix + 1;
            end
        end
    end

    methods (Access = private)
        function sendError(app, message, requestId, resultInvalidated)
            if nargin < 3, requestId = 0; end
            if nargin < 4, resultInvalidated = false; end
            payload = struct('action', 'error', 'message', message, ...
                'requestId', requestId, 'resultInvalidated', resultInvalidated, ...
                'dataRevision', app.DataRevision, ...
                'statusMessage', message, 'statusType', 'error', ...
                'toastType', 'error', 'toastTitle', 'Whittaker Smoother', ...
                'toastMessage', message);
            sendUIUpdate(app, payload);
        end

        function sendUIUpdate(app, payload)
            if isempty(app.UIFigure) || ~isvalid(app.UIFigure), return; end
            if ~app.UIReady
                app.PendingPayloads{end + 1} = payload;
                return;
            end
            writeUIUpdate(app, payload);
        end

        function writeUIUpdate(app, payload)
            if isempty(app.UIFigure) || ~isvalid(app.UIFigure), return; end
            app.TimestampCounter = app.TimestampCounter + 1;
            payload.source = 'matlab';
            payload.timestamp = app.TimestampCounter;
            app.HTMLComponent.Data = payload;
        end
    end

    methods (Access = public)
        function setInputData(app, inputData, wavelength)
        % SETINPUTDATA Load numeric or supported struct input.
        %
        %   setInputData(app, inputData) uses an axis embedded in the struct
        %   or channel indices. The optional wavelength argument overrides
        %   an embedded axis.
            if app.IsProcessing
                error('WhittakerSmoother:Busy', ...
                    'Cannot replace input data while processing is active.');
            end

            try
                if nargin >= 3
                    [matrix, xAxis, varName] = app.Validator.normalizeInput(inputData, wavelength);
                else
                    [matrix, xAxis, varName] = app.Validator.normalizeInput(inputData);
                end
            catch ME
                error('WhittakerSmoother:InvalidInput', '%s', ME.message);
            end

            loadDataIntoState(app, matrix, xAxis, varName, '');
            payload = buildDataLoadedPayload(app);
            payload.statusMessage = sprintf('Data loaded (%d x %d).', size(matrix, 1), size(matrix, 2));
            payload.toastType = 'success';
            payload.toastTitle = 'Data Loaded';
            payload.toastMessage = payload.statusMessage;
            sendUIUpdate(app, payload);
        end

        function output = getData(app)
        % GETDATA Return the standardized output struct.
        % getData Return the standardized module output.
            current = hasCurrentResult(app);
            if current
                processed = app.SmoothedData;
            else
                processed = [];
            end

            output = struct();
            output.data = processed;
            output.spectra = processed;
            output.smoothedData = processed;
            output.originalData = app.OriginalData;
            output.wavelength = app.Wavelength;
            output.wavelengths = app.Wavelength;
            output.varName = app.LoadedVarName;
            output.parameters = struct('lambda', app.AppliedLambda);
            output.metadata = struct('method', 'WhittakerSmoother', ...
                'isCurrent', current, 'dataRevision', app.DataRevision, ...
                'resultRevision', app.ResultRevision, 'differenceOrder', 2);
        end
    end

    methods (Access = private)
        function closeRequest(app, ~)
            app.UIFigure.CloseRequestFcn = [];
            delete(app.UIFigure);
        end

        function figureResized(app, ~)
            position = app.UIFigure.Position;
            app.HTMLComponent.Position = [1 1 position(3) position(4)];
        end
    end
end
