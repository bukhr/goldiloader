# frozen_string_literal: true

module Goldiloader
  module BasePatch
    extend ActiveSupport::Concern

    included do
      attr_writer :auto_include_context

      class << self
        delegate :auto_include, to: :all

        def auto_preload(auto_include = true)
          previous_state = Goldiloader.auto_preload
          Goldiloader.auto_preload = auto_include
          yield
        ensure
          Goldiloader.auto_preload = previous_state
        end
      end
    end

    def initialize_copy(other)
      super
      @auto_include_context = nil
    end

    def auto_include_context
      @auto_include_context ||= Goldiloader::AutoIncludeContext.new.register_model(self)
    end

    def reload(*)
      @auto_include_context = nil
      super
    end
  end
  ::ActiveRecord::Base.include(::Goldiloader::BasePatch)

  module RelationPatch
    def exec_queries
      return super if loaded?

      models = super
      Goldiloader::AutoIncludeContext.register_models(
        models,
        included_associations: eager_load_values,
        auto_include: auto_include_value
      )
      models
    end

    def auto_include(auto_include = true)
      spawn.auto_include!(auto_include)
    end

    def auto_include!(auto_include = true)
      self.auto_include_value = auto_include
      self
    end

    def auto_include_value
      @values.fetch(:auto_include, nil)
    end

    def auto_include_value=(value)
      assert_mutability!
      @values[:auto_include] = value
    end
  end
  ::ActiveRecord::Relation.prepend(::Goldiloader::RelationPatch)

  module MergerPatch
    private

    def merge_single_values
      relation.auto_include_value = other.auto_include_value
      super
    end
  end
  ActiveRecord::Relation::Merger.prepend(::Goldiloader::MergerPatch)

  module AssociationReflectionPatch
    # Note we need to pass the association's target class as an argument since it won't be known
    # outside the context of an association instance for polymorphic associations.
    def eager_loadable?(target_klass)
      @eager_loadable_cache ||= Hash.new do |cache, target_klass_key|
        cache[target_klass_key] = if scope.nil?
                                    # Associations without any scoping options are eager loadable
                                    true
                                  elsif scope.arity > 0
                                    # The scope will be evaluated for every model instance so it can't
                                    # be eager loaded
                                    false
                                  else
                                    scope_info = Goldiloader::ScopeInfo.new(scope_for(target_klass_key.unscoped))
                                    scope_info.auto_include? &&
                                      !scope_info.limit? &&
                                      !scope_info.offset? &&
                                      (!has_one? || !scope_info.order?)
                                  end
      end
      @eager_loadable_cache[target_klass]
    end
  end
  ActiveRecord::Reflection::AssociationReflection.include(::Goldiloader::AssociationReflectionPatch)
  ActiveRecord::Reflection::ThroughReflection.include(::Goldiloader::AssociationReflectionPatch)

  module AssociationPatch
    extend ActiveSupport::Concern

    included do
      class_attribute :default_fully_load
      self.default_fully_load = false
    end

    def auto_include?
      # We only auto include associations that don't have in-memory changes since the
      # Rails association Preloader clobbers any in-memory changes
      !loaded? && target.blank? && eager_loadable?
    end

    def preload?
      return owner.auto_include_context.auto_include unless owner.auto_include_context.auto_include.nil?
      return Goldiloader.auto_preload unless Goldiloader.auto_preload.nil?
      Goldiloader.configuration.auto_include
    end

    def fully_load?
      !loaded? && options.fetch(:fully_load) { self.class.default_fully_load }
    end

    private

    def eager_loadable?
      klass && reflection.eager_loadable?(klass) &&
        (::Goldiloader::Compatibility.destroyed_model_associations_eager_loadable? || !owner.destroyed?)
    end

    def load_with_auto_include
      if loaded? && !stale_target?
        target
      elsif !auto_include?
        yield
      elsif owner.auto_include_context.size == 1 || !preload?
        # Bypassing the preloader for a single model reduces object allocations by ~5% in benchmarks
        result = yield
        # As of https://github.com/rails/rails/commit/bd3b28f7f181dce53e872daa23dda101498b8fb4
        # ActiveRecord does not use ActiveRecord::Relation#exec_queries to resolve association
        # queries
        Goldiloader::AutoIncludeContext.register_models(result)
        result
      else
        Goldiloader::AssociationLoader.load(owner, reflection.name)
        target
      end
    end
  end
  ::ActiveRecord::Associations::Association.include(::Goldiloader::AssociationPatch)

  module SingularAssociationPatch
    private

    def find_target(*args)
      load_with_auto_include { super }
    end
  end
  ::ActiveRecord::Associations::SingularAssociation.prepend(::Goldiloader::SingularAssociationPatch)

  module CollectionAssociationPatch
    # Force these methods to load the entire association for fully_load associations
    [:size, :ids_reader, :empty?].each do |method|
      define_method(method) do |*args, &block|
        load_target if fully_load?
        super(*args, &block)
      end
    end

    def load_target(*args)
      load_with_auto_include { super }
    end

    def find_from_target?
      fully_load? || super
    end
  end
  ::ActiveRecord::Associations::CollectionAssociation.prepend(::Goldiloader::CollectionAssociationPatch)

  module ThroughAssociationPatch
    def auto_include?
      # Only auto include through associations if the target association is auto-loadable
      through_association = owner.association(through_reflection.name)
      through_association.auto_include? && super
    end
  end
  ::ActiveRecord::Associations::HasManyThroughAssociation.prepend(::Goldiloader::ThroughAssociationPatch)
  ::ActiveRecord::Associations::HasOneThroughAssociation.prepend(::Goldiloader::ThroughAssociationPatch)

  module CollectionProxyPatch
    # The CollectionProxy just forwards exists? to the underlying scope so we need to intercept this and
    # force it to use size which handles fully_load properly.
    def exists?(*args)
      # We don't fully_load the association when arguments are passed to exists? since Rails always
      # pushes this query into the database without any caching (and it likely not a common
      # scenario worth optimizing).
      if args.empty? && @association.fully_load?
        size > 0
      else
        scope.exists?(*args)
      end
    end
  end
  ::ActiveRecord::Associations::CollectionProxy.prepend(::Goldiloader::CollectionProxyPatch)
end
