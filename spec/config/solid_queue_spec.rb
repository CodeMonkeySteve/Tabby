# frozen_string_literal: true

require 'rails_helper'

# config/queue.yml and config/recurring.yml, which are only used in production, where an invalid configuration stops the jobs
# process from starting
RSpec.describe "Solid Queue's production configuration" do
  it "is valid, with a dispatcher, worker, and scheduler for the recurring tasks" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('production'))
    config = SolidQueue::Configuration.new(mode: :async, standalone: false)

    expect(config.errors.full_messages).to eq [] if config.invalid?
    expect(config.warnings.full_messages).to eq []
    expect(config.configured_processes.map(&:kind)).to eq %i[dispatcher worker scheduler]
    worker = config.configured_processes.find { it.kind == :worker }
    expect(worker.attributes).to include(queues: '*', threads: 2)
    scheduler = config.configured_processes.find { it.kind == :scheduler }
    expect(scheduler.attributes[:recurring_tasks].map(&:key)).to eq %w[clean_upload_cache clear_solid_queue_finished_jobs]
  end
end
