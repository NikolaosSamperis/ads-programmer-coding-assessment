test_that("calc_q1 returns R type-7 value for example data", {
  # stats::quantile(x, 0.25, type = 7) on c(1,2,2,3,4,5,5,5,6,10) is 2.25
  expect_equal(calc_q1(c(1, 2, 2, 3, 4, 5, 5, 5, 6, 10)), 2.25)
})

test_that("calc_q3 returns R type-7 value for example data", {
  expect_equal(calc_q3(c(1, 2, 2, 3, 4, 5, 5, 5, 6, 10)), 5.0)
})

test_that("calc_iqr returns R type-7 value for example data", {
  expect_equal(calc_iqr(c(1, 2, 2, 3, 4, 5, 5, 5, 6, 10)), 2.75)
})

test_that("calc_q1 matches stats::quantile type 7", {
  x <- c(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
  expect_equal(calc_q1(x), unname(quantile(x, 0.25, type = 7)))
})

test_that("calc_q3 matches stats::quantile type 7", {
  x <- c(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
  expect_equal(calc_q3(x), unname(quantile(x, 0.75, type = 7)))
})

test_that("quartile functions handle NA values", {
  x <- c(1, 2, 2, 3, 4, NA, 5, 5, 5, 6, 10)
  expect_equal(calc_q1(x), 2.5)
  expect_equal(calc_q3(x), 5.5)
  expect_equal(calc_iqr(x), 3)
})

test_that("quartile functions return NA on empty vector", {
  expect_warning(q1 <- calc_q1(numeric(0)))
  expect_warning(q3 <- calc_q3(numeric(0)))
  expect_warning(iqr <- calc_iqr(numeric(0)))
  expect_true(is.na(q1))
  expect_true(is.na(q3))
  expect_true(is.na(iqr))
})

test_that("quartile functions handle single value", {
  expect_equal(calc_q1(5), 5)
  expect_equal(calc_q3(5), 5)
  expect_equal(calc_iqr(5), 0)
})

test_that("quartile functions error on non-numeric input", {
  expect_error(calc_q1("a"), "must be numeric")
  expect_error(calc_q3("a"), "must be numeric")
  expect_error(calc_iqr("a"), "must be numeric")
})

test_that("calc_iqr equals calc_q3 minus calc_q1", {
  set.seed(42)
  x <- rnorm(100)
  expect_equal(calc_iqr(x), calc_q3(x) - calc_q1(x))
})
