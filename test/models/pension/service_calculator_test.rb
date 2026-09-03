require "test_helper"

module Pension
  class ServiceCalculatorTest < ActiveSupport::TestCase
    PERIOD_END = Date.new(2026, 9, 30)

    def member(overrides = {})
      {
        "member_id" => "TEST-0001",
        "birth_date" => "1958-01-01",
        "hire_date" => "1990-01-01",
        "prior_termination_date" => "",
        "rehire_date" => "",
        "termination_date" => "2023-01-01",
        "retirement_date" => "2023-01-01",
        "plan_tier" => "clergy",
        "survivor_option" => "none"
      }.merge(overrides)
    end

    test "vesting is inclusive at exactly five years" do
      calc = ServiceCalculator.new(member("hire_date" => "2018-01-01",
                                          "termination_date" => "2023-01-01",
                                          "retirement_date" => "2023-01-01"))
      assert calc.payable_for?(PERIOD_END)
      assert_equal 5r, calc.result.service_years
    end

    test "a month short of five years is not vested" do
      calc = ServiceCalculator.new(member("hire_date" => "2018-02-01",
                                          "termination_date" => "2023-01-01",
                                          "retirement_date" => "2023-01-01"))
      assert_not calc.payable_for?(PERIOD_END)
    end

    test "retirement at 62 reduces by half a percent per whole month before 65" do
      calc = ServiceCalculator.new(member("birth_date" => "1962-08-01",
                                          "retirement_date" => "2024-08-01",
                                          "termination_date" => "2024-08-01",
                                          "hire_date" => "1995-03-01"))
      assert_equal "0.82".to_r, calc.result.early_factor
    end

    test "no early reduction at or after 65" do
      calc = ServiceCalculator.new(member("birth_date" => "1958-01-01",
                                          "retirement_date" => "2023-06-01"))
      assert_equal 1r, calc.result.early_factor
    end

    test "a leap-day birthday four days short of 65 still clears the threshold" do
      calc = ServiceCalculator.new(member("birth_date" => "1960-02-29",
                                          "retirement_date" => "2025-03-01",
                                          "termination_date" => "2025-03-01"))
      assert_equal 1r, calc.result.early_factor
    end

    test "survivor options carry their factors" do
      assert_equal "0.90".to_r, ServiceCalculator.new(member("survivor_option" => "js50")).result.survivor_factor
      assert_equal "0.84".to_r, ServiceCalculator.new(member("survivor_option" => "js100")).result.survivor_factor
      assert_equal 1r, ServiceCalculator.new(member).result.survivor_factor
    end

    test "a member who has not retired is not payable" do
      calc = ServiceCalculator.new(member("retirement_date" => "", "termination_date" => ""))
      assert_not calc.payable_for?(PERIOD_END)
    end

    test "retirement after the run period is not yet payable" do
      calc = ServiceCalculator.new(member("retirement_date" => "2026-10-01",
                                          "termination_date" => "2026-10-01"))
      assert_not calc.payable_for?(PERIOD_END)
    end
  end
end
