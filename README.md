# WhittakerSmoother

This MATLAB app smooths each row of a data matrix with the Whittaker method.
It keeps the smoothed line close to the measured values while penalising rapid
changes from one channel to the next. The value of `lambda` controls the
balance: a small value follows the data more closely, while a large value
produces a smoother line.

The method is written as:

```text
minimize ||y - z||^2 + lambda ||D^2 z||^2
```

Rows are samples and columns are channels. The app shows the original and
smoothed data and can export the result.

## Start

```matlab
addpath('path/to/WhittakerSmoother')
Whittaker_test
app = WhittakerSmoother(spectra);
```

The constructor accepts a numeric matrix or a struct. Struct data fields
include `data`, `spectra`, `matrix`, and `originalData`. The optional x-axis
may be supplied as `wavelength`, `wavelengths`, `xAxis`, `x`, or `axis`. If it
is absent, channel numbers are used.

Input matrices must be nonempty, real, finite numeric 2-D arrays with at least
three columns. The x-axis must have the same length as the matrix width and must
increase or decrease without repeats.

## Parameters and method

| Parameter | Constraint |
|---|---|
| `lambda` | Finite positive number |

The smoother always uses the second-difference penalty `D^2`; there is no
selectable difference order. The calculation builds the corresponding system
and solves it with a cached Cholesky factorization. The same factor is reused
for all rows with the same channel count and lambda. A failed or non-finite
solve is reported as an error.

The app previews one selected sample while parameters are edited. Lambda
updates are throttled during slider movement, so the preview continues to
change while the pointer is being dragged. The sample selector can be used to
inspect different rows. The preview chart's `+` menu has an opt-in **Show all
spectra** mode. It is off by default, loaded only on request, and refused above
500,000 plotted elements to avoid large browser/RAM transfers. After `Apply`,
the result can be viewed as the mean, a sample of rows, or all rows. Display
choices do not change the full result.

## Result and calculation without the window

```matlab
output = app.getData();
```

The output contains `data`, `spectra`, and `smoothedData` for the smoothed
matrix, `originalData`, `wavelength` and `wavelengths`, the source name,
the applied `parameters`, and `metadata`.

The calculation can also be used without the window:

```matlab
addpath(fullfile('path/to/WhittakerSmoother', 'business_logic'))
core = WhittakerSmootherCore();
smoothed = core.smooth(spectra, 1e4);
[valid, message] = core.validateParams(1e4, size(spectra, 2));
stats = core.getCacheStats();
```

Changing the input or parameters makes the previous result out of date.
Export is available only after a successful `Apply` with the current values.

## Example data and tests

`Whittaker_test.m` creates noisy spectra with baseline drift:

```matlab
Whittaker_test
app = WhittakerSmoother(spectra);
```

Run the checks from this folder:

```matlab
runWhittakerSmootherTests
run_whittaker_assertions
run_whittaker_adversarial_tests
```

MATLAB R2022a or later is required. No additional toolbox is needed.

## Reference

Eilers, P. H. C. (2003). A perfect smoother. *Analytical Chemistry*, 75(14),
3631-3636.

License: MIT
