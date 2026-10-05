# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/solid_queue_service')

RSpec.describe SolidQueueService do
  let(:service) { described_class.allocate } # the service's environment isn't used by #run

  it "releases the jobs claimed by earlier processes before starting, and stops when stopped" do
    # left registered by a process that exited without deregistering, e.g. killed, or timing out during shutdown
    supervisor = SolidQueue::Process.register(kind: 'Supervisor(async)', name: 'supervisor-old', pid: 1)
    worker = SolidQueue::Process.register(kind: 'Worker', name: 'worker-old', pid: 1, supervisor_id: supervisor.id)
    job = SolidQueue::Job.enqueue(CleanUploadCacheJob.new)
    SolidQueue::ReadyExecution.claim('*', 1, worker.id)
    expect(job.reload).to be_claimed

    new_supervisor = instance_double(SolidQueue::Supervisor, stop: nil)
    processes_at_start = nil
    allow(SolidQueue::Supervisor).to receive(:start) do
      processes_at_start = SolidQueue::Process.count
      new_supervisor
    end
    Sync do
      task = service.run(nil, nil)
      sleep 0.01 until processes_at_start # the task yields to the reactor during its database queries
      task.stop
    end

    expect(processes_at_start).to eq 0 # released before starting

    expect(job.reload).to be_ready
    expect(SolidQueue::Supervisor).to have_received(:start).with(mode: :async, standalone: false)
    expect(new_supervisor).to have_received(:stop)
  end

  it "waits before failing to start, so Falcon doesn't restart it in a tight loop" do
    stub_const('SolidQueueService::START_FAILURE_DELAY', 0.2)
    allow(SolidQueue::Supervisor).to receive(:start).and_raise(ActiveRecord::ConnectionNotEstablished)

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect { Sync { service.run(nil, nil).wait } }.to raise_error ActiveRecord::ConnectionNotEstablished
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be >= 0.2
  end
end
