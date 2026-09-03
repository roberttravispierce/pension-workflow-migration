require "test_helper"

module Pension
  class EffectiveSalaryBuilderTest < ActiveSupport::TestCase
    def build(salary_rows, adjustment_rows, period_end:)
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "salary_history.csv"),
                   [ "member_id,effective_date,annual_salary", *salary_rows ].join("\n") + "\n")
        File.write(File.join(dir, "adjustments.csv"),
                   [ "member_id,effective_date,posted_date,corrected_annual_salary,reason", *adjustment_rows ].join("\n") + "\n")
        return EffectiveSalaryBuilder.new(input_dir: dir, period_end: period_end).call
      end
    end

    test "an adjustment does not exist until it is posted" do
      result = build(
        [ "M1,2021-01-01,50000.00" ],
        [ "M1,2021-01-01,2026-10-15,60000.00,late correction" ],
        period_end: Date.new(2026, 9, 30)
      )
      assert_equal 50_000r, result["M1"][2021]
    end

    test "a posted adjustment replaces the base salary for its year" do
      result = build(
        [ "M1,2021-01-01,50000.00" ],
        [ "M1,2021-01-01,2024-02-10,60000.00,restated after audit" ],
        period_end: Date.new(2026, 9, 30)
      )
      assert_equal 60_000r, result["M1"][2021]
    end

    test "the latest posting for a year wins" do
      result = build(
        [ "M1,2021-01-01,50000.00" ],
        [ "M1,2021-01-01,2024-02-10,60000.00,first restatement",
          "M1,2021-01-01,2025-01-05,58000.00,second restatement" ],
        period_end: Date.new(2026, 9, 30)
      )
      assert_equal 58_000r, result["M1"][2021]
    end
  end
end
