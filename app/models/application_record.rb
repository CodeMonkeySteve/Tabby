class ApplicationRecord
  include NoBrainer::Document
  include NoBrainer::Document::References
  include Sluggable
end
