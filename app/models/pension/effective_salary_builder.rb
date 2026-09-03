module Pension
  # Effective annual salary per member-year: base salary history with
  # retroactive adjustments applied. An adjustment is visible only once
  # posted (posted_date <= period end); the latest posting for a year wins.
  class EffectiveSalaryBuilder
    def initialize(input_dir:, period_end:)
      @input_dir = input_dir
      @period_end = period_end
    end

    def call
      salaries = Hash.new { |h, k| h[k] = {} }
      each_row("salary_history.csv") do |r|
        year = Date.iso8601(r["effective_date"]).year
        salaries[r["member_id"]][year] ||= r["annual_salary"].to_r
      end

      adjustments = Hash.new { |h, k| h[k] = [] }
      each_row("adjustments.csv") do |r|
        posted = Date.iso8601(r["posted_date"])
        next if posted > @period_end
        year = Date.iso8601(r["effective_date"]).year
        adjustments[[r["member_id"], year]] << [posted, r["corrected_annual_salary"].to_r]
      end
      adjustments.each do |(member_id, year), postings|
        salaries[member_id][year] = postings.max_by(&:first).last
      end

      salaries
    end

    private

    def each_row(file)
      lines = File.readlines(File.join(@input_dir, file), chomp: true)
      header = lines.shift.split(",")
      lines.each { |l| yield header.zip(l.split(",", -1)).to_h }
    end
  end
end
