# frozen_string_literal: true

module Goldiloader
  class AutoIncludeContext
    attr_reader :models
    attr_accessor :auto_include

    delegate :size, to: :models

    def initialize
      @models = []
      @auto_include = nil
    end

    def self.register_models(models, included_associations: nil, auto_include: nil)
      auto_include_context = Goldiloader::AutoIncludeContext.new
      auto_include_context.auto_include = auto_include unless auto_include.nil?
      auto_include_context.register_models(models)

      Array.wrap(included_associations).each do |included_association|
        associations = if included_association.is_a?(Hash)
                         included_association.keys
                       else
                         Array.wrap(included_association)
                       end
        nested_associations = if included_association.is_a?(Hash)
                                included_association
                              else
                                Hash.new([])
                              end

        associations.each do |association|
          nested_models = models.flat_map do |model|
            model.association(association).target
          end.compact

          register_models(nested_models, auto_include: Goldiloader.configuration.auto_include, included_associations: nested_associations[association])
        end
      end
    end

    def register_models(models)
      Array.wrap(models).each do |model|
        model.auto_include_context = self
        self.models << model
      end
      self
    end

    alias_method :register_model, :register_models
  end
end
