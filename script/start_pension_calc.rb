# Usage: bin/rails runner script/start_pension_calc.rb 2026-09
#
# The workflow ID is the business identity of the run — one execution per
# period. A second start while one is running is rejected by the server.
period = ARGV[0] or abort "usage: bin/rails runner script/start_pension_calc.rb YYYY-MM"

client = Temporalio::Client.connect("localhost:7233", "default")

begin
  handle = client.start_workflow(
    PensionCalcWorkflow,
    period,
    id: "pension-calc-#{period}",
    task_queue: "lab"
  )
  puts "Started #{handle.id}"
  puts handle.result
rescue Temporalio::Error::WorkflowAlreadyStartedError
  abort "pension-calc-#{period} is already running — one execution per period."
end
