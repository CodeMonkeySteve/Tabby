class User < ApplicationRecord
  include NoBrainer::Document::Timestamps
  include AuthenticationModel
end
