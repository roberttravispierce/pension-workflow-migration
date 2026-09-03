class AssembleOutputActivity < Temporalio::Activity::Definition
  def execute(period, shard_paths)
    rows = shard_paths
      .flat_map { |p| Pension::Pipeline.read_rows(p) }
      .sort_by { |r| r["member_id"] }

    Pension::Pipeline.write_rows(
      Pension::Pipeline.output_path(period),
      %w[member_id svc_yrs fas early_fct surv_fct mo_ben],
      rows.map { |r| r.values_at("member_id", "svc_yrs", "fas", "early_fct", "surv_fct", "mo_ben") }
    )

    total = rows.sum { |r| r["mo_ben"].to_r }
    "payable=#{rows.size} total=#{'%.2f' % total} output=#{Pension::Pipeline.output_path(period)}"
  end
end
