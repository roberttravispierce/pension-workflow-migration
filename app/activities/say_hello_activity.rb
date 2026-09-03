class SayHelloActivity < Temporalio::Activity::Definition
  def execute(name)
    "Hello, #{name}! (from PID #{Process.pid})"
  end
end
