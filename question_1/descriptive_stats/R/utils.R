#' Validate Numeric Vector Input
#'
#' Internal helper to validate that input is a numeric vector and to
#' optionally remove `NA` values. Used by all exported `calc_*` functions
#' to keep validation logic consistent.
#'
#' @param x Object to validate.
#' @param na.rm Logical; if `TRUE`, `NA` values are removed before returning.
#' @param fn_name Character; calling function name, used in error messages.
#'
#' @return A numeric vector with `NA`s optionally removed.
#' @keywords internal
#' @noRd
validate_numeric <- function(x, na.rm = TRUE, fn_name = "calc_*") {
  if (missing(x)) {
    stop(sprintf("`%s()`: argument 'x' is missing with no default.", fn_name),
         call. = FALSE)
  }
  if (is.null(x)) {
    stop(sprintf("`%s()`: input 'x' must be a numeric vector, not NULL.", fn_name),
         call. = FALSE)
  }
  if (!is.numeric(x)) {
    stop(sprintf("`%s()`: input 'x' must be numeric, not %s.",
                 fn_name, class(x)[1]),
         call. = FALSE)
  }
  if (length(x) == 0) {
    warning(sprintf("`%s()`: input 'x' is an empty vector; returning NA.",
                    fn_name),
            call. = FALSE)
    return(numeric(0))
  }
  if (isTRUE(na.rm)) {
    x <- x[!is.na(x)]
  }
  x
}
