test_that("calc_mode returns single mode", {
  expect_equal(calc_mode(c(1, 2, 2, 3, 4, 5, 5, 5, 6, 10)), 5)
})

test_that("calc_mode returns multiple modes when tied", {
  expect_equal(calc_mode(c(1, 1, 2, 2, 3)), c(1, 2))
})

test_that("calc_mode returns NA with message when no mode (all unique)", {
  expect_message(result <- calc_mode(c(1, 2, 3, 4)), "no mode found")
  expect_true(is.na(result))
})

test_that("calc_mode handles single value", {
  expect_equal(calc_mode(7), 7)
})

test_that("calc_mode handles NA values when na.rm = TRUE", {
  expect_equal(calc_mode(c(1, 2, 2, NA, NA, 3)), 2)
})

test_that("calc_mode returns NA_real_ when na.rm = FALSE and NAs present", {
  result <- calc_mode(c(1, 2, 2, NA, 3), na.rm = FALSE)
  expect_true(is.na(result))
  expect_type(result, "double")  # confirms it is NA_real_ not just NA
})

test_that("calc_mode returns NA on empty vector with warning", {
  expect_warning(result <- calc_mode(numeric(0)))
  expect_true(is.na(result))
})

test_that("calc_mode errors on non-numeric input", {
  expect_error(calc_mode(list(1, 2, 3)), "must be numeric")
})

test_that("calc_mode returns sorted modes when multiple", {
  expect_equal(calc_mode(c(3, 3, 1, 1, 2)), c(1, 3))
})
