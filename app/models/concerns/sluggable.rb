# frozen_string_literal: true

module Sluggable
  extend ActiveSupport::Concern

  included do
    before_save :slug
  end

  module ClassMethods
    def slug_from(*fields)
      @slug_fields = fields.map(&:to_s)
    end

    def find_by_slug_or_id(id_or_slug)
      find_by(slug: id_or_slug) || (find_by(id: id_or_slug) if id_or_slug.to_s.match?(/\A\d+\z/))
    end

    def find_by_slug_or_id!(id_or_slug)
      find_by_slug_or_id(id_or_slug) or
        raise ActiveRecord::RecordNotFound.new("Couldn't find #{name} with slug or id #{id_or_slug}", name)
    end
  end

  def slug
    slug_fields = self.class.instance_variable_get(:@slug_fields)
    slug_fields or return

    if read_attribute(:slug).blank? || (slug_fields & changed).any?
      base = slug_fields.map { read_attribute(it) }
               .reject(&:blank?).join('-').downcase
               .gsub(/\'s/, 's').gsub(/\W+/, '-').gsub(/-+/, '-').gsub(/(^-)|(-$)/, '')

      if base.present?
        slug = base
        if self.class.where(slug:).where.not(id:).exists?
          idx = 2
          loop do
            slug = "#{base}-#{idx}"
            break unless self.class.where(slug:).where.not(id:).exists?
            idx += 1
          end
        end

        write_attribute(:slug, slug)
      end
    end
    super
  end

  def to_param
    self.slug
  end
end
