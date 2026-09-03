class PensionCalcWorkflow < Temporalio::Workflow::Definition
  CHUNK_SIZE = 100

  def execute(period)
    Temporalio::Workflow.execute_activity(
      BuildEffectiveSalariesActivity, period,
      start_to_close_timeout: 120
    )

    member_ids = Temporalio::Workflow.execute_activity(
      ComputeServiceEligibilityActivity, period,
      start_to_close_timeout: 120
    )

    shard_paths = member_ids.each_slice(CHUNK_SIZE).with_index.map do |ids, index|
      Temporalio::Workflow.execute_activity(
        ComputeBenefitsActivity, period, ids, index,
        start_to_close_timeout: 300,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 3)
      )
    end

    Temporalio::Workflow.execute_activity(
      AssembleOutputActivity, period, shard_paths,
      start_to_close_timeout: 120
    )
  end
end
