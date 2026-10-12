# frozen_string_literal: true

require 'async/service/managed/environment'
require 'async/service/managed/service'

# Runs Solid Queue's supervisor, with its dispatcher, worker, and scheduler as threads (config/queue.yml), in a process forked by
# `falcon host` (see falcon.rb), which restarts and stops it like a web worker.  Falcon preloads the app before forking it.
class SolidQueueService < Async::Service::Managed::Service
  # Seconds before a failed start (e.g. with the database down) ends the process, which Falcon restarts without any delay
  START_FAILURE_DELAY = 10

  def run(_instance, _evaluator)
    Async do
      begin
        release_abandoned_jobs
        supervisor = SolidQueue::Supervisor.start(mode: :async, standalone: false)
      rescue
        sleep START_FAILURE_DELAY
        raise
      end
      sleep
    ensure
      # waits up to SolidQueue.shutdown_timeout for running jobs, then releases them back to the queue
      supervisor&.stop
    end
  end

private

  # Only this process runs jobs, so any Solid Queue processes still registered are gone: killed, or stopped before their worker
  # released its jobs (the supervisor and worker wait out the same shutdown timeout, and the supervisor can exit first).
  # Deregistering their workers releases the jobs back to the queue now, rather than Solid Queue failing them once they look dead.
  def release_abandoned_jobs
    SolidQueue::Process.where.not(supervisor_id: nil).find_each(&:deregister)
    SolidQueue::Process.find_each(&:deregister)
  end
end
