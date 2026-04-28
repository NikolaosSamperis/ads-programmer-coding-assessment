test_that("calc_median returns correct value for example data", {
  expect_equal(calc_median(c(1, 2, 2, 3, 4, 5, 5, 5, 6, 10)), 4.5)
})

test_that("calc_median handles odd-length vector", {
  expect_equal(calc_median(c(1, 3, 5)), 3)
})

test_that("calc_median handles even-length vector", {
  expect_equal(calc_median(c(1, 2, 3, 4)), 2.5)
})

test_that("calc_median handles single value", {
  expect_equal(calc_median(7), 7)
})

test_that("calc_median handles NA values when na.rm = TRUE", {
  expect_equal(calc_median(c(1, 2, NA, 4, 5)), 3)
})

test_that("calc_median returns NA when na.rm = FALSE and NAs present", {
  expect_true(is.na(calc_median(c(1, 2, NA, 4), na.rm = FALSE)))
})

test_that("calc_median returns NA on empty vector with warning", {
  expect_warning(result <- calc_median(numeric(0)))
  expect_true(is.na(result))
})

test_that("calc_median errors on non-numeric input", {
  expect_error(calc_median("a"), "must be numeric")
})
