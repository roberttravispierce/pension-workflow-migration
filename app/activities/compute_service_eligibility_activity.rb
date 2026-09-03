class ComputeServiceEligibilityActivity < Temporalio::Activity::Definition
  def execute(period)
    period_end = Pension::Pipeline.period_end(period)

    payable = Pension::Pipeline.read_rows(Pension::Pipeline.input_dir.join("members.csv"))
      .map { |m| Pension::ServiceCalculator.new(m) }
      .select { |calc| calc.payable_for?(period_end) }
      .map(&:result)
      .sort_by(&:member_id)

    Pension::Pipeline.write_rows(
      Pension::Pipeline.payable_path(period),
      %w[member_id service_years early_factor survivor_factor accrual_rate],
      payable.map { |r| [ r.member_id, "%.4f" % r.service_years, "%.4f" % r.early_factor,
                         "%.4f" % r.survivor_factor, "%.6f" % r.accrual_rate ] }
    )
    payable.map(&:member_id)
  end
end
