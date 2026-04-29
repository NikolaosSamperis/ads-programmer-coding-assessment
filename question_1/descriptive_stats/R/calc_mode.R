#' Calculate the Mode
#'
#' Computes the mode (most frequently occurring value) of a numeric vector.
#' Handles ties by returning all values that share the maximum frequency.
#' If every value occurs exactly once and the vector has more than one element,
#' the vector is considered to have no mode and `NA_real_` is returned with
#' a message.
#' 
#' @details
#' Unlike [calc_mean()] and [calc_median()], the mode is the only measure of
#' central tendency applicable to categorical (nominal) data. This implementation
#' is intentionally restricted to numeric vectors to remain consistent with the
#' rest of the package. For categorical data, the mode can be found directly
#' using `names(which.max(table(x)))` in base R.
#'
#' @param x A numeric vector.
#' @param na.rm Logical. Should `NA` values be removed before computation?
#'   Defaults to `TRUE`.
#'
#' @return A numeric vector containing the mode(s) of `x`:
#'   * A single value if there is one unique mode.
#'   * A vector of values if multiple values are tied for the maximum frequency.
#'   * `NA_real_` if no mode exists (all values appear exactly once and length
#'     is greater than 1), or if `x` is empty, or if `x` contains `NA` values
#'     and `na.rm = FALSE`.
#'
#' @examples
#' # Single mode
#' calc_mode(c(1, 2, 2, 3, 4, 5, 5, 5, 6, 10))
#' # 5
#'
#' # Tied modes (bimodal)
#' calc_mode(c(1, 1, 2, 2, 3))
#' # c(1, 2)
#'
#' # No mode (all unique)
#' calc_mode(c(1, 2, 3, 4))
#' # NA
#' 
#' #' # Single value is its own mode
#' calc_mode(7)
#' # 7
#'
#' @export
calc_mode <- function(x, na.rm = TRUE) {
  x <- validate_numeric(x, na.rm = na.rm, fn_name = "calc_mode")
  if (length(x) == 0) return(NA_real_)

  freq <- table(x)
  max_freq <- max(freq)

  # When na.rm = FALSE and NAs are present, return NA_real_
  if (any(is.na(x))) return(NA_real_)
  
  freq <- table(x)
  max_freq <- max(freq)
  
  # No mode case: every value appears exactly once AND vector has more than
  # one element. A single value is always its own mode.
  if (max_freq == 1 && length(x) > 1) {
    message("`calc_mode()`: no mode found (all values are unique); returning NA.")
    return(NA_real_)
  }

  modes <- as.numeric(names(freq)[freq == max_freq])
  sort(modes)
}
