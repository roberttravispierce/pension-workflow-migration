# The temporalio gem loads almost nothing from its root require;
# the client, worker, and definition APIs are explicit requires.
require "temporalio/client"
require "temporalio/worker"
require "temporalio/workflow"
require "temporalio/activity"
