#' Calculate the Arithmetic Mean
#'
#' Computes the arithmetic mean of a numeric vector. By default, missing
#' values (`NA`) are removed before computation.
#'
#' @param x A numeric vector.
#' @param na.rm Logical. Should `NA` values be removed before computation?
#'   Defaults to `TRUE`.
#'
#' @return A single numeric value: the arithmetic mean of `x`. Returns `NA_real_`
#'   if `x` is empty (or becomes empty after `NA` removal).
#'
#' @examples
#' calc_mean(c(1, 2, 2, 3, 4, 5, 5, 5, 6, 10))
#' # 3.3
#'
#' # Handles NA values
#' calc_mean(c(1, 2, NA, 4))
#' # 2.333333
#'
#' # Single value
#' calc_mean(42)
#' # 42
#'
#' @export
calc_mean <- function(x, na.rm = TRUE) {
  x <- validate_numeric(x, na.rm = na.rm, fn_name = "calc_mean")
  if (length(x) == 0) return(NA_real_)
  sum(x) / length(x)
}
