require_relative "../config/environment"

client = Temporalio::Client.connect("localhost:7233", "default")

worker = Temporalio::Worker.new(
  client: client,
  task_queue: "lab",
  workflows: [HelloWorkflow],
  activities: [SayHelloActivity]
)

puts "Worker PID #{Process.pid} polling task queue 'lab' — Ctrl-C to stop"
worker.run(shutdown_signals: ["SIGINT", "SIGTERM"])
