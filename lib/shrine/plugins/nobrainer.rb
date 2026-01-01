# frozen_string_literal: true

require 'shrine'
require 'nobrainer'

class Shrine
  module Plugins
    module NoBrainer
      def self.load_dependencies(uploader, *)
        uploader.plugin :model
        uploader.plugin :_persistence, plugin: self
      end

      def self.configure(uploader, **opts)
        uploader.opts[:nobrainer] ||= { validations: true, callbacks: true }
        uploader.opts[:nobrainer].merge!(opts)
      end

      module AttachmentMethods
        def included(model)
          super

          return unless model < ::NoBrainer::Document

          name = @name

          if shrine_class.opts[:nobrainer][:validations]
            # add validation plugin integration
            model.validate do
              send(:"#{name}_attacher").send(:nobrainer_validate)
            end
          end

          if shrine_class.opts[:nobrainer][:callbacks]
            model.before_save do
              send(:"#{name}_attacher").send(:nobrainer_before_save)
            end

            model.after_save do
              send(:"#{name}_attacher").send(:nobrainer_after_save)
            end

            model.after_destroy do
              send(:"#{name}_attacher").send(:nobrainer_after_destroy)
            end
          end

          define_method :reload do |*args|
            result = super(*args)
            instance_variable_set(:"@#{name}_attacher", nil)
            result
          end
        end
      end

      # The _persistence plugin uses #nobrainer_persist, #nobrainer_reload and
      # #nobrainer? to implement the following methods:
      #
      #   * Attacher#persist
      #   * Attacher#atomic_persist
      #   * Attacher#atomic_promote
      module AttacherMethods
        private

        def nobrainer_validate
          return unless respond_to?(:errors)

          errors.each do |message|
            record.errors.add(name, message)
          end
        end

        # Calls Attacher#save. Called before model save.
        def nobrainer_before_save
          return unless changed?

          save
        end

        # Finalizes attachment and persists changes. Called after model save.
        def nobrainer_after_save
          return unless changed?

          finalize
          persist
        end

        # Deletes attached files. Called after model destroy.
        def nobrainer_after_destroy
          destroy_attached
        end

        # Saves changes to the model instance, raising exception on validation
        # errors. Used by the _persistence plugin.
        def nobrainer_persist
          record.save(validate: false)
        end

        # Yields the reloaded record. Used by the _persistence plugin.
        def nobrainer_reload
          record_copy    = record.dup
          record_copy.id = record.id

          yield record_copy.reload
        end

        # Returns true if the data attribute represents a Hash field. Used by
        # the _persistence plugin to determine whether serialization should be
        # skipped.
        def nobrainer_hash_attribute?
          true
        end

        # Returns whether the record is a NoBrainer document. Used by the
        # _persistence plugin.
        def nobrainer?
          record.is_a?(::NoBrainer::Document)
        end
      end
    end

    register_plugin(:nobrainer, NoBrainer)
  end
end
