# descriptiveStats

A lightweight R package providing six descriptive-statistics functions for numeric vectors:

| Function       | Description                                 |
|----------------|---------------------------------------------|
| `calc_mean()`  | Arithmetic mean                             |
| `calc_median()`| Median (middle value)                       |
| `calc_mode()`  | Mode, with handling for ties and no-mode    |
| `calc_q1()`    | First quartile (25th percentile)            |
| `calc_q3()`    | Third quartile (75th percentile)            |
| `calc_iqr()`   | Interquartile range (Q3 − Q1)               |

All functions:

- accept any-length numeric vectors,
- remove `NA` values by default (toggle via `na.rm`),
- emit a warning and return `NA_real_` for empty input,
- emit a clear error for non-numeric input.

## Installation

```r
# install.packages("devtools")
devtools::install("question_1/descriptive_stats")
```

## Quick Example

```r
library(descriptiveStats)

data <- c(1, 2, 2, 3, 4, 5, 5, 5, 6, 10)

calc_mean(data)    # 4.3
calc_median(data)  # 4.5
calc_mode(data)    # 5
calc_q1(data)      # 2.25
calc_q3(data)      # 5.0
calc_iqr(data)     # 2.75
```

> **Note on the assessment example values:** The assessment PDF lists
> `calc_mean(data) # 3.3`, `calc_q1(data) # 2.5`, `calc_q3(data) # 5.5`, and
> `calc_iqr(data) # 3` for the data above. These don't match what any standard
> R/CDISC tool would return:
>
> - The true arithmetic mean of `c(1, 2, 2, 3, 4, 5, 5, 5, 6, 10)` is
>   `43 / 10 = 4.3`, not 3.3.
> - No `stats::quantile()` type (1–9) returns Q1 = 2.5 and Q3 = 5.5 for this
>   data; R's default (`type = 7`) returns Q1 = 2.25 and Q3 = 5.0.
>
> The PDF's expected values for `calc_median` (4.5) and `calc_mode` (5) are
> correct and match this package's output exactly. For the remaining functions,
> this package returns the mathematically correct values, computed using
> `stats::quantile()` with `type = 7` — R's documented default and the most
> widely used method for quartiles. The unit tests assert against these correct
> values.

## Edge Cases

```r
# Empty vector — warning + NA
calc_mean(numeric(0))

# Mode with ties — returns all tied values
calc_mode(c(1, 1, 2, 2, 3))     # c(1, 2)

# Mode when every value is unique — message + NA
calc_mode(c(1, 2, 3, 4))        # NA

# Non-numeric input — informative error
calc_mean("a")
#> Error: `calc_mean()`: input 'x' must be numeric, not character.
```

## Quartile Method

`calc_q1()` and `calc_q3()` use `stats::quantile()` with `type = 7` (linear
interpolation), R's default. This matches the expected values in the assessment
specification.

## Package Structure

```
descriptive_stats/
├── DESCRIPTION
├── NAMESPACE
├── LICENSE
├── README.md
├── R/
│   ├── utils.R          # internal validation helper
│   ├── calc_mean.R
│   ├── calc_median.R
│   ├── calc_mode.R
│   ├── calc_q1.R
│   ├── calc_q3.R
│   └── calc_iqr.R
├── man/                 # auto-generated Rd documentation
└── tests/
    ├── testthat.R
    └── testthat/
        ├── test-calc_mean.R
        ├── test-calc_median.R
        ├── test-calc_mode.R
        └── test-quartiles.R
```

## Testing

```r
devtools::test()        # run unit tests
devtools::check()       # full R CMD check
```
