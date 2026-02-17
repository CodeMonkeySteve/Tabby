# in some place that gets loaded for specs like spec/support/helpers/uploaded_file_helper.rb
module UploadedFileSpecHelper
  # Mimics a file upload parameter. Use like so:
  #   uploaded_file(fixtures_path("example.pdf"), "custom_name.pdf", "application/pdf")
  # def uploaded_file(path, name, mime_type, binmode: true)
  #   Rack::Test::UploadedFile.new(path, mime_type, binmode, original_filename: name)
  # end

  def upload_fixture(path, mime_type = 'application/octet-stream')
    path = Rails.root.join('spec', 'fixtures', path)
    file = path.open(binmode: true)
    Shrine.upload(file, :cache, metadata: false).tap do |uploaded_file|
      uploaded_file.metadata.update(
        'size'      => path.size,
        'mime_type' => mime_type,
        'filename'  => path.basename.to_s,
      )
    end
  end

end

RSpec.configure do |config|
  config.include UploadedFileSpecHelper
end
module FactoryBot
  class SyntaxRunner
    include UploadedFileSpecHelper
  end
end