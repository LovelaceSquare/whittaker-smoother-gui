classdef WhittakerSmootherCore < handle
    % WHITTAKERSMOOTHERCORE Penalised least-squares smoothing by rows.
    %
    %   The core solves
    %       (I + lambda * D2' * D2) * z = y
    %   for every row of a finite samples-by-channels matrix. A Cholesky
    %   factorization is cached for repeated calls with the same dimensions
    %   and parameters.
    %
    %   EXAMPLE:
    %       core = WhittakerSmootherCore();
    %       smoothed = core.smooth(spectra, 1e4);
    %       stats = core.getCacheStats();
    %
    %   SEE ALSO: WhittakerSmoother
    %
    %   Author: Lovelace's Square
    %   License: MIT

    properties (Access = private)
        CachedNColumns double = NaN
        CachedLambda   double = NaN
        CachedCholesky = []
        FactorizationBuildCount double = 0
    end

    methods (Access = public)
        function smoothedMatrix = smooth(obj, inputMatrix, lambda)
            % SMOOTH Apply Whittaker smoothing to every matrix row.
            %
            %   smoothedMatrix = smooth(inputMatrix, lambda)
            %
            %   lambda must be finite and positive. The penalty always uses
            %   second differences, so input must contain at least 3 columns.
            [valid, message] = obj.validateInputMatrix(inputMatrix);
            if ~valid
                error('WhittakerSmootherCore:InvalidData', '%s', message);
            end

            nColumns = size(inputMatrix, 2);
            [valid, message] = obj.validateParams(lambda, nColumns);
            if ~valid
                error('WhittakerSmootherCore:InvalidParameters', '%s', message);
            end

            inputMatrix = double(inputMatrix);
            if ~obj.hasCachedFactorization(nColumns, lambda)
                identity = speye(nColumns);
                difference = diff(identity, 2, 1);
                systemMatrix = identity + lambda * (difference' * difference);
                if any(~isfinite(nonzeros(systemMatrix)))
                    error('WhittakerSmootherCore:FactorizationFailed', ...
                        ['The Whittaker system is non-finite at this lambda. ' ...
                         'Use a smaller finite smoothing penalty.']);
                end
                try
                    factor = chol(systemMatrix);
                catch ME
                    error('WhittakerSmootherCore:FactorizationFailed', ...
                        'Could not factor the Whittaker system: %s', ME.message);
                end
                if any(~isfinite(nonzeros(factor)))
                    error('WhittakerSmootherCore:FactorizationFailed', ...
                        'The Whittaker factorization produced non-finite values.');
                end
                obj.CachedCholesky = factor;
                obj.CachedNColumns = nColumns;
                obj.CachedLambda = lambda;
                obj.FactorizationBuildCount = obj.FactorizationBuildCount + 1;
            end

            factor = obj.CachedCholesky;
            smoothedMatrix = (factor \ (factor' \ inputMatrix'))';
            if any(~isfinite(smoothedMatrix(:)))
                obj.clearCache();
                error('WhittakerSmootherCore:NumericalFailure', ...
                    ['The Whittaker solve produced non-finite values. ' ...
                     'Use a smaller finite smoothing penalty.']);
            end
        end

        function [valid, message] = validateParams(~, lambda, nColumns)
            % VALIDATEPARAMS Validate lambda and second-difference width.
            valid = false;
            message = '';

            if ~(isnumeric(lambda) && isscalar(lambda) && isreal(lambda) && ...
                    isfinite(lambda) && lambda > 0)
                message = 'Lambda must be a finite numeric scalar greater than zero.';
                return;
            end

            if nargin >= 3 && ~isempty(nColumns)
                if ~(isnumeric(nColumns) && isscalar(nColumns) && isreal(nColumns) && ...
                        isfinite(nColumns) && mod(nColumns, 1) == 0 && nColumns >= 3)
                    message = 'Second-difference smoothing requires at least three columns.';
                    return;
                end
            end

            valid = true;
        end

        function stats = getCacheStats(obj)
            % GETCACHESTATS Return read-only factorization cache information.
            stats = struct();
            stats.nColumns = obj.CachedNColumns;
            stats.lambda = obj.CachedLambda;
            stats.differenceOrder = 2;
            stats.factorizationBuildCount = obj.FactorizationBuildCount;
        end

        function clearCache(obj)
            % CLEARCACHE Remove the cached Cholesky factorization.
            obj.CachedNColumns = NaN;
            obj.CachedLambda = NaN;
            obj.CachedCholesky = [];
        end
    end

    methods (Access = private)
        function tf = hasCachedFactorization(obj, nColumns, lambda)
            tf = ~isempty(obj.CachedCholesky) && ...
                obj.CachedNColumns == nColumns && ...
                obj.CachedLambda == lambda;
        end

        function [valid, message] = validateInputMatrix(~, inputMatrix)
            valid = false;
            message = '';

            if isempty(inputMatrix) || ~isnumeric(inputMatrix) || ~ismatrix(inputMatrix)
                message = 'Input data must be a nonempty numeric 2-D matrix.';
                return;
            end
            if ~isreal(inputMatrix)
                message = 'Input data must be real-valued.';
                return;
            end
            if size(inputMatrix, 2) < 3
                message = 'Second-difference smoothing requires at least three columns.';
                return;
            end
            if any(~isfinite(inputMatrix(:)))
                message = 'Input data must not contain NaN or Inf values.';
                return;
            end

            valid = true;
        end
    end
end
