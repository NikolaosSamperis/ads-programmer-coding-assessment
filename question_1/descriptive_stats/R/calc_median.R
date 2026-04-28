#' Calculate the Median
#'
#' Computes the median (middle value) of a numeric vector. For vectors of
#' even length, the median is the average of the two middle values.
#'
#' @param x A numeric vector.
#' @param na.rm Logical. Should `NA` values be removed before computation?
#'   Defaults to `TRUE`.
#'
#' @return A single numeric value: the median of `x`. Returns `NA_real_`
#'   if `x` is empty (or becomes empty after `NA` removal).
#'
#' @examples
#' calc_median(c(1, 2, 2, 3, 4, 5, 5, 5, 6, 10))
#' # 4.5
#'
#' # Odd-length vector
#' calc_median(c(1, 3, 5))
#' # 3
#'
#' # Handles NA values
#' calc_median(c(1, 2, NA, 4, 5))
#' # 3
#'
#' @export
calc_median <- function(x, na.rm = TRUE) {
  x <- validate_numeric(x, na.rm = na.rm, fn_name = "calc_median")
  n <- length(x)
  if (n == 0) return(NA_real_)
  x_sorted <- sort(x)
  if (n %% 2 == 1) {
    x_sorted[(n + 1) / 2]
  } else {
    mean(x_sorted[c(n / 2, n / 2 + 1)])
  }
}
