# Usage: bin/rails runner script/start_hello.rb [name]
name = ARGV[0] || "Robert"

client = Temporalio::Client.connect("localhost:7233", "default")

handle = client.start_workflow(
  HelloWorkflow,
  name,
  id: "hello-#{Time.now.strftime('%H%M%S')}",
  task_queue: "lab"
)

puts "Started workflow #{handle.id} (run #{handle.result_run_id})"
puts "Result: #{handle.result}"
