test_that("calc_mean returns correct value for example data", {
  expect_equal(calc_mean(c(1, 2, 2, 3, 4, 5, 5, 5, 6, 10)), 4.3)
})

test_that("calc_mean handles single value", {
  expect_equal(calc_mean(42), 42)
})

test_that("calc_mean handles NA values when na.rm = TRUE", {
  expect_equal(calc_mean(c(1, 2, NA, 4)), (1 + 2 + 4) / 3)
})

test_that("calc_mean returns NA when na.rm = FALSE and NAs are present", {
  expect_true(is.na(calc_mean(c(1, 2, NA, 4), na.rm = FALSE)))
})

test_that("calc_mean returns NA on empty vector with warning", {
  expect_warning(result <- calc_mean(numeric(0)))
  expect_true(is.na(result))
})

test_that("calc_mean errors on non-numeric input", {
  expect_error(calc_mean("a"), "must be numeric")
  expect_error(calc_mean(TRUE), "must be numeric")
  expect_error(calc_mean(NULL), "NULL")
})

test_that("calc_mean handles negative numbers", {
  expect_equal(calc_mean(c(-2, -1, 0, 1, 2)), 0)
})
