class ComputeBenefitsActivity < Temporalio::Activity::Definition
  def execute(period, member_ids, shard_index)
    salaries = Hash.new { |h, k| h[k] = {} }
    Pension::Pipeline.read_rows(Pension::Pipeline.effective_salaries_path(period)).each do |r|
      salaries[r["member_id"]][r["year"].to_i] = r["salary"].to_r
    end

    members = Pension::Pipeline.read_rows(Pension::Pipeline.input_dir.join("members.csv"))
      .to_h { |m| [ m["member_id"], m ] }

    wanted = member_ids.to_set
    rows = Pension::Pipeline.read_rows(Pension::Pipeline.payable_path(period))
      .select { |r| wanted.include?(r["member_id"]) }
      .map do |r|
        service = Pension::ServiceCalculator::Result.new(
          member_id: r["member_id"],
          service_years: r["service_years"].to_r,
          early_factor: r["early_factor"].to_r,
          survivor_factor: r["survivor_factor"].to_r,
          accrual_rate: r["accrual_rate"].to_r
        )
        term_year = Date.iso8601(members.fetch(r["member_id"])["termination_date"]).year
        calc = Pension::BenefitCalculator.new(
          service: service,
          salaries_by_year: salaries[r["member_id"]],
          termination_year: term_year
        )
        [ r["member_id"], r["service_years"], "%.2f" % calc.final_average_salary,
         r["early_factor"], r["survivor_factor"], "%.2f" % calc.monthly_benefit ]
      end

    path = Pension::Pipeline.shard_path(period, shard_index)
    Pension::Pipeline.write_rows(path, %w[member_id svc_yrs fas early_fct surv_fct mo_ben], rows)
    path.to_s
  end
end
