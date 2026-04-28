#' Calculate the Third Quartile (Q3)
#'
#' Computes the third quartile (75th percentile) of a numeric vector using
#' the default linear interpolation method (`type = 7` in [stats::quantile()]).
#'
#' @param x A numeric vector.
#' @param na.rm Logical. Should `NA` values be removed before computation?
#'   Defaults to `TRUE`.
#'
#' @return A single numeric value: the third quartile of `x`. Returns
#'   `NA_real_` if `x` is empty (or becomes empty after `NA` removal).
#'
#' @examples
#' calc_q3(c(1, 2, 2, 3, 4, 5, 5, 5, 6, 10))
#' # 5.0
#'
#' calc_q3(c(1, 2, 3, 4, 5))
#' # 4
#'
#' @seealso [calc_q1()], [calc_iqr()]
#' @export
calc_q3 <- function(x, na.rm = TRUE) {
  x <- validate_numeric(x, na.rm = na.rm, fn_name = "calc_q3")
  if (length(x) == 0) return(NA_real_)
  unname(stats::quantile(x, probs = 0.75, type = 7, names = FALSE))
}
