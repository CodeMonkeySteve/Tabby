class ApplicationRecord
  def self.inherited(subclass)
    subclass.include NoBrainer::Document
    subclass.include NoBrainer::Document::References
  end
end
