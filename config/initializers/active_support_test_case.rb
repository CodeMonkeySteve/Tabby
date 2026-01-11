# require "rails/test_unit/railtie"

ActiveSupport.on_load(:active_support_test_case) do
  if Rails.application.config.active_support.executor_around_test_case
    require "active_support/executor/test_helper"
    include ActiveSupport::Executor::TestHelper
  else
    require "active_support/current_attributes/test_helper"
    include ActiveSupport::CurrentAttributes::TestHelper

    require "active_support/execution_context/test_helper"
    include ActiveSupport::ExecutionContext::TestHelper
  end
end
