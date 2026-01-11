# frozen_string_literal: true

require 'nobrainer'

module Sluggable
  extend ActiveSupport::Concern

  included do
    field :slug, type: String, index: true
    before_save :slug
  end

  module ClassMethods
    def slug_from(*fields)
      @slug_fields = fields.map(&:to_s)
    end

    def find_by_slug_or_id(id_or_slug)
      where(slug: id_or_slug).first || where(id: id_or_slug).first!
    end
  end

  def slug
    slug_fields = self.class.instance_variable_get(:@slug_fields)
    slug_fields or return

    if _read_attribute(:slug).blank? || (slug_fields & changed).any?
      base = slug_fields.map { _read_attribute(it) }
               .reject(&:blank?).join('-').downcase
               .gsub(/\'s/, 's').gsub(/\W+/, '-').gsub(/-+/, '-').gsub(/(^-)|(-$)/, '')

      if base.present?
        slug = base
        if self.class.where(slug:).any?
          idx = 2
          loop do
            slug = "#{base}-#{idx}"
            break if self.class.where(slug:).empty?
          end
        end

        _write_attribute(:slug, slug)
      end
    end
    super
  end

  def to_param
    self.slug
  end
end
