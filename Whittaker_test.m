%% Whittaker_test - Generate noisy spectra for Whittaker smoother testing
% Creates spectra with high-frequency noise and baseline drift.
% Use as demo data for the Whittaker Smoother GUI.
%
% Output variables:
%   spectra    - 25x500 matrix (samples x wavelengths)
%   wavelength - 1x500 vector (nm)
%
% Author: Lovelace's Square
% Date Created: 2026-03-16
% License: MIT
% Reviewed by Lovelace's Square: Yes
% Version: v 1.0

rng(42);

nSamples = 25;
nChannels = 500;
wavelength = linspace(1000, 2400, nChannels);

gauss = @(x, mu, h, w) h .* exp(-((x - mu).^2) ./ (2*w.^2));

spectra = zeros(nSamples, nChannels);

for s = 1:nSamples
    % Clean signal with absorption features
    clean = 0.5 + gauss(wavelength, 1200, 0.8+0.1*randn(), 55) + ...
        gauss(wavelength, 1500, 1.2+0.15*randn(), 40) + ...
        gauss(wavelength, 1730, 0.6+0.1*randn(), 60) + ...
        gauss(wavelength, 1950, 1.0+0.1*randn(), 45) + ...
        gauss(wavelength, 2200, 0.7+0.1*randn(), 70);

    clean = clean * (0.85 + 0.3*rand());

    % Broad high-frequency noise
    hfNoise = 0.04 * randn(1, nChannels);

    % Correlated noise (instrument drift)
    t = linspace(0, 1, nChannels);
    drift = 0.15*randn()*sin(2*pi*3*t + 2*pi*rand()) + ...
            0.08*randn()*sin(2*pi*7*t + 2*pi*rand());

    spectra(s, :) = clean + hfNoise + drift;
end

clearvars -except spectra wavelength

fprintf('Created: spectra (%dx%d), wavelength (1x%d)\n', ...
    size(spectra,1), size(spectra,2), length(wavelength));
fprintf('Contains high-frequency noise + correlated drift.\n');
fprintf('Run WhittakerSmoother to smooth the spectra.\n');
