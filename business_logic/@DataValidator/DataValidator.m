classdef DataValidator
    % DATAVALIDATOR Validation shared by GUI and programmatic input paths.
    %
    %   Methods return [valid, message] and do not modify the input values.

    methods (Access = public)
        function [valid, message] = validateMatrix(~, data)
            % VALIDATEMATRIX Check a real finite samples-by-channels matrix.
            valid = false;
            message = '';

            if isempty(data)
                message = 'Data matrix is empty.';
                return;
            end
            if ~isnumeric(data) || ~ismatrix(data)
                message = 'Data must be a numeric 2-D matrix.';
                return;
            end
            if ~isreal(data)
                message = 'Data must be real-valued.';
                return;
            end
            if size(data, 2) < 3
                message = 'Second-difference smoothing requires at least three columns.';
                return;
            end
            if any(~isfinite(data(:)))
                message = 'Data must not contain NaN or Inf values.';
                return;
            end

            valid = true;
        end

        function [valid, message] = validateWavelength(~, wavelength, nColumns)
            % VALIDATEWAVELENGTH Check a finite strictly monotonic x-axis.
            valid = false;
            message = '';

            if isempty(wavelength)
                message = 'The x-axis vector is empty.';
                return;
            end
            if ~isnumeric(wavelength) || ~isvector(wavelength)
                message = 'The x-axis must be a numeric vector.';
                return;
            end
            if ~isreal(wavelength) || any(~isfinite(wavelength(:)))
                message = 'The x-axis must contain only finite real values.';
                return;
            end
            if numel(wavelength) ~= nColumns
                message = sprintf( ...
                    'The x-axis length (%d) does not match the data width (%d).', ...
                    numel(wavelength), nColumns);
                return;
            end

            differences = diff(double(wavelength(:)));
            if ~(all(differences > 0) || all(differences < 0))
                message = 'The x-axis must be strictly monotonic with no duplicate values.';
                return;
            end

            valid = true;
        end

        function classes = supportedNumericClasses(~)
            classes = {'double', 'single', 'int8', 'int16', 'int32', 'int64', ...
                'uint8', 'uint16', 'uint32', 'uint64'};
        end

        function [data, wavelength, varName] = normalizeInput(obj, inputData, wavelengthOverride)
            % NORMALIZEINPUT Build the standard matrix, axis, and name.
            % normalizeInput Accept numeric input and common pipeline structs.
            if isnumeric(inputData)
                data = inputData;
                wavelength = [];
                varName = 'inputData';
            elseif isstruct(inputData) && isscalar(inputData)
                data = obj.firstMatchingField(inputData, ...
                    {'data', 'spectra', 'matrix', 'smoothedData', ...
                     'correctedData', 'filteredData', 'processedData', ...
                     'originalData'});
                if isempty(data)
                    error('DataValidator:MissingData', ...
                        ['Input struct must contain data, spectra, matrix, smoothedData, ' ...
                         'correctedData, filteredData, processedData, or originalData.']);
                end
                wavelength = obj.firstMatchingField(inputData, ...
                    {'wavelength', 'wavelengths', 'xAxis', 'x', 'axis'});
                rawName = obj.firstMatchingField(inputData, ...
                    {'varName', 'variableName', 'name'});
                varName = obj.normalizeName(rawName);
            else
                error('DataValidator:InvalidInput', ...
                    'Input must be a numeric matrix or a scalar struct.');
            end

            if nargin >= 3 && ~isempty(wavelengthOverride)
                wavelength = wavelengthOverride;
            end

            [valid, message] = obj.validateMatrix(data);
            if ~valid
                error('DataValidator:InvalidData', '%s', message);
            end
            data = double(data);

            if isempty(wavelength)
                wavelength = 1:size(data, 2);
            else
                [valid, message] = obj.validateWavelength(wavelength, size(data, 2));
                if ~valid
                    error('DataValidator:InvalidWavelength', '%s', message);
                end
                wavelength = double(wavelength(:).');
            end
        end
    end

    methods (Access = private)
        function value = firstMatchingField(~, inputStruct, candidates)
            value = [];
            available = fieldnames(inputStruct);
            for index = 1:numel(candidates)
                match = find(strcmpi(available, candidates{index}), 1, 'first');
                if ~isempty(match)
                    candidate = inputStruct.(available{match});
                    if ~isempty(candidate)
                        value = candidate;
                        return;
                    end
                end
            end
        end

        function name = normalizeName(~, rawName)
            name = 'inputData';
            if ischar(rawName) && isrow(rawName) && ~isempty(strtrim(rawName))
                name = strtrim(rawName);
            elseif isstring(rawName) && isscalar(rawName) && strlength(rawName) > 0
                name = char(strtrim(rawName));
            end
        end
    end
end
