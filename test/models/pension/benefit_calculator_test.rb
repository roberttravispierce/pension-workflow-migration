require "test_helper"

module Pension
  class BenefitCalculatorTest < ActiveSupport::TestCase
    def service(years: 30r, early: 1r, survivor: 1r, accrual: "0.0175".to_r)
      ServiceCalculator::Result.new(
        member_id: "TEST-0001", service_years: years, early_factor: early,
        survivor_factor: survivor, accrual_rate: accrual
      )
    end

    test "picks the best three-consecutive-year average in the final ten years" do
      salaries = (2014..2023).to_h { |y| [ y, 50_000r ] }
      salaries[2018] = 80_000r
      salaries[2019] = 80_000r
      salaries[2020] = 80_000r
      calc = BenefitCalculator.new(service: service, salaries_by_year: salaries, termination_year: 2023)
      assert_equal 80_000r, calc.final_average_salary
    end

    test "years outside the final ten are ignored" do
      salaries = (2005..2023).to_h { |y| [ y, 50_000r ] }
      salaries[2006] = 200_000r
      calc = BenefitCalculator.new(service: service, salaries_by_year: salaries, termination_year: 2023)
      assert_equal 50_000r, calc.final_average_salary
    end

    test "a window requires all three calendar years present" do
      salaries = { 2019 => 90_000r, 2021 => 90_000r, 2022 => 60_000r, 2023 => 60_000r }
      calc = BenefitCalculator.new(service: service, salaries_by_year: salaries, termination_year: 2023)
      assert_equal 70_000r, calc.final_average_salary
    end

    test "no benefit basis without three consecutive years" do
      calc = BenefitCalculator.new(service: service, salaries_by_year: { 2020 => 90_000r, 2022 => 90_000r },
                                   termination_year: 2023)
      assert_equal 0r, calc.final_average_salary
      assert_equal 0r, calc.monthly_benefit
    end

    test "monthly benefit rounds to the cent at the final step" do
      salaries = (2014..2023).to_h { |y| [ y, "51428.57".to_r ] }
      calc = BenefitCalculator.new(service: service(years: 32r, early: "0.955".to_r),
                                   salaries_by_year: salaries, termination_year: 2023)
      exact = "51428.57".to_r * "0.0175".to_r * 32 * "0.955".to_r / 12
      assert_equal exact.round(2, half: :up), calc.monthly_benefit
    end
  end
end
