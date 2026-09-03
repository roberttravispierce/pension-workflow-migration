class HelloWorkflow < Temporalio::Workflow::Definition
  def execute(name)
    Temporalio::Workflow.execute_activity(
      SayHelloActivity,
      name,
      start_to_close_timeout: 10
    )
  end
end
