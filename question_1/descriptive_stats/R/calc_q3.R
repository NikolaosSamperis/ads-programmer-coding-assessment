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
#'   `NA_real_` if `x` is empty or if `x` contains `NA` values and
#'   `na.rm = FALSE`.
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
  # Pass na.rm = FALSE to validate_numeric so NAs are preserved.
  # NA removal is delegated to stats::quantile() via its na.rm argument.
  x <- validate_numeric(x, na.rm = FALSE, fn_name = "calc_q3")
  if (length(x) == 0) return(NA_real_)
  result <- unname(stats::quantile(x, probs = 0.75, type = 7,
                                   na.rm = na.rm, names = FALSE))
  if (is.na(result)) return(NA_real_)
  result
}
