#' Calculate the First Quartile (Q1)
#'
#' Computes the first quartile (25th percentile) of a numeric vector using
#' the default linear interpolation method (`type = 7` in [stats::quantile()]).
#'
#' @param x A numeric vector.
#' @param na.rm Logical. Should `NA` values be removed before computation?
#'   Defaults to `TRUE`.
#'
#' @return A single numeric value: the first quartile of `x`. Returns
#'   `NA_real_` if `x` is empty (or becomes empty after `NA` removal).
#'
#' @examples
#' calc_q1(c(1, 2, 2, 3, 4, 5, 5, 5, 6, 10))
#' # 2.25
#'
#' calc_q1(c(1, 2, 3, 4, 5))
#' # 2
#'
#' @seealso [calc_q3()], [calc_iqr()]
#' @export
calc_q1 <- function(x, na.rm = TRUE) {
  x <- validate_numeric(x, na.rm = na.rm, fn_name = "calc_q1")
  if (length(x) == 0) return(NA_real_)
  unname(stats::quantile(x, probs = 0.25, type = 7, names = FALSE))
}
