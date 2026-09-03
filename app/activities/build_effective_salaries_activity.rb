class BuildEffectiveSalariesActivity < Temporalio::Activity::Definition
  def execute(period)
    salaries = Pension::EffectiveSalaryBuilder.new(
      input_dir: Pension::Pipeline.input_dir,
      period_end: Pension::Pipeline.period_end(period)
    ).call

    rows = salaries.flat_map do |member_id, by_year|
      by_year.sort.map { |year, sal| [ member_id, year, "%.2f" % sal ] }
    end
    Pension::Pipeline.write_rows(
      Pension::Pipeline.effective_salaries_path(period),
      %w[member_id year salary], rows
    )
    rows.size
  end
end
