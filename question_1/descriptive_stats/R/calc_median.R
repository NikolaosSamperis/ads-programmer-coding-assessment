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
#'  if `x` is empty or if `x` contains `NA` values and `na.rm = FALSE`.
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
  # Pass na.rm = FALSE to validate_numeric so that NAs are preserved in x.
  # NA removal is delegated entirely to stats::median(), which handles
  # the user's na.rm argument.
  x <- validate_numeric(x, na.rm = FALSE, fn_name = "calc_median")
  if (length(x) == 0) return(NA_real_)
  result <- stats::median(x, na.rm = na.rm)
  if (is.na(result)) return(NA_real_)
  result
}
