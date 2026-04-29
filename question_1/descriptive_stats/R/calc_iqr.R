#' Calculate the Interquartile Range (IQR)
#'
#' Computes the interquartile range (IQR), defined as the difference between
#' the third and first quartiles: \eqn{IQR = Q3 - Q1}.
#'
#' @param x A numeric vector.
#' @param na.rm Logical. Should `NA` values be removed before computation?
#'   Defaults to `TRUE`.
#'
#' @return A single numeric value: the interquartile range of `x`. Returns
#'   `NA_real_` if `x` is empty (or becomes empty after `NA` removal).
#'
#' @examples
#' calc_iqr(c(1, 2, 2, 3, 4, 5, 5, 5, 6, 10))
#' # 2.75
#'
#' calc_iqr(c(1, 2, 3, 4, 5))
#' # 2
#'
#' @seealso [calc_q1()], [calc_q3()]
#' @export
calc_iqr <- function(x, na.rm = TRUE) {
  # Pass na.rm = FALSE to validate_numeric so NAs are preserved.
  # NA removal is delegated to calc_q1() and calc_q3() via their na.rm argument.
  x <- validate_numeric(x, na.rm = FALSE, fn_name = "calc_iqr")
  if (length(x) == 0) return(NA_real_)
  result <- calc_q3(x, na.rm = na.rm) - calc_q1(x, na.rm = na.rm)
  if (is.na(result)) return(NA_real_)
  result
}
